# MusyncMIMO — Agent Onboarding Guide

> **Ce fichier est le POINT D'ENTRÉE OBLIGATOIRE pour tout agent IA travaillant sur MusyncMIMO.**
> Lis-le EN PREMIER avant toute action sur le codebase.

---

## Qui suis-je ?

Tu es un agent IA qui travaille sur **MusyncMIMO**, une application Flutter multi-appareils qui synchronise la lecture musicale sur plusieurs smartphones/tablettes via Wi-Fi local.

**Ta mission** : Maintenir, améliorer et faire évoluer ce projet de manière professionnelle, gitable et transmissible d'agent en agent.

---

## Étape 0 — Lecture obligatoire (dans l'ordre)

Avant de toucher au code, lis ces fichiers **dans cet ordre** :

| Ordre | Fichier | Pourquoi |
|-------|---------|----------|
| 1 | `AGENT_ONBOARDING.md` | Ce fichier — ta boussole |
| 2 | `00-RESUME-EXECUTIF.md` | Vision du projet en 30 secondes |
| 3 | `03-ARCHITECTURE-TECHNIQUE.md` | Architecture complète (sync, réseau, audio) |
| 4 | `GUIDE_BONNES_PRATIQUES.md` | Patterns, sécurité, API, code examples |
| 5 | `TASKS_BACKLOG.md` | Ce sur quoi travailler (bugs + features) |
| 6 | `CHANGELOG.md` | Historique des modifications récentes |
| 7 | `04-STACK-RECOMMANDEE.md` | Stack technique et justifications |

**Ensuite seulement**, explore le code dans `musync_app/lib/`.

---

## Étape 1 — Comprendre le projet en 2 minutes

**MusyncMIMO** = Synchronisation musicale multi-appareils via Wi-Fi.

```
Hôte (📱) ──WebSocket LAN──► Esclaves (📱📱📱)
  │                              │
  │  NTP-like clock sync         │
  │  + Kalman filter             │
  │  + file transfer             │
  │                              │
  └── Tous jouent en même temps (< 30ms) ──┘
```

**Stack** : Flutter 3.27 / Dart 3.6 / BLoC / just_audio / WebSocket / mDNS / Firebase

**Version actuelle** : v0.1.17 (95/95 tests passent)

---

## Étape 2 — Règles de travail

### Règle 1 : Toujours mettre à jour les fichiers de suivi

Quand tu termines une tâche, tu DOIS :

1. **Cocher** la tâche dans `TASKS_BACKLOG.md` → `[x]`
2. **Ajouter une entrée** dans `CHANGELOG.md` avec :
   - Date
   - Catégorie (`FIX`, `FEAT`, `REFACTOR`, `TEST`, `DOC`, `CHORE`, `OPTIM`)
   - Description courte
   - Fichiers modifiés
3. **Mettre à jour** `README.md` si la roadmap change
4. **Mettre à jour** `app_constants.dart` si la version change

### Règle 2 : Ne jamais casser les tests

```bash
cd musync_app && flutter test
```

Si les tests cassent → **fixe-les avant de continuer**. Objectif : 95/95 toujours vert.

### Règle 3 : Suivre les conventions du projet

- **State management** : BLoC (flutter_bloc) — pas de setState dans les features
- **Architecture** : Clean Architecture simplifiée (core/ + features/)
- **Logging** : `Logger` (package `logger`) — pas de `print()`
- **Types** : Toujours typer les variables, éviter les `dynamic`
- **Null safety** : Toujours vérifier les null avant accès
- **Sérialisation** : Toujours valider les payloads JSON avant cast

### Règle 4 : Documenter chaque modification

Chaque modification significative doit être documentée dans `CHANGELOG.md` :

```markdown
## Session du YYYY-MM-DD (vX.Y.Z) — Titre

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | Description du fix | `fichier.dart` |
```

### Règle 5 : Respecter le GUIDE_BONNES_PRATIQUES.md

