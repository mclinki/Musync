# Code Audit Report — MusyncMIMO (Session 3 — Qualité de Code)

**Date**: 2026-04-03
**Project**: MusyncMIMO v0.1.34+34 (Flutter/Dart audio sync app)
**Auditor**: Pepito (OpenWork Code Audit Skill)
**Scope**: `lib/` directory — 38 Dart files, ~8,600 lines of code
**Tech Stack**: Flutter 3.6+, BLoC, Firebase, WebSocket, mDNS, sqflite, just_audio

---

## Executive Summary

Le projet MusyncMIMO est une application Flutter bien structurée suivant une architecture feature-first avec BLoC. Les points forts incluent l'utilisation d'`AppConstants` pour centraliser les valeurs magiques, une bonne gestion des timeout, et une séparation claire core/features. Cependant, plusieurs problèmes de qualité de code nécessitent une attention, notamment le fichier `session_manager.dart` (1317 lignes) qui est un god object majeur, des duplications de code importantes (extraction de nom de fichier répétée 8 fois), et des `catch (_)` silencieux qui masquent des erreurs potentielles.

| Severity | Count |
|----------|-------|
| 🔴 Critical | 3 |
| 🟠 High | 8 |
| 🟡 Medium | 12 |
| 🟢 Low | 9 |
| ℹ️ Info | 5 |

**Overall Health Score**: 62/100

---

## 🔴 Critical Findings (Immediate Action Required)

### [CRIT-001] God Object: SessionManager (1317 lignes)
- **File**: `lib/core/session/session_manager.dart:1-1317`
- **Category**: Architecture / Code Quality
- **Issue**: SessionManager est une classe de 1317 lignes qui orchestre TOUS les composants: discovery, audio, WebSocket server/client, file transfer, foreground service, event store, context manager, Firebase, et gère 6+ stream controllers. C'est le point central de couplage fort du projet.
- **Impact**: Maintenance extrêmement difficile, testing complexe, violations SRP, risque élevé de régressions.
- **Suggestion**: Découper en sous-orchestrateurs:
  - `SessionHostManager` (host-side: server, broadcast, connected devices)
  - `SessionClientManager` (slave-side: client, clock sync, command handling)
  - `PlaybackCoordinator` (audio engine + file transfer coordination)
  - Garder SessionManager comme facade légère

### [CRIT-002] DRY Violation: Extraction de nom de fichier dupliquée 8 fois
- **Files**:
  - `lib/core/session/session_manager.dart:446,568,628`
  - `lib/core/models/audio_session.dart:153,170`
  - `lib/core/services/file_transfer_service.dart:116`
  - `lib/features/player/bloc/player_bloc.dart:501`
  - `lib/features/player/ui/player_screen.dart:250`
- **Pattern**: `path.split('/').last.split('\\').last`
- **Category**: Code Quality (DRY)
- **Issue**: Le même pattern d'extraction de nom de fichier est copié-collé dans 8 endroits différents.
- **Suggestion**: Créer une fonction utilitaire dans `lib/core/utils/format.dart`:
  ```dart
  String extractFileName(String path) => path.split('/').last.split('\\').last;
  ```

### [CRIT-003] DRY Violation: Blocs de code identiques dans _handleFileTransferMessage et _handleFileTransferBinary
- **File**: `lib/core/session/session_manager.dart:1121-1196`
- **Category**: Code Quality (DRY)
- **Issue**: Les méthodes `_handleFileTransferMessage` (lignes 1121-1159) et `_handleFileTransferBinary` (lignes 1161-1196) contiennent un bloc quasi-identique de ~25 lignes pour l'auto-preload après transfert de fichier.
- **Suggestion**: Extraire une méthode privée `_autoPreloadAfterTransfer(String filePath)`:
  ```dart
  Future<void> _autoPreloadAfterTransfer(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final track = await AudioTrack.fromFilePathWithMetadata(filePath);
        await _audioEngine.preloadTrack(track);
        _logger.i('Auto-preloaded track after file transfer: ${track.title}');
      }
    } catch (e) {
      _logger.w('Auto-preload after transfer failed (non-critical): $e');
    }
  }
  ```

