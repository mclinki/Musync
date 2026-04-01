# MusyncMIMO -- Backlog de Fonctionnalités

> Fichier vivant : à mettre à jour au fil du développement.
> Conventions : `[x]` fait, `[ ]` à faire, `[~]` partiellement fait.
> Priorités : **P0** critique, **P1** important, **P2** confort, **P3** futur.

---

## 1. Bugs & Dette Technique

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 1.1 | Implémenter le bouton skip/next | **P0** | `features/player/ui/player_screen.dart:229` | `onPressed: null, // TODO: implement skip` |
| 1.2 | Bug: file d'attente ne charge pas + "charger" remplace au lieu d'ajouter | **P0** | `features/player/bloc/player_bloc.dart`, `features/player/ui/player_screen.dart` | Si on ajoute un morceau en file d'attente sans faire "charger" d'abord → reste bloqué (ne charge pas, ne peut pas jouer). Ensuite "charger" remplace le morceau en file au lieu d'ajouter. **Fix UX** : un seul bouton "Charger un premier morceau" qui se transforme en "Ajouter à la file d'attente" dès qu'au moins un morceau est chargé |
| 1.3 | Bug: premier play ne fonctionne pas (il faut stop puis play) | **P0** | `features/player/bloc/player_bloc.dart`, `core/audio/audio_engine.dart` | Quand un morceau est chargé pour la 1ère fois, appuyer sur play ne fait rien. Il faut d'abord appuyer sur stop (qui "charge" réellement le morceau) puis play pour que ça fonctionne. Problème probable : `playTrack()` ne fait pas le `load` + `play` atomiquement |
| 1.4 | Bug: sync imparfaite au premier play, se corrige après pause/play | **P1** | `core/network/clock_sync.dart`, `session_manager.dart` | La synchronisation n'est pas optimale au premier lancement. Pause puis play améliore la sync (parfois il faut plusieurs cycles). Problème probable : le clock offset n'est pas appliqué ou recalculé au bon moment lors du premier `playAt` ; la pause/play force une resynchronisation |
| 1.5 | Supprimer les variables inutilisées | **P1** | `clock_sync.dart`, `websocket_client.dart:41`, `file_transfer_service.dart` | `_maxSampleAgeMs`, `_maxSyncAttempts`, `_syncCompleter`, `_chunkIndex` |
| 1.6 | Remplacer les `print()` par le `logger` | **P1** | `bin/analyze_sync.dart` + autres | ~20 occurrences `avoid_print` |
| 1.7 | Corriger `withOpacity` deprecated | **P2** | divers | Remplacer par `Color.withValues()` |
| 1.8 | Ajouter `Key` aux widgets manquants | **P2** | 1 widget | `use_key_in_widget_constructors` |
| 1.9 | Exporter `file_transfer_service.dart` dans `core.dart` | **P1** | `core/core.dart:9` | Le barrel file n'exporte pas ce service |

---

## 2. Fonctionnalités Manquantes (MVP / v0.1)

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 2.1 | Implémenter le vrai mDNS publishing | **P0** | `core/network/device_discovery.dart:60-93` | `startPublishing()` ne crée qu'un TCP probe server, pas de registration mDNS réelle |
| 2.2 | Demande de permissions runtime | **P0** | nouveau fichier dans `features/` | mDNS/Wi-Fi sur Android 13+ non demandé ; permissions déclarées dans manifest mais jamais sollicitées |
| 2.3 | Parser les métadonnées ID3 | **P1** | `core/models/audio_session.dart` | `AudioTrack` a `artist`/`album` mais aucun parsing ; titre = nom de fichier uniquement |
| 2.4 | Système de queue / playlist + sauvegarde | **P1** | nouveau : `core/models/playlist.dart`, `features/player/` | Modèle queue, UI playlist, skip-next/skip-prev, sauvegarde locale pour réutilisation (SharedPreferences ou sqflite) |
| 2.5 | Indicateur de qualité de sync dans l'UI | **P1** | `features/player/ui/`, `features/discovery/ui/` | `ClockSyncStats.qualityLabel` existe mais n'est pas exposé visuellement |
| 2.6 | Widget tests significatifs | **P1** | `test/widget_test.dart` | Test actuel = `expect(true, isTrue)` (no-op) |
| 2.7 | Tests BLoC | **P1** | `test/` | `bloc_test` est dans dev_dependencies mais aucun test BLoC n'existe |

