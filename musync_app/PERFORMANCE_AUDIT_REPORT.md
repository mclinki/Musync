# Performance Audit Report — MusyncMIMO

**Date**: 2026-04-03
**Project**: MusyncMIMO (Flutter multi-device audio sync)
**Scope**: All lib/ files (15 Dart files, ~6,000 lines)
**Tech Stack**: Flutter/Dart, just_audio, flutter_bloc, sqflite, multicast_dns, WebSocket

---

## Executive Summary

The MusyncMIMO codebase is a real-time audio synchronization app with generally solid architecture. However, several performance issues exist that could cause jank, memory leaks, and network flooding under production conditions. The most critical concerns are: (1) the `session_manager.dart` file at 1,317 lines is a god object that will become unmaintainable, (2) position updates fire at 250ms intervals through a BLoC chain that causes unnecessary widget rebuilds, (3) file transfer holds entire files in memory on the slave side, and (4) multiple timers run without backpressure controls.

| Severity | Count |
|----------|-------|
| 🔴 Critical | 4 |
| 🟠 High | 6 |
| 🟡 Medium | 7 |
| 🟢 Low | 4 |

**Overall Health Score**: 62/100

---

## Critical Findings (Immediate Action Required)

### [CRIT-001] God Object: session_manager.dart is 1,317 lines
- **File**: `lib/core/session/session_manager.dart:1`
- **Category**: Architecture / Quality
- **Issue**: The `SessionManager` class manages device discovery, WebSocket server, WebSocket client, audio engine, file transfer, foreground service, event sourcing, context management, Firebase analytics, and 6 StreamControllers. This violates the Single Responsibility Principle and makes the file impossible to reason about or test effectively.
- **Impact**: Any change risks regressions across unrelated subsystems. Hot-reload times are slow. New developers cannot onboard efficiently.
- **Suggestion**: Split into focused managers:
  ```dart
  // session_manager.dart becomes a coordinator only
  class SessionManager {
    final DiscoveryManager _discovery;
    final ConnectionManager _connection; // wraps server/client
    final PlaybackManager _playback;     // wraps audio engine + file transfer
    final ContextManager _context;
  }
  ```

### [CRIT-002] Slave-side file transfer holds entire file in memory
- **File**: `lib/core/services/file_transfer_service.dart:269`
- **Category**: Memory / Performance
- **Issue**: `_IncomingTransfer.chunks` stores every chunk as a separate `Uint8List` in a `List<Uint8List>`. For a 50MB song file at 64KB chunks, this creates ~800 separate allocations. The chunks list grows unbounded and is only combined + freed at `_handleTransferEnd`. If a transfer is interrupted, the memory is leaked until the 30-second cleanup timer fires.
- **Impact**: OOM crashes on low-end Android devices with large audio files. Memory fragmentation from hundreds of small allocations.
- **Suggestion**: Write chunks directly to a file using `RandomAccessFile` instead of buffering in memory:
  ```dart
  // Instead of List<Uint8List> chunks:
  File _tempFile = File('${_tempDir!.path}/$transferId.tmp');
  RandomAccessFile raf = await _tempFile.open(mode: FileMode.write);
  
  // On chunk received:
  await raf.setPosition(chunkIndex * chunkSize);
  await raf.writeFrom(data);
  
  // On transfer end:
  await raf.close();
  await _tempFile.rename('${_tempDir!.path}/$fileName');
  ```

