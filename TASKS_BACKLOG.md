# MusyncMIMO — Backlog de Tâches

## Tâches en attente (non bloquantes)

### Sécurité
- [ ] **SÉCURITÉ 1** : Implémenter WebSocket chiffré (wss://) au lieu de ws://
  - Nécessite un certificat TLS ou un mécanisme de chiffrement applicatif
  - Priorité : Moyenne (important pour la production)

- [ ] **SÉCURITÉ 2** : Ajouter authentification entre appareils
  - Token de session partagé lors de la découverte
  - Priorité : Moyenne

### Conception
- [ ] **REDONDANCE 1** : Centraliser la gestion d'état session
  - `SessionManager` et `DiscoveryBloc` dupliquent la logique
  - Refactoring majeur nécessaire
  - Priorité : Basse

- [ ] **REDONDANCE 2** : Unifier `AudioEngineState` et `PlayerStatus`
  - Deux enums quasi-identiques dans des fichiers différents
  - Priorité : Basse

### Performance
- [ ] **PERFORMANCE 1** : Optimiser le timer de position (200ms → 500ms)
  - Réduire la consommation batterie
  - Priorité : Basse

- [ ] **PERFORMANCE 2** : Optimiser le scan subnet
  - Scanner uniquement les IPs actives (ARP cache)
  - Priorité : Basse

### Robustesse
- [ ] **CONCEPTION 4** : Ajouter timeout au transfert de fichiers
  - Nettoyer les transferts incomplets après X secondes
  - Priorité : Moyenne

- [ ] **BUG 5** : Afficher le nom de l'hôte pendant la connexion
  - `_buildJoiningView` ne montre pas à quel appareil on se connecte
  - Priorité : Basse

---

*Dernière mise à jour : 28 Mars 2026*
