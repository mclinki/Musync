# MusyncMIMO — Backlog de Tâches

## 🔥 Bugs Crashlytics — v0.1.11 (194 events, 6 users)

> Source : Firebase Crashlytics API — 7 derniers jours (24 mars → 31 mars 2026)

### 🔴 P0 — Critique

- [x] **CRASH-1** : `RenderFlex overflowed by 48 pixels on the bottom`
  - 57 events · 6 users · 17 sessions · **FATAL**
  - Signal : répétitif (10x/user), fresh (2 jours)
  - Fichier : `firebase_crashlytics/src/firebase_crashlytics.dart` → `recordFlutterFatalError`
  - Stack : `RenderFlex` overflow pendant le layout
  - Cause probable : UI qui déborde (texte trop long, écran trop petit)
  - ✅ **FIXÉ** : `player_screen.dart` — `Column` wrappé dans `SingleChildScrollView`
  - ✅ **FIXÉ** : `main.dart` — `HomeScreen` wrappé dans `SingleChildScrollView` + `ConstrainedBox`
  - Lien : [Firebase Console](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/6823bac6cff18a6fb1acad2b89d2c8ac)

- [x] **CRASH-2** : `Duplicate GlobalKeys detected in widget tree`
  - 28 events · 6 users · 11 sessions · **FATAL**
  - Signal : répétitif (5x/user), 81% crash dans 1ère seconde, fresh
  - Fichier : `framework.dart` → `BuildOwner.finalizeTree`
  - Cause probable : widgets recréés avec la même GlobalKey (Overlay, Navigator)
  - ✅ **FIXÉ** : `settings_screen.dart` — `ScaffoldMessenger.showSnackBar()` déplacé dans `addPostFrameCallback` + `context.mounted` check
  - Lien : [Firebase Console](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/8de8c4745ab62af74437b1cc55194c2a)

- [x] **CRASH-3** : `Tried to build dirty widget in the wrong build scope`
  - 51 events · 6 users · 9 sessions · **FATAL**
  - Signal : répétitif (9x/user), 92% crash dans 1ère seconde, fresh
  - Fichier : `framework.dart` → `BuildScope._flushDirtyElements`
  - Cause probable : setState() appelé hors du build scope (async gap)
  - ✅ **FIXÉ** : Même fix que CRASH-2 (même cause racine)
  - Lien : [Firebase Console](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/91602f0e9bc37d08396ed0abdee3a739)

### 🟠 P1 — Important

- [x] **CRASH-4** : `TextEditingController used after being disposed` (×2 issues)
  - Issue A : 30 events · 6 users · 9 sessions — fichier `change_notifier.dart`
  - Issue B : 3 events · 2 users · 1 session — fichier `settings_screen.dart` (hier)
  - **FATAL** · Signal : répétitif, fresh
  - Cause probable : controller.dispose() appelé puis le controller réutilisé après async gap
  - ✅ **FIXÉ** : `settings_screen.dart` — Pattern `safeDispose()` avec flag `disposed` + `PopScope`
  - ✅ **FIXÉ** : `discovery_screen.dart` — Pattern `safeDispose()` + `.then((_) => safeDispose())`
  - Liens : [Issue A](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/e4814d1548ab8659afe1e39de9a13ec3) · [Issue B](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/00e11509c830d5a9e7da3b7ff03949cc)

- [x] **CRASH-5** : `SocketException errno=103 — Software caused connection abort`
  - 7 events · 2 users · 2 sessions · **FATAL**
  - ⚠️ **RÉGRESSÉ** en v0.1.11 (était fermé, rouvert)
  - Fichier : `firebase_service.dart` → `FirebaseService.initialize`
  - Port : 0.0.0.0:7891
  - Cause probable : socket fermé pendant l'init Firebase sur réseau instable
  - ✅ **FIXÉ** : `firebase_service.dart` — Timeout 15s sur `Firebase.initializeApp()` + catch spécifique `errno=103`
  - Lien : [Firebase Console](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/5d50d1c5498da2adf8ddb1219f588b3c)

