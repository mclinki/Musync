# MusyncMIMO — Feuille de Route Technique

> **État au 2026-04-04** : Phases 0 et 1 terminées. Phase 2 (Bêta) en cours.
> Toutes les features P0/P1 sont implémentées. 213 tests. Score santé : 85/100.

## Phase 0 : Prototype (Semaines 1-4) — ✅ TERMINÉE

### Objectifs
- Prouver que la synchronisation audio < 30ms est atteignable sur Wi-Fi local
- Valider l'architecture NTP-like + WebSocket
- Créer un proof-of-concept fonctionnel (2 appareils)

### Livrables
- [x] POC Flutter : 2 apps qui jouent le même fichier MP3 synchronisé
- [x] Moteur de clock sync NTP-like fonctionnel (Kalman filter, calibration adaptative)
- [x] Mesures de performance : latence, drift, skew
- [x] Rapport technique : faisabilité validée

### Tâches détaillées

| Semaine | Tâche | Livrable |
|---------|-------|----------|
| S1 | Setup projet Flutter, intégration `just_audio` | App qui joue un MP3 |
| S1 | Implémentation WebSocket server/client basique | Communication bidirectionnelle |
| S2 | Implémentation clock sync NTP-like | Synchronisation horloge entre 2 appareils |
| S2 | Implémentation audio chunk streaming | Flux audio du serveur au client |
| S3 | Intégration sync + audio : "play at time T" | 2 appareils qui jouent ensemble |
| S3 | Mesures de performance (skew, latence, drift) | Rapport de mesures |
| S4 | Optimisation : buffer adaptatif, drift compensation | Skew < 30ms atteint |
| S4 | Documentation architecture, décisions techniques | Document technique |

### Risques
| Risque | Impact | Mitigation |
|--------|--------|------------|
| Skew > 30ms impossible à atteindre | Critique | Explorer buffer plus grand, codec plus léger, ou accepter 50ms |
| `just_audio` ne permet pas le seek précis | Élevé | Explorer `media_kit` ou platform channels natifs |
| WebSocket trop lent pour le streaming audio | Moyen | Tester, optimiser, ou passer à UDP custom |

### Critères de passage
- ✅ Skew moyen < 30ms sur 3 réseaux Wi-Fi différents
- ✅ 2 appareils jouent ensemble pendant 5 minutes sans désynchronisation
- ✅ Architecture documentée et validée
- ❌ Si skew > 50ms sur tous les réseaux : réévaluer l'approche (buffer plus grand, protocole différent)

---

## Phase 1 : MVP (Semaines 5-16) — ✅ TERMINÉE

### Objectifs
- Livrer une app fonctionnelle sur Android et iOS
- Valider les hypothèses produit avec de vrais utilisateurs
- Atteindre les critères de succès du MVP

### Livrables
- [x] App Flutter complète (F1-F8) — Android + Windows (iOS en attente de build)
- [x] Découverte mDNS fonctionnelle (mDNS + TCP subnet scan fallback)
- [x] Gestion de groupe (création, join, leave, rename, Firestore sync)
- [x] UI/UX complète (design system, onboarding 4 pages, animations, thème sombre)
- [x] Firebase intégré (auth anonyme, crashlytics, analytics)
- [x] Tests unitaires (213 tests, couverture en cours)
- [x] Build CI/CD (GitHub Actions : analyze + test + coverage + build Android/Windows + release)
- [ ] Publication TestFlight (iOS) + Internal Testing (Android) — en attente

### Tâches détaillées

| Semaine | Tâche | Livrable |
|---------|-------|----------|
| S5-6 | Architecture complète : modules, états, navigation | Squelette de l'app |
| S5-6 | Implémentation mDNS discovery | Scan et publication de services |
| S7-8 | UI découverte : liste d'appareils, invitation | Écran de découverte |
| S7-8 | Gestion de session : création, join, leave, heartbeat | Session manager |
| S9-10 | UI lecteur : play/pause/skip/volume, file picker | Écran de lecteur |
| S9-10 | Intégration audio engine + clock sync | Lecture synchronisée |
| S11-12 | Gestion erreurs : reconnexion, timeout, erreurs réseau | Robustesse |
| S11-12 | UI polish : animations, feedback, onboarding | UX soignée |
| S13-14 | Firebase : auth anonyme, crashlytics, analytics | Backend minimal |
| S13-14 | Tests : unitaires, intégration, manuels | Qualité |
| S15 | CI/CD : build automatique, distribution TestFlight/Play | Pipeline |
| S15 | Beta testing interne (5-10 personnes) | Feedback |
| S16 | Corrections bugs, optimisations, documentation | MVP stable |

### Risques
| Risque | Impact | Mitigation |
|--------|--------|------------|
| Découverte mDNS ne fonctionne pas sur certains réseaux | Élevé | Fallback : saisie manuelle de l'IP |
| iOS tue l'app en background | Élevé | Audio session + foreground service Android |
| Fragmentation Android (permissions, battery) | Moyen | Guide de dépannage, foreground service |
| UX trop complexe pour les non-techniques | Moyen | Tests utilisateurs itératifs |