---

## 3. Écran Paramètres

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 3.1 | Créer l'écran Settings | **P1** | `features/settings/ui/settings_screen.dart` | Dossier entièrement vide |
| 3.2 | Choix du thème (clair/sombre/système) | **P2** | `features/settings/` | Dark mode existe en dur, pas de toggle persistant |
| 3.3 | Nom de l'appareil personnalisable | **P2** | `features/settings/` | Défaut = nom téléphone (device_info) ou modèle si pas de nom perso ; éditable dans Settings |
| 3.4 | Volume par défaut | **P2** | `features/settings/` | |
| 3.5 | Calibration manuelle du clock sync | **P3** | `features/settings/` | Pour debug avancé |
| 3.6 | Gestion du cache (taille, nettoyage) | **P2** | `features/settings/` | `FileTransferService` stocke en cache sans limite |
| 3.7 | Rendre fonctionnelles les options existantes du menu Settings | **P1** | `features/settings/ui/` | Lien GitHub, "Signaler un bug", option chiffrement, À propos/version — actuellement présentes dans l'UI mais sans action |
| 3.8 | Notification "un invité a rejoint" (optionnel) | **P2** | `features/settings/`, `session_manager.dart` | Toggle dans Settings ; quand activé, notif sonore/vibration à chaque connexion d'un appareil |
| 3.9 | Settings supplémentaires | **P2** | `features/settings/` | Délai de lecture par défaut, auto-rejoindre dernière session |

---

## 4. Groupes & Sessions

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 4.1 | Créer le BLoC Groups | **P1** | `features/groups/bloc/groups_bloc.dart` | Dossier vide |
| 4.2 | UI de création/gestion de groupes | **P1** | `features/groups/ui/groups_screen.dart` | `FirebaseService.saveGroup()`/`loadGroups()` existent, pas de UI |
| 4.3 | Sauvegarde locale (sqflite) des groupes | **P2** | `features/groups/` | Pour fonctionner sans Firebase |
| 4.4 | Historique des appareils connectés + reconnexion rapide | **P2** | `features/groups/`, `core/models/` | Liste des appareils avec lesquels on s'est déjà connecté (nom, IP, dernière session) ; rejoindre en un tap |
| 4.5 | Partage de groupe par QR code (optionnel) | **P2** | `features/groups/` | Bouton "QR Code" dans l'écran de session ; le guest scanne pour rejoindre ; optionnel, pas le flux par défaut |
| 4.6 | Renommer un groupe/session | **P2** | `features/groups/`, `session_manager.dart` | Permettre de donner un nom perso à la session ("Soirée chez Marc" au lieu de "Session_8472") |

---

## 5. Player & Audio

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 5.1 | Skip next / Skip previous | **P0** | `features/player/ui/player_screen.dart` | Dépend de 2.4 (queue) |
| 5.2 | Contrôle du volume à distance (host → slave) | **P2** | `session_manager.dart`, `protocol_message.dart` | Le slave a son slider local mais l'hôte ne peut pas le piloter |
| 5.3 | Mode shuffle | **P2** | `features/player/` | |
| 5.4 | Mode repeat (un / all) | **P2** | `features/player/` | |
| 5.5 | Égaliseur simple (bass/treble) | **P3** | `core/audio/` | just_audio supporte un `AudioPipeline` |
| 5.6 | Affichage de la pochette d'album | **P3** | `features/player/ui/` | Extraction depuis ID3 ou URL |
| 5.7 | Contrôle depuis la notification (Android) | **P2** | `core/services/foreground_service.kt` | MediaSession / media controls dans la notification |
| 5.8 | Dashboard host : appareils connectés + latence | **P1** | `features/player/ui/`, `session_manager.dart` | Afficher nombre d'appareils connectés, latence de chaque (clock offset), bouton "Rafraîchir" manuel (pas de polling auto) ; données utiles : nom appareil, OS, qualité sync, état (connecté/en lecture/déconnecté) |
| 5.9 | Indicateur "tous les invités ont chargé" | **P2** | `features/player/ui/`, `session_manager.dart` | Voyant vert quand tous les appareils ont fini de charger le morceau (prêt à jouer en sync) |
| 5.10 | Stats de session | **P3** | `features/player/`, `core/models/` | Récap en fin de session : durée, nb morceaux joués, nb appareils connectés, qualité moyenne de sync |

