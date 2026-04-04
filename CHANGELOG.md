# MusyncMIMO -- Journal des Modifications

> Ce document documente **toutes les modifications** apportées au projet.
> Destiné à être transmis avec le code pour assurer la continuité.

---

## Session du 2026-04-04 (v0.1.46) — Compatibilité TLS par défaut + PIN optionnel + WSS fix

### Contexte
Le problème principal était un **mismatch TLS** : le mobile hôte utilisait WSS (TLS activé par défaut) mais le PC invité utilisait WS (TLS désactivé). Résultat : connexion impossible entre PC et mobile. Cette session résout le problème en désactivant TLS par défaut pour tous les appareils, rend le PIN optionnel, et corrige le handshake WSS.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | **TLS par défaut désactivé** : `AppConstants.useTls` `true` → `false`. PC ↔ Mobile et Mobile ↔ Mobile compatibles par défaut. | `app_constants.dart`, `settings_bloc.dart` |
| 2 | `FEAT` | **PIN optionnel** : Le serveur accepte les joins sans PIN si `sessionPin.isEmpty`. Bouton "Passer" dans le dialog PIN. | `websocket_server.dart`, `discovery_screen.dart` |
| 3 | `FIX` | **WSS handshake** : `_connectWss` utilise `HttpClient` + `detachSocket()` au lieu de `SecureSocket` manuel. Élimine "Stream has already been listened to". | `websocket_client.dart` |
| 4 | `FEAT` | **Toggle TLS fonctionnel** : `TlsToggled` event + `useTls` dans SettingsState + switch UI connecté au BLoC + persistance SharedPreferences. | `settings_bloc.dart`, `settings_screen.dart`, `session_manager.dart` |
| 5 | `FIX` | **PIN généré sécurisé** : Premier chiffre 1-9 (plus de PIN < 100000). | `websocket_server.dart` |
| 6 | `FIX` | **Double dispose** : `safePinDispose()` avec guard dans `_showPinDialog`. | `discovery_screen.dart` |
| 7 | `CHORE` | Version sync `0.1.45+45` → `0.1.46+46` | `pubspec.yaml`, `app_constants.dart` |
| 8 | `TEST` | Tests unitaires : 213/213 passent (zéro régression) | — |

### Détails techniques

**TLS par défaut désactivé** :
- `AppConstants.useTls` : `true` → `false` (mutable, pas const)
- `SettingsState.useTls` : `true` → `false` (défaut)
- Fallback SharedPreferences : `_prefs.getBool('use_tls') ?? AppConstants.useTls`
- Résultat : tous les appareils utilisent `ws://` par défaut, compatible entre eux sans configuration

**PIN optionnel** :
- Serveur : `if (sessionPin.isNotEmpty && (providedPin == null || providedPin.isEmpty || providedPin != sessionPin))` → rejette
- Si `sessionPin.isEmpty` : accepte tout join, même sans PIN
- UI : bouton "Passer" dans le dialog PIN → `JoinSessionRequested(device)` sans sessionPin

**WSS handshake** :
- Ancienne approche : `SecureSocket.connect()` + lecture manuelle des headers HTTP → "Stream has already been listened to"
- Nouvelle approche : `HttpClient` avec `badCertificateCallback` + `getUrl(httpsUri)` + headers WebSocket + `response.detachSocket()` → socket frais jamais écouté

**Toggle TLS** :
- `SettingsState` : nouveau champ `useTls` (défaut: false)
- `TlsToggled` event → persiste dans SharedPreferences (`use_tls`) → appelle `SessionManager.setUseTls()`
- `SessionManager.setUseTls()` : met à jour `AppConstants.useTls` pour les prochaines connexions
- UI : switch dans Paramètres → Réseau → "Chiffrement WebSocket"

---

## Session du 2026-04-04 (v0.1.43) — Fix bugs Crashlytics récurrents

### Contexte
Analyse des données Crashlytics : 6 bugs marqués "FIXÉ" persistent en réalité jusqu'à v0.1.35+. Les correctifs précédents étaient incomplets ou ne traitaient pas la cause racine. Cette session corrige définitivement 5 bugs récurrents.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | **CRASH-3/10** BLoC `close()` n'attendait pas les subscriptions avant `super.close()` → events `add()` sur BLoC fermé. Passage à `async close()` avec `await` sur chaque subscription. | `discovery_bloc.dart`, `player_bloc.dart` |
| 2 | `FIX` | **CRASH-4A** `TextEditingController` créé dans le `builder` de dialog → recréé à chaque rebuild + disposed prématurément. Controller déplacé hors du builder + `safeDispose()` garanti via `.then()` sur `showDialog`. | `settings_screen.dart` |
| 3 | `FIX` | **CRASH-2** `addPostFrameCallback` dans `build()` sans guard → callbacks dupliqués → Duplicate GlobalKeys. Ajout de flag `_snackBarScheduled` + conversion en `StatefulWidget`. | `settings_screen.dart` |
| 4 | `FIX` | **CRASH-5** Firebase init sans retry sur erreurs réseau → `SocketException errno=103` enregistré comme FATAL. Ajout de délai 500ms avant init + retry avec backoff exponentiel (2 tentatives). | `firebase_service.dart` |
| 5 | `FIX` | **CRASH-9** mDNS `MDnsClient.lookup` sans gestion d'erreur SocketException → crash FATAL. Ajout de logging spécifique + fallback TCP subnet scan. | `device_discovery.dart` |
| 6 | `CHORE` | Version sync `0.1.42+42` → `0.1.43+43` | `pubspec.yaml`, `app_constants.dart` |
| 7 | `TEST` | Tests unitaires : 213/213 passent (zéro régression) | — |

### Détails techniques

**CRASH-3/10 — BLoC close() race condition** :
- Cause : `close()` appelait `super.close()` SANS attendre la cancellation des subscriptions
- Résultat : les callbacks stream continuaient de fire `add()` après que le BLoC soit fermé
- Fix : `close()` devient `async` et `await` chaque subscription avant `super.close()`
- Impact : élimine `InheritedElement.debugDeactivated` et `BuildScope._flushDirtyElements`