- [x] **CRASH-6** : `Cannot hit test a render box that has never been laid out`
  - 12 events · 2 users · 2 sessions · **FATAL**
  - Fichier : `box.dart` → `RenderBox.hitTest`
  - Cause probable : ErrorWidget affiché avant d'être layouté (crash en cascade du CRASH-1)
  - ✅ **FIXÉ** : Cascade de CRASH-1 résolu par les `SingleChildScrollView`
  - ⚠️ **RÉSIDUEL** : Erreurs RenderBox encore présentes sur émulateur (autres vues dans `discovery_screen.dart`)
  - Lien : [Firebase Console](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/9842003dd1cf73d0ca4fd4a8cb1bb796)

### 🟡 P2 — Non bloquant

- [ ] **CRASH-7** : `just_audio Connection aborted` (loadPreloaded)
  - 3 events · 1 user · 1 session · **NON_FATAL**
  - Fichier : `just_audio.dart` → `AudioPlayer._load`
  - ✅ **FIXÉ** : Retry logic + timeout 10s + fallback loadTrack
  - Lien : [Firebase Console](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/145c1c46c78706f9c589369bc5e02067)

- [ ] **CRASH-8** : `ANR — slow operations in main thread`
  - 2 events · 1 user · 1 session · **ANR**
  - Cause probable : opération bloquante sur le thread principal
  - ✅ **FIXÉ** : Timeouts sur init (permissions 5s, Firebase 10s, session 10s)
  - Lien : [Firebase Console](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/a67b188e9d38c13f2dc537ba35ae24c0)

