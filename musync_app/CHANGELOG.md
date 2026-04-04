# Changelog

All notable changes to MusyncMIMO will be documented in this file.

## [0.1.45] - 2026-04-04 — Critical Bug Fixes (10 CRIT + 8 HIGH resolved)

### Critical Fixes
- **C1** — Reconnection permanently blocked after first failure: `_isReconnecting` flag now properly reset in `_doConnect()` catch block
- **C2** — Fire-and-forget async timer callback in reconnect now wrapped in try/catch to prevent isolate crash
- **C3** — Stream subscription leak on failed `joinSession()`: subscription now cancelled on connection failure
- **C4** — Unexpected disconnect handler now fully cleans up timers, foreground service, and playback coordinator state
- **C5** — Session PIN now generated with `Random.secure()` instead of predictable `DateTime.now()`
- **C6** — `_handleReject` now closes socket and resets connection state on join rejection
- **C7** — Client heartbeat now sends `heartbeat()` (ping) instead of `heartbeatAck()` — fixes false timeout disconnects
- **C8** — Race condition on `_server!` force-unwrap: captured to local variable before async operations in `playTrack()` and `resumePlayback()`
- **C9** — Late-compensation seek now clamped to `[0, duration]` to prevent invalid seek positions
- **C10** — Race between `_autoPreloadTrack` and `handlePlayCommand`: added `_isAudioEngineBusy` mutex

### High Priority Fixes
- **H1** — Playback commands now gated behind `_isAuthenticated` flag — no commands processed before welcome message
- **H2** — `_handleError` now cancels `_reconnectTimer` to prevent stale timer firing
- **H3** — `completeError` on already-completed completer now wrapped in try/catch
- **H4** — WebSocket upgrade failure now properly closes the HTTP response
- **H5** — `_checkHeartbeats` now copies slaves list before iteration to prevent `ConcurrentModificationError`
- **H6** — `disconnect()` now checks `_userDisconnected` after async connect to prevent connecting after user requested disconnect
- **H7** — `handlePauseCommand` and `handleSeekCommand` now wrapped in try/catch
- **H8** — File transfer failure on host now logged as warning (slaves will skip silently)

## [0.1.44] - 2026-04-04 — CRIT-002 Fix: Session PIN Authentication

### Bug Fix
- **CRIT-002 (complete)** — Session PIN authentication is now fully wired end-to-end. The `DiscoveryBloc` was calling `joinSession()` without passing the `sessionPin`, causing the host to reject every join attempt with "Invalid session PIN". This fix adds a PIN input dialog in the UI and threads the PIN through the entire join flow.

### Changed
- `JoinSessionRequested` event now accepts optional `sessionPin` parameter
- `DiscoveryScreen` shows a PIN input dialog before joining (both device tap and manual IP entry)
- Host view now displays the session PIN prominently so it can be shared with guests
- Updated 3 tests in `discovery_bloc_test.dart` to include `sessionPin` parameter

## [0.1.39] - 2026-04-04 — HIGH Priority Performance & Architecture Fixes

### Performance
- **HIGH-011** — Position slider decoupled from BLoC state: `PositionSlider` now listens directly to `audioEngine.positionStream` instead of receiving position through BLoC state. Eliminates full widget tree rebuilds at 5Hz (200ms interval). Only the slider rebuilds on position changes
- **HIGH-012** — Connected devices emission now uses change detection: `_emitConnectedDevices()` only emits if the device list actually changed (different IDs). Eliminates unnecessary stream events every 2 seconds

### Architecture
- **HIGH-008** — Law of Demeter fix: `PlayerBloc` now receives `AudioEngine` directly via constructor injection instead of accessing it through `sessionManager.audioEngine`. Reduces coupling, improves testability
- **HIGH-007** — mDNS info leak fixed: TXT records now broadcast only truncated device ID (`id=abcd1234`) and version (`v=0.1.38`) instead of full device_id, device_name, device_type. TCP probe response also minimized. Full device details exchanged via WebSocket after PIN auth

