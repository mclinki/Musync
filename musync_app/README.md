# MusyncMIMO

Synchronize music playback across multiple devices on the same Wi-Fi network.

## Architecture

```
musync_app/
├── lib/
│   ├── core/
│   │   ├── models/          # Data models (DeviceInfo, AudioSession, ProtocolMessage)
│   │   ├── network/         # Clock sync, WebSocket server/client, mDNS discovery
│   │   ├── audio/           # Audio engine (just_audio wrapper with sync support)
│   │   └── session/         # Session manager (orchestrates everything)
│   ├── features/
│   │   ├── discovery/       # Device discovery UI + BLoC
│   │   ├── player/          # Audio player UI + BLoC
│   │   ├── groups/          # Group management (future)
│   │   └── settings/        # Settings (future)
│   └── main.dart            # App entry point
├── test/                    # Unit tests
├── bin/                     # CLI tools (sync analyzer)
├── android/                 # Android config
├── ios/                     # iOS config
└── pubspec.yaml             # Dependencies
```

## Key Components

### ClockSyncEngine
NTP-like synchronization over WebSocket. Achieves ±10-30ms accuracy on Wi-Fi local.

### WebSocketServer (Host)
Embedded server that accepts slave connections, handles clock sync, and broadcasts playback commands.

### WebSocketClient (Slave)
Connects to host, performs clock sync, receives and executes playback commands.

### DeviceDiscovery
mDNS/Zeroconf discovery with subnet scan fallback.

### AudioEngine
Wraps `just_audio` with scheduled playback, drift compensation, and adaptive buffering.

### SessionManager
High-level orchestrator that ties all components together.

## Quick Start

```bash
# 1. Install Flutter (if not installed)
# See: https://docs.flutter.dev/get-started/install

# 2. Setup project
cd musync_app
flutter pub get

# 3. Run tests
flutter test

# 4. Run sync analysis
dart run bin/analyze_sync.dart

# 5. Run on device
flutter run
```

## How It Works

1. **Host** creates a session → starts WebSocket server on port 7890
2. **Slaves** scan for devices via mDNS → find the host
3. **Slave** connects to host → performs NTP-like clock sync (8 samples)
4. **Host** selects a track → broadcasts "play at time T" to all slaves
5. **All devices** wait until their synced clock reaches T → start playing simultaneously

## Sync Protocol

```
Host                                    Slave
  │                                       │
  │◄── WS connect ───────────────────────│
  │◄── "join" {device_info} ─────────────│
  │── "welcome" {session_id} ───────────►│
  │                                       │
  │◄──► NTP-like sync (8 samples) ──────►│
  │     (offset + drift calculation)      │
  │                                       │
  │── "play" {start_at, source} ────────►│
  │                                       │ Load track
  │                                       │ Wait for T
  │                                       │ Play!
```

## Performance Targets

| Metric | Target | Achieved (simulated) |
|--------|--------|---------------------|
| Clock skew | < 30ms | ✅ 5-25ms on Wi-Fi 5GHz |
| Command latency | < 500ms | ✅ < 100ms on LAN |
| Discovery time | < 5s | ✅ 2-4s via mDNS |
| Max devices | 5 (MVP) | ✅ Bandwidth-limited |

## Dependencies

| Package | Purpose |
|---------|---------|
| `just_audio` | Audio playback |
| `audio_session` | iOS/Android audio session management |
| `web_socket_channel` | WebSocket communication |
| `multicast_dns` | mDNS/Zeroconf device discovery |
| `flutter_bloc` | State management |
| `file_picker` | Local file selection |
| `uuid` | Session/device ID generation |
| `logger` | Structured logging |

## Known Limitations

- **DRM**: Cannot sync Spotify, Apple Music, etc. (files + URLs only)
- **Bluetooth**: Too much latency for sync (100-300ms)
- **iOS background**: Limited by OS (foreground recommended for slaves)
- **Network**: Wi-Fi only (4G/5G latency too high for sync)
