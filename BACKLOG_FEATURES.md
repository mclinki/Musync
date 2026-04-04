# MusyncMIMO -- Backlog de Fonctionnalités

> Fichier vivant : à mettre à jour au fil du développement.
> Conventions : `[x]` fait, `[ ]` à faire, `[~]` partiellement fait.
> Priorités : **P0** critique, **P1** important, **P2** confort, **P3** futur.
> **Vérifié code source réel le 2026-04-04** — audit complet des fichiers .dart.

---

## 1. Bugs & Dette Technique

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 1.1 | [x] Implémenter le bouton skip/next | **P0** | `features/player/ui/player_screen.dart` | ✅ **FIXÉ** v0.1.22 : Skip next/prev fonctionnels avec propagation hôte→invités |
| 1.2 | [x] Bug: file d'attente ne charge pas + "charger" remplace au lieu d'ajouter | **P0** | `features/player/bloc/player_bloc.dart`, `features/player/ui/player_screen.dart` | ✅ **FIXÉ** v0.1.22 : Bouton contextuel unique + `AddToQueueRequested` charge si playlist vide |
| 1.3 | [x] Bug: premier play ne fonctionne pas (il faut stop puis play) | **P0** | `features/player/bloc/player_bloc.dart`, `core/audio/audio_engine.dart` | ✅ **FIXÉ** v0.1.18 : `resumePlayback()` fallback sur `_audioEngine.currentTrack` |
| 1.4 | [x] Bug: sync imparfaite au premier play, se corrige après pause/play | **P1** | `core/network/clock_sync.dart`, `session_manager.dart` | ✅ **FIXÉ** v0.1.18 : `defaultPlayDelayMs` 3000→5000ms, `resumeDelayMs` 1500→2500ms |
| 1.5 | [x] Supprimer les variables inutilisées | **P1** | `clock_sync.dart`, `websocket_client.dart:41`, `file_transfer_service.dart` | ✅ **FAIT** v0.1.22 |
| 1.6 | [x] Remplacer les `print()` par le `logger` | **P1** | `bin/analyze_sync.dart` + autres | ✅ **FAIT** v0.1.22 : 26 `print()` → `_logger.i()` |
| 1.7 | [x] Corriger `withOpacity` deprecated | **P2** | divers | ✅ **FAIT** : Code utilise déjà `withValues(alpha: ...)` |
| 1.8 | [~] Ajouter `Key` aux widgets manquants | **P2** | analysis_options.yaml | ⚠️ **PARTIEL** : Widgets ont `super.key`, mais lint `use_key_in_widget_constructors` non activé |
| 1.9 | [x] Exporter `file_transfer_service.dart` dans `core.dart` | **P1** | `core/core.dart:9` | ✅ **FAIT** v0.1.15 |
| 1.10 | [ ] Unifier `AudioEngineState` et `PlayerStatus` | **P2** | `audio_engine.dart`, `player_bloc.dart` | ❌ **PAS FAIT** : 2 enums identiques maintenues séparément avec mapping manuel (lignes 850-867) |
| 1.11 | [ ] Logging structuré (JSON) | **P3** | divers | ❌ **PAS FAIT** : Package `logger` en mode texte uniquement |
| 1.12 | [ ] Versioning du protocole WebSocket | **P3** | `protocol_message.dart` | ❌ **PAS FAIT** : Pas de `protocol_version` dans le protocole |

---