### Critères de passage
- ✅ Toutes les fonctionnalités P0 implémentées et testées
- ✅ Critères de succès du MVP atteints (sync < 30ms, rétention > 30%)
- ✅ < 2 crashs / 1000 sessions
- ✅ Publication sur les stores (TestFlight + Play Internal)
- ✅ 50+ utilisateurs beta actifs

---

## Phase 2 : Bêta (Semaines 17-28) — 🔄 EN COURS

### Objectifs
- Élargir la base utilisateurs
- Ajouter les fonctionnalités P2 restantes
- Intégrer les premiers protocoles tiers (Cast, AirPlay)
- Préparer la monétisation

### Livrables
- [ ] Fonctionnalités P2 restantes (QR code, rotation IP DHCP, HMAC, tests intégration)
- [ ] Intégration Chromecast (Android)
- [ ] Intégration AirPlay 2 (iOS)
- [ ] Auth email/password + sociale (Google, Apple)
- [ ] Profil utilisateur complet
- [ ] Historique des sessions
- [ ] Publication publique sur les stores
- [ ] Landing page et communication

### Tâches détaillées

| Semaine | Tâche | Livrable |
|---------|-------|----------|
| S17-18 | Volume par appareil | UI + backend |
| S17-18 | Lecture d'URL streaming | Support radio/podcast |
| S19-20 | Sauvegarde de groupes (Firestore) | Groupes persistants |
| S19-20 | Métadonnées ID3, pochette | UI enrichie |
| S21-22 | Intégration Chromecast SDK (Android) | Cast vers enceintes Google |
| S21-22 | Intégration AirPlay (iOS platform channel) | Cast vers enceintes Apple |
| S23-24 | Authentification (email, Google, Apple) | Comptes utilisateurs |
| S23-24 | Mode sombre, thèmes | UI polish |
| S25-26 | Beta publique : ouverture à 500+ utilisateurs | Scale test |
| S25-26 | Monitoring : performance, crash rate, usage | Dashboard |
| S27-28 | Corrections, optimisations, préparation lancement | Bêta stable |

### Risques
| Risque | Impact | Élevé |
|--------|--------|-------|
| Chromecast SDK complexe à intégrer | Élevé | Budget 2 semaines supplémentaires |
| AirPlay nécessite des entitlements Apple | Moyen | Demander les entitlements tôt |
| Scale : 500+ utilisateurs révèlent des problèmes | Moyen | Monitoring proactif, limites de groupe |

### Critères de passage
- ✅ Fonctionnalités P1 implémentées
- ✅ Chromecast fonctionnel sur Android
- ✅ AirPlay fonctionnel sur iOS
- ✅ 500+ utilisateurs bêta actifs
- ✅ Rétention J+7 > 40%
- ✅ NPS > 30

---

## Phase 3 : Industrialisation (Semaines 29-40+)

### Objectifs
- Lancer publiquement
- Monétiser
- Préparer la scalabilité long terme
- Explorer les fonctionnalités avancées

### Livrables
- [ ] Lancement public (Product Hunt, presse, réseaux sociaux)
- [ ] Modèle de monétisation (freemium ou achat)
- [ ] Fonctionnalités premium (EQ, spatial audio, groupes illimités)
- [ ] Support hors LAN (cloud signaling)
- [ ] SDK/API pour intégration tierce
- [ ] Documentation développeur

### Monétisation envisagée

| Modèle | Description | Prix suggéré |
|--------|-------------|-------------|
| Freemium | Gratuit : 3 appareils, fichiers locaux. Premium : illimité + streaming + EQ | 4,99€/mois ou 29,99€/an |
| Achat unique | Toutes les fonctionnalités | 9,99€ |
| Les deux | Achat unique + abonnement pour le cloud | 9,99€ + 2,99€/mois |

### Risques
| Risque | Impact | Mitigation |
|--------|--------|------------|
| Faible conversion freemium | Élevé | A/B testing, valeur premium évidente |
| Concurrent (Sonos, Apple) ajoute la fonctionnalité | Moyen | Vitesse d'exécution, niche "tous appareils" |
| Coût infrastructure cloud | Moyen | Limiter le cloud au signaling, pas au streaming |

---

## Timeline visuel

```
Semaines:  1----4  5---------16  17---------28  29---------40+
            ┌──────┐┌────────────┐┌─────────────┐┌─────────────┐
Phase:     │PROTO✅││   MVP ✅   ││  BÊTA 🔄    ││ INDUSTRIAL. │
            └──────┘└────────────┘└─────────────┘└─────────────┘
            
Objectif:  Prouver  Valider      Élargir        Lancer
           sync     produit      marché         publiquement
           
Utilisateurs: 2     50-100       500-1000       5000+
           
Fonctions:  POC     P0           P2+Cast        P3+Premium
           (fait)  (fait)       (en cours)     (futur)
```

### État d'avancement détaillé (2026-04-04)

| Catégorie | P0 | P1 | P2 | P3 |
|-----------|----|----|----|----|
| **Total** | 4 | 11 | 22 | 19 |
| ✅ Faites | 4 | 11 | 14 | 3 |
| ⚠️ Partielles | 0 | 0 | 3 | 2 |
| ❌ Restantes | 0 | 0 | 5 | 14 |

**Version actuelle** : v0.1.43 · **Tests** : 213/213 · **Score santé** : 85/100