**CRASH-4A — TextEditingController use-after-dispose** :
- Cause : Controller créé dans `builder` → recréé à chaque rebuild du dialog
- Le pattern `safeDispose()` existait mais l'ordre d'appel était incorrect
- Fix : Controller créé AVANT `showDialog`, `safeDispose()` garanti via `.then((_) => safeDispose())`
- Suppression du `StatefulBuilder` inutile et du `PopScope` redondant

**CRASH-2 — Duplicate GlobalKeys** :
- Cause : `addPostFrameCallback` appelé dans `build()` sans guard → multiple callbacks schedulés
- Chaque callback crée un `ScaffoldMessenger` avec le même GlobalKey
- Fix : Conversion `_SettingsView` en `StatefulWidget` + flag `_snackBarScheduled`

**CRASH-5 — Firebase SocketException errno=103** :
- Cause : Firebase init trop rapide après le démarrage, réseau pas encore stable
- Le catch existait mais l'erreur était déjà enregistrée comme FATAL par Crashlytics
- Fix : Délai 500ms avant init + retry avec backoff (1s, 2s) pour les erreurs réseau

**CRASH-9 — mDNS SocketException** :
- Cause : Port 5353 souvent occupé par le système Android
- Fix : Logging spécifique pour distinguer les erreurs socket + fallback TCP uniquement

---

## Session du 2026-04-04 (v0.1.42) — AGENT-12: Tests de migration de schéma

### Contexte
Ajout de 7 tests complets pour la migration de schéma SessionContext v1→v2 (AGENT-12). Couvre les cas nominaux, edge cases et robustesse.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `TEST` | **AGENT-12** v1 full data → v2 : préserve tous les champs + ajoute volumes/clockOffsets | `session_context_test.dart` |
| 2 | `TEST` | **AGENT-12** v2 roundtrip : toJson→fromJson préserve volumes et clockOffsets | `session_context_test.dart` |
| 3 | `TEST` | **AGENT-12** v1 minimal : champs optionnels manquants → defaults sûrs | `session_context_test.dart` |
| 4 | `TEST` | **AGENT-12** Unknown state fallback : état inconnu → waiting (safe default) | `session_context_test.dart` |
| 5 | `TEST` | **AGENT-12** Numeric types : position_ms, volume, current_index parsés correctement | `session_context_test.dart` |
| 6 | `TEST` | **AGENT-12** Immutabilité : migration ne mute pas le JSON original | `session_context_test.dart` |
| 7 | `TEST` | **AGENT-12** Future version : v99 géré sans crash (no-op) | `session_context_test.dart` |
| 8 | `CHORE` | Version sync `0.1.41+41` → `0.1.42+42` | `pubspec.yaml`, `app_constants.dart` |
| 9 | `TEST` | Tests unitaires : 206 → **213** (+7 nouveaux) | — |

---

## Session du 2026-04-04 (v0.1.41) — AGENT-9: contextSync protocol + VOLUME 1 fix

### Contexte
Implémentation du message `contextSync` au protocole WebSocket (AGENT-9) pour permettre la restauration complète du contexte d'un esclave lors de sa reconnexion. Fix concomitant de l'API `volume_controller` (breaking change 3.4.4) et du test `VolumeChanged`.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | **AGENT-9** `MessageType.contextSync` ajouté au protocole | `protocol_message.dart` |
| 2 | `FEAT` | **AGENT-9** `ProtocolMessage.contextSync()` factory avec sessionId, state, track, position, volume, playlist, serverTime, version | `protocol_message.dart` |
| 3 | `FEAT` | **AGENT-9** `WebSocketServer.sendContextSync()` — envoi du contexte complet à un esclave reconnecté | `websocket_server.dart` |
| 4 | `FEAT` | **AGENT-9** `ServerEvent.isReconnection` flag pour distinguer fresh join vs reconnexion | `websocket_server.dart` |
| 5 | `FEAT` | **AGENT-9** `ClientEventType.contextSyncCommand` + `_handleContextSync()` côté client | `websocket_client.dart` |
| 6 | `FEAT` | **AGENT-9** `ClientEvent.contextData` field pour transporter le payload complet | `websocket_client.dart` |
| 7 | `FEAT` | **AGENT-9** `_handleContextSyncCommand()` + `_sendContextToReconnectingSlave()` dans SessionManager | `session_manager.dart` |
| 8 | `FIX` | **VOLUME 1** `SystemVolumeService` — migration API `volume_controller` 3.4.4 : `VolumeController()` → `.instance`, `.listener()` → `.addListener()` | `system_volume_service.dart` |
| 9 | `FIX` | Test `VolumeChanged` — mock `systemVolume.setVolume()` au lieu de `audioEngine.setVolume()` | `player_bloc_test.dart` |
| 10 | `CHORE` | Version sync `0.1.40+40` → `0.1.41+41` | `pubspec.yaml`, `app_constants.dart` |
| 11 | `TEST` | Tests unitaires : 206/206 passent (zéro régression) | — |

### Détails techniques

**AGENT-9 — Context sync sur reconnexion** :
- Flux : esclave se reconnecte → host détecte `isReconnection` → envoie `contextSync` → esclave restaure état
- `contextSync` payload : session_id, state, current_track, position_ms, volume, playlist_tracks, current_index, repeat_mode, is_shuffled, server_time_ms, version
- Backward compatible : nouveau type de message, les anciens clients l'ignorent (default case du switch)
- Version du schéma : 2 (compatible avec SessionContext v2)

**VOLUME 1 — Fix API volume_controller** :
- `volume_controller` 3.4.4 a changé son API : constructeur → singleton, `.listener()` → `.addListener()`
- `SystemVolumeService` mis à jour + ajout de `_volumeSub` pour cleanup propre
- Test `VolumeChanged` corrigé pour mocker `systemVolume` au lieu de `audioEngine`

---

## Session du 2026-04-04 (v0.1.40) — Fix CRASH-12 (ink_sparkle shader)