## 2. Fonctionnalités Manquantes (MVP / v0.1)

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 2.1 | [x] Implémenter le vrai mDNS publishing | **P0** | `core/network/device_discovery.dart` | ✅ **FAIT** : TCP probe server + mDNS multicast responder + fallback TCP subnet scan |
| 2.2 | [x] Demande de permissions runtime | **P0** | `core/services/permission_service.dart` | ✅ **FAIT** v0.1.12 : `PermissionService.requestAllPermissions()` au démarrage |
| 2.3 | [x] Parser les métadonnées ID3 | **P1** | `core/models/audio_session.dart` | ✅ **FAIT** v0.1.25 : `MetadataService` + `flutter_media_metadata` |
| 2.4 | [x] Système de queue / playlist + sauvegarde | **P1** | `core/models/playlist.dart`, `features/player/` | ✅ **FAIT** v0.1.26 : `toJson()`/`fromJson()` + SharedPreferences |
| 2.5 | [x] Indicateur de qualité de sync dans l'UI | **P1** | `features/player/ui/`, `features/discovery/ui/` | ✅ **FAIT** v0.1.16 : Badge coloré dans player, discovery, host_dashboard |
| 2.6 | [x] Widget tests significatifs | **P1** | `test/widget_test.dart` | ✅ **FAIT** v0.1.13 : 3 tests (AudioTrack fromFilePath, fromUrl, JSON serialization) |
| 2.7 | [x] Tests BLoC | **P1** | `test/` | ✅ **FAIT** v0.1.17 : 62 tests BLoC (39 DiscoveryBloc + 23 PlayerBloc) |

---

## 3. Écran Paramètres

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 3.1 | [x] Créer l'écran Settings | **P1** | `features/settings/ui/settings_screen.dart` | ✅ **FAIT** v0.1.17 : Sections Apparence/Appareil/Stockage/Réseau/Partage/Mise à jour/À propos |
| 3.2 | [x] Choix du thème (clair/sombre/système) | **P2** | `features/settings/` | ✅ **FAIT** : Dialog + persistance SharedPreferences |
| 3.3 | [x] Nom de l'appareil personnalisable | **P2** | `features/settings/` | ✅ **FAIT** v0.1.18 : Dialog + propagation SessionManager/DeviceDiscovery |
| 3.4 | [x] Volume par défaut | **P2** | `features/settings/` | ✅ **FAIT** : Slider + persistance SharedPreferences |
| 3.5 | [ ] Calibration manuelle du clock sync | **P3** | `features/settings/` | ❌ **PAS FAIT** : Calibration automatique uniquement (`startAutoCalibration()`, `forceRecalibrate()`) |
| 3.6 | [x] Gestion du cache (taille, nettoyage) | **P2** | `features/settings/` | ✅ **FAIT** : Bouton "Vider le cache" avec confirmation |
| 3.7 | [x] Rendre fonctionnelles les options Settings | **P1** | `features/settings/ui/` | ✅ **FAIT** v0.1.21 : Theme, nom, volume, cache, APK share, update check/download |
| 3.8 | [x] Notification "un invité a rejoint" | **P2** | `features/settings/`, `session_manager.dart` | ✅ **FAIT** : Switch `joinNotificationEnabled`, `HapticFeedback.lightImpact()`, SnackBar dans host_dashboard |
| 3.9 | [x] Settings supplémentaires | **P2** | `features/settings/` | ✅ **FAIT** : Délai de lecture (slider 1000-10000ms), auto-rejoindre dernière session |

---

## 4. Groupes & Sessions

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 4.1 | [x] Créer le BLoC Groups | **P1** | `features/groups/bloc/groups_bloc.dart` | ✅ **FAIT** v0.1.27 : LoadGroups, CreateGroup, DeleteGroup, RenameGroup + Firestore sync |
| 4.2 | [x] UI de création/gestion de groupes | **P1** | `features/groups/ui/groups_screen.dart` | ✅ **FAIT** v0.1.27 : Liste, FAB créer, dialogs rename/delete, empty state, route `/groups` |
| 4.3 | [~] Sauvegarde locale (sqflite) des groupes | **P2** | `features/groups/` | ⚠️ **PARTIEL** : sqflite utilisé pour EventStore (`event_store.dart`), mais groupes sauvegardés dans Firestore uniquement |
| 4.4 | [~] Historique appareils + reconnexion rapide | **P2** | `features/groups/`, `core/models/` | ⚠️ **PARTIEL** : `_discoveredDevices` en mémoire uniquement, pas de persistance ni reconnexion rapide |
| 4.5 | [ ] Partage de groupe par QR code | **P2** | `features/groups/` | ❌ **PAS FAIT** : Aucun package QR dans le projet. Partage via URL HTTP copiable uniquement |
| 4.6 | [x] Renommer un groupe/session | **P2** | `session_manager.dart`, `host_dashboard.dart` | ✅ **FAIT** : `renameSession()` dans SessionManager + `_showRenameSessionDialog()` dans host_dashboard |

