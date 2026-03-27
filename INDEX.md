# MusyncMIMO — Document d'Architecture Produit & Technique

## Index des documents

| # | Document | Contenu |
|---|----------|---------|
| 00 | [Résumé Exécutif](./00-RESUME-EXECUTIF.md) | Vision, proposition de valeur, stack, MVP en un coup d'œil |
| 01 | [Hypothèses de Départ](./01-HYPOTHESES.md) | Hypothèses fonctionnelles et techniques, zones d'incertitude |
| 02 | [Analyse Produit](./02-ANALYSE-PRODUIT.md) | Cas d'usage, persona, besoins utilisateurs, limites, risques |
| 03 | [Architecture Technique](./03-ARCHITECTURE-TECHNIQUE.md) | Front, backend, sync, découverte, diffusion, sécurité |
| 04 | [Stack Recommandée](./04-STACK-RECOMMANDEE.md) | Technologies, justifications, alternatives évaluées et rejetées |
| 05 | [Découpage MVP](./05-MVP.md) | Fonctionnalités P0/P1/P2, critères de succès, périmètre |
| 06 | [Feuille de Route](./06-ROADMAP.md) | Phases prototype → MVP → bêta → industrialisation |
| 07 | [Points de Vigilance](./07-POINTS-VIGILANCE.md) | Compatibilité, permissions, sync, batterie, sécurité, stores |
| 08 | [Recommandations](./08-RECOMMANDATIONS.md) | Stratégie prototype, compromis, pièges à éviter, arbitrages |

## Comment utiliser ce document

1. **Décision Go/No-Go** : Lire le [Résumé Exécutif](./00-RESUME-EXECUTIF.md) et les [Hypothèses](./01-HYPOTHESES.md)
2. **Comprendre le produit** : Lire l'[Analyse Produit](./02-ANALYSE-PRODUIT.md)
3. **Concevoir l'implémentation** : Lire l'[Architecture](./03-ARCHITECTURE-TECHNIQUE.md) et la [Stack](./04-STACK-RECOMMANDEE.md)
4. **Planifier le développement** : Lire le [MVP](./05-MVP.md) et la [Roadmap](./06-ROADMAP.md)
5. **Anticiper les risques** : Lire les [Points de Vigilance](./07-POINTS-VIGILANCE.md)
6. **Prendre des décisions** : Lire les [Recommandations](./08-RECOMMANDATIONS.md)

## Métadonnées

- **Date de création** : Mars 2026
- **Version** : 1.0
- **Auteur** : Architecte produit / lead mobile / expert audio temps réel
- **Statut** : Document de conception, prêt pour validation

## Résumé en 30 secondes

**MusyncMIMO** synchronise la lecture musicale sur plusieurs smartphones/tablettes via Wi-Fi local.

- **Comment** : NTP-like clock sync + WebSocket + mDNS discovery
- **Stack** : Flutter + just_audio + Firebase
- **MVP** : 4 mois, fichiers locaux, 2-5 appareils, Wi-Fi uniquement
- **Risque principal** : Synchronisation < 30ms sur réseaux Wi-Fi dégradés
- **Différenciation** : Simplicité (5 taps, 15 secondes), pas de matériel requis
