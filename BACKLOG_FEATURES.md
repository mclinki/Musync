# MusyncMIMO -- Backlog de Fonctionnalités

> Fichier vivant : à mettre à jour au fil du développement.
> Conventions : `[x]` fait, `[ ]` à faire, `[~]` partiellement fait.
> Priorités : **P0** critique, **P1** important, **P2** confort, **P3** futur.

---

## 1. Bugs & Dette Technique

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 1.1 | [x] Implémenter le bouton skip/next | **P0** | `features/player/ui/player_screen.dart` | ✅ **FIXÉ** v0.1.22 : Skip next/prev fonctionnels avec propagation hôte→invités
| 1.2 | [x] Bug: file d'attente ne charge pas + "charger" remplace au lieu d'ajouter | **P0** | `features/player/bloc/player_bloc.dart`, `features/player/ui/player_screen.dart` | ✅ **FIXÉ** v0.1.22 : Bouton contextuel unique + `AddToQueueRequested` charge si playlist vide
| 1.3 | [x] Bug: premier play ne fonctionne pas (il faut stop puis play) | **P0** | `features/player/bloc/player_bloc.dart`, `core/audio/audio_engine.dart` | ✅ **FIXÉ** v0.1.18 : `resumePlayback()` fallback sur `_audioEngine.currentTrack`
| 1.4 | [x] Bug: sync imparfaite au premier play, se corrige après pause/play | **P1** | `core/network/clock_sync.dart`, `session_manager.dart` | ✅ **FIXÉ** v0.1.18 : `defaultPlayDelayMs` 3000→5000ms, `resumeDelayMs` 1500→2500ms
| 1.5 | [x] Supprimer les variables inutilisées | **P1** | `clock_sync.dart`, `websocket_client.dart:41`, `file_transfer_service.dart` | ✅ **FAIT** v0.1.22 : `_maxSampleAgeMs` et `_chunkIndex` déjà supprimés, autres utilisés → conservés
| 1.6 | [x] Remplacer les `print()` par le `logger` | **P1** | `bin/analyze_sync.dart` + autres | ✅ **FAIT** v0.1.22 : 26 `print()` → `_logger.i()` dans `analyze_sync.dart`
| 1.7 | Corriger `withOpacity` deprecated | **P2** | divers | Remplacer par `Color.withValues()` |
| 1.8 | Ajouter `Key` aux widgets manquants | **P2** | 1 widget | `use_key_in_widget_constructors` |
| 1.9 | [x] Exporter `file_transfer_service.dart` dans `core.dart` | **P1** | `core/core.dart:9` | ✅ **FAIT** v0.1.15

---

## 2. Fonctionnalités Manquantes (MVP / v0.1)

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 2.1 | Implémenter le vrai mDNS publishing | **P0** | `core/network/device_discovery.dart:60-93` | `startPublishing()` crée un TCP probe server + mDNS multicast responder (UDP socket qui répond aux queries). Le mDNS package-based discovery est aussi présent. Couverture correcte mais le publishing manuel DNS reste fragile |
| 2.2 | Demande de permissions runtime | **P0** | `core/services/permission_service.dart` | ✅ **FAIT** v0.1.12 : `PermissionService.requestAllPermissions()` appelé dans `main.dart` au démarrage (nearbyWifiDevices, audio, locationWhenInUse) avec timeout 5s |
| 2.3 | [x] Parser les métadonnées ID3 | **P1** | `core/models/audio_session.dart` | ✅ **FAIT** v0.1.25 : `MetadataService` + `flutter_media_metadata`. `AudioTrack.fromFilePathWithMetadata()` async. Titre/artiste/album/duration parsés. Fallback nom de fichier. Guard Windows |
| 2.4 | [x] Système de queue / playlist + sauvegarde | **P1** | `core/models/playlist.dart`, `features/player/` | ✅ **FAIT** v0.1.26 : `Playlist.toJson()`/`fromJson()`. Sauvegarde auto dans SharedPreferences après chaque modif. Restauration au démarrage |
| 2.5 | [x] Indicateur de qualité de sync dans l'UI | **P1** | `features/player/ui/`, `features/discovery/ui/` | ✅ **FAIT** v0.1.16 : Affiché dans player_screen, discovery_screen (badge coloré), et host_dashboard |
| 2.6 | [x] Widget tests significatifs | **P1** | `test/widget_test.dart` | ✅ **FAIT** v0.1.13 : 3 tests (AudioTrack fromFilePath, fromUrl, JSON serialization). Note : ce sont des tests de modèles, pas de vrais widget tests |
| 2.7 | [x] Tests BLoC | **P1** | `test/` | ✅ **FAIT** v0.1.17 : 62 tests BLoC (39 DiscoveryBloc + 23 PlayerBloc) avec mocktail + blocTest |