---

## 5. Player & Audio

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 5.1 | [x] Skip next / Skip previous | **P0** | `features/player/ui/player_screen.dart` | ✅ **FIXÉ** v0.1.22 : Propagation hôte→invités via WebSocket |
| 5.2 | [x] Contrôle du volume à distance (host → slave) | **P2** | `session_manager.dart`, `protocol_message.dart` | ✅ **FAIT** v0.1.31 : `MessageType.volumeControl`, `broadcastVolume`, `VolumeRemoteChanged` |
| 5.3 | [x] Mode shuffle | **P2** | `features/player/` | ✅ **FAIT** v0.1.28 : `Playlist.shuffle()`, `ToggleShuffleRequested`, propagation aux invités |
| 5.4 | [x] Mode repeat (un / all) | **P2** | `features/player/` | ✅ **FAIT** v0.1.28 : `RepeatMode` enum (off/one/all), `toggleRepeat()`, bouton repeat |
| 5.5 | [ ] Égaliseur simple (bass/treble) | **P3** | `core/audio/` | ❌ **PAS FAIT** : `just_audio` utilisé sans `AudioPipeline` |
| 5.6 | [ ] Affichage de la pochette d'album | **P3** | `features/player/ui/` | ❌ **PAS FAIT** : `audio_metadata_reader` dans pubspec mais pas utilisé pour les pochettes |
| 5.7 | [x] Contrôle depuis la notification (Android) | **P2** | `core/services/foreground_service.dart` | ✅ **FAIT** : `ForegroundService` avec MethodChannel `startForeground`/`stopForeground` |
| 5.8 | [x] Dashboard host : appareils connectés + latence | **P1** | `features/player/ui/host_dashboard.dart` | ✅ **FAIT** v0.1.17 : HostDashboardCard avec nom, IP, badge sync, offset ms |
| 5.9 | [x] Indicateur "tous les invités ont chargé" | **P2** | `session_manager.dart` | ✅ **FAIT** : `StreamController` broadcast `_allGuestsReadyController` émet `slaves.every((s) => s.isSynced)` |
| 5.10 | [x] Stats de session | **P3** | `core/models/session_context.dart` | ✅ **FAIT** : `summary` getter avec résumé lisible + stats de sync (offset, jitter, qualité) |
| 5.11 | [x] Volume système (au lieu de volume interne) | **P2** | `core/services/system_volume_service.dart` | ✅ **FAIT** : `SystemVolumeService` avec `volume_controller`, just_audio à 1.0, volume système prend le relais |
| 5.12 | [ ] Spatialisation audio multi-appareils | **P3** | `core/audio/` | ❌ **PAS FAIT** : Répartir canaux L/R/C/RL/RR sur les appareils connectés (feature différenciante) |

---