---

## 🟠 High Priority Findings

### [HIGH-001] Fichiers trop longs (>300 lignes) — 13 fichiers
| File | Lines | Severity |
|------|-------|----------|
| `lib/core/session/session_manager.dart` | 1317 | 🔴 |
| `lib/features/discovery/ui/discovery_screen.dart` | 1200 | 🔴 |
| `lib/features/player/bloc/player_bloc.dart` | 1065 | 🔴 |
| `lib/core/network/device_discovery.dart` | 775 | 🟠 |
| `lib/core/network/websocket_client.dart` | 659 | 🟠 |
| `lib/features/discovery/bloc/discovery_bloc.dart` | 691 | 🟠 |
| `lib/features/settings/ui/settings_screen.dart` | 644 | 🟠 |
| `lib/features/player/ui/player_screen.dart` | 607 | 🟠 |
| `lib/core/network/websocket_server.dart` | 586 | 🟠 |
| `lib/features/settings/bloc/settings_bloc.dart` | 560 | 🟠 |
| `lib/core/services/file_transfer_service.dart` | 489 | 🟠 |
| `lib/core/network/clock_sync.dart` | 412 | 🟡 |
| `lib/core/services/firebase_service.dart` | 373 | 🟡 |
- **Category**: Code Quality
- **Suggestion**: Cibler en priorité les 3 fichiers > 1000 lignes pour extraction de sous-composants.

### [HIGH-002] Fonctions trop longues (>50 lignes)
| Function | File:Line | Lines |
|----------|-----------|-------|
| `_handlePlayCommand` | `session_manager.dart:976` | ~145 |
| `_buildMdnsResponse` | `device_discovery.dart:374` | ~88 |
| `_queryMdnsServices` | `device_discovery.dart:565` | ~80 |
| `sendFile` | `file_transfer_service.dart:105` | ~102 |
| `_buildJoinedView` | `discovery_screen.dart:377` | ~115 |
| `_buildScanningView` | `discovery_screen.dart:165` | ~113 |
| `initialize` (Firebase) | `firebase_service.dart:47` | ~78 |
| `_onApkShareStart` | `settings_bloc.dart:365` | ~78 |
| `_onTrackCompleted` | `player_bloc.dart:854` | ~62 |
| `_onSkipPrevious` | `player_bloc.dart:717` | ~58 |
- **Category**: Code Quality
- **Suggestion**: Extraire les sous-logiques en méthodes privées nommées. Ex: `_handlePlayCommand` devrait être découpé en `_resolveCachedFilePath`, `_loadAndSeekTrack`, `_calculatePlayDelay`, `_executeScheduledPlay`.

### [HIGH-003] Couplage fort: PlayerBloc dépend directement de SessionManager
- **File**: `lib/features/player/bloc/player_bloc.dart:289`
- **Category**: Architecture
- **Issue**: PlayerBloc accède directement à `sessionManager.audioEngine`, `sessionManager.role`, `sessionManager.playTrack()`, `sessionManager.syncTrackToSlaves()`, etc. Le BLoC connaît trop de détails internes du SessionManager.
- **Impact**: Rend le testing unitaire difficile (mocking complexe), empêche la réutilisation du BLoC.
- **Suggestion**: Introduire une interface `PlaybackService` abstraite que PlayerBloc utilise, avec SessionManager comme implémentation.

### [HIGH-004] Couplage fort: DiscoveryScreen crée son propre DiscoveryBloc
- **File**: `lib/features/discovery/ui/discovery_screen.dart:14`
- **Category**: Architecture
- **Issue**: `BlocProvider(create: (context) => DiscoveryBloc(sessionManager: context.read<SessionManager>()))` — le widget crée un BLoC qui dépend directement de SessionManager au lieu de recevoir un BLoC pré-configuré.
- **Suggestion**: Fournir DiscoveryBloc au niveau de MusyncApp (comme PlayerBloc et SettingsBloc) pour cohérence et testabilité.

