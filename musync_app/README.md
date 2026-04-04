# MusyncMIMO

Synchronize music playback across multiple devices on the same Wi-Fi network.

**Version actuelle** : 0.1.46  
**Tests** : 213/213 ✅  
**Plateformes** : Android, Windows (macOS/iOS en préparation)

## Fonctionnalités

- 🎵 **Lecture synchronisée** : Tous les appareils jouent la même musique en même temps (±10-30ms)
- 📱 **Multi-plateforme** : Android ↔ Windows ↔ Android
- 🔍 **Découverte automatique** : mDNS + scan TCP subnet fallback
- 🔐 **Authentification PIN** : Code PIN optionnel pour rejoindre un groupe
- 📡 **Connexion directe** : ws:// par défaut (LAN), wss:// optionnel dans les paramètres
- 📦 **Partage APK** : Serveur HTTP local pour partager l'app
- 🔄 **Mise à jour OTA** : Vérification GitHub Releases intégrée
- 🎛️ **Dashboard hôte** : Latence et qualité de sync en temps réel
- 🔀 **Shuffle & Repeat** : Modes aléatoire et répétition (off/one/all)
- 📋 **Playlist persistante** : Sauvegardée automatiquement via SharedPreferences

## Architecture

```
musync_app/
├── lib/
│   ├── core/
│   │   ├── models/          # Data models (DeviceInfo, AudioSession, ProtocolMessage, Playlist, Group, SessionContext)
│   │   ├── network/         # Clock sync (Kalman), WebSocket server/client, mDNS discovery, device_discovery
│   │   ├── audio/           # Audio engine (just_audio wrapper with sync support)
│   │   ├── session/         # Session manager + PlaybackCoordinator
│   │   ├── context/         # EventStore (SQLite), ContextManager
│   │   └── services/        # Firebase, foreground, file_transfer, permission, apk_share, update, system_volume
│   ├── features/
│   │   ├── discovery/       # Device discovery UI + BLoC
│   │   ├── player/          # Audio player UI + BLoC + host_dashboard
│   │   ├── groups/          # Group management (Firestore)
│   │   ├── settings/        # Settings (theme, device name, volume, TLS toggle, APK share, update)
│   │   └── onboarding/      # First-run tutorial
│   └── main.dart            # App entry point
├── test/                    # 213 unit tests
├── bin/                     # CLI tools (sync analyzer)
├── android/                 # Android config
├── ios/                     # iOS config
└── pubspec.yaml             # Dependencies
```

## Key Components

### ClockSyncEngine
NTP-like synchronization over WebSocket with Kalman filter. Achieves ±10-30ms accuracy on Wi-Fi local.
Adaptive calibration interval (1s-15s) based on network jitter.

### WebSocketServer (Host)
Embedded server that accepts slave connections, handles clock sync, and broadcasts playback commands.
Supports both ws:// (default) and wss:// (optional TLS toggle in settings).

### WebSocketClient (Slave)
Connects to host, performs clock sync, receives and executes playback commands.
Auto-reconnection with exponential backoff (1s → 30s max).

### DeviceDiscovery
mDNS/Zeroconf discovery with TCP subnet scan fallback.

### AudioEngine
Wraps `just_audio` with scheduled playback, drift compensation, and adaptive buffering.

### SessionManager
High-level orchestrator that ties all components together.

### PlaybackCoordinator
Handles playback commands, file transfer, and audio engine coordination.

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

1. **Host** creates a session → starts WebSocket server on port 7890 (ws:// by default)
2. **Slaves** scan for devices via mDNS/TCP → find the host
3. **Slave** connects to host → performs NTP-like clock sync (8 samples, Kalman filter)
4. **Host** selects a track → broadcasts "play at time T" to all slaves
5. **All devices** wait until their synced clock reaches T → start playing simultaneously

## Sync Protocol

```
Host                                    Slave
  │                                       │
  │◄── WS connect ───────────────────────│
  │◄── "join" {device_info, session_pin}─│  (PIN optional)
  │── "welcome" {session_id} ───────────►│
  │                                       │
  │◄──► NTP-like sync (8 samples) ──────►│
  │     (offset + drift, Kalman filter)   │
  │                                       │
  │── "play" {start_at, source} ────────►│
  │                                       │ Load track
  │                                       │ Wait for T
  │                                       │ Play!
```

## Performance Targets

| Metric | Target | Achieved |
|--------|--------|----------|
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
| `basic_utils` | TLS certificate generation |
| `shared_preferences` | Settings persistence |
| `share_plus` | APK link sharing |

## Known Limitations

- **DRM**: Cannot sync Spotify, Apple Music, etc. (files + URLs only)
- **Bluetooth**: Too much latency for sync (100-300ms)
- **iOS background**: Limited by OS (foreground recommended for slaves)
- **Network**: Wi-Fi only (4G/5G latency too high for sync)
- **TLS**: Disabled by default for LAN simplicity. Enable in Settings → Réseau → Chiffrement WebSocket.
