# MusyncMIMO — Découpage MVP

## Objectif du MVP
Valider la proposition de valeur centrale : **synchroniser la lecture audio sur 2-5 appareils sur le même Wi-Fi, avec une qualité perçue comme "simultanée" par l'utilisateur.**

## Fonctionnalités indispensables (P0)

| # | Fonctionnalité | Description | Critère d'acceptation |
|---|----------------|-------------|----------------------|
| F1 | **Lecture de fichier local** | L'hôte sélectionne un fichier MP3/AAC sur son appareil | Fichier lu correctement, métadonnées affichées |
| F2 | **Découverte d'appareils** | Scan mDNS pour trouver les appareils MusyncMIMO sur le LAN | Appareils détectés en < 5 secondes |
| F3 | **Création de groupe** | L'hôte sélectionne les appareils à inclure dans le groupe | Groupe créé, appareils confirmés |
| F4 | **Synchronisation de lecture** | Tous les appareils commencent la lecture au même moment | Écart < 30ms mesuré, imperceptible à l'oreille |
| F5 | **Contrôle de lecture** | Play, pause, skip depuis l'hôte | Commande exécutée en < 500ms sur tous les appareils |
| F6 | **Volume global** | Contrôle du volume depuis l'hôte | Volume ajusté sur tous les appareils |
| F7 | **Indicateur de statut** | Chaque appareil affiche son état (connecté, synchronisé, en lecture) | État clair et à jour |
| F8 | **Reconnexion automatique** | Reprise après déconnexion courte (< 5s) | Reconnexion transparente, pas de reset de la lecture |

## Fonctionnalités secondaires (P1)

| # | Fonctionnalité | Description | Justification |
|---|----------------|-------------|---------------|
| F9 | **Volume par appareil** | Ajuster le volume individuellement | UX avancée, utile en soirée |
| F10 | **Lecture d'URL streaming** | Support des URLs de streaming (radio, podcast) | Élargit le catalogue sans DRM |
| F11 | **Sauvegarde de groupes** | Enregistrer un groupe pour le réutiliser | Gain de temps pour utilisateurs récurrents |
| F12 | **Métadonnées ID3** | Afficher titre, artiste, album, pochette | UX enrichie |
| F13 | **Mode sombre** | Thème sombre | Standard UX 2026 |
| F14 | **Historique des sessions** | Voir les sessions passées | Engagement utilisateur |

## Fonctionnalités à repousser (P2+)

| # | Fonctionnalité | Raison du report |
|---|----------------|------------------|
| F15 | Support Spotify/Apple Music/Deezer | DRM impossible sans licence |
| F16 | Intégration Chromecast | SDK complexe, nécessite receiver app |
| F17 | Intégration AirPlay 2 | iOS uniquement, SDK fermé |
| F18 | Spatial audio | Complexité DSP, matériel variable |
| F19 | Égaliseur par appareil | Nécessite traitement audio temps réel |
| F20 | Mode karaoké (paroles synchronisées) | Dépendance API paroles |
| F21 | Bluetooth (enceinte unique) | Latence trop élevée pour sync |
| F22 | Connexion hors LAN (cloud) | Infrastructure serveur nécessaire |
| F23 | Support TV (Android TV, Apple TV) | Plateforme spécifique, SDK dédié |
| F24 | Support desktop (Windows, macOS) | Extension de scope |

## Hypothèses à valider en priorité

| # | Hypothèse | Méthode de validation | Critère de succès |
|---|-----------|----------------------|-------------------|
| V1 | La synchronisation < 30ms est atteignable sur Wi-Fi domestique | Mesure avec 2+ appareils sur 5 réseaux différents | 80% des mesures < 30ms |
| V2 | L'utilisateur comprend et utilise la fonctionnalité en < 60s | Test utilisateur avec 10 personnes non-techniques | 8/10 réussissent sans aide |
| V3 | La découverte mDNS fonctionne sur la majorité des réseaux | Test sur 10 réseaux Wi-Fi différents (opérateurs, mesh, etc.) | 8/10 réseaux OK |
| V4 | L'app ne se fait pas tuer en background sur Android | Test sur 10 appareils Android (Samsung, Xiaomi, Google, OnePlus) | 8/10 appareils OK avec foreground service |
| V5 | La qualité audio est acceptable (pas de craquements, latence) | Test écute avec 5 utilisateurs | 4/5 satisfaits |
| V6 | L'utilisateur revient après la première session | Mesure rétention J+7 sur 100 utilisateurs test | > 30% de rétention J+7 |

## Critères de succès du MVP

### Quantitatifs
- **Synchronisation** : Écart moyen < 30ms entre appareils (mesuré)
- **Latence de commande** : Play/pause propagé en < 500ms
- **Découverte** : Appareils détectés en < 5s dans 80% des cas
- **Stabilité** : < 2 crashs par 1000 sessions
- **Rétention** : > 30% de rétention J+7

### Qualitatifs
- **"Ça marche"** : L'utilisateur arrive à créer un groupe et lancer une musique sans aide
- **"C'est synchro"** : Pas d'écho perceptible entre les appareils
- **"C'est simple"** : L'interface est comprise en < 30 secondes
- **"Je veux réutiliser"** : L'utilisateur voit la valeur et revient

### Anti-critères (ce qui ne doit PAS arriver)
- Désynchronisation audible (> 50ms) dans plus de 20% des cas
- Crash au lancement sur plus de 5% des appareils
- Découverte impossible sur plus de 30% des réseaux
- Processus de setup prenant plus de 2 minutes

## Périmètre technique du MVP

### Inclus
- App Flutter Android + iOS
- Moteur de synchronisation NTP-like
- Découverte mDNS
- Serveur WebSocket embarqué (dans l'hôte)
- Lecture de fichiers locaux (MP3, AAC)
- Lecture d'URLs de streaming
- Firebase (auth anonyme, crashlytics, analytics)

### Exclu
- Backend serveur dédié
- Base de données distante (Firestore uniquement pour config)
- Intégration services tiers (Cast, AirPlay, DLNA)
- Traitement audio avancé (EQ, spatial)
- Comptes utilisateurs (auth anonyme suffit)