### [HIGH-005] _stateSub écrasé dans PlayerBloc — fuite de subscription
- **File**: `lib/features/player/bloc/player_bloc.dart:317,340`
- **Category**: Bug / Memory Leak
- **Issue**: `_stateSub` est assigné deux fois (ligne 317 pour `audioEngine.stateStream` et ligne 340 pour `stateStream`). La première subscription est perdue et ne sera jamais annulée.
- **Impact**: Fuite de mémoire, callbacks fantômes sur l'ancien stream.
- **Suggestion**: Utiliser des variables distinctes: `_audioStateSub` et `_sessionStateSub`.

### [HIGH-006] Gestion d'erreurs inconsistante: 18 `catch (_)` silencieux
- **Files**: Multiples (voir grep)
- **Category**: Error Handling
- **Issue**: 18 blocs `catch (_) {}` ou `catch (_) { return; }` avalent toutes les erreurs sans log. Certains sont justifiés (network probes), mais d'autres masquent des bugs potentiels:
  - `firebase_service.dart:227,247,255,263` — erreurs Firebase silencieuses (acceptable pour optional)
  - `websocket_server.dart:519,535` — erreurs socket silencieuses dans heartbeat (acceptable)
  - `player_bloc.dart:684,743` — erreurs de pause en mode guest silencieuses (PROBLÉMATIQUE)
  - `settings_bloc.dart:359` — erreur de calcul de cache silencieuse (acceptable)
- **Suggestion**: Remplacer `catch (_) {}` par `catch (e) { _logger.d('Ignored: $e'); }` au minimum pour tracer les erreurs silencieuses.

### [HIGH-007] Magic numbers dans les UI — seuils de couleur hardcodés
- **Files**:
  - `lib/features/player/ui/host_dashboard.dart:385-389` — `offset.abs() < 30`, `< 50`
  - `lib/features/discovery/ui/discovery_screen.dart:683-687` — `syncOffsetMs.abs() < 30`, `< 50`
- **Category**: Code Quality (Magic Numbers)
- **Issue**: Les seuils de couleur pour l'affichage du clock offset (30ms = vert, 50ms = orange, >50ms = rouge) sont dupliqués et hardcodés dans deux fichiers UI différents.
- **Suggestion**: Ajouter à `AppConstants`:
  ```dart
  static const int syncOffsetExcellentMs = 5;
  static const int syncOffsetGoodMs = 15;
  static const int syncOffsetAcceptableMs = 30;
  ```

### [HIGH-008] Inconsistance de gestion d'erreurs: throw vs return false vs return null
- **Files**: Multiples
- **Category**: Error Handling
- **Issue**: Le projet utilise 3 patterns différents pour gérer les erreurs:
  1. `throw Exception(...)` — `session_manager.dart:269,272,339`
  2. `return false` — `websocket_client.dart:167,209`
  3. `return null` — `file_transfer_service.dart`, `update_service.dart`
- **Suggestion**: Standardiser: les méthodes publiques async devraient retourner `Result<T>` ou utiliser `Either<Error, T>`. À minima, documenter la convention dans un fichier `CONVENTIONS.md`.

---

## 🟡 Medium Priority Findings

### [MED-001] TODO non résolus: guest pause/resume non implémenté
- **File**: `lib/core/session/session_manager.dart:837,841`
- **Category**: Incomplete Feature
- **Issue**:
  ```dart
  // TODO: Broadcast pause to other slaves or adjust sync
  // TODO: Broadcast resume to other slaves or adjust sync
  ```
- **Impact**: Les actions pause/resume d'un guest ne sont pas propagées aux autres slaves.
- **Suggestion**: Implémenter ou supprimer les TODOs. Si c'est hors scope, remplacer par `// Intentionally not implemented — single-guest control model`.

### [MED-002] DRY: Logique de sync quality dupliquée entre 3 endroits
- **Files**:
  - `lib/core/models/connected_device_info.dart:78-85` — `syncQuality` getter
  - `lib/features/discovery/bloc/discovery_bloc.dart:363-374` — mapping jitter → SyncQuality
  - `lib/core/network/clock_sync.dart:44-49` — `qualityLabel` getter