### Changed
- `PositionSlider` API changed: `position` parameter replaced with `positionStream` (Stream<Duration>)
- `PlayerBloc` constructor now requires `audioEngine` parameter
- `DeviceDiscovery` mDNS/TCP responses now return minimal info only

## [0.1.38] - 2026-04-04 — HIGH Priority Security Fixes

### Security
- **HIGH-004** — WebSocket server now binds to local IP instead of `anyIPv4` (0.0.0.0). Prevents exposure on public networks
- **HIGH-005** — Self-signed TLS certificate persisted to disk (`~/.musync_certs/`) across restarts. Enables certificate pinning (CRIT-001) to work reliably
- **HIGH-006** — APK download integrity: SHA-256 hash computed after download (verification prepared, compare against expected hash from GitHub release)
- **HIGH-018** — Version parsing crash fix: `_compareVersions` uses `int.tryParse` instead of `int.parse` to handle non-numeric tags like `0.1.36-beta`
- **MED-011** — Partial APK download cleanup: file deleted on failure

### Changed
- `WebSocketServer` constructor now accepts optional `localIp` parameter
- `SessionManager` passes `_localIp` to `WebSocketServer` on host session start

## [0.1.37] - 2026-04-04 — Critical Security & Architecture Release

### Security
- **CRIT-001** — TLS certificate pinning: `badCertificateCallback` now validates SHA-1 fingerprint when `AppConstants.expectedCertFingerprint` is set (empty = legacy mode with warning)
- **CRIT-002** — Session PIN authentication: WebSocket server generates a 6-digit PIN, clients must provide it to join. Prevents unauthorized devices from joining sessions
- **CRIT-003** — APK share access token: random 32-char token required in URL + server binds to specific local IP instead of `anyIPv4`
- **CRIT-004** — Firebase App Check integration prepared (code added, requires `flutter pub add firebase_app_check` + console setup)
- **HIGH-001** — WebSocket message size validation (1MB max) before JSON decoding to prevent DoS
- **HIGH-002** — Path traversal fix: filename sanitization now uses `.split('/').last` to extract basename before stripping special chars
- **HIGH-003** — File size validation (100MB max) enforced on receiver side in `_handleTransferStart`
- **HIGH-018** — Version parsing crash fix: `_compareVersions` now uses `int.tryParse` instead of `int.parse` to handle non-numeric tags like `0.1.36-beta`

### Architecture
- **CRIT-005** — God Object refactoring: extracted `PlaybackCoordinator` (~380 lines) from `SessionManager` (1317→~900 lines, -32%). Separates playback coordination from session lifecycle
- **CRIT-006** — `_handlePlayCommand` (142 lines, 5+ nesting levels) extracted into dedicated methods within `PlaybackCoordinator`
- **CRIT-008** — File transfer streaming: chunks now written directly to disk via `RandomAccessFile` instead of buffering in memory. Eliminates OOM risk for large files

### Tests
- **CRIT-007** — 48 new tests added across 3 new test files:
  - `playback_coordinator_test.dart` (22 tests) — Host playback, slave commands, file transfer, state management
  - `file_transfer_service_test.dart` (15 tests) — Binary chunk parsing, protocol factories, size constants, TransferProgress
  - `websocket_server_pin_test.dart` (6 tests) — PIN generation, ProtocolMessage join with PIN, AppConstants
  - `websocket_client_test.dart` (5 tests) — Session PIN parameter, cert pinning constants, rejection handling
- **Total tests**: 158 → **206** (+48)

### Changed
- `SessionManager.joinSession()` now accepts optional `sessionPin` parameter
- `SessionManager.sessionPin` getter exposes host's PIN for out-of-band sharing
- `ApkShareService.start()` now requires `localIp` parameter (binds to specific interface)
- `ApkShareService.shareUrl()` now includes access token in URL
- `ProtocolMessage.join()` factory now accepts optional `sessionPin` parameter