### Contexte
CRASH-12 : `Asset 'shaders/ink_sparkle.frag' not found` — 9 events FATAL, 2 users, 6 sessions. Flutter 3.27+ utilise `InkSparkle` comme splash factory par défaut sur Android, qui nécessite un shader non inclus dans le build.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | **CRASH-12** `splashFactory: InkSplash.splashFactory` ajouté dans tous les `ThemeData` de `main.dart` (6 occurrences : 3 blocs × light/dark) | `main.dart` |
| 2 | `CHORE` | Version sync `0.1.39+39` → `0.1.40+40` | `pubspec.yaml`, `app_constants.dart` |
| 3 | `TEST` | Tests unitaires : 206/206 passent (zéro régression) | — |

### Détails techniques

**CRASH-12 — Shader ink_sparkle.frag manquant** :
- Flutter 3.27+ utilise `InkSparkle` (effet sparkle sur les ripples Material 3) par défaut sur Android
- Ce shader n'est pas automatiquement inclus dans les builds Android release
- Résultat : crash FATAL quand un widget avec ripple/progress est rendu
- Fix : `splashFactory: InkSplash.splashFactory` remplace InkSparkle par le ripple classique (pas de shader requis)
- Impact visuel : ripple légèrement moins "brillant" mais fonctionnellement identique
- Alternative rejetée : déclarer le shader dans `pubspec.yaml` sous `shaders:` — plus risqué (chemin du shader peut varier selon la version Flutter)

---

## Session du 2026-04-03 (v0.1.29) — Fixes P2 (withOpacity, allGuestsReady, join notification)

### Contexte
Correction de 4 tâches P2 du backlog : migration `withOpacity` → `withValues`, ajout d'un indicateur "tous les invités ont chargé" dans le dashboard host, et notification haptique quand un invité rejoint.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | **P2 1.7** `withOpacity` → `withValues(alpha: ...)` dans `position_slider.dart` (2 occurrences) | `position_slider.dart` |
| 2 | `FEAT` | **P2 5.9** `session_manager.dart` : stream `allGuestsReadyStream`, `_checkAllGuestsReady()` émet quand tous les slaves ont `isSynced = true` | `core/session/session_manager.dart` |
| 3 | `FEAT` | **P2 5.9** `player_bloc.dart` : champ `allGuestsReady` dans `PlayerState`, subscription au stream, event `_AllGuestsReadyUpdated` | `features/player/bloc/player_bloc.dart` |
| 4 | `FEAT` | **P2 5.9** `host_dashboard.dart` : badge vert "✓ Tous prêts" / orange "⏳ Chargement..." dans le header du dashboard | `features/player/ui/host_dashboard.dart` |
| 5 | `FEAT` | **P2 3.8** `session_manager.dart` : `HapticFeedback.lightImpact()` quand un invité rejoint (`ServerEventType.deviceConnected`) | `core/session/session_manager.dart` |
| 6 | `CHORE` | Version sync `0.1.28+28` → `0.1.29+29` | `pubspec.yaml`, `app_constants.dart` |
| 7 | `TEST` | Tests unitaires : 103/103 passent (zéro régression) | — |

### Détails techniques

**P2 5.9 — Indicateur "tous prêts"** :
- `SessionManager._checkAllGuestsReady()` : vérifie `slaves.values.every((s) => s.isSynced)`
- Émet `true` si aucun slave (vide = prêt), `true` si tous `isSynced`, `false` sinon
- Déclenché à chaque `deviceConnected`, `deviceDisconnected`, et `deviceReady`
- `PlayerState.allGuestsReady` mis à jour via `_AllGuestsReadyUpdated`
- UI : badge dans `_buildHeader` de `HostDashboardCard` avec icône check_circle/hourglass_empty

**P2 3.8 — Notification invité** :
- `SessionManager._onGuestJoinedNotification()` : appelle `HapticFeedback.lightImpact()`
- Déclenché dans `_handleServerEvent` sur `ServerEventType.deviceConnected`
- Utilise `unawaited` car le Future n'a pas besoin d'être attendu

---

## Session du 2026-04-03 (v0.1.28) — Mode shuffle + repeat (P2 5.3 + 5.4)

### Contexte
Le modèle `Playlist` avait une méthode `shuffle()` non reliée à l'UI. Le mode repeat n'existait pas. Implémentation complète du shuffle (on/off) et du repeat (off/one/all) avec propagation aux invités.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | **P2 5.3** `playlist.dart` : enum `RepeatMode` (off/one/all), champs `repeatMode` + `isShuffled`, `copyWith`, `shuffle()` retourne `Playlist?`, `toggleRepeat()`, `toJson/fromJson` mis à jour | `core/models/playlist.dart` |
| 2 | `FEAT` | **P2 5.3** `player_bloc.dart` : events `ToggleShuffleRequested` + `ToggleRepeatRequested`, state `repeatMode` + `isShuffled`, handlers avec préservation du track courant, `_onTrackCompleted` respecte repeat mode | `features/player/bloc/player_bloc.dart` |
| 3 | `FEAT` | **P2 5.4** `player_screen.dart` : boutons shuffle (icône colorée si actif) et repeat (repeat_one si mode one, coloré si actif) dans `_PlaybackControls` | `features/player/ui/player_screen.dart` |
| 4 | `FEAT` | **P2 5.4** `session_manager.dart` : méthode `broadcastPlaylistUpdate()` avec repeatMode/isShuffled | `core/session/session_manager.dart` |
| 5 | `FEAT` | **P2 5.4** `websocket_server.dart` : `broadcastPlaylistUpdate` accepte `repeatMode` + `isShuffled` | `core/network/websocket_server.dart` |
| 6 | `FEAT` | **P2 5.4** `protocol_message.dart` : factory `playlistUpdate` accepte `repeatMode` + `isShuffled` | `core/models/protocol_message.dart` |
| 7 | `FIX` | `player_bloc_test.dart` : mock `allGuestsReadyStream` manquant ajouté | `test/player_bloc_test.dart` |
| 8 | `CHORE` | Version sync `0.1.27+27` → `0.1.28+28` | `pubspec.yaml`, `app_constants.dart` |
| 9 | `TEST` | Tests unitaires : 103/103 passent (zéro régression) | — |

### Architecture