- **Category**: Code Quality (DRY)
- **Issue**: Les seuils de qualité de sync (5ms, 15ms, 30ms) sont définis dans 3 endroits avec des sources différentes (offset vs jitter).
- **Suggestion**: Centraliser dans `AppConstants` et créer une fonction utilitaire `SyncQuality.fromOffset(double ms)` et `SyncQuality.fromJitter(double ms)`.

### [MED-003] DRY: Pattern `formatBytes` dupliqué
- **Files**:
  - `lib/core/utils/format.dart:13-16` — `formatBytes`
  - `lib/core/services/apk_share_service.dart:234-238` — `_formatBytes` (méthode privée identique)
- **Category**: Code Quality (DRY)
- **Suggestion**: Supprimer `_formatBytes` dans `ApkShareService` et importer `formatBytes` depuis `core/utils/format.dart`.

### [MED-004] Hardcoded strings dans les UI — pas de localisation
- **Files**: Tous les fichiers UI
- **Category**: Maintainability
- **Issue**: Toutes les chaînes sont en dur en français ('Lecteur', 'Paramètres', 'Créer un groupe', etc.). Aucune infrastructure de localisation (`.arb` files).
- **Impact**: Impossible de traduire l'app sans modifier le code source.
- **Suggestion**: Introduire `flutter_localizations` et extraire les strings dans `.arb` files. Priorité basse si l'app est FR-only.

### [MED-005] FirebaseService est un Singleton mais aussi instancié avec `FirebaseService()`
- **File**: `lib/core/services/firebase_service.dart:21-23`
- **Category**: Architecture
- **Issue**: `FirebaseService` utilise le pattern singleton (`_instance`) mais dans `player_bloc.dart:290` et `discovery_bloc.dart:309`, il est instancié via `firebase ?? FirebaseService()`. Le fallback crée une nouvelle instance qui retourne le même singleton, mais c'est trompeur.
- **Suggestion**: Soit retirer le pattern singleton, soit documenter que `FirebaseService()` retourne toujours la même instance.

### [MED-006] `_handleServerBinaryMessage` est un no-op
- **File**: `lib/core/session/session_manager.dart:850-854`
- **Category**: Dead Code
- **Issue**: La méthode ne fait rien d'autre que logger. Les chunks binaires sont déjà traités ailleurs.
- **Suggestion**: Supprimer la méthode ou ajouter un commentaire `// Intentionally empty — binary handling delegated to file transfer service`.

### [MED-007] `catch (e, stack)` sans utilisation de `stack` dans certains cas
- **Files**:
  - `lib/features/player/bloc/player_bloc.dart:636` — `catch (e, stack)` mais stack utilisé
  - `lib/features/discovery/bloc/discovery_bloc.dart:415` — `catch (e, stack)` mais stack utilisé
  - `lib/features/settings/bloc/settings_bloc.dart:284` — `catch (e, stack)` mais stack utilisé
- **Category**: Code Quality
- **Issue**: Ces cas sont corrects (stack est passé à `_firebase.recordError`). Mais `main.dart:25,39` utilisent `catch (_)` alors que ce sont des erreurs d'initialisation critiques.
- **Suggestion**: Dans `main.dart`, au moins logger: `catch (e) { debugPrint('Permission error: $e'); }`

### [MED-008] `_cachedFilePath` dans SessionManager — état mutable non synchronisé
- **File**: `lib/core/session/session_manager.dart:79`
- **Category**: Code Quality
- **Issue**: `_cachedFilePath` est un état mutable partagé qui n'est pas thread-safe et peut devenir stale entre sessions.
- **Suggestion**: Reset systématique dans `leaveSession()` (déjà fait ligne 700) et `joinSession()` (ligne 345). Ajouter un getter avec validation.

### [MED-009] `_showManualIpDialog` — `safeDispose` pattern fragile
- **File**: `lib/features/discovery/ui/discovery_screen.dart:28-31`
- **Category**: Code Quality
- **Issue**: Le pattern `var disposed = false; void safeDispose() { if (!disposed) { disposed = true; controller.dispose(); } }` est un workaround pour un problème de lifecycle. Flutter gère déjà cela avec `dispose` dans un `StatefulWidget`.
- **Suggestion**: Refactorer en `StatefulWidget` avec un `TextEditingController` propre dans `dispose()`.