- [ ] **CRASH-9** : `mDNS SocketException errno=103` (port 5353)
  - 1 event · 1 user · 1 session · **FATAL**
  - Fichier : `multicast_dns.dart` → `MDnsClient.lookup`
  - ✅ **FIXÉ** : Retry logic (2 tentatives) + catch SocketException
  - Lien : [Firebase Console](https://console.firebase.google.com/project/musync-6e5aa/crashlytics/app/android:com.musync.mimo/issues/2674000b5de0c894cee869a400cd4947)

---

## 🐛 Bugs tests réels (2026-03-31)

### 🟠 P1 — Important

- [x] **BUG-NEW-1** : Hôte ferme le lecteur → nouveau PlayerBloc créé au lieu de retrouver l'état
  - Cause : `PlayerScreen` créait un nouveau `BlocProvider(create: ...)` à chaque navigation
  - ✅ **FIXÉ** : `PlayerBloc` créé au niveau app (`main.dart`) + `PlayerScreen` utilise le bloc existant
  - Fichiers : `main.dart`, `player_screen.dart`

- [x] **BUG-NEW-2** : Les lecteurs ne se resynchronisent pas automatiquement quand ils se décalent
  - Cause : `clock_sync.dart` a un `startAutoCalibration()` mais il n'était jamais appelé
  - ✅ **FIXÉ** : `startAutoCalibration()` appelé après connexion + `stopAutoCalibration()` appelé à la déconnexion
  - Fichiers : `session_manager.dart`, `websocket_client.dart`

- [x] **BUG-NEW-3** : Indicateur de latence ne s'actualise pas
  - Cause : `SyncQualityChanged` émis une seule fois après join, pas périodiquement
  - ✅ **FIXÉ** : Timer périodique (10s) déjà existant + auto-calibration active maintenant les stats à jour
  - Fichier : `session_manager.dart`

- [x] **BUG-NEW-4** : Appareil invité continue de scanner le réseau après connexion → bande passante saturée
  - Cause : `_onJoinSession` n'appelait pas `stopScanning()` après connexion réussie
  - ✅ **FIXÉ** : `await sessionManager.stopScanning()` ajouté dans `_onJoinSession` après succès
  - Fichiers : `discovery_bloc.dart`, `discovery_bloc_test.dart` (mock mis à jour)

---

## 🔍 Issues détectées par analyse code (2026-03-31)

### 🔴 Critical (3)

- [x] **ANALYZE-1** : `audio_engine.dart` — Stream subscription leak + closed controller
  - ✅ **FIXÉ** : `_playerStateSub` stocké et annulé dans `dispose()` + guard `_stateController.isClosed`

- [x] **ANALYZE-2** : `discovery_bloc.dart` — `add()` appelé sur BLoC fermé
  - ✅ **FIXÉ** : Flag `_isClosed` + guard dans `_handleAudioStateChange` et `_handlePositionChange`

- [x] **ANALYZE-3** : `player_screen.dart` — `context.mounted` manquant après `await`
  - ✅ **FIXÉ** : Check `context.mounted` après `FilePicker.platform.pickFiles()`

### 🟠 High (6)

- [x] **ANALYZE-4** : `websocket_client.dart` — Double reconnection scheduling
  - ✅ **FIXÉ** : `_reconnectTimer?.cancel()` dans `_handleDisconnect`

- [x] **ANALYZE-5** : `session_manager.dart` — Controllers ajoutés après `close()`
  - ✅ **FIXÉ** : Guard `_stateController.isClosed` + `_playlistUpdateController.isClosed`

- [x] **ANALYZE-6** : `discovery_screen.dart` — `stop()` non awaited + pas de BLoC routing
  - ✅ **FIXÉ** : Nouveau event `StopPlaybackRequested` + handler dans DiscoveryBloc

- [x] **ANALYZE-7** : `discovery_bloc.dart` — `errorMessage` non cleared on recovery
  - ✅ **FIXÉ** : `errorMessage: null` ajouté aux états `hosting`, `joined`, `playing`, `paused`

- [x] **ANALYZE-8** : `file_transfer_service.dart` — Null check `_tempDir` manquant
  - ✅ **FIXÉ** : Guard `_tempDir == null` + safe casts payload avec `num?` et `String?`

- [x] **ANALYZE-9** : `websocket_client.dart` — `_performSyncExchange` logic error
  - ✅ **FIXÉ** : Cleanup complet du `_syncCompleter` avant création nouveau (même si déjà completed)

### 🟡 Medium (12)

- [x] **ANALYZE-10** : `player_bloc.dart` — Slave skip ne stoppe pas l'audio
  - ✅ **FIXÉ** : `await sessionManager.audioEngine.pause()` avant `emit(loading)`

- [x] **ANALYZE-11** : `discovery_screen.dart` — Bouton "Réessayer" fait "Leave" au lieu de retry
  - ✅ **FIXÉ** : `StartScanning` au lieu de `LeaveSessionRequested`

- [x] **ANALYZE-12** : `file_transfer_service.dart` — Unsafe casts dans `_handleTransferStart`
  - ✅ **FIXÉ** : Safe casts avec `num?` et `String?` + validation payload

- [x] **ANALYZE-18** : `websocket_client.dart` — Unsafe casts dans message handlers
  - ✅ **FIXÉ** : Type check `data is! String` avant decode

- [x] **ANALYZE-19** : `protocol_message.dart` — Cast payload sans validation type
  - ✅ **FIXÉ** : Safe cast avec `Map<String, dynamic>.from(rawPayload)` + `num?`

- [x] **ANALYZE-13** : `file_transfer_service.dart` — Concurrent transfers non supportés
  - ✅ **FIXÉ** : Utilise `_incomingTransfers.values.last` au lieu de `.first`

- [x] **ANALYZE-14** : `clock_sync.dart` — Division by zero potential
  - ✅ **FIXÉ** : Seuil minimum `elapsedSec > 1.0` au lieu de `> 0`

- [x] **ANALYZE-15** : `device_discovery.dart` — RangeError si deviceId < 8 chars
  - ✅ **FIXÉ** : Safe substring avec check `deviceId.length > 8`

- [x] **ANALYZE-20** : `audio_session.dart` — `copyWith` ne peut pas clear `currentTrack`
  - ✅ **FIXÉ** : Paramètre `clearTrack = false` pour permettre le reset

- [x] **ANALYZE-16** : `websocket_server.dart` — ConcurrentModificationError dans `broadcast()`
  - ✅ **FIXÉ** : Copie de `_slaves.values` avant itération

- [x] **ANALYZE-17** : `websocket_server.dart` — Socket non fermé sur heartbeat timeout
  - ✅ **FIXÉ** : `slave.socket.close()` avant `_slaves.remove()`

- [x] **ANALYZE-21** : `settings_bloc.dart` — Pas de try-catch dans `_onThemeChanged`
  - ✅ **FIXÉ** : Try-catch ajouté avec logging Firebase

### 🟢 Low (20)

- [ ] ANALYZE-22 à ANALYZE-41 : Voir rapport d'analyse complet

---

## 🔍 Issues détectées par audit complet (2026-03-31)

### Compatibilité

- [x] **AUDIT-1** : Version mismatch `app_constants.dart` (0.1.11) vs `pubspec.yaml` (0.1.12)
  - ✅ **FIXÉ** : `app_constants.dart` mis à jour à 0.1.12

- [x] **AUDIT-2** : SDK constraint `>=3.2.0` incompatible avec `withValues()` (Flutter 3.27+)
  - ✅ **FIXÉ** : SDK constraint mis à jour `>=3.6.0 <4.0.0`

- [x] **AUDIT-3** : `firebase_options.dart` — Placeholder Windows App ID
  - ✅ **FIXÉ** : Commentaire clarifié (Firebase skip sur Windows)

- [x] **AUDIT-4** : `device_discovery.dart` — mDNS publisher pas skipped sur Windows
  - ✅ **FIXÉ** : `Platform.isWindows` check ajouté dans `_startMdnsPublisher`

- [ ] **AUDIT-5** : `audio_engine.dart` — `AudioSession` class name collision avec package
  - Note: Renommage non effectué (refactoring majeur, faible impact)

### Type Safety

- [x] **AUDIT-6** : `protocol_message.dart` — Unsafe JSON payload cast
  - ✅ **FIXÉ** : Safe cast avec `Map<String, dynamic>.from(rawPayload)`

- [x] **AUDIT-7** : `websocket_client.dart` — Unsafe `data as String` cast
  - ✅ **FIXÉ** : Type check `data is! String` avant decode

- [x] **AUDIT-8** : `websocket_server.dart` — Unsafe `data as String` cast
  - ✅ **FIXÉ** : Type check `data is! String` avant decode

- [x] **AUDIT-9** : `session_manager.dart` — Force-unwrap `_server!` sans null check
  - ✅ **FIXÉ** : Null check `if (_server == null) throw Exception(...)` dans `playTrack`, `pausePlayback`, `resumePlayback`

- [x] **AUDIT-10** : `websocket_client.dart` — Unsafe casts dans `_handleWelcome`, `_handleSyncResponse`
  - ✅ **FIXÉ** : Safe casts avec `String?`, `num?` + null check `_syncT1`

### Dead Code

- [x] **AUDIT-11** : `protocol_message.dart` — Enum values `hello`, `stop`, `audioChunk`, `deviceUpdate` jamais utilisés
  - ✅ **FIXÉ** : 4 valeurs supprimées de l'enum `MessageType`

- [x] **AUDIT-12** : `clock_sync.dart` — `startAutoCalibration()` jamais appelée
  - Note: Gardé (utilisé par `stopAutoCalibration` et `dispose`)

- [x] **AUDIT-13** : `player_bloc.dart` — Events `ResumeRequested` jamais dispatché
  - ✅ **FIXÉ** : Event + handler `_onResume` supprimés

### Tests

- [ ] **AUDIT-14** : Tests manquants pour SessionManager, WebSocketClient, WebSocketServer
  - Note: Nécessite refactoring DI (hors scope actuel)

- [x] **AUDIT-15** : `widget_test.dart` — Placeholder assertion `expect(true, isTrue)`
  - ✅ **FIXÉ** : Tests réels ajoutés (AudioTrack instantiation, JSON serialization)

- [ ] **AUDIT-16** : `discovery_bloc_test.dart` — Streams vides masquent le comportement réel
  - Note: Nécessite mocks streams (hors scope actuel)

---

## Tâches en attente (non bloquantes)

### Sécurité
- [ ] **SÉCURITÉ 1** : Implémenter WebSocket chiffré (wss://) au lieu de ws://
  - Nécessite un certificat TLS ou un mécanisme de chiffrement applicatif
  - Priorité : Moyenne (important pour la production)

- [ ] **SÉCURITÉ 2** : Ajouter authentification entre appareils
  - Token de session partagé lors de la découverte
  - Priorité : Moyenne

### Conception
- [ ] **REDONDANCE 1** : Centraliser la gestion d'état session
  - `SessionManager` et `DiscoveryBloc` dupliquent la logique
  - Refactoring majeur nécessaire
  - Priorité : Basse

- [ ] **REDONDANCE 2** : Unifier `AudioEngineState` et `PlayerStatus`
  - Deux enums quasi-identiques dans des fichiers différents
  - Priorité : Basse

### Performance
- [ ] **PERFORMANCE 1** : Optimiser le timer de position (200ms → 500ms)
  - Réduire la consommation batterie
  - Priorité : Basse

- [ ] **PERFORMANCE 2** : Optimiser le scan subnet
  - Scanner uniquement les IPs actives (ARP cache)
  - Priorité : Basse

### Robustesse
- [x] **CONCEPTION 4** : Ajouter timeout au transfert de fichiers
  - Nettoyer les transferts incomplets après X secondes
  - ✅ **FIXÉ** : Timer cleanup 10s + timeout 30s pour transferts inactifs
  - Priorité : Moyenne

- [ ] **BUG 5** : Afficher le nom de l'hôte pendant la connexion
  - `_buildJoiningView` ne montre pas à quel appareil on se connecte
  - Priorité : Basse

- [ ] **BUG 6** : Nom personnalisé de l'appareil non propagé lors de la découverte
  - Le nom modifié dans les paramètres est bien sauvegardé localement
  - Mais quand l'appareil passe en mode hôte, les autres appareils voient le nom système (pas le nom personnalisé)
  - Cause probable : le mDNS broadcast ou le message de bienvenue utilise le nom device par défaut au lieu du nom custom des paramètres
  - Fichiers suspects : `device_discovery.dart`, `websocket_server.dart`, `settings_bloc.dart`
  - Priorité : Moyenne (UX — les utilisateurs ne reconnaissent pas leurs appareils)

- [ ] **BUG 7** : Premier play ne fonctionne pas — nécessite un stop puis play
  - Quand un morceau est chargé pour la première fois, appuyer sur play ne déclenche rien
  - Il faut appuyer sur stop pour que le morceau se "charge" vraiment, puis rappuyer sur play
  - Cause probable : l'audio n'est pas préparé (preload/prepare) avant le premier play, ou l'état du player n'est pas synchronisé avec l'UI
  - Fichiers suspects : `player_bloc.dart`, `audio_engine.dart`, `session_manager.dart`
  - Priorité : Haute (bloque l'utilisation basique de l'app)

- [ ] **BUG 8** : Synchronisation imparfaite au premier play — se corrige après pause/play
  - Au premier lancement, la synchro entre appareils n'est pas optimale (décalage audible)
  - Si on fait pause puis play, la synchro s'améliore nettement
  - Parfois il faut refaire pause/play plusieurs fois pour une synchro parfaite
  - Cause probable : le clock offset n'est pas appliqué correctement au premier play, ou la calibration auto n'a pas encore convergé au moment du lancement
  - Fichiers suspects : `clock_sync.dart`, `session_manager.dart`, `websocket_client.dart`
  - Priorité : Haute (core feature — la synchro est le but principal de l'app)

- [ ] **BUG 9** : `LateInitializationError: Field '_discovery' has not been initialized`
  - Crash quand on appuie sur "Partager l'app" dans les paramètres
  - Cause : `SessionManager` accède à `_discovery` (late) avant `initialize()`
  - Fix : vérifier si `_discovery` est initialisé avant d'accéder à `discoveredDevices`
  - Fichier : `session_manager.dart` (getter `discoveredDevices`), `settings_screen.dart`
  - Priorité : Haute (crash utilisateur)

- [x] **SYNC 1** : Émettre SyncQualityChanged après chaque recalibration auto
  - Actuellement émis une seule fois après join
  - ✅ **DÉJÀ FAIT** : Timer périodique 10s appelle `_emitSyncQuality()`
  - Priorité : Moyenne

- [ ] **SYNC 2** : Guest pause/resume ne propage pas à l'hôte
  - Le guest peut mettre en pause localement mais l'hôte ne le sait pas
  - Priorité : Basse (comportement actuel = volume local)

- [ ] **SPATIAL 1** : Spatialisation audio multi-appareils
  - Répartir les canaux audio (L/R/C/RL/RR...) sur les appareils connectés selon leur nombre
  - Configurations : 2 appareils → stéréo, 3 → L/C/R, 4 → quadraphonique, 5+ → surround
  - L'utilisateur choisit la position de chaque appareil dans l'UI (ou auto-répartition)
  - Nécessite de splitter le flux audio en canaux mono par appareil
  - Impact : transforme MuSync en système surround avec des téléphones
  - Priorité : Moyenne (feature différenciante, demande du créateur)

---

## ✅ Corrections bugs tests réels (v0.1.4 + v0.1.5)

- [x] **BUG-TEST 1** : Clock offset non appliqué dans startAtMs (retard CLK NX1)
- [x] **BUG-TEST 2** : Playlist invité invisible → nouveau protocole playlistUpdate
- [x] **BUG-TEST 3** : Skip next hôte ne propage pas au guest
- [x] **BUG-TEST 4** : Pas de bouton stop dans UI invité
- [x] **BUG-TEST 5** : Indicateur décalage = 0 (SyncQualityChanged jamais émis)
- [x] **BUG-TEST 6** : Paramètres non persistés (SharedPreferences)
- [x] **BUG-AUDIT 1** : _cachedFilePath non réinitialisé entre sessions
- [x] **BUG-AUDIT 2** : cachePath null dans _handlePrepareCommand
- [x] **BUG-AUDIT 3** : resumePlayback envoie chemin complet au lieu du filename
- [x] **BUG-AUDIT 4** : dispose() WebSocketClient sans await
- [x] **BUG-AUDIT 5** : t2/t3 identiques dans _handleHostSyncRequest
- [x] **BUG-AUDIT 6** : Guest skip affiche mauvaise piste brièvement

---

## 🔍 Issues détectées par audit Qwen3.6-Plus (2026-04-01)

> Source : Audit complet du codebase — ~4 500 lignes analysées
> Détails complets, code exemples et rationale dans : `Rapport_Qwen36Plus.md`

### 🔴 P0 — Critique

- [x] **QWEN-P0-3** : Fuite mémoire — `FileTransferService.dispose()` jamais appelé
  - `SessionManager.dispose()` ne ferme pas le `_progressController` du service
  - Impact : fuite mémoire progressive sur sessions longues / reconnexions multiples
  - ✅ **FIXÉ** : `await _fileTransfer.dispose()` ajouté dans `SessionManager.dispose()`
  - 📄 Rapport : §P0-3

### 🟠 P1 — Important

- [x] **QWEN-P1-2** : Transfert de fichiers en Base64 — surcoût 33 %
  - `file_transfer_service.dart` encode chaque chunk en Base64 au lieu d'utiliser les WebSocket binary frames natifs
  - Impact : bande passante ×1.33, mémoire ×1.33, transferts plus lents
  - ✅ **FIXÉ** : Binary frames WebSocket implémentés (format: [4B chunkIndex][4B dataLength][data])
  - 📄 Rapport : §P1-2

- [x] **QWEN-P1-3** : Pas de gestion de backpressure dans le transfert
  - L'hôte envoie des chunks sans vérifier si les sockets esclaves sont prêts
  - Impact : saturation mémoire hôte, déconnexion d'esclaves lents
  - ✅ **FIXÉ (simplifié)** : délai 10ms entre chaque chunk (au lieu de 5ms/5 chunks)
  - 📄 Rapport : §P1-3

- [x] **QWEN-P1-6** : mDNS publishing manuel fragile
  - `_buildMdnsResponse()` construit des paquets DNS binaires à la main — risque de corruption silencieuse
  - Impact : découverte d'appareils unreliable sur certains réseaux
  - ✅ **FIXÉ** : Retry logic (2 tentatives) + catch SocketException
  - 📄 Rapport : §P1-6

### 🟡 P2 — Modéré

- [ ] **QWEN-P2-4** : Pas de gestion de rotation d'IP (DHCP renewal)
  - Si l'IP de l'hôte change pendant une session, les esclaves ne peuvent pas se reconnecter
  - Impact : session irrécupérable après changement de réseau
  - 📄 Rapport : §P2-4

- [x] **QWEN-P2-5** : Pas de gestion des interruptions audio (appel, alarme)
  - `AudioEngine` ne gère pas `audioSession.interruptionEventStream`
  - Impact : lecture interrompue sans reprise automatique après un appel
  - ✅ **FIXÉ** : `_interruptionSub` ajouté + handler `_handleInterruption()` (pause/resume auto)
  - 📄 Rapport : §P2-5

- [x] **QWEN-P2-1** : `FirebaseService()` instancié directement au lieu d'être injecté
  - 5 occurrences dans `player_bloc.dart`, `discovery_bloc.dart`, `session_manager.dart`
  - Impact : couplage fort, mocking impossible pour les tests
  - ✅ **FIXÉ** : Injection via constructeur (paramètre optionnel `firebase`)
  - 📄 Rapport : §P2-1

- [x] **QWEN-P2-2** : `analysis_options.yaml` — linter presque vide
  - Aucune règle activée au-delà du défaut (pas de `unawaited_futures`, `prefer_const_constructors`, etc.)
  - Impact : bugs asynchrones silencieux, incohérences de style
  - ✅ **FIXÉ** : 12 règles ajoutées (`prefer_const`, `unawaited_futures`, `avoid_print`, etc.)
  - 📄 Rapport : §P2-2

### 🟢 P3 — Améliorations

- [ ] **QWEN-P3-1** : Ajouter des métriques de performance (découverte, sync, transfert, latence)
  - 📄 Rapport : §P3-1

- [ ] **QWEN-P3-2** : Logging structuré (JSON) au lieu de texte libre
  - 📄 Rapport : §P3-2

- [ ] **QWEN-P3-3** : Tests d'intégration réseau (hôte + esclave en boucle locale)
  - 📄 Rapport : §P3-3

- [ ] **QWEN-P3-5** : Versioning du protocole WebSocket
  - 📄 Rapport : §P3-5

---

## ✅ Tâches P0 complétées (v0.1.3)

- [x] **P0-1** : Système de queue/playlist + skip next/prev
- [x] **P0-2** : Vrai mDNS publishing (multicast_dns)
- [x] **P0-3** : Permissions runtime Android 13+ (permission_handler)
- [x] **FIX** : Export file_transfer_service.dart dans core.dart

---

*Dernière mise à jour : 01 Avril 2026*