### [CRIT-003] Position updates cause excessive BLoC emits and widget rebuilds
- **File**: `lib/core/audio/audio_engine.dart:93` → `lib/features/player/bloc/player_bloc.dart:330`
- **Category**: Performance / Widget Rebuilds
- **Issue**: `AudioEngine` creates a `Timer.periodic` at `AppConstants.positionUpdateIntervalMs` (typically 250ms). Each tick fires `_positionController.add()`, which the `PlayerBloc` receives and emits a new `PlayerState` via `PositionUpdated`. The `PlayerState` has 14 fields in its `props` list, so every position update triggers a full Equatable comparison of the entire state tree. The `BlocBuilder` in `player_screen.dart:47` rebuilds the entire player UI 4 times per second.
- **Impact**: 4 full widget tree rebuilds/second on the player screen. On low-end devices this causes dropped frames and jank during playback.
- **Suggestion**: Use a `ValueListenableBuilder` or `StreamBuilder` for the position slider separately, instead of routing position through BLoC state:
  ```dart
  // In player_screen.dart, isolate position updates:
  StreamBuilder<Duration>(
    stream: sessionManager.audioEngine.positionStream,
    builder: (context, snapshot) {
      return PositionSlider(
        position: snapshot.data ?? Duration.zero,
        duration: state.duration,
        onSeek: (p) => context.read<PlayerBloc>().add(SeekRequested(p)),
      );
    },
  ),
  ```

### [CRIT-004] Connected devices timer emits every 2 seconds with O(N) scan
- **File**: `lib/core/session/session_manager.dart:312-315`
- **Category**: Performance
- **Issue**: `_connectedDevicesTimer` fires every 2 seconds, calling `_emitConnectedDevices()` which calls `getConnectedDevices()`. This method iterates `_server!.slaves.values` and for each slave performs a linear `firstWhere` scan on `_currentSession?.slaves` — an O(N*M) operation. With 5 slaves, this is 25 comparisons every 2 seconds, each creating new `ConnectedDeviceInfo` objects.
- **Impact**: Unnecessary object allocation and CPU usage. The `connectedDevicesStream` fires 30 times/minute even when nothing has changed, causing downstream BLoC emits and widget rebuilds.
- **Suggestion**: Only emit when the set of connected devices actually changes:
  ```dart
  List<ConnectedDeviceInfo>? _lastEmittedDevices;
  
  void _emitConnectedDevices() {
    if (_role != DeviceRole.host || _server == null) return;
    final devices = getConnectedDevices();
    // Only emit if devices actually changed
    if (_lastEmittedDevices == null || 
        !_listsEqual(_lastEmittedDevices!, devices)) {
      _connectedDevicesController.add(devices);
      _lastEmittedDevices = devices;
    }
  }
  ```

---

## High Priority Findings

### [HIGH-001] TCP subnet scan creates 254 concurrent socket connections
- **File**: `lib/core/network/device_discovery.dart:696-711`
- **Category**: Performance / Resource Exhaustion
- **Issue**: `scanSubnet()` iterates IPs `.1` through `.254` and creates a `Socket.connect()` for each, batching them in groups of `AppConstants.tcpScanBatchSize`. Even with batching, this creates dozens of concurrent socket connections on a single device. Each failed connection attempt allocates OS-level socket resources.
- **Impact**: On networks with many hosts, this can exhaust available ephemeral ports or cause the OS to rate-limit connection attempts. Battery drain from rapid network activity.
- **Suggestion**: Reduce batch size to 10-20 and increase inter-batch delay. Consider using UDP broadcast instead of TCP probing:
  ```dart
  const batchSize = 20; // was likely higher
  for (int batch = 0; batch < 254; batch += batchSize) {
    // ... probe batch ...
    await Future.delayed(const Duration(milliseconds: 500)); // was 100ms
  }
  ```

### [HIGH-002] PlayerBloc subscribes to 9 streams simultaneously
- **File**: `lib/features/player/bloc/player_bloc.dart:282-295`
- **Category**: Memory / Architecture
- **Issue**: The `PlayerBloc` constructor creates 9 `StreamSubscription` instances: `_stateSub`, `_sessionStateSub`, `_positionSub`, `_clientEventSub`, `_syncQualitySub`, `_fileTransferSub`, `_connectedDevicesSub`, `_allGuestsReadySub`, plus the internal `on<_SyncingFileProgress>` and `on<_SyncingFilesChanged` handlers. Every subscription fires events that go through the BLoC event queue, creating backpressure under load.
- **Impact**: When multiple streams fire simultaneously (e.g., position update + sync quality + file transfer progress), the BLoC event queue backs up, causing delayed UI updates. Memory overhead from 9 active subscriptions even when the device is in idle state.
- **Suggestion**: Use lazy subscription — only subscribe to streams when the relevant feature is active. For example, only subscribe to `connectedDevicesStream` when the user is on the host dashboard.