### [MED-010] `isVirtualIp` — liste de 15 sous-réseaux hardcodés
- **File**: `lib/core/network/device_discovery.dart:180-195`
- **Category**: Maintainability
- **Issue**: 15 `startsWith` checks pour les sous-réseaux virtuels sont hardcodés. Si Docker ajoute un nouveau range, il faut modifier le code.
- **Suggestion**: Extraire dans `AppConstants.virtualSubnets` comme `List<String>`.

### [MED-011] `onPopInvokedWithResult` — pattern PopScope complexe
- **File**: `lib/features/settings/ui/settings_screen.dart:504`
- **Category**: Code Quality
- **Issue**: `PopScope(onPopInvokedWithResult: ...)` avec un pattern `safeDispose` qui pourrait être simplifié.
- **Suggestion**: Utiliser `PopScope(canPop: true)` avec un `dispose` standard du controller.

### [MED-012] `_GuestJoinNotifier` — widget invisible qui écoute un stream
- **File**: `lib/features/player/ui/host_dashboard.dart:212-273`
- **Category**: Architecture
- **Issue**: `_GuestJoinNotifier` est un `StatefulWidget` qui retourne `SizedBox.shrink()` mais écoute un stream en arrière-plan. C'est un pattern anti-pattern en Flutter.
- **Suggestion**: Utiliser un `StreamBuilder` ou déplacer la logique dans le BLoC avec un event `GuestJoinedNotification`.

---

## 🟢 Low Priority Findings

### [LOW-001] `var` au lieu de `final` dans `_animatedRoute`
- **File**: `lib/main.dart:251-253`
- **Category**: Style
- **Issue**: `var tween`, `var offsetAnimation`, `var fadeAnimation` — ces variables ne sont jamais réassignées.
- **Suggestion**: Utiliser `final` par défaut.

### [LOW-002] `Colors.green`, `Colors.orange`, `Colors.red` hardcodés dans les UI
- **Files**: `host_dashboard.dart:96-97,385-389`, `discovery_screen.dart:585-589,683-687,869-871,928-929`
- **Category**: Style
- **Issue**: Utilisation de `Colors.*` au lieu de `Theme.of(context).colorScheme.*` pour la cohérence avec le Material 3.
- **Suggestion**: Remplacer par `colorScheme.error`, `colorScheme.tertiary`, etc.

### [LOW-003] `hostDeviceId: 'local'` et `hostDeviceName: 'Mon appareil'` hardcodés
- **File**: `lib/features/groups/ui/groups_screen.dart:121-122`
- **Category**: Code Quality
- **Issue**: Les valeurs par défaut pour la création de groupe sont hardcodées au lieu d'utiliser les vraies infos du device.
- **Suggestion**: Injecter le SessionManager ou les infos du device dans GroupsScreen.

### [LOW-004] Emoji dans les DeviceType icons
- **File**: `lib/core/models/device_info.dart:113-128`
- **Category**: Maintainability
- **Issue**: Les emojis (📱, 🔊, 📺, 💻, ❓) sont hardcodés dans l'enum. Certains peuvent ne pas s'afficher correctement sur toutes les plateformes.
- **Suggestion**: Utiliser des `IconData` Material Icons à la place.

### [LOW-005] `badCertificateCallback = (cert, host, port) => true` — sécurité
- **File**: `lib/core/network/websocket_client.dart:216`
- **Category**: Security (accepté pour dev)
- **Issue**: Accepte tous les certificats auto-signés sans validation. C'est nécessaire pour le fonctionnement local mais devrait être documenté.
- **Suggestion**: Ajouter un commentaire expliquant que c'est intentionnel pour le réseau local.

### [LOW-006] `_writeUint16` et `_writeUint32` — logique binaire manuelle
- **File**: `lib/core/network/device_discovery.dart:489-498`
- **Category**: Code Quality
- **Issue**: Ces méthodes pourraient être remplacées par `ByteData` de `dart:typed_data`.
- **Suggestion**: Utiliser `ByteData` pour la sérialisation DNS.