## 6. Réseau & Sync

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 6.1 | [x] Chiffrement WSS/TLS | **P1** | `websocket_server.dart`, `websocket_client.dart` | ✅ **FAIT** v0.1.24 : Certificat auto-signé, `bindSecure`, `wss://` + `badCertificateCallback` + certificate pinning SHA-1. **v0.1.46** : TLS désactivé par défaut (`ws://`) pour compatibilité LAN. Toggle fonctionnel dans Paramètres → Réseau. |
| 6.2 | [x] Buffering adaptatif (jitter réseau) | **P2** | `core/network/clock_sync.dart` | ✅ **FAIT** : Calibration adaptative (15s/10s/3s/1s), filtrage IQR + Kalman filter, measurement noise adaptatif |
| 6.3 | [x] Gestion background iOS | **P1** | `ios/` | ✅ **FAIT** v0.1.23 : `UIBackgroundModes` (audio+fetch) + `AVAudioSessionCategoryPlayback` |
| 6.4 | [ ] Sync cross-network (via signaling cloud) | **P3** | `core/network/` | ❌ **PAS FAIT** : LAN uniquement (mDNS + TCP subnet scan). Firestore pour groupes, pas de signaling temps réel |
| 6.5 | [ ] Support Bluetooth comme fallback découverte | **P3** | `core/network/` | ❌ **PAS FAIT** : Aucune dépendance Bluetooth dans pubspec.yaml |
| 6.6 | [x] Envoi direct de l'APK vers appareil Android | **P2** | `core/services/apk_share_service.dart` | ✅ **FAIT** : Service HTTP local + token aléatoire 32 chars + bind IP locale + UI Settings complète |
| 6.7 | [x] Mise à jour OTA entre appareils | **P1** | `core/services/update_service.dart` | ✅ **FAIT** v0.1.21 : Vérifie GitHub Releases, compare semver, télécharge APK, installe |
| 6.8 | [x] Backoff exponentiel reconnexion | **P2** | `websocket_client.dart` | ✅ **FAIT** : `1s → 2s → 4s → 8s → 16s → 30s (max)` avec formule `(1 << (_reconnectAttempts - 1))` |
| 6.9 | [ ] Gestion rotation d'IP (DHCP renewal) | **P2** | `session_manager.dart`, `websocket_client.dart` | ❌ **PAS FAIT** : Pas de reconnexion auto si IP hôte change pendant session |
| 6.10 | [ ] Scan subnet optimisé (ARP cache) | **P3** | `core/network/device_discovery.dart` | ⚠️ **PARTIEL** : TCP subnet scan `.1-254` existe comme fallback, mais pas de scan ARP pour IPs actives |
| 6.11 | [ ] Signature HMAC des messages | **P2** | `core/auth/message_signer.dart` | ❌ **PAS FAIT** : Uniquement SHA-256 pour vérif APK, pas de HMAC sur les messages WebSocket |

---

## 7. Authentification & Comptes

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 7.1 | [ ] Auth par email/mot de passe | **P2** | `core/services/firebase_service.dart` | ❌ **PAS FAIT** : Uniquement `signInAnonymously()` implémenté |
| 7.2 | [ ] Auth sociale (Google, Apple) | **P3** | `core/services/firebase_service.dart` | ❌ **PAS FAIT** : Aucune dépendance GoogleSignIn/AppleSignIn |
| 7.3 | [~] Profil utilisateur (nom, avatar) | **P3** | nouveau : `features/profile/` | ⚠️ **PARTIEL** : `CircleAvatar` présent dans plusieurs écrans, mais pas de vrai profil (nom, photo, bio) |
| 7.4 | [ ] Historique des sessions | **P3** | nouveau : `features/history/` | ❌ **PAS FAIT** : EventStore garde session courante uniquement, pas d'historique passé |
| 7.5 | [ ] Auth JWT custom pour sessions | **P2** | `core/auth/auth_service.dart` | ⚠️ **PARTIEL** : Firebase Auth utilise JWT en interne, mais pas de système JWT custom pour l'app |

---

## 8. Intégrations Externes

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 8.1 | [ ] Chromecast (Google Cast) | **P3** | nouveau | ❌ **PAS FAIT** : Icône `Icons.cast_connected` présente mais non fonctionnel |
| 8.2 | [ ] AirPlay 2 | **P3** | nouveau | ❌ **PAS FAIT** |
| 8.3 | [ ] Spotify / Deezer integration | **P3** | nouveau | ❌ **PAS FAIT** |
| 8.4 | [ ] Import depuis DLNA / SMB | **P3** | nouveau | ❌ **PAS FAIT** |
| 8.5 | [ ] YouTube (audio sans pub) | **P3** | nouveau | ❌ **PAS FAIT** |