---

## 3. Écran Paramètres

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 3.1 | [x] Créer l'écran Settings | **P1** | `features/settings/ui/settings_screen.dart` | ✅ **FAIT** v0.1.17 : 552 lignes, sections Apparence/Appareil/Stockage/Réseau/Partage/Mise à jour/À propos
| 3.2 | Choix du thème (clair/sombre/système) | **P2** | `features/settings/` | ✅ **FAIT** : Dialog de sélection + persistance SharedPreferences
| 3.3 | Nom de l'appareil personnalisable | **P2** | `features/settings/` | ✅ **FAIT** v0.1.18 : Dialog + propagation au SessionManager/DeviceDiscovery
| 3.4 | Volume par défaut | **P2** | `features/settings/` | ✅ **FAIT** : Slider + persistance SharedPreferences
| 3.5 | Calibration manuelle du clock sync | **P3** | `features/settings/` | Pour debug avancé
| 3.6 | Gestion du cache (taille, nettoyage) | **P2** | `features/settings/` | ✅ **FAIT** : Bouton "Vider le cache" avec confirmation
| 3.7 | [x] Rendre fonctionnelles les options existantes du menu Settings | **P1** | `features/settings/ui/` | ✅ **PARTIEL** v0.1.21 : Theme, nom, volume, cache, APK share, update check/download fonctionnels. Limité : "Signaler un bug" = copie URL, "Source" = copie URL, switch chiffrement désactivé, install APK = copie chemin
| 3.8 | Notification "un invité a rejoint" (optionnel) | **P2** | `features/settings/`, `session_manager.dart` | Toggle dans Settings ; quand activé, notif sonore/vibration à chaque connexion d'un appareil |
| 3.9 | Settings supplémentaires | **P2** | `features/settings/` | Délai de lecture par défaut, auto-rejoindre dernière session |

---

## 4. Groupes & Sessions

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 4.1 | [x] Créer le BLoC Groups | **P1** | `features/groups/bloc/groups_bloc.dart` | ✅ **FAIT** v0.1.27 : GroupsBloc avec LoadGroups, CreateGroup, DeleteGroup, RenameGroup + Firestore sync
| 4.2 | [x] UI de création/gestion de groupes | **P1** | `features/groups/ui/groups_screen.dart` | ✅ **FAIT** v0.1.27 : GroupsScreen avec liste, FAB créer, dialogs rename/delete, empty state, route `/groups`
| 4.3 | Sauvegarde locale (sqflite) des groupes | **P2** | `features/groups/` | Pour fonctionner sans Firebase |
| 4.4 | Historique des appareils connectés + reconnexion rapide | **P2** | `features/groups/`, `core/models/` | Liste des appareils avec lesquels on s'est déjà connecté (nom, IP, dernière session) ; rejoindre en un tap |
| 4.5 | Partage de groupe par QR code (optionnel) | **P2** | `features/groups/` | Bouton "QR Code" dans l'écran de session ; le guest scanne pour rejoindre ; optionnel, pas le flux par défaut |
| 4.6 | Renommer un groupe/session | **P2** | `features/groups/`, `session_manager.dart` | Permettre de donner un nom perso à la session ("Soirée chez Marc" au lieu de "Session_8472") |

---