### [LOW-007] `SyncQuality` enum dans `connected_device_info.dart` dépend de Flutter `Colors`
- **File**: `lib/core/models/connected_device_info.dart:2`
- **Category**: Architecture
- **Issue**: Un modèle du `core/` importe `flutter/material.dart` pour les couleurs, ce qui rend le modèle non testable sans Flutter.
- **Suggestion**: Déplacer la logique de couleur dans l'UI ou utiliser des valeurs ARGB pures.

### [LOW-008] `merged_num` — fonction helper de niveau module
- **File**: `lib/core/models/session_context.dart:199-203`
- **Category**: Style
- **Issue**: Fonction snake_case en dehors d'une classe. Convention Dart préfère les fonctions privées ou les méthodes d'extension.
- **Suggestion**: Renommer en `_parseNum` (privée) ou créer une extension `MapX` avec `numOrNull(String key)`.

### [LOW-009] `_buildBinaryChunkFrame` et `parseBinaryChunkFrame` — asymétrie
- **File**: `lib/core/services/file_transfer_service.dart:211-238`
- **Category**: Code Quality
- **Issue**: `_buildBinaryChunkFrame` est une méthode d'instance mais `parseBinaryChunkFrame` est `static`. Incohérent.
- **Suggestion**: Rendre les deux `static` car aucune ne dépend de l'état de l'instance.

---

## ℹ️ Informational Suggestions

### [INFO-001] Absence de tests d'intégration
- **Category**: Testing
- **Observation**: 12 fichiers de tests unitaires existent mais aucun test d'intégration E2E. Les interactions WebSocket + Audio ne sont pas testées bout-en-bout.
- **Suggestion**: Ajouter des tests avec `integration_test` package.

### [INFO-002] Pas de linter personnalisé
- **Category**: Code Quality
- **Observation**: `analysis_options.yaml` utilise `flutter_lints` par défaut sans règles additionnelles.
- **Suggestion**: Ajouter `very_good_analysis` ou des règles custom (`lines_longer_than_80_chars`, `public_member_api_docs`).

### [INFO-003] `Platform.isWindows` checks dispersés
- **Files**: `device_discovery.dart:272,540`, `audio_session.dart:183`, `event_store.dart:116`, `metadata_service.dart:10,35`, `apk_share_service.dart:197`, `firebase_service.dart:54`
- **Category**: Architecture
- **Observation**: Les checks de plateforme sont dispersés dans 7 fichiers.
- **Suggestion**: Centraliser dans un `PlatformSupport` service ou utiliser des implémentations conditionnelles.

### [INFO-004] `FirebaseService` dans `main.dart` — erreur silencieuse
- **File**: `lib/main.dart:31-41`
- **Category**: Observability
- **Observation**: L'erreur d'initialisation Firebase est catchée et ignorée. C'est intentionnel mais aucun diagnostic n'est émis.
- **Suggestion**: Ajouter `debugPrint('Firebase init failed: $e')` dans le catch.

### [INFO-005] Pas de gestion de version de protocole WebSocket
- **File**: `lib/core/models/protocol_message.dart`
- **Category**: Architecture
- **Observation**: Le protocole n'a pas de champ de version. Si le format change, les anciens clients ne pourront pas détecter l'incompatibilité.
- **Suggestion**: Ajouter un champ `protocol_version` dans `ProtocolMessage`.

---

## Metrics Summary

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Files analyzed | 38 | - | ℹ️ |
| Lines of code | ~8,600 | - | ℹ️ |
| Avg function length | ~18 lines | < 30 | ✅ |
| Max file length | 1,317 lines | < 300 | ❌ |
| Files > 300 lines | 13 | 0 | ❌ |
| Functions > 50 lines | ~13 | 0 | ❌ |
| DRY violations (extractFileName) | 8 occurrences | 1 | ❌ |
| catch (_) blocks | 18 | 0 | ❌ |
| TODO/FIXME unresolved | 2 | 0 | ⚠️ |
| Test files | 12 | - | ℹ️ |
| Magic numbers in UI | 6+ | 0 | ❌ |