---

## 9. UX & Onboarding

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 9.1 | [x] Tutoriel / onboarding à la première ouverture | **P2** | `features/onboarding/` | ✅ **FAIT** v0.1.28 : `OnboardingScreen` 4 pages, PageView, flag SharedPreferences |
| 9.2 | [x] Animations de transition entre écrans | **P2** | `features/*/ui/` | ✅ **FAIT** v0.1.31 : `PageRouteBuilder` slide+fade, `flutter_animate`, `AnimatedSwitcher` |
| 9.3 | [x] Feedback haptique sur les actions | **P3** | `session_manager.dart`, `host_dashboard.dart` | ✅ **FAIT** : `HapticFeedback.lightImpact()` sur arrivée invité et dans snackbar |
| 9.4 | [ ] Widget iOS / Android home screen | **P3** | `ios/`, `android/` | ❌ **PAS FAIT** : Aucune dépendance home_widget |
| 9.5 | [~] Mode paysage / tablette | **P3** | `features/*/ui/` | ⚠️ **PARTIEL** : `DeviceType.tablet` existe dans l'enum, mais pas de layout responsive (`OrientationBuilder`, `LayoutBuilder`) |

---

## 10. Tests & CI

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 10.1 | [x] Tests unitaires BLoC (Discovery, Player) | **P1** | `test/` | ✅ **FAIT** : `bloc_test` + `mocktail`, 200+ tests |
| 10.2 | [ ] Tests d'intégration (2 émulateurs) | **P2** | `integration_test/` | ❌ **PAS FAIT** : Aucun dossier `test_driver/` ni `integration_test/` |
| 10.3 | [x] CI/CD (GitHub Actions) | **P2** | `.github/workflows/` | ✅ **FAIT** v0.1.31 : `ci.yml` (analyze+test+coverage+build), `release.yml` (tag → APK + Release) |
| 10.4 | [~] Couverture de code > 60% | **P2** | | ⚠️ **PARTIEL** : `flutter test --coverage` configuré dans CI, mais % actuel inconnu |
| 10.5 | [x] Tests de performance clock sync | **P2** | `test/clock_sync_perf_test.dart` | ✅ **FAIT** : 9 tests de performance (convergence, jitter, qualité) inclus dans CI |

---

## 11. Architecture Agentique (GUIDE_BONNES_PRATIQUES)

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 11.1 | [x] SessionContext versionné | **P1** | `core/models/session_context.dart` | ✅ **FAIT** v0.1.20 : Schéma v2 avec migration v1→v2, Equatable, copyWith, summary |
| 11.2 | [x] EventStore (SQLite) | **P1** | `core/context/event_store.dart` | ✅ **FAIT** v0.1.20 : Tables session_events + context_snapshots |
| 11.3 | [x] ContextManager | **P1** | `core/context/context_manager.dart` | ✅ **FAIT** v0.1.20 : recordEvent, createSnapshot, restoreContext, getContextSummary |
| 11.4 | [x] Intégration ContextManager dans SessionManager | **P1** | `core/session/session_manager.dart` | ✅ **FAIT** v0.1.20 : Events + snapshot on leaveSession |
| 11.5 | [x] contextSync dans protocole WebSocket | **P1** | `protocol_message.dart`, `websocket_server.dart` | ✅ **FAIT** v0.1.41 : Envoi auto du contexte lors reconnexion |
| 11.6 | [ ] TokenManager avec refresh auto | **P2** | `core/auth/token_manager.dart` | ❌ **PAS FAIT** |
| 11.7 | [ ] AgentContextInterface | **P2** | `core/context/agent_context_interface.dart` | ❌ **PAS FAIT** |
| 11.8 | [ ] Reprise auto avec backoff exponentiel | **P2** | `core/context/auto_recovery_manager.dart` | ❌ **PAS FAIT** (backoff WebSocket existe, mais pas de recovery manager dédié) |