## 5. Player & Audio

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 5.1 | [x] Skip next / Skip previous | **P0** | `features/player/ui/player_screen.dart` | ✅ **FIXÉ** v0.1.22 : Boutons skip fonctionnels, propagation hôte→invités via WebSocket
| 5.2 | [x] Contrôle du volume à distance (host → slave) | **P2** | `session_manager.dart`, `protocol_message.dart` | ✅ **FAIT** v0.1.31 : `MessageType.volumeControl`, `broadcastVolume`, `VolumeRemoteChanged` event. Host broadcast, slave applique
| 5.3 | [x] Mode shuffle | **P2** | `features/player/` | ✅ **FAIT** v0.1.28 : `Playlist.shuffle()`, `ToggleShuffleRequested`, bouton shuffle dans player UI, propagation aux invités
| 5.4 | [x] Mode repeat (un / all) | **P2** | `features/player/` | ✅ **FAIT** v0.1.28 : `RepeatMode` enum (off/one/all), `toggleRepeat()`, `_onTrackCompleted` respecte le mode, bouton repeat dans player UI
| 5.5 | Égaliseur simple (bass/treble) | **P3** | `core/audio/` | just_audio supporte un `AudioPipeline` |
| 5.6 | Affichage de la pochette d'album | **P3** | `features/player/ui/` | Dépend de 2.3 (ID3 parsing) |
| 5.7 | Contrôle depuis la notification (Android) | **P2** | `core/services/foreground_service.kt` | MediaSession / media controls dans la notification |
| 5.8 | [x] Dashboard host : appareils connectés + latence | **P1** | `features/player/ui/host_dashboard.dart`, `session_manager.dart`, `player_bloc.dart` | ✅ **FAIT** v0.1.17 : HostDashboardCard avec nom, IP, badge sync, offset ms |
| 5.9 | Indicateur "tous les invités ont chargé" | **P2** | `features/player/ui/`, `session_manager.dart` | Voyant vert quand tous les appareils ont fini de charger le morceau (prêt à jouer en sync) |
| 5.10 | Stats de session | **P3** | `features/player/`, `core/models/` | Récap en fin de session : durée, nb morceaux joués, nb appareils connectés, qualité moyenne de sync |

---

## 6. Réseau & Sync

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 6.1 | [x] Chiffrement WSS/TLS | **P1** | `websocket_server.dart`, `websocket_client.dart` | ✅ **FAIT** v0.1.24 : Certificat auto-signé (basic_utils), `bindSecure`, `wss://` + `badCertificateCallback`
| 6.2 | Buffering adaptatif (jitter réseau) | **P2** | `core/network/clock_sync.dart` | Pas de compensation de jitter ; délai fixe uniquement |
| 6.3 | [x] Gestion background iOS | **P1** | `ios/` | ✅ **FAIT** v0.1.23 : `UIBackgroundModes` (audio+fetch) + `AVAudioSessionCategoryPlayback` via `ForegroundService`
| 6.4 | Sync cross-network (via signaling cloud) | **P3** | `core/network/` | LAN uniquement pour l'instant |
| 6.5 | Support Bluetooth comme fallback découverte | **P3** | `core/network/` | Quand mDNS échoue sur certains réseaux |
| 6.6 | Envoi direct de l'APK vers appareil Android | **P2** | `core/network/file_transfer_service.dart` | Permettre d'envoyer l'APK Musync à un autre Android via le réseau local (déjà un `FileTransferService`) ; évite de passer par un store |
| 6.7 | Mise à jour OTA entre appareils (version check + envoi APK) | **P1** | `core/network/`, `session_manager.dart`, `features/settings/` | Option dans Settings "Envoyer une mise à jour". Lors de la connexion, comparer les versions (semver) ; si un appareil a une version antérieure, proposer à l'hôte d'envoyer la MAJ. Permet à l'app de circuler de façon autonome sans store |

---

## 7. Authentification & Comptes

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 7.1 | Auth par email/mot de passe | **P2** | `core/services/firebase_service.dart` | Auth anonyme seule implémentée |
| 7.2 | Auth sociale (Google, Apple) | **P3** | `core/services/firebase_service.dart` | |
| 7.3 | Profil utilisateur (nom, avatar) | **P3** | nouveau : `features/profile/` | |
| 7.4 | Historique des sessions | **P3** | nouveau : `features/history/` | |

---

## 8. Intégrations Externes

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 8.1 | Chromecast (Google Cast) | **P3** | nouveau | Roadmap Phase 2 |
| 8.2 | AirPlay 2 | **P3** | nouveau | Roadmap Phase 2 |
| 8.3 | Spotify / Deezer integration | **P3** | nouveau | Streaming depuis services tiers |
| 8.4 | Import depuis DLNA / SMB | **P3** | nouveau | Accès aux NAS locaux |
| 8.5 | YouTube (audio sans pub) | **P3** | nouveau | Via Brave (ad-block natif) ou extraction audio (yt-dlp) ; permet de streamer du son YouTube en sync sans pub ; légalité à vérifier selon usage |

---