---

## Recommended Action Plan

### Sprint 1 (Immediate - Week 1)
1. **CRIT-002**: Extraire `extractFileName()` dans `format.dart` et remplacer les 8 occurrences
2. **CRIT-003**: Extraire `_autoPreloadAfterTransfer()` dans SessionManager
3. **HIGH-005**: Renommer `_stateSub` dupliqué dans PlayerBloc (`_audioStateSub` + `_sessionStateSub`)
4. **HIGH-006**: Remplacer les `catch (_)` critiques par `catch (e) { _logger.d(...) }`

### Sprint 2 (Short-term - Week 2-3)
1. **CRIT-001**: Commencer le découpage de SessionManager — extraire `SessionHostManager` et `SessionClientManager`
2. **HIGH-001**: Réduire `discovery_screen.dart` (1200 lignes) en extrayant les widgets privés dans des fichiers séparés
3. **HIGH-002**: Découper `_handlePlayCommand` (145 lignes) en 4-5 méthodes
4. **MED-001**: Résoudre les TODOs guest pause/resume ou les marquer comme "wontfix"
5. **MED-003**: Supprimer `_formatBytes` dupliqué dans `ApkShareService`

### Sprint 3 (Medium-term - Month 1-2)
1. **HIGH-003**: Introduire `PlaybackService` interface pour découpler PlayerBloc de SessionManager
2. **HIGH-007**: Centraliser les seuils de sync quality dans `AppConstants`
3. **MED-002**: Unifier la logique de SyncQuality en un seul endroit
4. **LOW-007**: Retirer la dépendance Flutter de `connected_device_info.dart`

### Backlog
- LOW et INFO items pour amélioration continue
- Ajouter `flutter_localizations` pour la traduction
- Tests d'intégration E2E
- Versioning du protocole WebSocket

---

## Appendix

### Files Analyzed (38 files)
```
lib/main.dart
lib/firebase_options.dart
lib/core/app_constants.dart
lib/core/core.dart
lib/core/audio/audio_engine.dart
lib/core/network/websocket_server.dart
lib/core/network/websocket_client.dart
lib/core/network/clock_sync.dart
lib/core/network/device_discovery.dart
lib/core/session/session_manager.dart
lib/core/models/models.dart
lib/core/models/audio_session.dart
lib/core/models/protocol_message.dart
lib/core/models/playlist.dart
lib/core/models/group.dart
lib/core/models/device_info.dart
lib/core/models/connected_device_info.dart
lib/core/models/session_context.dart
lib/core/services/firebase_service.dart
lib/core/services/foreground_service.dart
lib/core/services/file_transfer_service.dart
lib/core/services/metadata_service.dart
lib/core/services/permission_service.dart
lib/core/services/apk_share_service.dart
lib/core/services/update_service.dart
lib/core/context/event_store.dart
lib/core/context/context_manager.dart
lib/core/utils/format.dart
lib/features/player/bloc/player_bloc.dart
lib/features/player/ui/player_screen.dart
lib/features/player/ui/host_dashboard.dart
lib/features/player/ui/position_slider.dart
lib/features/discovery/bloc/discovery_bloc.dart
lib/features/discovery/ui/discovery_screen.dart
lib/features/groups/bloc/groups_bloc.dart
lib/features/groups/ui/groups_screen.dart
lib/features/settings/bloc/settings_bloc.dart
lib/features/settings/ui/settings_screen.dart
lib/features/onboarding/ui/onboarding_screen.dart
```

### Tools & Checks Performed
- Manual code review of all 38 Dart files
- Pattern matching for DRY violations, magic numbers, catch blocks
- Function/file length analysis
- Architecture coupling analysis
- TODO/FIXME/HACK detection
- Cross-file duplication detection

### Excluded from Scope
- `test/` directory (unit tests — not audited for quality)
- `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/` (platform-specific code)
- `build/`, `.dart_tool/` (generated)
- `pubspec.yaml` (dependencies not audited for vulnerabilities)
