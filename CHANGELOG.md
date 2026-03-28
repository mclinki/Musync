# MusyncMIMO -- Journal des Modifications

> Ce fichier documente **toutes les modifications** apportées au projet.
> Destiné à être transmis avec le code pour assurer la continuité.

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