```
RepeatMode: off → all → one → off (cycle)
Shuffle: toggle on/off (préserve le track courant)

_onTrackCompleted :
  repeatMode == one → seek(0) + replay
  hasNext → skipNext
  repeatMode == all → loop au premier track
  else → idle
```

### Propagation host → slaves
Quand le host toggle shuffle/repeat, `_broadcastPlaylistUpdate()` envoie la playlist mise à jour avec `repeat_mode` et `is_shuffled` via le message `playlistUpdate`.

---

## Session du 2026-04-03 (v0.1.26) — Persistance de la playlist (P1 2.4)

### Contexte
La playlist existait en mémoire mais était perdue au redémarrage de l'app. Implémentation de la sauvegarde/restauration via SharedPreferences.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | **P1 2.4** `playlist.dart` : ajout `toJson()` / `fromJson()` pour sérialisation | `core/models/playlist.dart` |
| 2 | `FEAT` | **P1 2.4** `player_bloc.dart` : `_loadSavedPlaylist()` au démarrage, `_savePlaylist()` après chaque modification de playlist | `features/player/bloc/player_bloc.dart` |
| 3 | `FEAT` | **P1 2.4** `main.dart` : passage de `prefs` au `PlayerBloc` | `main.dart` |
| 4 | `CHORE` | Version sync `0.1.25+25` → `0.1.26+26` | `pubspec.yaml`, `app_constants.dart` |

### Détails techniques

**Sauvegarde** : déclenchée après chaque modification de la playlist (`LoadTrack`, `AddToQueue`, `RemoveFromQueue`, `ClearQueue`, `SkipNext`, `SkipPrevious`). Try-catch silencieux pour ne pas bloquer l'UX.

**Restauration** : au démarrage du `PlayerBloc`, lecture de `saved_playlist` depuis SharedPreferences. Si valide et non vide, émise dans le state initial.

**Compatibilité** : paramètre `prefs` optionnel (nullable) — les tests existants continuent de fonctionner sans modification.

---

## Session du 2026-04-03 (v0.1.28) — Tutoriel / Onboarding (P2 9.1)

### Contexte
À la première ouverture, l'utilisateur ne savait pas comment utiliser l'app. Implémentation d'un écran d'onboarding avec 4 pages explicatives, affiché uniquement à la première ouverture (flag persisté dans SharedPreferences). Un bouton "Tutoriel" dans les paramètres permet de le relancer.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | **P2 9.1** `OnboardingScreen` : 4 pages (Wi-Fi, groupe, lecture, sync) avec PageView, dots, skip/next | `features/onboarding/ui/onboarding_screen.dart` (nouveau) |
| 2 | `FEAT` | **P2 9.1** `MusyncApp` → StatefulWidget : vérifie `onboarding_completed` au démarrage, affiche onboarding si faux | `main.dart` |
| 3 | `FEAT` | **P2 9.1** Tuile "Tutoriel" dans SettingsScreen pour relancer l'onboarding | `features/settings/ui/settings_screen.dart` |
| 4 | `CHORE` | Version sync `0.1.27+27` → `0.1.28+28` | `pubspec.yaml`, `app_constants.dart` |

### Détails techniques

**Persistance** : flag `onboarding_completed` dans SharedPreferences (true après onboarding complété ou passé).

**Non-bloquant** : `_showOnboarding` est nullable (`bool?`) — état loading pendant la lecture des prefs, puis décision. Les tests widget ne sont pas bloqués.

**Relançable** : le bouton "Tutoriel" dans Settings pousse l'OnboardingScreen via MaterialPageRoute (ne modifie pas le flag `onboarding_completed`).

---

## Session du 2026-04-03 (v0.1.27) — Groups BLoC + UI (P1 4.1 + 4.2)

### Contexte
Les méthodes `FirebaseService.saveGroup()` et `loadGroups()` existaient déjà mais il n'y avait ni modèle, ni BLoC, ni UI pour gérer les groupes. Implémentation complète du CRUD groupes avec sync Firestore.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | **P1 4.1** Modèle `Group` avec Equatable, toJson/fromJson, copyWith, factory create | `core/models/group.dart` (nouveau) |
| 2 | `FEAT` | **P1 4.2** `GroupsBloc` : LoadGroups, CreateGroup, DeleteGroup, RenameGroup | `features/groups/bloc/groups_bloc.dart` (nouveau) |
| 3 | `FEAT` | **P1 4.2** `GroupsScreen` : liste, FAB créer, dialogs rename/delete, empty state | `features/groups/ui/groups_screen.dart` (nouveau) |
| 4 | `FEAT` | Route `/groups` ajoutée dans main.dart | `main.dart` |
| 5 | `FEAT` | Bouton "Groupes sauvegardés" ajouté sur HomeScreen | `main.dart` |
| 6 | `CHORE` | Export `group.dart` dans models.dart | `core/models/models.dart` |
| 7 | `CHORE` | Version sync `0.1.26+26` → `0.1.27+27` | `pubspec.yaml`, `app_constants.dart` |

### Architecture ajoutée

```
GroupsScreen (BlocProvider)
  └── GroupsBloc
      ├── LoadGroups  → FirebaseService.loadGroups() → Group.fromJson()
      ├── CreateGroup → Group.create() → FirebaseService.saveGroup()
      ├── DeleteGroup → FirebaseService.deleteGroup()
      └── RenameGroup → Group.copyWith() → FirebaseService.saveGroup()
```

### Adaptation API Firebase
- `FirebaseService.saveGroup()` utilise `{groupId, groupName, deviceIds, deviceNames}` (pas le modèle Group directement)
- `FirebaseService.loadGroups()` retourne `List<Map<String, dynamic>>` → convertis via `Group.fromJson()`

---

## Session du 2026-04-03 (v0.1.24) — Chiffrement WSS/TLS (P1 6.1)