## [0.1.36] - 2026-04-03 — Build Fix + Pure Dart ID3

### Changed
- **REPLACED** `flutter_media_metadata` (abandoned, native code, build broken) → `audio_metadata_reader` (pure Dart, cross-platform, actively maintained)
- No more local cache patches needed — builds cleanly on any machine
- APK release: 58.6MB (down from 163MB debug)

## [0.1.35] - 2026-04-03 — Audit & Security Release

### Added
- **AUDIT** — Full codebase audit completed (38 files, ~8,500 lines). Score: 62/100
- **SECURITY** — WebSocket message size validation (1MB max) to prevent OOM attacks
- **SECURITY** — File name sanitization in file transfer service (path traversal prevention)
- **SECURITY** — `.gitignore` updated to exclude `firebase_options.dart`
- **SECURITY** — `maxFileSizeBytes` (100MB) and `maxMessageSizeBytes` (1MB) constants added
- **DRY** — `extractFileName()` utility function replaces 8 duplicated occurrences across 6 files
- **README** — Security section added with Firebase setup instructions
- **AUDIT_REPORT.md** — Full audit report with findings and action plan

### Fixed
- **DRY** — `path.split('/').last.split('\\').last` extracted to `extractFileName()` in `core/utils/format.dart`
- **SECURITY** — File transfer now sanitizes filenames (replaces `./\` and non-alphanumeric chars)
- **SECURITY** — ProtocolMessage.decode rejects messages > 1MB

## [0.1.34] - 2026-04-03

### Added
- **P2 3.9** — Settings avancés : délai de lecture personnalisable (1-10s, slider) + toggle auto-rejoin dernière session. Persistance SharedPreferences.
- **P2 4.6** — Renommer la session : bouton edit dans le host dashboard, dialog avec TextField pré-rempli, `sessionManager.renameSession()`.
- **P2 6.2** — Buffering adaptatif : compensation automatique du jitter réseau dans `broadcastPlay`. Si jitter > 5ms, ajoute 2× le jitter au délai de lecture.

### Fixed
- **P2 3.9** — Handlers `PlayDelayChanged` et `AutoRejoinToggled` ajoutés au SettingsBloc (events/state existaient mais pas les handlers).

## [0.1.32] - 2026-04-03

### Fixed
- **CRASH-10** : `InheritedElement.debugDeactivated` (47 events, 7 users) — `_GuestJoinNotifier` stream subscription jamais annulé dans `dispose()`. Fix : ajout `StreamSubscription` + `cancel()` dans `dispose()` + double guard `mounted` après `context.read<SettingsBloc>()`. Autres guards ajoutés : `discovery_screen.dart` (context.mounted après Navigator.pop), `onboarding_screen.dart` (mounted après SharedPreferences), `groups_screen.dart` (BLoC capturé avant showDialog au lieu de context.read dans callback)

## [0.1.31] - 2026-04-03

### Added
- **P2 5.2** — Contrôle du volume à distance : l'hôte peut maintenant contrôler le volume des slaves via broadcast WebSocket
- **P2 9.2** — Animations de transition entre écrans (slide + fade, 300ms)
- **P2 9.2** — Animations subtiles sur le lecteur : titre (fade + slide up), contrôles (scale au tap), file d'attente (staggered slide-in)

## [0.1.30] - 2026-04-03

### Added
- **P2 3.8** — Notification d'arrivée d'invité : vibration + snack bar quand un invité rejoint la session (paramétrable dans les paramètres)
- **P2 5.9** — Indicateur visuel "Tous prêts" / "Chargement..." dans le host dashboard (déjà présent, consolidé)

### Changed
- **P2 1.7** — Tous les `.withOpacity()` remplacés par `.withValues(alpha: ...)` (déjà fait, vérifié)
- **P2 1.8** — Vérification des `use_key_in_widget_constructors` : aucun widget manquant (déjà conforme)

## [0.1.29] - 2026-04-02

### Fixed
- Corrections de bugs mineurs et améliorations de performance