### [HIGH-003] `_handlePlayCommand` has a blocking sync call before time-critical playback
- **File**: `lib/core/session/session_manager.dart:1078-1085`
- **Category**: Performance / Real-Time
- **Issue**: In `_handlePlayCommand`, right before the time-sensitive playback scheduling, the code calls `await _client!.synchronize()` — a full clock sync that takes 2-4 seconds (8 sync exchanges × 100ms delay + network RTT). This blocks the entire playback pipeline and can cause the scheduled `startAtMs` to become stale.
- **Impact**: The clock offset computed before the sync is more accurate than the one computed after, because the sync itself takes seconds. Playback starts later than intended, increasing audio desync between devices.
- **Suggestion**: Remove the pre-play sync and rely on the auto-calibration timer. If a fresh offset is needed, use a single lightweight sync exchange instead of a full calibration:
  ```dart
  // Instead of full synchronize():
  // Do a single NTP exchange
  final sample = await _client!.performSingleSync();
  final freshOffset = sample.offset;
  ```

### [HIGH-004] `PlayerState` Equatable comparison includes `connectedDevices` list
- **File**: `lib/features/player/bloc/player_bloc.dart:247-262`
- **Category**: Performance
- **Issue**: `PlayerState.props` includes `connectedDevices` (a `List<ConnectedDeviceInfo>`). Equatable does deep equality comparison on lists, which is O(N) per comparison. Since `connectedDevices` is emitted every 2 seconds (CRIT-004), this triggers a full list comparison on every BLoC state emission — even when only the position changed.
- **Impact**: Every position update (250ms) triggers a list comparison of connected devices, multiplying the cost of each state change.
- **Suggestion**: Remove `connectedDevices` from `PlayerState.props` and use a separate stream or BLoC for device state, or use an identity-based comparison:
  ```dart
  // Use a wrapper with identity comparison
  class ConnectedDevicesSnapshot {
    final List<ConnectedDeviceInfo> devices;
    final int hashCode; // computed once
    // operator== compares hashCode only
  }
  ```

### [HIGH-005] `broadcastBinary` iterates slaves sequentially without concurrency control
- **File**: `lib/core/network/websocket_server.dart:250-258`
- **Category**: Performance
- **Issue**: `broadcastBinary()` iterates through all slaves and calls `slave.socket.add(data)` sequentially. For large binary chunks (64KB), if one slave's socket buffer is full, it blocks the entire broadcast, delaying delivery to faster slaves.
- **Impact**: The slowest slave determines the broadcast speed for all slaves. This directly impacts audio synchronization quality.
- **Suggestion**: Use `Future.wait` with error isolation:
  ```dart
  Future<void> broadcastBinary(List<int> data) async {
    final slavesCopy = [..._slaves.values];
    await Future.wait(
      slavesCopy.map((slave) async {
        try {
          slave.socket.add(data);
        } catch (e) {
          _logger.e('Error sending binary to ${slave.deviceName}: $e');
        }
      }),
    );
  }
  ```