Ce guide contient les patterns architecturaux, les formats de sérialisation, les bonnes pratiques de sécurité et les exemples de code. **Consulte-le** avant d'implémenter quoi que ce soit de nouveau.

---

## Étape 3 — Structure du projet

```
MusyncMIMO/
│
├── 📄 DOCUMENTATION (racine)
│   ├── AGENT_ONBOARDING.md       ← TU ES ICI
│   ├── GUIDE_BONNES_PRATIQUES.md  ← Patterns, sécurité, API
│   ├── INDEX.md                   ← Table des matières des docs
│   ├── 00-RESUME-EXECUTIF.md      ← Vision projet
│   ├── 01-HYPOTHESES.md           ← Hypothèses de départ
│   ├── 02-ANALYSE-PRODUIT.md      ← Cas d'usage, persona
│   ├── 03-ARCHITECTURE-TECHNIQUE.md ← Architecture détaillée
│   ├── 04-STACK-RECOMMANDEE.md    ← Stack et justifications
│   ├── 05-MVP.md                  ← Périmètre MVP
│   ├── 06-ROADMAP.md              ← Feuille de route
│   ├── 07-POINTS-VIGILANCE.md     ← Risques identifiés
│   ├── 08-RECOMMANDATIONS.md      ← Recommandations concrètes
│   ├── TASKS_BACKLOG.md           ← Tâches en cours (bugs + features)
│   ├── BACKLOG_FEATURES.md        ← Backlog features long terme
│   ├── CHANGELOG.md               ← Historique des modifications
│   ├── README.md                  ← Présentation + tuto
│   ├── RAPPORT_J1.md              ← Rapport jour 1
│   ├── RAPPORT_TESTS_2026-03-31.md ← Rapport de tests
│   └── Rapport_Qwen36Plus.md      ← Audit externe
│
├── 📁 musync_app/                 ← CODE SOURCE FLUTTER
│   ├── lib/
│   │   ├── core/
│   │   │   ├── models/            ← DeviceInfo, AudioSession, ProtocolMessage, Playlist
│   │   │   ├── network/           ← ClockSync, WebSocket, mDNS discovery
│   │   │   ├── audio/             ← AudioEngine (just_audio wrapper)
│   │   │   ├── session/           ← SessionManager (orchestrateur principal)
│   │   │   └── services/          ← Firebase, ForegroundService, FileTransfer, Permissions
│   │   ├── features/
│   │   │   ├── discovery/         ← UI + BLoC découverte appareils
│   │   │   ├── player/            ← UI + BLoC lecteur audio (queue, skip)
│   │   │   └── settings/          ← Écran paramètres
│   │   └── main.dart              ← Point d'entrée
│   ├── test/                      ← Tests unitaires (95 tests)
│   ├── android/                   ← Config Android + ForegroundService
│   ├── ios/                       ← Config iOS
│   ├── windows/                   ← Config Windows desktop
│   └── macos/                     ← Config macOS desktop
│
└── 📁 .git/                       ← Repository Git
```

---

## Étape 4 — Fichiers clés à connaître

| Fichier | Rôle | À modifier quand... |
|---------|------|---------------------|
| `core/session/session_manager.dart` | Orchestrateur principal | Nouvelle fonctionnalité de session |
| `core/network/clock_sync.dart` | Moteur de sync NTP-like + Kalman | Amélioration de la précision |
| `core/network/websocket_server.dart` | Serveur WS (côté hôte) | Nouveau message protocole |
| `core/network/websocket_client.dart` | Client WS (côté esclave) | Nouveau message protocole |
| `core/models/protocol_message.dart` | Messages du protocole | Ajout d'un type de message |
| `core/audio/audio_engine.dart` | Moteur audio (just_audio) | Changement de comportement audio |
| `core/network/device_discovery.dart` | Découverte mDNS + TCP | Amélioration de la découverte |
| `core/app_constants.dart` | Constantes centralisées | Changement de config/version |
| `features/player/bloc/player_bloc.dart` | État du lecteur | Nouvelle action player |
| `features/discovery/bloc/discovery_bloc.dart` | État de la découverte | Nouvelle action discovery |