---

## 6. Réseau & Sync

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 6.1 | Chiffrement WSS/TLS | **P1** | `websocket_server.dart`, `websocket_client.dart` | Actuellement `ws://` non chiffré ; `android:usesCleartextTraffic="true"` |
| 6.2 | Buffering adaptatif (jitter réseau) | **P2** | `core/network/clock_sync.dart` | Pas de compensation de jitter ; délai fixe uniquement |
| 6.3 | Gestion background iOS | **P1** | `ios/` | Foreground service = Android uniquement |
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
| 9.1 | Tutoriel / onboarding à la première ouverture | **P2** | nouveau : `features/onboarding/` | Recommandé dans `08-RECOMMANDATIONS.md` |
| 9.2 | Animations de transition entre écrans | **P2** | `features/*/ui/` | `flutter_animate` déjà dans les deps |
| 9.3 | Feedback haptique sur les actions | **P3** | `features/player/ui/` | |
| 9.4 | Widget iOS / Android home screen | **P3** | `ios/`, `android/` | Accès rapide aux sessions favorites ; à réfléchir : quoi afficher ? (sessions dispo, bouton rejoindre, morceau en cours ?) |
| 9.5 | Mode paysage / tablette | **P3** | `features/*/ui/` | Layout responsive |

---

## 10. Tests & CI

| # | Tâche | Priorité | Fichier(s) | Notes |
|---|-------|----------|------------|-------|
| 10.1 | Tests unitaires BLoC (Discovery, Player) | **P1** | `test/` | `bloc_test` + `mocktail` déjà installés |
| 10.2 | Tests d'integration (2 émulateurs) | **P2** | `test_driver/` | Vérifier sync réelle |
| 10.3 | CI/CD (GitHub Actions) | **P2** | `.github/workflows/` | Build + test automatique |
| 10.4 | Couverture de code > 60% | **P2** | | Actuellement ~32 tests unitaires |
| 10.5 | Tests de performance clock sync | **P2** | `bin/analyze_sync.dart` | Intégrer dans CI |

---

## Résumé des priorités

| Priorité | Count | Tâches |
|----------|-------|--------|
| **P0** | 6 | 1.1, 1.2, 1.3, 2.1, 2.2, 5.1 |
| **P1** | 17 | 1.4, 1.5, 1.6, 1.9, 2.3, 2.4, 2.5, 2.6, 2.7, 3.1, 3.7, 4.1, 4.2, 5.8, 6.1, 6.3, 6.7, 10.1 |
| **P2** | 25 | 1.7, 1.8, 3.2, 3.3, 3.4, 3.6, 3.8, 3.9, 4.3, 4.4, 4.5, 4.6, 5.2, 5.3, 5.4, 5.7, 5.9, 6.2, 6.6, 7.1, 9.1, 9.2, 10.2, 10.3, 10.4, 10.5 |
| **P3** | 16 | 3.5, 5.5, 5.6, 5.10, 6.4, 6.5, 7.2, 7.3, 7.4, 8.1, 8.2, 8.3, 8.4, 8.5, 9.3, 9.4, 9.5 |

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

*Dernière mise à jour : 2026-03-31 (YouTube integration)*