### [HIGH-006] `fileTransfer.sendFile` loads entire file into memory via `buffer`
- **File**: `lib/core/services/file_transfer_service.dart:148`
- **Category**: Memory
- **Issue**: The `sendFile` method uses `buffer = <int>[]` and `buffer.addAll(data)` to accumulate file data before chunking. For a 50MB file, this means the entire file is loaded into a Dart `List<int>` (which has significant per-element overhead — ~28 bytes per int on 64-bit). A 50MB file becomes ~1.4GB in memory.
- **Impact**: Host device can OOM when sending large files. The `file.openRead()` already streams from disk, so the buffer is unnecessary.
- **Suggestion**: Process chunks directly from the stream without accumulating:
  ```dart
  int offset = 0;
  int chunkIndex = 0;
  List<int> buffer = [];
  
  await for (final data in reader) {
    buffer.addAll(data);
    while (buffer.length >= chunkSize) {
      final chunk = buffer.sublist(0, chunkSize);
      buffer.removeRange(0, chunkSize);
      // send chunk...
    }
  }
  // The buffer here only holds at most chunkSize + 1 stream chunk,
  // not the entire file. This is actually acceptable IF stream chunks
  // are small. But addAll on List<int> is still O(N) per call.
  // Better: use BytesBuilder or process with fixed-size reads.
  ```

---

## Medium Priority Findings

### [MED-001] `_queryMdnsServices` performs sequential nested mDNS lookups
- **File**: `lib/core/network/device_discovery.dart:570-638`
- **Category**: Performance
- **Issue**: For each PTR record found, the code does a sequential `await for` on SRV records, then within that does another `await for` on A records, then another `await for` on TXT records. This serial chain means discovering 3 devices requires 9 sequential network lookups instead of parallelizing them.
- **Impact**: Device discovery takes 3-5 seconds instead of <1 second. Users perceive the app as slow to find devices.
- **Suggestion**: Use `Future.wait` to parallelize the SRV + A + TXT lookups for each discovered PTR.

### [MED-002] `DiscoveryBloc` position handler fires on every position tick
- **File**: `lib/features/discovery/bloc/discovery_bloc.dart:396-406`
- **Category**: Performance
- **Issue**: `_handlePositionChange` fires every 250ms and dispatches a `PlaybackStateChanged` event to the BLoC. This event includes the full `state.currentTrack`, `state.isPlaying`, and `state.duration` — all of which are unchanged. The BLoC then emits a new `DiscoveryState` with full Equatable comparison.
- **Impact**: In the joined state, the DiscoveryBloc emits 4 new states per second, each triggering a rebuild of the entire `_buildJoinedView`.
- **Suggestion**: Throttle position events or use a separate `ValueNotifier` for the progress bar in the joined view.

### [MED-003] `getConnectedDevices` creates new objects on every call
- **File**: `lib/core/session/session_manager.dart:160-186`
- **Category**: Performance
- **Issue**: Every call to `getConnectedDevices()` creates new `ConnectedDeviceInfo` instances for every slave. Called every 2 seconds by the timer, this generates 30 new objects/minute per slave. Combined with CRIT-004, these objects are immediately compared and discarded.
- **Impact**: GC pressure increases proportionally with session duration and slave count.
- **Suggestion**: Cache the `ConnectedDeviceInfo` objects and only recreate them when slave state actually changes (isSynced flag, clockOffsetMs).

### [MED-004] `PlayerScreen` reads `SessionManager` inside `BlocBuilder`
- **File**: `lib/features/player/ui/player_screen.dart:49`
- **Category**: Performance
- **Issue**: `final sessionManager = context.read<SessionManager>()` is called inside the `BlocBuilder` builder callback. While `context.read` is fast, this line executes on every BLoC state emission (including position updates at 250ms intervals).
- **Impact**: Minor but cumulative overhead. More importantly, it couples the UI rebuild frequency to the BLoC emission frequency.
- **Suggestion**: Read the session manager outside the builder or use `context.select` for fine-grained rebuild control.

### [MED-005] Queue animation in `_showQueueSheet` uses per-item delay
- **File**: `lib/features/player/ui/player_screen.dart:304-309`
- **Category**: Performance
- **Issue**: Each queue item has `.animate().slideX(delay: (index * 50).ms)`. For a playlist of 100 tracks, the last item's animation is delayed by 5 seconds. The `flutter_animate` library also creates animation controllers for each item.
- **Impact**: Memory leak risk from orphaned animation controllers if the sheet is dismissed before animations complete. Jank on long playlists.
- **Suggestion**: Cap the delay and use `ListView.builder` with `itemExtent` for better performance:
  ```dart
  delay: (index * 50).clamp(0, 500).ms, // cap at 500ms
  ```

