# MusyncMIMO — Résumé Exécutif

## Vision
MusyncMIMO est une application mobile cross-platform (Android/iOS) permettant à un utilisateur de synchroniser la lecture musicale sur plusieurs appareils de son écosystème (smartphones, tablettes, enceintes connectées, TV, ordinateurs) pour créer un effet de volume collectif et de profondeur sonore spatialisée.

## Proposition de valeur
Transformer chaque appareil disponible en haut-parleur supplémentaire, synchronisé à moins de 30ms, sans matériel spécifique — juste une app et un réseau Wi-Fi.

## Stratégie recommandée
**Approche hybride par couches de protocoles**, priorisant le Wi-Fi local comme transport principal, avec intégration progressive de Chromecast et AirPlay 2 comme canaux de sortie vers appareils propriétaires.

## Stack recommandée
- **Framework** : Flutter 3.x + Dart
- **Synchronisation** : NTP-like custom over WebSocket (LAN) + clock drift compensation
- **Audio** : `just_audio` + `audio_session` (local) / Cast SDK / AirPlay (remote)
- **Backend** : Firebase (auth, config) + serveur WebSocket léger (signaling + clock sync)
- **Découverte** : mDNS/Zeroconf (LAN) + Cast discovery + BLE fallback

## MVP — 3 mois
1. App hôte lance une musique (fichier local ou URL streaming)
2. Découverte mDNS des appareils MusyncMIMO sur le même Wi-Fi
3. Groupe jusqu'à 5 appareils
4. Synchronisation NTP-like avec compensation de dérive
5. Contrôle play/pause/volume depuis l'hôte
6. Reprise automatique après déconnexion/reconnexion courte

## Risques majeurs
- Synchronisation sub-30ms sur réseaux Wi-Fi dégradés (réalité : 50-200ms sans optimisation)
- Restrictions iOS pour audio background + découverte réseau
- Fragmentation Android (permissions, battery optimization)
- Impossibilité de piloter nativement enceintes/TV sans SDK constructeur

## Horizon de rentabilité
- Phase 1 (MVP) : Gratuit, validation produit, 1000 utilisateurs test
- Phase 2 (Bêta) : Freemium, fonctionnalités premium (groupes sauvegardés, EQ, spatial audio)
- Phase 3 (Production) : Abonnement ou achat unique, intégration services streaming

---