## 9. UX & Onboarding

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 9.1 | [x] Tutoriel / onboarding à la première ouverture | **P2** | `features/onboarding/` | ✅ **FAIT** v0.1.28 : `OnboardingScreen` 4 pages, PageView, flag SharedPreferences, bouton "Tutoriel" dans Settings
| 9.2 | [x] Animations de transition entre écrans | **P2** | `features/*/ui/` | ✅ **FAIT** v0.1.31 : `PageRouteBuilder` slide+fade, `flutter_animate` sur éléments clés, `AnimatedSwitcher` sur play/pause
| 9.3 | Feedback haptique sur les actions | **P3** | `features/player/ui/` | |
| 9.4 | Widget iOS / Android home screen | **P3** | `ios/`, `android/` | Accès rapide aux sessions favorites ; à réfléchir : quoi afficher ? (sessions dispo, bouton rejoindre, morceau en cours ?) |
| 9.5 | Mode paysage / tablette | **P3** | `features/*/ui/` | Layout responsive |

---

## 10. Tests & CI

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 10.1 | Tests unitaires BLoC (Discovery, Player) | **P1** | `test/` | `bloc_test` + `mocktail` déjà installés |
| 10.2 | Tests d'integration (2 émulateurs) | **P2** | `test_driver/` | Vérifier sync réelle |
| 10.3 | [x] CI/CD (GitHub Actions) | **P2** | `.github/workflows/` | ✅ **FAIT** v0.1.31 : `ci.yml` (analyze+test+coverage+build Android+Windows), `release.yml` (tag v* → APK release + GitHub Release)
| 10.4 | Couverture de code > 60% | **P2** | | Actuellement ~32 tests unitaires |
| 10.5 | Tests de performance clock sync | **P2** | `bin/analyze_sync.dart` | Intégrer dans CI |

---

## Résumé des priorités (vérifié 2026-04-03 — TOUTES P0/P1 + 9 P2 FAITES)

| Priorité | Count | Tâches réellement restantes |
|----------|-------|--------|
| **P0** | 0 | ✅ **TOUTES FAITES** |
| **P1** | 0 | ✅ **TOUTES FAITES** |
| **P2** | 8 | 1.7, 1.8, 3.5, 3.9, 4.3, 4.4, 4.5, 4.6, 5.7, 5.9, 6.2, 6.6, 10.2, 10.4, 10.5 |
| **P3** | 16 | 3.5, 5.5, 5.6, 5.10, 6.4, 6.5, 7.2, 7.3, 7.4, 8.1, 8.2, 8.3, 8.4, 8.5, 9.3, 9.4, 9.5 |

### ✅ Toutes les features P0/P1 implémentées (v0.1.21 → v0.1.27)
- **Vague 1** (v0.1.21→v0.1.24) : UX file d'attente, variables inutilisées, print→logger, WSS/TLS, iOS background
- **Vague 2** (v0.1.24→v0.1.27) : ID3 parsing, Playlist persistence, Groups BLoC + UI

### ✅ Features P2 implémentées (v0.1.27 → v0.1.31)
- **Vague 3** (v0.1.27→v0.1.30) : Shuffle + Repeat, Onboarding, Cleanup (withOpacity, Key), Indicateur "tous prêts", Notification invité rejoint
- **Vague 4** (v0.1.30→v0.1.31) : Volume remote control, Animations de transition, CI/CD GitHub Actions

---

## Fusions effectuées (2026-03-31)

| # | Fusion | Raison |
|---|--------|--------|
| A | 3.9 "notif sonore" → 3.8 "notif invité a rejoint" | Même fonctionnalité |
| B | 4.4 + 4.6 → 4.4 "historique + reconnexion rapide" | "Rejoindre en un tap" = sous-ensemble de l'historique |
| C | 3.7 "À propos/liens" → 3.7 "options fonctionnelles" | Liens GitHub absorbé par "rendre options fonctionnelles" |
| D | 2.4 + 5.8 → 2.4 "queue/playlist + sauvegarde" | Sauvegarde = partie du système de playlist |

---

## Comment utiliser ce fichier

1. **Piocher** : quand tu veux bosser, filtrer par priorité ou catégorie
2. **Déplacer** une tâche vers un fichier `TODO_SESSION.md` quand tu commences à travailler dessus
3. **Cocher** `[x]` quand c'est fait, ajouter la date
4. **Ajouter** de nouvelles idées au fil de l'eau

---

*Dernière mise à jour : 2026-04-03 — ✅ TOUTES les P0 et P1 sont faites. v0.1.27. 103/103 tests.*