---

## Étape 5 — Workflow de contribution

### Pour un bug :

1. Lire `TASKS_BACKLOG.md` → trouver le bug
2. Lire les fichiers suspects listés
3. Reproduire le bug
4. Fixer le bug
5. Lancer `flutter test` (95/95)
6. Cocher le bug dans `TASKS_BACKLOG.md` → `[x]`
7. Ajouter l'entrée dans `CHANGELOG.md`
8. Commiter avec message descriptif

### Pour une feature :

1. Lire `BACKLOG_FEATURES.md` ou `TASKS_BACKLOG.md` → trouver la feature
2. Lire `GUIDE_BONNES_PRATIQUES.md` → patterns applicables
3. Lire `03-ARCHITECTURE-TECHNIQUE.md` → architecture
4. Implémenter
5. Lancer `flutter test` (95/95 + nouveaux tests)
6. Mettre à jour `TASKS_BACKLOG.md`, `CHANGELOG.md`, `README.md` (roadmap)
7. Commiter

### Pour un refactoring :

1. Documenter le "pourquoi" dans `CHANGELOG.md`
2. S'assurer que tous les tests passent
3. Ne pas changer le comportement externe
4. Mettre à jour la documentation si l'architecture change

---

## Étape 6 — Commandes utiles

```bash
# Lancer les tests
cd musync_app && flutter test

# Analyse statique
cd musync_app && flutter analyze

# Build APK debug
cd musync_app && flutter build apk --debug

# Build Windows
cd musync_app && flutter build windows

# Voir la couverture de code
cd musync_app && flutter test --coverage
```

---

## Étape 7 — État actuel du projet

### Version : v0.1.17
### Tests : 95/95 ✅
### Plateformes : Android ✅ | iOS ⚠️ (macOS requis) | Windows ✅ | macOS ⚠️ (macOS requis)

### Dernières modifications :
- v0.1.17 : Dashboard host (appareils connectés + latence + qualité sync)
- v0.1.16 : Filtre de Kalman + calibration adaptative (sync ±2-3ms)
- v0.1.15 : Fixes Crashlytics + APK Transfer
- v0.1.14 : Audit Qwen3.6-Plus + fixes critiques

### Bugs ouverts critiques :
- CRASH-10 : `InheritedElement.debugDeactivated` (47 events, 7 users)
- CRASH-11 : `RenderFlex.performLayout` unbounded height (3 events)
- BUG-7 : Premier play ne fonctionne pas (priorité Haute)
- BUG-8 : Sync imparfaite au premier play (priorité Haute)
- BUG-9 : `LateInitializationError` sur Partager l'app (priorité Haute)

---

## Étape 8 — Rappels importants

> **"La synchronisation doit fonctionner (< 30ms). C'est le produit."**
> — 08-RECOMMANDATIONS.md

> **"Commencer petit, prouver la sync, puis élargir."**
> — 08-RECOMMANDATIONS.md

> **"5 taps, 15 secondes. C'est l'objectif UX."**
> — 08-RECOMMANDATIONS.md

---

## Checklist de fin de session

Avant de terminer ta session de travail, vérifie :

- [ ] Tous les tests passent (`flutter test`)
- [ ] `TASKS_BACKLOG.md` est à jour (tâches cochées, nouvelles tâches ajoutées)
- [ ] `CHANGELOG.md` a une nouvelle entrée pour cette session
- [ ] `README.md` est à jour si la roadmap a changé
- [ ] `app_constants.dart` a la bonne version si elle a changé
- [ ] Les fichiers modifiés sont documentés
- [ ] Aucune régression introduite

---

*Dernière mise à jour : 2026-04-01*
*Ce fichier doit être mis à jour à chaque changement significatif de structure du projet.*
