# 🎵 MusyncMIMO

**Synchronize music playback across multiple devices on the same Wi-Fi network.**

Turn any collection of phones, tablets, or speakers into a synchronized multi-room audio system — no internet required.

[![Flutter](https://img.shields.io/badge/Flutter-3.27-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.6-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-32%2F32-passing-brightgreen.svg)](musync_app/test/)
[![Version](https://img.shields.io/badge/Version-0.1.1-blue.svg)](CHANGELOG.md)

---

## ✨ Features

- **Multi-device sync** — Play music simultaneously on up to 9 devices (1 host + 8 slaves)
- **NTP-like clock sync** — Achieves ±10-30ms accuracy over Wi-Fi
- **Local file playback** — Pick any audio file from your device
- **URL streaming** — Play audio from any direct URL
- **Auto-discovery** — Devices find each other via TCP subnet scan
- **Auto-reconnection** — Seamless recovery from network hiccups
- **Background playback** — Android foreground service keeps sessions alive
- **File transfer** — Host automatically shares local files with slaves

---

## 📦 Builds

| Platform | Chemin | Statut |
|----------|--------|--------|
| **Android** | `musync_app/build/app/outputs/flutter-apk/app-debug.apk` | ✅ v0.1.1 |
| **iOS** | Build via Xcode (`flutter build ios`) | ⚠️ Nécessite macOS |

---

## 🏗️ Architecture

```
MusyncMIMO/
├── musync_app/
│   ├── lib/
│   │   ├── core/
│   │   │   ├── models/           # DeviceInfo, AudioSession, ProtocolMessage
│   │   │   ├── network/          # ClockSync, WebSocket, mDNS discovery
│   │   │   ├── audio/            # AudioEngine (just_audio wrapper)
│   │   │   ├── session/          # SessionManager (orchestrator)
│   │   │   └── services/         # Firebase, ForegroundService, FileTransfer
│   │   ├── features/
│   │   │   ├── discovery/        # Device discovery UI + BLoC
│   │   │   └── player/           # Audio player UI + BLoC
│   │   └── main.dart
│   ├── test/                     # Unit tests (32 tests)
│   ├── android/                  # Android config + ForegroundService
│   └── ios/                      # iOS config
├── 00-RESUME-EXECUTIF.md         # Executive summary
├── 03-ARCHITECTURE-TECHNIQUE.md  # Technical architecture
├── 05-MVP.md                     # MVP specification
└── RAPPORT_J1.md                 # Day 1 analysis report
```

---

## 🚀 Quick Start

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.27+
- Android Studio / Xcode (for device emulators)
- 2+ devices on the same Wi-Fi network (for real testing)

### Setup

```bash
# Clone the repo
git clone https://github.com/mclinki/Musync.git
cd Musync/musync_app

# Install dependencies
flutter pub get

# Run tests
flutter test

# Run on device
flutter run
```

### Firebase (Optional)

Firebase is optional — the app works without it. To enable:

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add your Android app and download `google-services.json`
3. Place it in `musync_app/android/app/`
4. See [FIREBASE_SETUP.md](musync_app/FIREBASE_SETUP.md) for details

---

## 🎯 How It Works

```
┌─────────────┐                    ┌─────────────┐
│   HOST 📱   │                    │  SLAVE 📱   │
└──────┬──────┘                    └──────┬──────┘
       │                                  │
       │  1. Start WebSocket server       │
       │     (port 7890)                  │
       │                                  │
       │  2. mDNS broadcast               │
       │  ──────────────────────────────► │
       │                                  │
       │  3. Connect via WebSocket        │
       │  ◄────────────────────────────── │
       │                                  │
       │  4. NTP-like clock sync          │
       │  ◄─────────── 8 samples ───────► │
       │                                  │
       │  5. Transfer audio file          │
       │  ──────────────────────────────► │
       │                                  │
       │  6. "Play at time T"             │
       │  ──────────────────────────────► │
       │                                  │
       │                                  │  7. Wait for T
       │         ▼                        │         ▼
       │      🎵 Play!                    │      🎵 Play!
       │                                  │
       └──────────────────────────────────┘
              Synchronized playback!
```

---

## 🔧 Tech Stack

| Layer | Technology |
|-------|------------|
| **Framework** | Flutter 3.27 / Dart 3.6 |
| **State Management** | BLoC (flutter_bloc) |
| **Audio** | just_audio + audio_session |
| **Networking** | WebSocket (web_socket_channel) |
| **Discovery** | mDNS (multicast_dns) + TCP fallback |
| **Backend** | Firebase (optional: Crashlytics, Analytics, Firestore) |
| **Platform** | Android (foreground service) / iOS |

---

## 📊 Performance

| Metric | Target | Status |
|--------|--------|--------|
| Clock skew | < 30ms | ✅ 5-25ms on Wi-Fi 5GHz |
| Command latency | < 500ms | ✅ < 100ms on LAN |
| Discovery time | < 5s | ✅ 2-4s via mDNS |
| Max devices | 9 (1+8) | ✅ Tested |
| Tests | 32/32 | ✅ All passing |

---

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/clock_sync_test.dart

# Static analysis
flutter analyze
```

---

## 📱 Screenshots

| Discovery | Hosting | Player |
|-----------|---------|--------|
| Scan for devices | Share your IP | Play & sync |

---

## 🗺️ Roadmap

### ✅ MVP (v0.1) — Done
- [x] Local file playback
- [x] Device discovery (mDNS)
- [x] Session creation & joining
- [x] Synchronized playback
- [x] Play/pause/seek controls
- [x] Volume control
- [x] Auto-reconnection
- [x] Background playback (Android)

### 🔜 v0.2
- [ ] Per-device volume control
- [ ] Saved groups (Firestore)
- [ ] ID3 metadata display
- [ ] Queue / playlist support

### 🔮 v1.0
- [ ] WSS/TLS encryption
- [ ] Adaptive buffering
- [ ] iOS background audio
- [ ] Cross-network sync (experimental)

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [00-RESUME-EXECUTIF.md](00-RESUME-EXECUTIF.md) | Executive summary |
| [01-HYPOTHESES.md](01-HYPOTHESES.md) | Assumptions & constraints |
| [02-ANALYSE-PRODUIT.md](02-ANALYSE-PRODUIT.md) | Product analysis |
| [03-ARCHITECTURE-TECHNIQUE.md](03-ARCHITECTURE-TECHNIQUE.md) | Technical architecture |
| [04-STACK-RECOMMANDEE.md](04-STACK-RECOMMANDEE.md) | Tech stack rationale |
| [05-MVP.md](05-MVP.md) | MVP specification |
| [06-ROADMAP.md](06-ROADMAP.md) | Development roadmap |
| [07-POINTS-VIGILANCE.md](07-POINTS-VIGILANCE.md) | Known issues & risks |
| [08-RECOMMANDATIONS.md](08-RECOMMANDATIONS.md) | Recommendations |
| [RAPPORT_J1.md](RAPPORT_J1.md) | Day 1 analysis report |

---

## ⚠️ Known Limitations

- **DRM content** — Cannot sync Spotify, Apple Music, etc. (local files & direct URLs only)
- **Bluetooth** — Too much latency for sync (100-300ms)
- **Network** — Wi-Fi only (4G/5G latency too high)
- **iOS background** — Limited by OS (foreground recommended for slaves)

---

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## 👤 Author

**Frade** — [github.com/mclinki](https://github.com/mclinki)

---

## 🙏 Acknowledgments

- [just_audio](https://pub.dev/packages/just_audio) — Excellent audio playback library
- [flutter_bloc](https://pub.dev/packages/flutter_bloc) — Predictable state management
- [multicast_dns](https://pub.dev/packages/multicast_dns) — mDNS/Zeroconf implementation