---

## Résumé des priorités (vérifié 2026-04-04 — audit code source réel)

| Priorité | Total | ✅ Faites | ⚠️ Partielles | ❌ Restantes |
|----------|-------|-----------|---------------|-------------|
| **P0** | 4 | 4 | 0 | 0 |
| **P1** | 11 | 11 | 0 | 0 |
| **P2** | 22 | 14 | 3 | 5 |
| **P3** | 19 | 3 | 2 | 14 |

### ✅ P0/P1 — TOUTES FAITES
- Skip/next, file d'attente, premier play, sync, mDNS, permissions, ID3, playlist, sync quality, BLoC tests, Settings screen, Groups BLoC+UI, WSS/TLS, iOS background, OTA update, context system

### ✅ P2 — FAITES (14/22)
- withOpacity→withValues, cache management, Settings fonctionnelles, notif invité rejoint, Settings supplémentaires (délai+auto-rejoin), rename session, volume remote, shuffle, repeat, foreground service, tous prêts indicator, APK share, backoff exponentiel, volume système, tests perf clock sync

### ⚠️ P2 — PARTIELLES (3/22)
- 1.8 Key widgets (lint pas activé mais super.key présent)
- 4.3 sqflite groupes (sqflite utilisé pour EventStore, pas groupes)
- 4.4 Historique appareils (mémoire uniquement, pas persisté)
- 10.4 Couverture code (CI configuré, % inconnu)

### ❌ P2 — RESTANTES (5/22)
- 4.5 QR code partage groupe
- 6.9 Gestion rotation IP DHCP
- 6.11 Signature HMAC messages
- 7.1 Auth email/password
- 7.5 Auth JWT custom
- 10.2 Tests intégration 2 émulateurs

### ❌ P3 — RESTANTES (14/19)
- 3.5 Calibration manuelle clock sync
- 5.5 Égaliseur
- 5.6 Pochette album
- 5.12 Spatialisation audio
- 6.4 Sync cross-network cloud
- 6.5 Bluetooth fallback
- 6.10 Scan subnet ARP (partiel)
- 7.2 Auth sociale
- 7.3 Profil utilisateur (partiel)
- 7.4 Historique sessions
- 8.1-8.5 Intégrations externes (Chromecast, AirPlay, Spotify, DLNA, YouTube)
- 9.4 Widget home screen
- 9.5 Mode paysage/tablette (partiel)
- 11.6 TokenManager, 11.7 AgentContextInterface, 11.8 Auto recovery
- 1.11 Logging JSON, 1.12 Versioning protocole

---

## Fusions effectuées (2026-03-31)

| # | Fusion | Raison |
|---|--------|--------|
| A | 3.9 "notif sonore" → 3.8 "notif invité a rejoint" | Même fonctionnalité |
| B | 4.4 + 4.6 → 4.4 "historique + reconnexion rapide" | "Rejoindre en un tap" = sous-ensemble de l'historique |
| C | 3.7 "À propos/liens" → 3.7 "options fonctionnelles" | Liens GitHub absorbé |
| D | 2.4 + 5.8 → 2.4 "queue/playlist + sauvegarde" | Sauvegarde = partie du système de playlist |

---

## Comment utiliser ce fichier

1. **Piocher** : quand tu veux bosser, filtrer par priorité ou catégorie
2. **Déplacer** une tâche vers un fichier `TODO_SESSION.md` quand tu commences à travailler dessus
3. **Cocher** `[x]` quand c'est fait, ajouter la date
4. **Ajouter** de nouvelles idées au fil de l'eau

---

*Dernière mise à jour : 2026-04-04 — ✅ TOUTES les P0 et P1 sont faites. Audit code source réel effectué. 200+ tests.*
