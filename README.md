# 🎵 MusyncMIMO

**Synchronize music playback across multiple devices on the same Wi-Fi network.**

Turn any collection of phones, tablets, or speakers into a synchronized multi-room audio system — no internet required.

[![Flutter](https://img.shields.io/badge/Flutter-3.27-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.6-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-48%2F48-passing-brightgreen.svg)](musync_app/test/)
[![Version](https://img.shields.io/badge/Version-0.1.11-blue.svg)](CHANGELOG.md)

---

## ✨ Features

- **Multi-device sync** — Play music simultaneously on up to 9 devices (1 host + 8 slaves)
- **NTP-like clock sync** — Achieves ±10-30ms accuracy over Wi-Fi
- **Queue / playlist** — Add multiple tracks, skip next/prev, auto-advance
- **Local file playback** — Pick any audio file from your device
- **URL streaming** — Play audio from any direct URL
- **mDNS discovery** — Real mDNS (multicast DNS) + TCP subnet fallback
- **Auto-reconnection** — Seamless recovery from network hiccups
- **Background playback** — Android foreground service keeps sessions alive
- **File transfer** — Host automatically shares local files with slaves
- **Runtime permissions** — Android 13+ (NEARBY_WIFI_DEVICES, READ_MEDIA_AUDIO)
- **Settings** — Theme, device name, default volume, cache management

---

## 📦 Builds

| Platform | Chemin | Statut |
|----------|--------|--------|
| **Android** | `musync_app/build/app/outputs/flutter-apk/app-debug.apk` | ✅ v0.1.11 |
| **iOS** | Build via Xcode (`flutter build ios`) | ⚠️ Nécessite macOS |
| **Windows** | `musync_app/build/windows/x64/Runner/Debug/` | ✅ v0.1.11 |
| **macOS** | Build via Xcode (`flutter build macos`) | ⚠️ Nécessite macOS |

> **Note** : Les fichiers binaires ne sont pas inclus dans le dépôt GitHub (trop volumineux).
> Pour obtenir un build, compilez le projet (voir [Tuto pour les nuls](#-tuto-pour-les-nuls) ci-dessous).

---

## 🏗️ Architecture

```
MusyncMIMO/
├── musync_app/
│   ├── lib/
│   │   ├── core/
│   │   │   ├── models/           # DeviceInfo, AudioSession, ProtocolMessage, Playlist
│   │   │   ├── network/          # ClockSync, WebSocket, mDNS discovery
│   │   │   ├── audio/            # AudioEngine (just_audio wrapper)
│   │   │   ├── session/          # SessionManager (orchestrator)
│   │   │   └── services/         # Firebase, ForegroundService, FileTransfer, Permissions
│   │   ├── features/
│   │   │   ├── discovery/        # Device discovery UI + BLoC
│   │   │   ├── player/           # Audio player UI + BLoC (queue, skip)
│   │   │   └── settings/         # Settings screen
│   │   └── main.dart
│   ├── test/                     # Unit & BLoC tests (48 tests)
│   ├── android/                  # Android config + ForegroundService
│   ├── ios/                      # iOS config
│   ├── windows/                  # Windows desktop config
│   └── macos/                    # macOS desktop config
├── CHANGELOG.md                  # Version history
├── TASKS_BACKLOG.md              # Remaining tasks
└── README.md                     # This file
```

---

## 📖 Tuto pour les nuls

> **Objectif** : Installer et lancer MusyncMIMO sur votre appareil, même si vous n'avez jamais touché à Flutter.

### Prérequis communs

Avant tout, installez **Git** pour télécharger le code :
- **Windows** : [git-scm.com](https://git-scm.com) → télécharger → Next/Next/Finish
- **Mac** : ouvrez le Terminal, tapez `git --version`, macOS proposera l'installation automatique

Ensuite, clonez le projet :
```bash
git clone https://github.com/mclinki/Musync.git
cd Musync/musync_app
```

---

### 🤖 Android

#### Option A — Compiler l'APK (recommandé)

**Étape 1 : Installer Flutter**

1. Téléchargez Flutter : [docs.flutter.dev/get-started/install/windows/android](https://docs.flutter.dev/get-started/install/windows/android)
2. Dézippez le dossier `flutter` dans `C:\` (Windows) ou `~/` (Mac/Linux)
3. Ajoutez Flutter au PATH :
   - **Windows** : Paramètres → Variables d'environnement → PATH → Ajouter `C:\flutter\bin`
   - **Mac/Linux** : ajoutez `export PATH="$HOME/flutter/bin:$PATH"` dans `~/.bashrc` ou `~/.zshrc`
4. Vérifiez : ouvrez un terminal et tapez `flutter doctor`
   - Résolvez les erreurs affichées (Android SDK, etc.)

**Étape 2 : Installer Android Studio**

1. Téléchargez [Android Studio](https://developer.android.com/studio)
2. Installez-le, puis lancez-le
3. Allez dans **More Actions → SDK Manager** :
   - Onglet **SDK Platforms** : cochez **Android 14 (API 34)**
   - Onglet **SDK Tools** : cochez **Android SDK Command-line Tools**
4. Acceptez les licences : `flutter doctor --android-licenses` (tapez `y` pour chaque)

**Étape 3 : Brancher votre téléphone**

1. Sur votre Android : **Paramètres → À propos → Appuyez 7 fois sur "Numéro de build"** (mode développeur)
2. Retour : **Paramètres → Options développeur → Activer le débogage USB**
3. Branchez le téléphone en USB, autorisez le débogage sur l'écran

**Étape 4 : Compiler et installer**

```bash
cd Musync/musync_app
flutter pub get
flutter run
```

> L'app se lance directement sur votre téléphone.
> Pour générer un APK standalone : `flutter build apk --debug`
> L'APK sera dans `build/app/outputs/flutter-apk/app-debug.apk`

---

### 🍎 iPhone

> ⚠️ **Nécessite un Mac** avec Xcode installé. Impossible sur Windows.

**Étape 1 : Installer Xcode**

1. Ouvrez l'**App Store** sur votre Mac
2. Cherchez **Xcode** → Installer (≈15 Go, patience)
3. Ouvrez Xcode, acceptez la licence
4. Installez les outils en ligne de commande : `sudo xcode-select --install`

**Étape 2 : Installer Flutter**

```bash
# Télécharger Flutter
cd ~/development
git clone https://github.com/flutter/flutter.git -b stable

# Ajouter au PATH
export PATH="$HOME/development/flutter/bin:$PATH"
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zshrc

# Vérifier
flutter doctor
```

**Étape 3 : Ouvrir le projet dans Xcode**

```bash
cd Musync/musync_app
flutter pub get
open ios/Runner.xcworkspace
```

**Étape 4 : Configurer la signature**

1. Dans Xcode : sélectionnez **Runner** dans la barre latérale
2. Onglet **Signing & Capabilities**
3. Sélectionnez votre **Team** (Apple ID personnel gratuit = 7 jours de validité)
4. Changez le **Bundle Identifier** si nécessaire (ex: `com.votrenom.musync`)

**Étape 5 : Lancer sur le iPhone**

1. Branchez votre iPhone en USB
3. Dans Xcode : sélectionnez votre iPhone en haut → ▶️ Play
4. Sur l'iPhone : **Réglages → Général → VPN et gestion de l'appareil** → faire confiance au développeur

> **Astuce** : avec un Apple ID gratuit, l'app expire après 7 jours. Pour un usage prolongé, un compte développeur Apple (99$/an) est nécessaire.

---

### 🪟 Windows

**Étape 1 : Installer Flutter**

1. Téléchargez Flutter : [docs.flutter.dev/get-started/install/windows/desktop](https://docs.flutter.dev/get-started/install/windows/desktop)
2. Dézippez dans `C:\flutter`
3. Ajoutez `C:\flutter\bin` au PATH (Paramètres système)
4. Vérifiez : `flutter doctor`

**Étape 2 : Activer le support Windows desktop**

```bash
flutter config --enable-windows-desktop
```

**Étape 3 : Installer Visual Studio**

1. Téléchargez [Visual Studio Community](https://visualstudio.microsoft.com/fr/) (gratuit)
2. Pendant l'installation, cochez **Développement desktop en C++**
3. Redémarrez le PC

**Étape 4 : Compiler et lancer**

```bash
cd Musync/musync_app
flutter pub get
flutter run -d windows
```

> Pour générer un exécutable standalone :
> ```bash
> flutter build windows
> ```
> Le binaire sera dans `build/windows/x64/runner/Release/`

---

### 🍏 macOS

**Étape 1 : Installer Xcode**

1. App Store → **Xcode** → Installer
2. Terminal : `sudo xcode-select --install`
3. Accepter la licence : `sudo xcodebuild -license accept`

**Étape 2 : Installer Flutter**

```bash
cd ~/development
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$HOME/development/flutter/bin:$PATH"
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zshrc
flutter doctor
```

**Étape 3 : Activer le support macOS desktop**

```bash
flutter config --enable-macos-desktop
```

**Étape 4 : Compiler et lancer**

```bash
cd Musync/musync_app
flutter pub get
flutter run -d macos
```

> Pour générer une app `.app` :
> ```bash
> flutter build macos
> ```
> L'app sera dans `build/macos/Build/Products/Release/musync_mimo.app`

---

### 🎉 Utilisation

1. **Lancez l'app** sur au moins 2 appareils connectés au **même Wi-Fi**
2. Sur l'appareil **hôte** : appuyez sur **"Créer ou rejoindre un groupe"** → l'app scanne et attend
3. Sur l'appareil **invité** : appuyez sur **"Créer ou rejoindre un groupe"** → l'hôte apparaît → appuyez dessus
4. Sur l'hôte : chargez un fichier audio → la musique se lance **synchronisée** sur tous les appareils !

---

## 🚀 Quick Start (développeurs)

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
| **Platform** | Android / iOS / Windows / macOS |

---

## 📊 Performance

| Metric | Target | Status |
|--------|--------|--------|
| Clock skew | < 30ms | ✅ 5-25ms on Wi-Fi 5GHz |
| Command latency | < 500ms | ✅ < 100ms on LAN |
| Discovery time | < 5s | ✅ 2-4s via mDNS |
| Max devices | 9 (1+8) | ✅ Tested |
| Tests | 48/48 | ✅ All passing |

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
- [x] Device discovery (mDNS + TCP fallback)
- [x] Session creation & joining
- [x] Synchronized playback
- [x] Play/pause/seek controls
- [x] Volume control
- [x] Auto-reconnection
- [x] Background playback (Android)
- [x] Queue / playlist support
- [x] Skip next/prev
- [x] Runtime permissions (Android 13+)
- [x] Settings screen
- [x] Windows desktop support

### 🔜 v0.2
- [ ] Per-device volume control
- [ ] Saved groups (Firestore)
- [ ] ID3 metadata display
- [ ] BLoC tests (Discovery)

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