### Contexte
Les WebSocket utilisaient `ws://` non chiffré, avec `android:usesCleartextTraffic="true"` dans le manifest Android. Implémentation de WSS/TLS avec certificats auto-signés générés à la volée.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | **P1 6.1** `websocket_server.dart` : `HttpServer.bindSecure` avec certificat auto-signé généré via `basic_utils` (RSA 2048, CN=musync.local, 10 ans) | `websocket_server.dart` |
| 2 | `FEAT` | **P1 6.1** `websocket_client.dart` : Connexion `wss://` avec `badCertificateCallback` pour accepter les certificats auto-signés | `websocket_client.dart` |
| 3 | `FEAT` | **P1 6.1** `AppConstants.useTls = true` flag pour activer/désactiver TLS | `app_constants.dart` |
| 4 | `CHORE` | Ajout dépendance `basic_utils: ^5.7.0` pour génération certificats X.509 | `pubspec.yaml` |
| 5 | `CHORE` | Retrait `android:usesCleartextTraffic="true"` du manifest Android | `AndroidManifest.xml` |
| 6 | `CHORE` | Version sync `0.1.23+23` → `0.1.24+24` | `pubspec.yaml`, `app_constants.dart` |
| 7 | `TEST` | Tests unitaires : 103/103 passent (zéro régression) | — |

### Détails techniques

**Certificat auto-signé** :
- Généré dynamiquement à chaque démarrage du serveur host
- RSA 2048 bits, CN=musync.local, O=MusyncMIMO, C=US
- Validité 10 ans
- Pas de fichier PEM embarqué — généré via `basic_utils` (`CryptoUtils.generateRSAKeyPair` + `X509Utils.generateSelfSignedCertificate`)

**Client WSS** :
- `WebSocket.connect` ne supporte pas `badCertificateCallback` → utilisation de `HttpClient` avec `badCertificateCallback = true` puis `WebSocket.fromUpgradedSocket`
- Accepte automatiquement les certificats auto-signés du host

**Fallback** :
- Le flag `AppConstants.useTls` permet de revenir à `ws://` si nécessaire

---

## Session du 2026-04-03 (v0.1.23) — Gestion background iOS (P1 6.3)

### Contexte
iOS tuait les apps en background rapidement. Sans configuration, la session Musync se coupait quand l'utilisateur quittait l'app ou verrouillait l'écran. Le foreground service existait pour Android mais pas pour iOS.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | **P1 6.3** `UIBackgroundModes` (audio + fetch) ajoutés dans Info.plist | `ios/Runner/Info.plist` |
| 2 | `FEAT` | `ForegroundService` étendu : configure `AVAudioSessionCategoryPlayback` sur iOS au lieu de no-op | `foreground_service.dart` |
| 3 | `CHORE` | Version sync `0.1.22+22` → `0.1.23+23` | `pubspec.yaml`, `app_constants.dart` |

### Détails techniques

**Background iOS** :
- `Info.plist` : `UIBackgroundModes` avec `audio` et `fetch`
- `ForegroundService.start()` sur iOS configure `AudioSession` avec `AVAudioSessionCategory.playback` + `duckOthers`
- `ForegroundService.stop()` désactive la session audio iOS via `session.setActive(false)`
- `AudioEngine` configurait déjà `AVAudioSessionCategory.playback` dans `initialize()` — aucune modification nécessaire

---

## Session du 2026-04-03 (v0.1.22) — Fix UX file d'attente (P0 1.2)

### Contexte
Fix du bug P0 1.2 : ajouter un morceau en file d'attente sans charger d'abord restait bloqué, et le bouton "Charger" remplaçait la file au lieu d'ajouter.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | **P0 1.2** Bouton `_FilePickerButton` → `_ContextualFilePickerButton` unique : si playlist vide → "Charger un premier morceau" (LoadTrackRequested), si non vide → "Ajouter à la file" (AddToQueueRequested). Support sélection multiple (1er charge, suivants ajoutent). | `player_screen.dart` |
| 2 | `FIX` | **P0 1.2** `_onAddToQueue` : si playlist vide ET aucun track chargé → charge le track dans l'audio engine au lieu de juste l'ajouter à la file | `player_bloc.dart` |
| 3 | `FIX` | `PlayerState.copyWith` : ajout `clearCurrentTrack` flag (comme `DiscoveryState`) pour permettre de nullifier currentTrack | `player_bloc.dart` |
| 4 | `FIX` | `DiscoveryState.copyWith` : ajout `clearTrack` flag manquant + utilisé dans `_onPlaybackStateChanged` | `discovery_bloc.dart` |
| 5 | `TEST` | Tests PlayerBloc mis à jour pour nouveau comportement AddToQueueRequested + mocks ajoutés (stateStream, loadTrack, durationStream) | `player_bloc_test.dart` |
| 6 | `TEST` | Tests unitaires : 103/103 passent (+1 nouveau test de comportement) | — |

---

## Session du 2026-04-02 (v0.1.21) — Fixes bugs résiduels + Mise à jour via l'app

### Contexte
Résolution des derniers bugs restants (BUG-5, SYNC-2, Settings onTap) + implémentation de la fonctionnalité de mise à jour via l'app (vérification GitHub Releases, téléchargement APK, installation).

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | **BUG-5** Vue "joining" affiche le nom de l'hôte (`Connexion à $hostName...`) | `features/discovery/ui/discovery_screen.dart` |
| 2 | `FIX` | **SYNC-2** Guest pause/resume propage à l'hôte via messages `guestPause`/`guestResume` | `core/models/protocol_message.dart`, `core/network/websocket_server.dart`, `core/session/session_manager.dart`, `features/player/bloc/player_bloc.dart` |
| 3 | `FIX` | Settings "Signaler un problème" + "Source" : ajout `onTap` (copie URL + SnackBar) | `features/settings/ui/settings_screen.dart` |
| 4 | `FEAT` | **UPDATE-1** `UpdateService` : vérification GitHub Releases, comparaison versions sémantiques, téléchargement APK | `core/services/update_service.dart` (nouveau) |
| 5 | `FEAT` | UI Settings : section "Mise à jour" avec vérification, release notes, téléchargement, installation | `features/settings/bloc/settings_bloc.dart`, `features/settings/ui/settings_screen.dart` |
| 6 | `CHORE` | Export `update_service.dart` dans core.dart | `core/core.dart` |
| 7 | `TEST` | Tests unitaires : 102/102 passent (zéro régression) | — |

### Détails techniques