### [MED-006] `EventStore` double-encodes JSON for event data
- **File**: `lib/core/context/event_store.dart:44-48`
- **Category**: Performance
- **Issue**: `SessionEvent.toMap()` calls `jsonEncode(data)` to store the data field as a JSON string in SQLite. When reading back, `SessionEvent.fromMap()` calls `jsonDecode(raw)` to parse it. This means the data is JSON-encoded twice (once by the app, once by sqflite's internal handling) and decoded twice.
- **Impact**: Unnecessary CPU overhead on every event write/read. For high-frequency events (e.g., if position tracking were added), this becomes significant.
- **Suggestion**: Store the data as a TEXT column with direct JSON, or use sqflite's built-in JSON support.

### [MED-007] `_checkAllGuestsReady` iterates all slaves on every server event
- **File**: `lib/core/session/session_manager.dart:1254-1262`
- **Category**: Performance
- **Issue**: `_checkAllGuestsReady()` is called on `deviceConnected`, `deviceDisconnected`, and `deviceReady` events. It iterates all slaves and checks `s.isSynced`. While this is O(N), it's called from a hot path (server event handler) and the result is emitted even when the value hasn't changed.
- **Impact**: Unnecessary stream emissions cause the `PlayerBloc` to emit new states, triggering widget rebuilds.
- **Suggestion**: Track the previous `allGuestsReady` value and only emit when it changes.

---

## Low Priority Findings

### [LOW-001] `DeviceDiscovery.getLocalIp` has 17 hardcoded virtual IP prefixes
- **File**: `lib/core/network/device_discovery.dart:180-195`
- **Category**: Quality
- **Issue**: The `isVirtualIp` function has 17 `startsWith` checks hardcoded. This is a maintenance burden and doesn't cover all virtual adapter scenarios.
- **Impact**: Minimal performance impact, but the function runs on every discovery scan and publish operation.
- **Suggestion**: Use a `Set<String>` of known virtual subnets for O(1) lookup, or use a regex pattern.

### [LOW-002] `PlayerBloc._onToggleShuffle` reads `state.playlist.tracks.length` then calls `state.playlist.shuffle()`
- **File**: `lib/features/player/bloc/player_bloc.dart:951-982`
- **Category**: Quality
- **Issue**: The shuffle handler creates a new shuffled playlist, then searches for the current track by ID in the new list (`indexWhere`), and emits state. For large playlists, this is O(N) search after O(N) shuffle.
- **Impact**: Negligible for typical playlist sizes (<100 tracks), but could be noticeable for very large libraries.

### [LOW-003] `HostDashboardCard` rebuilds entire device list on every state change
- **File**: `lib/features/player/ui/host_dashboard.dart:20-48`
- **Category**: Performance
- **Issue**: The `BlocBuilder<PlayerBloc, PlayerState>` wraps the entire dashboard including the device list. Any change to `PlayerState` (position, volume, sync quality) triggers a rebuild of all `_DeviceTile` widgets.
- **Impact**: Unnecessary widget rebuilds. Each `_DeviceTile` has multiple `Text` widgets and icon containers.
- **Suggestion**: Use `BlocSelector` to only rebuild when `connectedDevices` or `allGuestsReady` changes:
  ```dart
  BlocSelector<PlayerBloc, PlayerState, ({List<ConnectedDeviceInfo> devices, bool allGuestsReady})>(
    selector: (state) => (devices: state.connectedDevices, allGuestsReady: state.allGuestsReady),
    builder: (context, selected) { ... }
  )
  ```

### [LOW-004] `main.dart` generates a new UUID on every app launch
- **File**: `lib/main.dart:57`
- **Category**: Quality
- **Issue**: `final deviceId = const Uuid().v4()` generates a new device ID on every launch. This means the device appears as a "new" device to other hosts each time the app restarts, preventing any device-level caching or history.
- **Impact**: Not a performance issue per se, but causes unnecessary re-discovery and prevents any device-level optimizations.
- **Suggestion**: Persist the device ID in `SharedPreferences` and reuse it across launches.

---

## Metrics Summary

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Files analyzed | 15 | - | ℹ️ |
| Lines of code | ~6,000 | - | ℹ️ |
| Largest file | session_manager.dart (1,317 lines) | < 300 | ❌ |
| Avg function length | ~15 lines | < 30 | ✅ |
| Stream subscriptions in PlayerBloc | 9 | < 5 | ⚠️ |
| Timer.periodic instances | 6 | < 4 | ⚠️ |
| BLoC state emissions/sec (idle) | ~4 | < 1 | ❌ |
| Memory model for file transfer | In-memory buffer | Streaming | ❌ |
| Test coverage (est.) | ~40% | > 80% | ⚠️ |

---

## Recommended Action Plan

### Sprint 1 (Immediate - Week 1)
1. **CRIT-002**: Switch file transfer to disk-backed streaming (RandomAccessFile)
2. **CRIT-003**: Decouple position updates from BLoC state — use direct StreamBuilder
3. **CRIT-004**: Add change detection to `_emitConnectedDevices` to reduce timer emissions
4. **HIGH-006**: Fix host-side file buffer to avoid loading entire file into `List<int>`

### Sprint 2 (Short-term - Week 2-3)
1. **HIGH-001**: Reduce TCP scan batch size and increase delay
2. **HIGH-003**: Remove blocking pre-play sync from `_handlePlayCommand`
3. **HIGH-004**: Remove `connectedDevices` from `PlayerState.props`
4. **HIGH-005**: Parallelize `broadcastBinary` with `Future.wait`
5. **MED-002**: Throttle position events in DiscoveryBloc

### Sprint 3 (Medium-term - Month 1-2)
1. **CRIT-001**: Refactor `SessionManager` into focused sub-managers
2. **HIGH-002**: Implement lazy stream subscriptions in PlayerBloc
3. **MED-001**: Parallelize mDNS lookups
4. **MED-003**: Cache `ConnectedDeviceInfo` objects
5. **LOW-003**: Use `BlocSelector` in HostDashboardCard

### Backlog
- LOW-001: Refactor virtual IP detection
- LOW-002: Optimize shuffle for large playlists
- LOW-004: Persist device ID across launches
- MED-006: Eliminate double JSON encoding in EventStore
- MED-007: Add change detection to `_checkAllGuestsReady`
- MED-005: Cap queue animation delays

---

## Appendix

### Files Analyzed
- `lib/main.dart` (386 lines)
- `lib/core/session/session_manager.dart` (1,317 lines)
- `lib/core/audio/audio_engine.dart` (337 lines)
- `lib/core/network/websocket_client.dart` (666 lines)
- `lib/core/network/websocket_server.dart` (590 lines)
- `lib/core/network/device_discovery.dart` (779 lines)
- `lib/core/network/clock_sync.dart` (412 lines)
- `lib/core/context/event_store.dart` (286 lines)
- `lib/core/context/context_manager.dart` (180 lines)
- `lib/core/services/file_transfer_service.dart` (492 lines)
- `lib/core/models/playlist.dart` (177 lines)
- `lib/features/player/bloc/player_bloc.dart` (1,072 lines)
- `lib/features/player/ui/player_screen.dart` (608 lines)
- `lib/features/player/ui/host_dashboard.dart` (404 lines)
- `lib/features/player/ui/position_slider.dart` (89 lines)
- `lib/features/discovery/ui/discovery_screen.dart` (1,200 lines)
- `lib/features/discovery/bloc/discovery_bloc.dart` (691 lines)

### Tools & Checks Performed
- Static analysis of async/await patterns
- Stream subscription lifecycle audit
- Memory allocation pattern review
- Widget rebuild chain analysis
- Timer and periodic task inventory
- Equatable comparison cost analysis
- Network broadcast pattern review
- File I/O streaming vs buffering audit
