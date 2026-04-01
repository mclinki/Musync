# MusyncMIMO -- Journal des Modifications

> Ce fichier documente **toutes les modifications** apportées au projet.
> Destiné à être transmis avec le code pour assurer la continuité.

---

## Session du 2026-04-01 (v0.1.15) — Fixes Crashlytics + APK Transfer

### Contexte
Fix des 3 derniers bugs Crashlytics (CRASH-7/8/9), fixes Qwen P1/P2, et nouvelle fonctionnalité APK Transfer (envoyer l'app à un appareil du réseau + mettre à jour les appareils connectés). 95/95 tests passent.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | CRASH-7 `just_audio Connection aborted` : retry 2x + timeout 10s + fallback | `audio_engine.dart` |
| 2 | `FIX` | CRASH-8 `ANR slow operations` : timeouts init (permissions 5s, Firebase 10s, session 10s) | `main.dart` |
| 3 | `FIX` | CRASH-9 `mDNS SocketException errno=103` : retry 2x + catch | `device_discovery.dart` |
| 4 | `FIX` | QWEN-P1-2 Base64 overhead : binary frames WebSocket (format `[4B idx][4B len][data]`) | `file_transfer_service.dart`, `websocket_server.dart`, `websocket_client.dart` |
| 5 | `FIX` | QWEN-P1-6 mDNS publishing fragile : retry logic ajouté | `device_discovery.dart` |
| 6 | `FIX` | QWEN-P2-1 FirebaseService injection (DI) pour tests | `player_bloc.dart`, `discovery_bloc.dart`, `settings_bloc.dart` |
| 7 | `FIX` | CONCEPTION 4 Timeout transfert fichiers : cleanup 10s + timeout 30s | `file_transfer_service.dart` |
| 8 | `FEAT` | APK Transfer : envoyer l'app à un appareil + mettre à jour appareils connectés | `protocol_message.dart`, `settings_bloc.dart`, `settings_screen.dart`, `session_manager.dart`, `discovery_bloc.dart` |
| 9 | `CHORE` | Version sync `0.1.14+14` → `0.1.15+15` | `pubspec.yaml`, `app_constants.dart` |
| 10 | `TEST` | Tests unitaires : 95/95 passent | — |

### Nouveaux messages protocole
- `apkTransferOffer` — Hôte offre d'envoyer l'APK (version, taille)
- `apkTransferAccept` — Esclave accepte le transfert
- `apkTransferDecline` — Esclave refuse le transfert

### UI Settings ajoutée
- Section "Partager l'application"
- "Envoyer l'APK" : liste les appareils découverts, envoie l'offre
- "Mettre à jour les appareils" : envoie l'offre à tous les esclaves connectés (hôte uniquement)

---

## Session du 2026-04-01 (v0.1.14) — Audit Qwen3.6-Plus + fixes critiques

### Contexte
Reprise projet Musync. Audit complet par Qwen3.6-Plus : 10 problèmes identifiés (1 P0, 3 P1, 4 P2, 2 P3). Fixes appliqués pour les issues critiques et importantes. 95/95 tests passent.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | P0-3 Memory leak : `FileTransferService.dispose()` ajouté dans `SessionManager.dispose()` | `session_manager.dart`, `file_transfer_service.dart` |
| 2 | `FIX` | P0-2 Validation payloads JSON : 22 casts unsafe remplacés par validations défensives | `websocket_client.dart`, `websocket_server.dart`, `protocol_message.dart`, `audio_session.dart`, `device_info.dart` |
| 3 | `FIX` | P1-3 Backpressure : délai entre chunks (5ms/5 chunks → 10ms/chaque chunk) | `app_constants.dart`, `file_transfer_service.dart` |
| 4 | `FIX` | P1-5 Firebase error handlers chaînés (précédent handler préservé) | `firebase_service.dart` |
| 5 | `FIX` | P2-2 Linter strict : 12 règles ajoutées (`prefer_const`, `unawaited_futures`, etc.) | `analysis_options.yaml` |
| 6 | `FIX` | P2-5 Gestion interruptions audio (phone calls, alarms) | `audio_engine.dart` |
| 7 | `CHORE` | Version sync `0.1.13+13` → `0.1.14+14` | `pubspec.yaml`, `app_constants.dart` |
| 8 | `TEST` | Tests unitaires : 95/95 passent (zéro régression) | — |

### Tâches différées (refactoring majeur)
- P1-2 : Transfert Base64 → binaire (nécessite refactoring protocole WebSocket)
- P1-4 : Race condition fichiers → Completer (nécessite refactoring file transfer)
- P1-6 : mDNS publishing via package (nécessite refactoring discovery)

---

## Session du 2026-03-31 (v0.1.13) — Audit complet + cleanup

### Contexte
Audit complet du codebase : analyse statique, compatibilité, dead code, tests. Fix de 30+ bugs (3 Critical, 6 High, 12 Medium). Suppression dead code, amélioration tests, mise à jour SDK constraints.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | ANALYZE-8 Null check `_tempDir` + safe casts payload | `file_transfer_service.dart` |
| 2 | `FIX` | ANALYZE-9 `_performSyncExchange` cleanup complet `_syncCompleter` | `websocket_client.dart` |
| 3 | `FIX` | ANALYZE-12 Safe casts `_handleTransferStart` + `_handleTransferChunk` | `file_transfer_service.dart` |
| 4 | `FIX` | ANALYZE-13 Concurrent transfers : `.values.last` au lieu de `.first` | `file_transfer_service.dart` |
| 5 | `FIX` | ANALYZE-14 Division by zero : seuil `elapsedSec > 1.0` | `clock_sync.dart` |
| 6 | `FIX` | ANALYZE-15 RangeError substring : safe `deviceId.length > 8` | `device_discovery.dart` |
| 7 | `FIX` | ANALYZE-16 ConcurrentModificationError : copie `[..._slaves.values]` | `websocket_server.dart` |
| 8 | `FIX` | ANALYZE-17 Socket fermé heartbeat timeout : `slave.socket.close()` | `websocket_server.dart` |
| 9 | `FIX` | ANALYZE-18/19 Unsafe casts `data is! String` + safe cast payload | `websocket_client.dart`, `websocket_server.dart`, `protocol_message.dart` |
| 10 | `FIX` | ANALYZE-20 `copyWith` clear `currentTrack` : paramètre `clearTrack` | `audio_session.dart` |
| 11 | `FIX` | ANALYZE-21 Try-catch `_onThemeChanged` + Firebase logging | `settings_bloc.dart` |
| 12 | `FIX` | AUDIT-3 Commentaire clarifié Windows App ID placeholder | `firebase_options.dart` |
| 13 | `FIX` | AUDIT-4 mDNS publisher skip Windows : `Platform.isWindows` | `device_discovery.dart` |
| 14 | `FIX` | AUDIT-10 Safe casts `_handleWelcome` + `_handleSyncResponse` | `websocket_client.dart` |
| 15 | `CLEANUP` | AUDIT-11 Suppression 4 valeurs enum inutilisées (`hello`, `stop`, `audioChunk`, `deviceUpdate`) | `protocol_message.dart` |
| 16 | `CLEANUP` | AUDIT-13 Suppression event `ResumeRequested` + handler `_onResume` | `player_bloc.dart` |
| 17 | `TEST` | AUDIT-15 Tests réels widget_test (AudioTrack instantiation, JSON serialization) | `widget_test.dart` |
| 18 | `CHORE` | SDK constraint `>=3.2.0` → `>=3.6.0` (compatibilité `withValues()`) | `pubspec.yaml` |
| 19 | `CHORE` | Version sync `0.1.12+12` → `0.1.13+13` | `pubspec.yaml`, `app_constants.dart` |
| 20 | `TEST` | Tests unitaires : 95/95 passent (+2 nouveaux) | — |

---

## Session du 2026-03-31 (v0.1.12)

### Contexte
Analyse complète du codebase + fix de 12 bugs critiques/high détectés par Crashlytics et analyse statique. Tests sur émulateur Android Pixel 9.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | CRASH-1 RenderFlex overflow : `Column` wrappé dans `SingleChildScrollView` | `player_screen.dart` |
| 2 | `FIX` | CRASH-1 HomeScreen overflow : `SingleChildScrollView` + `ConstrainedBox` | `main.dart` |
| 3 | `FIX` | CRASH-2/3 ScaffoldMessenger dans build() : déplacé dans `addPostFrameCallback` + `context.mounted` | `settings_screen.dart` |
| 4 | `FIX` | CRASH-4 TextEditingController double-dispose : pattern `safeDispose()` avec flag `disposed` + `PopScope` | `settings_screen.dart`, `discovery_screen.dart` |
| 5 | `FIX` | CRASH-5 SocketException Firebase init : timeout 15s + catch `errno=103` | `firebase_service.dart` |
| 6 | `FIX` | ANALYZE-1 Stream subscription leak : `_playerStateSub` stocké/annulé + guard `_stateController.isClosed` | `audio_engine.dart` |
| 7 | `FIX` | ANALYZE-2 BLoC fermé `add()` : flag `_isClosed` + guard dans handlers stream | `discovery_bloc.dart` |
| 8 | `FIX` | ANALYZE-3 context.mounted manquant : check après `FilePicker.platform.pickFiles()` | `player_screen.dart` |
| 9 | `FIX` | ANALYZE-4 Double reconnect : `_reconnectTimer?.cancel()` dans `_handleDisconnect` | `websocket_client.dart` |
| 10 | `FIX` | ANALYZE-5 Controllers après close() : guard `_stateController.isClosed` + `_playlistUpdateController.isClosed` | `session_manager.dart` |
| 11 | `FIX` | ANALYZE-6 Unawaited stop() : nouveau event `StopPlaybackRequested` + handler BLoC | `discovery_bloc.dart`, `discovery_screen.dart` |
| 12 | `FIX` | ANALYZE-7 errorMessage non cleared : `errorMessage: null` sur recovery states | `discovery_bloc.dart` |
| 13 | `FIX` | ANALYZE-10 Slave skip audio : `pause()` avant `emit(loading)` | `player_bloc.dart` |
| 14 | `FIX` | ANALYZE-11 Retry button UX : `StartScanning` au lieu de `LeaveSessionRequested` | `discovery_screen.dart` |
| 15 | `TEST` | Tests unitaires : 93/93 passent (zéro régression) | — |
| 16 | `BUILD` | APK debug Android : build réussi | — |
| 17 | `TEST` | Émulateur Pixel 9 (Android 15) : app lancée, erreurs RenderBox résiduelles | — |

---

## Session du 2026-03-30 (v0.1.11)

### Contexte
Bug critique : play depuis hôte mobile ne lance pas la musique sur les invités. Cause identifiée : file transfer lit le fichier entier en mémoire (OOM sur mobile) + compensation clock offset trop limitée (5s max). Audit complet de toutes les fonctions → 14 bugs/incohérences supplémentaires trouvés et corrigés.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | File transfer : remplacé `readAsBytes()` (charge tout en RAM) par `openRead()` streaming par chunks → élimine OOM sur mobile | `file_transfer_service.dart` |
| 2 | `FIX` | Compensation clock offset : nouvelle limite 30s (au lieu de 5s) + gestion cas `delayMs` très positif (cap attente) | `session_manager.dart`, `app_constants.dart` |
| 3 | `FIX` | Logging diagnostique : contenu du cache directory quand fichier non trouvé + nombre de slaves au transfert | `session_manager.dart`, `file_transfer_service.dart` |
| 4 | `FIX` | `dispose()` WebSocketServer n'attendait pas `stop()` (async) → fermeture incomplète | `websocket_server.dart` |
| 5 | `FIX` | `sendFile` doc indiquait "complète quand ACK reçus" mais ne vérifiait jamais les ACKs → doc corrigée, timeout documenté | `file_transfer_service.dart` |
| 6 | `FIX` | DiscoveryBloc sync devices ne retirait jamais les devices disparus → remplacement par sync complet via `_DevicesSynced` | `discovery_bloc.dart` |
| 7 | `FIX` | Port `7890` codé en dur dans dialog IP manuelle → remplacé par `kDefaultPort` | `discovery_screen.dart` |
| 8 | `CLEANUP` | Suppression factory `hello()` morte (jamais appelée, client envoie `join`) | `protocol_message.dart` |
| 9 | `CLEANUP` | Imports inutiles `firebase_service.dart` supprimés (déjà dans `core.dart`) | `player_bloc.dart`, `discovery_bloc.dart`, `settings_bloc.dart` |
| 10 | `CLEANUP` | Import inutile `permission_service.dart` supprimé dans `main.dart` | `main.dart` |
| 11 | `CLEANUP` | Variable locale `_isVirtual` renommée `isVirtual` (lint) + `prefer_conditional_assignment` | `device_discovery.dart` |
| 12 | `CLEANUP` | Indentation incohérente dans `_handlePlayCommand` | `session_manager.dart` |
| 13 | `CHORE` | Version sync : pubspec.yaml mis à jour (0.1.7+7 → 0.1.11+11) | `pubspec.yaml` |

---

## Session du 2026-03-30 (v0.1.10)

### Contexte
2e passe de review complète de toutes les fonctions. 3 bugs supplémentaires détectés et corrigés.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 15 | `FIX` | Dialog nom appareil : `controller.dispose()` jamais appelé si dialog fermé par tap extérieur → fuite mémoire. Ajout `PopScope(onPopInvokedWithResult)` | `settings_screen.dart` |
| 16 | `FIX` | Listener `progressStream` lit `state.syncingFiles` stale → race condition si 2 transferts finissent ensemble. Nouveau event `_SyncingFileProgress` traité dans handler BLoC | `player_bloc.dart` |
| 17 | `FIX` | `_onRemoveFromQueue` ne stoppait que si `playing` → piste `paused` restée chargée dans l'engine. Vérifie maintenant `playing \|\| paused` | `player_bloc.dart` |

---

## Session du 2026-03-30 (v0.1.9)

### Contexte
Corrections de bugs suite aux tests : play ne lançait plus la musique, pas de synchronisation automatique, indicateurs latence/connexion non mis à jour, crash TextEditingController. Review complète de toutes les fonctions → 5 bugs supplémentaires trouvés et corrigés (passe 1). 3 bugs supplémentaires (passe 2).

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | Play ne lançait plus la musique : `resumePlayback()` appelé au lieu de `playTrack()` car `_currentSession.currentTrack` était null après `loadTrack`. Détection `isTrueResume` ajoutée | `player_bloc.dart` |
| 2 | `FEAT` | Sync automatique des morceaux aux slaves dès ajout en playlist (sans lancer la lecture). Nouvelle méthode `syncTrackToSlaves()` | `session_manager.dart`, `player_bloc.dart` |
| 3 | `FEAT` | Indicateur de synchronisation par piste dans la queue (CircularProgressIndicator + texte "Synchronisation..."). Nouveau champ `PlayerState.syncingFiles` | `player_bloc.dart`, `player_screen.dart` |
| 4 | `FEAT` | Auto-preload sur slave quand file transfer complet (au lieu d'attendre le prepareCommand) | `session_manager.dart` |
| 5 | `FIX` | `_handlePrepareCommand` : retry 5×500ms si fichier pas encore en cache (file transfer en cours) | `session_manager.dart` |
| 6 | `FIX` | Indicateur latence : timer périodique (10s) émet `_emitSyncQuality()` côté slave après connexion | `session_manager.dart` |
| 7 | `FIX` | Indicateur connexion : `_onSessionStateChanged` met à jour `connectionDetail` pour tous les états | `discovery_bloc.dart` |
| 8 | `FIX` | File transfer progress : listener ajouté dans DiscoveryBloc pour afficher la progression côté guest | `discovery_bloc.dart` |
| 9 | `FIX` | Crash `TextEditingController used after being disposed` dans dialog nom appareil | `settings_screen.dart` |
| 10 | `FIX` | `_onAddToQueue` : `state.syncingFiles` lu après `emit()` → variable locale pour éviter race condition | `player_bloc.dart` |
| 11 | `FIX` | `_onStop` ne broadcast pas aux slaves → ajout `pausePlayback()` avant stop local | `player_bloc.dart` |
| 12 | `FIX` | `_onRemoveFromQueue` : arrêt lecture si suppression de la piste en cours | `player_bloc.dart` |
| 13 | `FIX` | `_onClearQueue` : ajout `stop()` audio engine + `pausePlayback()` pour slaves | `player_bloc.dart` |
| 14 | `FIX` | `syncTrackToSlaves` : ajout délai 500ms après `sendFile` avant `broadcastPrepare` | `session_manager.dart` |

---

## Session du 2026-03-29 (v0.1.5)

### Contexte
Audit fonction par fonction complet. 7 bugs supplémentaires trouvés et corrigés.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | `_cachedFilePath` non réinitialisé entre sessions → ancien fichier d'une session précédente | `session_manager.dart` |
| 2 | `FIX` | `_handlePrepareCommand()` : `cachePath` null → chemin `"null/filename"` | `session_manager.dart` |
| 3 | `FIX` | `resumePlayback()` envoie chemin complet au lieu du nom de fichier → guest ne trouve pas le fichier | `session_manager.dart` |
| 4 | `FIX` | `dispose()` WebSocketClient n'attendait pas `disconnect()` → fermeture incomplète | `websocket_client.dart` |
| 5 | `FIX` | `_handleHostSyncRequest()` : t2 et t3 quasi identiques → précision NTP réduite | `websocket_client.dart` |
| 6 | `FIX` | Guest skip mettait à jour sa playlist locale (différente de l'hôte) → mauvaise piste brièvement | `player_bloc.dart` |
| 7 | `REFACTOR` | `_syncQualityController` déplacé dans la section champs | `session_manager.dart` |

---

## Session du 2026-03-28 (v0.1.4)

### Contexte
Corrections de 6 bugs critiques suite aux tests sur CLK NX1 et VOG-L29 (Android 14).

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | Compensation clock offset dans _handlePlayCommand (startAtMs → temps local guest) | `session_manager.dart` |
| 2 | `FEAT` | Nouveau message `playlistUpdate` pour sync playlist hôte→invité | `protocol_message.dart`, `websocket_server.dart`, `websocket_client.dart` |
| 3 | `FEAT` | Affichage playlist hôte dans UI invité (_PlaylistCard) | `discovery_screen.dart` |
| 4 | `FIX` | PlayerBloc invitéécoute les commandes skip de l'hôte via clientEvents | `player_bloc.dart`, `session_manager.dart` |
| 5 | `FEAT` | Bouton stop local dans UI invité | `discovery_screen.dart` |
| 6 | `FIX` | Émission SyncQualityChanged après calibration clock | `session_manager.dart`, `discovery_bloc.dart` |
| 7 | `FEAT` | Persistance paramètres avec SharedPreferences (thème, nom, volume) | `settings_screen.dart`, `pubspec.yaml` |
| 8 | `FEAT` | broadcastPlaylistUpdate dans WebSocketServer | `websocket_server.dart` |
| 9 | `FEAT` | Stream playlistUpdateStream et syncQualityStream dans SessionManager | `session_manager.dart` |

---

## Session du 2026-03-28 (v0.1.3)

### Contexte
Implémentation des 3 tâches P0 + P1 (tests, settings, cleanup).

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | Modèle Playlist avec gestion de queue complète | `core/models/playlist.dart` (nouveau) |
| 2 | `FEAT` | Skip next/prev dans PlayerBloc avec auto-advance | `features/player/bloc/player_bloc.dart` |
| 3 | `FEAT` | UI queue (bottom sheet) + boutons skip prev/next | `features/player/ui/player_screen.dart` |
| 4 | `FEAT` | Protocole skipNext/skipPrev + broadcast | `protocol_message.dart`, `websocket_server.dart`, `websocket_client.dart` |
| 5 | `FEAT` | mDNS réel via multicast_dns (publishing + discovery) | `core/network/device_discovery.dart` |
| 6 | `FEAT` | Service de permissions runtime (Android 13+) | `core/services/permission_service.dart` (nouveau) |
| 7 | `FEAT` | Demande permissions au démarrage de l'app | `main.dart` |
| 8 | `FEAT` | Écran Settings (thème, nom appareil, volume, cache) | `features/settings/ui/settings_screen.dart` (nouveau) |
| 9 | `TEST` | Tests BLoC Player + modèle Playlist (16 tests) | `test/player_bloc_test.dart` (nouveau) |
| 10 | `FIX` | Double subscription stateStream → memory leak | `player_bloc.dart` |
| 11 | `FIX` | openAppSettingsPage() récursion infinie | `permission_service.dart` |
| 12 | `FIX` | Export file_transfer_service + permission_service dans core.dart | `core/core.dart` |
| 13 | `FIX` | Variables inutilisées (transactionId, qType, srv) | `device_discovery.dart` |
| 14 | `CHORE` | Ajout dépendances multicast_dns + permission_handler | `pubspec.yaml` |
| 15 | `CHORE` | Permission ACCESS_FINE_LOCATION dans manifest | `AndroidManifest.xml` |
| 16 | `CHORE` | Lint ignore avoid_print pour CLI script | `bin/analyze_sync.dart` |

---

## Session du 2026-03-28 (v0.1.2)

### Contexte
Optimisation de la synchronisation audio pour réduire la latence au maximum.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | Ajout du protocole `prepare` pour pré-charger les fichiers | `protocol_message.dart`, `websocket_server.dart`, `websocket_client.dart` |
| 2 | `OPTIM` | Réduction du délai entre samples de calibration (100ms → 50ms) | `clock_sync.dart` |
| 3 | `OPTIM` | Augmentation de la fréquence de calibration (30s → 10s) | `clock_sync.dart` |
| 4 | `OPTIM` | Réduction du délai de démarrage par défaut (2000ms → 1000ms) | `session_manager.dart`, `websocket_server.dart` |
| 5 | `FEAT` | Méthodes `preloadTrack` et `loadPreloaded` dans AudioEngine | `audio_engine.dart` |
| 6 | `OPTIM` | Réduction du temps d'attente pour sauvegarde fichier (1500ms → 500ms) | `session_manager.dart` |
| 7 | `FEAT` | Commande `prepare` envoyée avant `play` pour pré-chargement | `session_manager.dart` |

---

## Session du 2026-03-28 (v0.1.1)

### Contexte
Review complète du projet et corrections de bugs. Amélioration de l'UI invité et du système de découverte.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | Correction de l'ordre des chunks dans le transfert de fichiers | `file_transfer_service.dart` |
| 2 | `FIX` | Compensation automatique quand l'esclave est en retard | `session_manager.dart` |
| 3 | `FIX` | Null-safety sur les getters Firebase | `firebase_service.dart`, `main.dart` |
| 4 | `REFACTOR` | Suppression du code mort dans `_handleSyncRequest` | `websocket_server.dart` |
| 5 | `FEAT` | Ajout TTL (60s) pour les appareils découverts | `device_discovery.dart` |
| 6 | `REFACTOR` | Extraction de `formatDuration` dans un utilitaire commun | `format.dart`, `position_slider.dart`, `discovery_screen.dart` |
| 7 | `FIX` | Ajout du paramètre `key` au widget `PositionSlider` | `position_slider.dart` |
| 8 | `FEAT` | UI invité enrichie (statut connexion, qualité sync, transfert fichier) | `discovery_bloc.dart`, `discovery_screen.dart` |
| 9 | `FIX` | Le `DiscoveryBloc` émet maintenant les événements `DeviceFound` | `discovery_bloc.dart` |
| 10 | `FIX` | Amélioration du TCP scan (batching, timeouts, logging) | `device_discovery.dart` |
| 11 | `DOC` | Création du TASKS_BACKLOG.md | `TASKS_BACKLOG.md` |

---

## Session du 2026-03-27

### Contexte
Travail sur le backlog de fonctionnalités (`BACKLOG_FEATURES.md`).
Objectif : réduire la dette technique et implémenter les features manquantes du MVP.

### Modifications

_(les entrées seront ajoutées au fur et à mesure des modifications)_

---

## Conventions

- Chaque modification est datée et catégorisée
- Format : **[catégorie]** Description du changement → `fichier(s) modifié(s)`
- Catégories : `FIX` `FEAT` `REFACTOR` `TEST` `DOC` `CHORE` `OPTIM`

---

## Historique Complet

### 2026-03-30 (v0.1.11)

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | File transfer : remplacé `readAsBytes()` par `openRead()` streaming → élimine OOM sur mobile | `file_transfer_service.dart` |
| 2 | `FIX` | Compensation clock offset : limite 30s (au lieu de 5s) + cap attente si delay positif | `session_manager.dart`, `app_constants.dart` |
| 3 | `FIX` | Logging diagnostique cache directory + slaves count | `session_manager.dart`, `file_transfer_service.dart` |
| 4 | `FIX` | `dispose()` WebSocketServer n'attendait pas `stop()` async | `websocket_server.dart` |
| 5 | `FIX` | `sendFile` doc corrigée (ne vérifie pas ACKs) | `file_transfer_service.dart` |
| 6 | `FIX` | DiscoveryBloc sync complet devices (suppression disparus) | `discovery_bloc.dart` |
| 7 | `FIX` | Port hardcodé 7890 → `kDefaultPort` | `discovery_screen.dart` |
| 8 | `CLEANUP` | Suppression factory `hello()` morte + imports inutiles | `protocol_message.dart`, `player_bloc.dart`, `discovery_bloc.dart`, `settings_bloc.dart`, `main.dart` |
| 9 | `CLEANUP` | Lint fixes (`_isVirtual`, `prefer_conditional_assignment`, indentation) | `device_discovery.dart`, `session_manager.dart` |
| 10 | `CHORE` | Version sync pubspec.yaml (0.1.7+7 → 0.1.11+11) | `pubspec.yaml` |

### 2026-03-28 (v0.1.2)

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | Ajout du protocole `prepare` pour pré-charger les fichiers | `protocol_message.dart`, `websocket_server.dart`, `websocket_client.dart` |
| 2 | `OPTIM` | Réduction du délai entre samples de calibration (100ms → 50ms) | `clock_sync.dart` |
| 3 | `OPTIM` | Augmentation de la fréquence de calibration (30s → 10s) | `clock_sync.dart` |
| 4 | `OPTIM` | Réduction du délai de démarrage par défaut (2000ms → 1000ms) | `session_manager.dart`, `websocket_server.dart` |
| 5 | `FEAT` | Méthodes `preloadTrack` et `loadPreloaded` dans AudioEngine | `audio_engine.dart` |
| 6 | `OPTIM` | Réduction du temps d'attente pour sauvegarde fichier (1500ms → 500ms) | `session_manager.dart` |
| 7 | `FEAT` | Commande `prepare` envoyée avant `play` pour pré-chargement | `session_manager.dart` |

### 2026-03-28 (v0.1.1)

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | Correction de l'ordre des chunks dans le transfert de fichiers | `file_transfer_service.dart` |
| 2 | `FIX` | Compensation automatique quand l'esclave est en retard | `session_manager.dart` |
| 3 | `FIX` | Null-safety sur les getters Firebase | `firebase_service.dart`, `main.dart` |
| 4 | `REFACTOR` | Suppression du code mort dans `_handleSyncRequest` | `websocket_server.dart` |
| 5 | `FEAT` | Ajout TTL (60s) pour les appareils découverts | `device_discovery.dart` |
| 6 | `REFACTOR` | Extraction de `formatDuration` dans un utilitaire commun | `format.dart`, `position_slider.dart`, `discovery_screen.dart` |
| 7 | `FIX` | Ajout du paramètre `key` au widget `PositionSlider` | `position_slider.dart` |
| 8 | `FEAT` | UI invité enrichie (statut connexion, qualité sync, transfert fichier) | `discovery_bloc.dart`, `discovery_screen.dart` |
| 9 | `FIX` | Le `DiscoveryBloc` émet maintenant les événements `DeviceFound` | `discovery_bloc.dart` |
| 10 | `FIX` | Amélioration du TCP scan (batching, timeouts, logging) | `device_discovery.dart` |
| 11 | `DOC` | Création du TASKS_BACKLOG.md | `TASKS_BACKLOG.md` |

### 2026-03-27

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `DOC` | Création du BACKLOG_FEATURES.md (55 tâches) | `BACKLOG_FEATURES.md` |
| 2 | `DOC` | Création du CHANGELOG.md (ce fichier) | `CHANGELOG.md` |