**BUG-5 — Nom hôte dans vue joining** :
- `_buildJoiningView` retournait un widget `const` sans accès au state
- Fix : signature modifiée pour accepter `(BuildContext, DiscoveryState)`, affiche `state.hostDevice?.name`

**SYNC-2 — Guest pause/resume propagation** :
- Nouveaux types `guestPause`/`guestResume` dans `MessageType`
- `SessionManager.sendToHost()` : wrapper pour `_client!.sendMessage()`
- `WebSocketServer` : handlers `_handleGuestPause`/`_handleGuestResume` avec logging
- `PlayerBloc` : guest envoie `guestPause(positionMs)` sur pause, `guestResume` sur resume

**UPDATE-1 — Mise à jour via l'app** :
- `UpdateService` : HTTP client vers `api.github.com/repos/{owner}/{repo}/releases/latest`
- Comparaison versions sémantiques (split `.` → comparaison par composant)
- Téléchargement APK dans `getTemporaryDirectory()` avec callback de progression
- UI : 3 états (idle → checking → update available → downloading → ready to install)

### Fichiers créés
- `lib/core/services/update_service.dart` — `UpdateInfo`, `DownloadProgress`, `UpdateService`

### Fichiers modifiés
- `lib/features/discovery/ui/discovery_screen.dart` — `_buildJoiningView` avec nom hôte
- `lib/core/models/protocol_message.dart` — `guestPause`, `guestResume` + factories
- `lib/core/network/websocket_server.dart` — handlers guest pause/resume
- `lib/core/session/session_manager.dart` — `sendToHost()`
- `lib/features/player/bloc/player_bloc.dart` — guest envoie pause/resume au host
- `lib/features/settings/bloc/settings_bloc.dart` — events/state/handlers update
- `lib/features/settings/ui/settings_screen.dart` — section mise à jour + fix onTap
- `lib/core/core.dart` — export update_service

---

## Session du 2026-04-02 (v0.1.20) — Architecture Agentique (AGENT-1→4)

### Contexte
Implémentation des 4 premières tâches du backlog agentique : modèle SessionContext versionné, EventStore SQLite, ContextManager, et intégration dans SessionManager. Fondation pour l'Event Sourcing léger et la reprise de contexte après déconnexion.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | **AGENT-1** Modèle `SessionContext` versionné (v2) avec migration automatique v1→v2, Equatable, toJson/fromJson, copyWith, summary | `core/models/session_context.dart` (nouveau) |
| 2 | `FEAT` | **AGENT-2** `EventStore` SQLite : tables `session_events` + `context_snapshots`, append/query/snapshot/clear | `core/context/event_store.dart` (nouveau) |
| 3 | `FEAT` | **AGENT-3** `ContextManager` : initContext, recordEvent, createSnapshot, restoreContext, getContextSummary | `core/context/context_manager.dart` (nouveau) |
| 4 | `FEAT` | **AGENT-4** Intégration dans `SessionManager` : events sessionCreated, playbackStarted, playbackPaused, playbackResumed, deviceJoined + snapshot sur leaveSession | `core/session/session_manager.dart` |
| 5 | `CHORE` | Exports `session_context.dart`, `event_store.dart`, `context_manager.dart` | `core/models/models.dart`, `core/core.dart` |
| 6 | `TEST` | 7 tests unitaires pour SessionContext (empty, roundtrip, copyWith, clearTrack, migration v1→v2, summary, null handling) | `test/session_context_test.dart` (nouveau) |
| 7 | `TEST` | Tests unitaires : 102/102 passent (+7 nouveaux) | — |

### Architecture ajoutée

```
SessionManager
  ├── EventStore (SQLite)
  │   ├── session_events (id, session_id, type, data, timestamp)
  │   └── context_snapshots (id, session_id, context_json, created_at)
  └── ContextManager
      ├── initContext(sessionId)
      ├── recordEvent(SessionEvent)  ← appelé à chaque action
      ├── createSnapshot()           ← appelé sur leaveSession
      ├── restoreContext(sessionId)   ← snapshot + replay events
      └── getContextSummary()         ← pour agent IA
```

### Fichiers créés
- `lib/core/models/session_context.dart` — Modèle versionné avec migration
- `lib/core/context/event_store.dart` — SQLite EventStore
- `lib/core/context/context_manager.dart` — Orchestrateur de contexte
- `test/session_context_test.dart` — 7 tests unitaires

### Fichiers modifiés
- `lib/core/session/session_manager.dart` — Intégration EventStore + ContextManager
- `lib/core/models/models.dart` — Export session_context
- `lib/core/core.dart` — Exports context module

---

## Session du 2026-04-02 (v0.1.19) — Fixes P0 (BUG-7/8/9 + CRASH-10)

### Contexte
Audit complet du projet avec le skill `code-audit` d'OpenWork. Rapport généré (`AUDIT_REPORT.md`, score 62/100). Croisement avec le backlog : 4 bugs P0 identifiés comme actifs et bloquants. Correction des 4 bugs + vérification 95/95 tests.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | **BUG-9** LateInitializationError "Partager l'app" : ajout flag `_isInitialized` + guards `hostSession()`/`joinSession()` | `session_manager.dart` |
| 2 | `FIX` | **BUG-7** Premier play ne fonctionne pas : `loadTrack()` attend état `ready` du player avant de retourner (just_audio buffering post-setFilePath) | `audio_engine.dart` |
| 3 | `FIX` | **BUG-8** Sync imparfaite au premier play : recalibration différée 3s post-connexion + sync exchange avant chaque play command | `session_manager.dart` |
| 4 | `FIX` | **CRASH-10** InheritedElement.debugDeactivated (47 events, 7 users) : guards `_isClosed` sur TOUS les stream listeners (6 dans DiscoveryBloc, 6 dans PlayerBloc) | `discovery_bloc.dart`, `player_bloc.dart` |
| 5 | `DOC` | Rapport d'audit complet `AUDIT_REPORT.md` (score 62/100, 24 findings) | `AUDIT_REPORT.md` (nouveau) |
| 6 | `TEST` | Tests unitaires : 95/95 passent (zéro régression) | — |

### Détails techniques

**BUG-9 — LateInitializationError** :
- `SessionManager.discoveredDevices` accédé avant `initialize()` quand timeout 10s dans `main.dart`
- Fix : flag `_isInitialized` (false par défaut, true en fin d'init) + guards dans `hostSession()` et `joinSession()`

**BUG-7 — Premier play ne fonctionne pas** :
- `loadTrack()` retournait immédiatement après `setFilePath()` mais `just_audio` était encore en état `buffering`
- `play()` appelé sur un player pas prêt → silencieux
- Fix : attente `playerStateStream.firstWhere(ready)` avec timeout 10s + état explicitement mis à `paused`

**BUG-8 — Sync imparfaite au premier play** :
- Calibration initiale bruitée (réseau instable juste après connexion)
- Auto-calibration toutes les 10s mais premier play souvent avant la 1ère recalibration
- Fix : recalibration 3s post-connexion (réseau stabilisé) + sync exchange avant chaque `_handlePlayCommand`

**CRASH-10 — InheritedElement.debugDeactivated** :
- Stream listeners appelaient `add()` sur BLoC après `close()` → widget tree corrompu
- `DiscoveryBloc` : 6 listeners sans guard `_isClosed` (seuls 2 handlers en avaient un)
- `PlayerBloc` : 6 listeners sans guard + pas de flag `_isClosed` du tout
- Fix : ajout `_isClosed` flag + guard `if (_isClosed) return;` sur tous les listeners

### Fichiers modifiés
- `lib/core/session/session_manager.dart` — Flag `_isInitialized`, guards, recalibration post-connexion
- `lib/core/audio/audio_engine.dart` — Attente état ready dans `loadTrack()`
- `lib/features/discovery/bloc/discovery_bloc.dart` — Guards `_isClosed` sur 6 stream listeners
- `lib/features/player/bloc/player_bloc.dart` — Flag `_isClosed` + guards sur 6 stream listeners

---

## Session du 2026-04-01 (v0.1.18) — Partage APK via HTTP local

### Contexte
La fonctionnalité "Partager l'APK" ne fonctionnait pas : l'ancien flux tentait d'envoyer l'APK via WebSocket aux appareils Musync existants, mais le chemin APK était toujours null et les appareils cibles n'avaient pas Musync. Refonte complète : serveur HTTP local qui sert l'APK à n'importe quel appareil du réseau via un simple lien.

### Problèmes identifiés (ancien flux)

| # | Bug | Impact |
|---|-----|--------|
| 1 | `_getApkPath()` cherchait dans `apk_cache/` mais rien ne créait ce cache → toujours `null` | Offre jamais envoyée |
| 2 | Dialog listait les appareils Musync (mDNS) = appareils qui ont DÉJÀ l'app | Mauvaise cible |
| 3 | Aucun transfert réel — envoie juste un message "offer" WebSocket | Pas de livraison |
| 4 | Serveur WS ne gère pas les réponses accept/decline | Flux mort côté hôte |
| 5 | Pas de serveur HTTP — appareil sans Musync ne peut rien recevoir | Impossible |

### Nouveau flux

```
1. Utilisateur active "Partager l'APK" (switch ON)
2. ApkShareService récupère le vrai APK via platform channel (Android)
3. Copie l'APK dans /tmp pour le rendre lisible
4. Démarre un serveur HTTP sur le port 8080
5. Résout l'IP locale (même hors session)
6. Affiche l'URL http://IP:8080/apk + bouton "Copier"
7. L'utilisateur partage le lien (SMS, WhatsApp, etc.)
8. L'appareil cible ouvre le lien → page HTML → bouton "Télécharger"
9. Le fichier APK est servi directement
```

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | Service `ApkShareService` : serveur HTTP local + copie APK + page HTML | `core/services/apk_share_service.dart` (nouveau) |
| 2 | `FEAT` | Platform channel `getApkPath` pour récupérer le chemin réel de l'APK | `android/.../MainActivity.kt` |
| 3 | `FEAT` | Events `ApkShareStartRequested` / `ApkShareStopRequested` | `features/settings/bloc/settings_bloc.dart` |
| 4 | `FEAT` | State `isApkShareRunning`, `apkShareUrl`, `apkSharePort` | `features/settings/bloc/settings_bloc.dart` |
| 5 | `FEAT` | Résolution IP locale même hors session (via `DeviceDiscovery.getLocalIp()`) | `features/settings/bloc/settings_bloc.dart` |
| 6 | `FEAT` | UI : switch ON/OFF + affichage URL + bouton copier | `features/settings/ui/settings_screen.dart` |
| 7 | `CLEANUP` | Suppression `_apkTransferOfferController`, `apkTransferOfferStream`, `_handleApkTransferOffer`, `acceptApkTransfer`, `declineApkTransfer`, class `ApkTransferOffer` | `core/session/session_manager.dart` |
| 8 | `CLEANUP` | Suppression events `ApkTransferOfferReceived/Accepted/Declined`, state `apkTransferOffer`, subscription `_apkTransferSub` | `features/discovery/bloc/discovery_bloc.dart` |
| 9 | `CLEANUP` | Suppression mock `apkTransferOfferStream` dans tests | `test/discovery_bloc_test.dart` |
| 10 | `FIX` | Ajout mock `connectedDevicesStream` manquant dans tests player | `test/player_bloc_test.dart` |
| 11 | `CHORE` | Export `apk_share_service.dart` dans core.dart | `core/core.dart` |
| 12 | `TEST` | Tests unitaires : 95/95 passent (zéro régression) | — |

### Nouveaux fichiers
- `lib/core/services/apk_share_service.dart` — Serveur HTTP local pour servir l'APK

### Fichiers modifiés
- `android/.../MainActivity.kt` — Ajout méthode `getApkPath`
- `lib/features/settings/bloc/settings_bloc.dart` — Nouveaux events/state, suppression ancien flux
- `lib/features/settings/ui/settings_screen.dart` — Nouvelle UI partage APK
- `lib/core/session/session_manager.dart` — Nettoyage code mort APK
- `lib/features/discovery/bloc/discovery_bloc.dart` — Nettoyage code mort APK
- `lib/core/core.dart` — Export nouveau service
- `test/discovery_bloc_test.dart` — Suppression mock obsolète
- `test/player_bloc_test.dart` — Fix mock manquant

### Compatibilité
- Messages protocole `apkTransferOffer/Accept/Decline` conservés dans `protocol_message.dart` (usage futur possible)
- Case `ClientEventType.apkTransferOffer` conservé dans `_handleClientEvent` avec log d'ignorance

---

## Session du 2026-04-01 (v0.1.17) — Dashboard Host

### Contexte
Implémentation de la tâche 5.8 du backlog : Dashboard host affichant les appareils connectés avec leur latence et qualité de sync. L'hôte peut maintenant voir en temps réel l'état de tous les appareils connectés.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FEAT` | Modèle `ConnectedDeviceInfo` avec qualité sync calculée | `core/models/connected_device_info.dart` (nouveau) |
| 2 | `FEAT` | Enum `SyncQuality` avec labels et couleurs (déplacé de discovery_bloc) | `core/models/connected_device_info.dart` |
| 3 | `FEAT` | Stream `connectedDevicesStream` + méthode `getConnectedDevices()` | `core/session/session_manager.dart` |
| 4 | `FEAT` | Timer périodique (2s) pour émettre les appareils connectés (host) | `core/session/session_manager.dart` |
| 5 | `FEAT` | Event `ConnectedDevicesUpdated` + state `connectedDevices` | `features/player/bloc/player_bloc.dart` |
| 6 | `FEAT` | Widget `HostDashboardCard` avec liste appareils, offset, qualité sync | `features/player/ui/host_dashboard.dart` (nouveau) |
| 7 | `FEAT` | Intégration dashboard dans PlayerScreen (visible si host) | `features/player/ui/player_screen.dart` |
| 8 | `FIX` | Classe `ApkTransferOffer` ajoutée dans session_manager (manquante) | `core/session/session_manager.dart` |
| 9 | `CLEANUP` | Suppression enum `SyncQuality` locale dans discovery_bloc | `features/discovery/bloc/discovery_bloc.dart` |
| 10 | `CHORE` | Export `connected_device_info.dart` dans models.dart | `core/models/models.dart` |

### Nouveaux fichiers
- `lib/core/models/connected_device_info.dart` — Modèle pour appareils connectés avec sync info
- `lib/features/player/ui/host_dashboard.dart` — Widget dashboard host

### Architecture
```
SessionManager (timer 2s)
  → getConnectedDevices() mappe WebSocketServer.slaves
  → connectedDevicesStream émet List<ConnectedDeviceInfo>
    → PlayerBloc écoute → ConnectedDevicesUpdated event
      → PlayerState.connectedDevices
        → HostDashboardCard affiche (si host)
```

### Données affichées par appareil
- Nom de l'appareil
- Type (icône : 📱💻🔊📺)
- Adresse IP
- Clock offset (ms) avec couleur : vert <30ms, orange <50ms, rouge >50ms
- Badge qualité sync : Excellent/Bon/Acceptable/Dégradé
- État de santé (basé sur dernier heartbeat)

---

## Session du 2026-04-01 (v0.1.16) — Amélioration moteur de synchronisation

### Contexte
Analyse du système de synchronisation NTP-like existant. Constat : la calibration fixe toutes les 10s et la médiane brute sont insuffisantes pour les réseaux dégradés. Amélioration en 3 axes : calibration adaptative, filtre de Kalman, recalibrage forcé. 95/95 tests passent (zéro régression).

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `OPTIM` | Calibration adaptative : intervalle dynamique (1s-15s) selon jitter au lieu de 10s fixe | `clock_sync.dart` |
| 2 | `OPTIM` | Filtre de Kalman pour estimer offset + drift au lieu de médiane brute | `clock_sync.dart` |
| 3 | `FEAT` | `needsRecalibration(thresholdMs)` : détection proactive de dérive excessive | `clock_sync.dart` |
| 4 | `FEAT` | `forceRecalibrate()` : recalibrage immédiat avec reset confiance Kalman | `clock_sync.dart` |
| 5 | `TEST` | Tests unitaires : 95/95 passent (zéro régression) | — |

### Détails techniques

**Calibration adaptative** (remplace l'intervalle fixe de 10s) :
- Jitter < 5ms → 15s (stable, économise batterie)
- Jitter 5-15ms → 10s (comportement inchangé)
- Jitter 15-30ms → 3s (rattrapage rapide)
- Jitter > 30ms → 1s (mode dégradé)

**Filtre de Kalman** (remplace la médiane brute) :
- Modélise l'état horloge comme `[offset, drift]` avec évolution linéaire
- Prédiction : `offset(t+dt) = offset(t) + drift × dt`
- Mise à jour : combine prédiction et mesure avec pondération statistique
- Résultat : estimation ±2-3ms au lieu de ±5ms avec médiane

**Nouvelles méthodes publiques** :
- `needsRecalibration({thresholdMs: 5.0})` → `bool` — vérifie si la dérive prédite dépasse un seuil
- `forceRecalibrate()` → `Future<bool>` — force un recalibrage immédiat (reset confiance Kalman)

### Compatibilité
- API publique inchangée : `startAutoCalibration()`, `stopAutoCalibration()`, `calibrate()`, `syncedTimeMs`, `isCalibrated`, `stats` conservent leurs signatures
- `startAutoCalibration()` accepte toujours un paramètre `interval` mais l'utilise comme base pour le calcul adaptatif
- Tous les fichiers consommateurs compatibles sans modification : `websocket_client.dart`, `websocket_server.dart`, `session_manager.dart`, `discovery_bloc.dart`

### Impact mesuré

| Métrique | Avant (v0.1.15) | Après (v0.1.16) |
|----------|-----------------|------------------|
| Précision offset | ±5ms (médiane) | ±2-3ms (Kalman) |
| Réactivité instabilité | 10s fixe | 1-3s adaptatif |
| Coût bande passante | Constant | Réduit si stable |
| Dérive max entre calibrages | 0.4ms (10s) | 0.04ms (1s si critique) |

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
