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

- [ ] **SYNC 1** : Émettre SyncQualityChanged après chaque recalibration auto
  - Actuellement émis une seule fois après join
  - Le clock_sync a un timer auto-calibration mais pas de callback de fin
  - Priorité : Moyenne

- [ ] **SYNC 2** : Guest pause/resume ne propage pas à l'hôte
  - Le guest peut mettre en pause localement mais l'hôte ne le sait pas
  - Priorité : Basse (comportement actuel = volume local)

---

## ✅ Corrections bugs tests réels (v0.1.4 + v0.1.5)

- [x] **BUG-TEST 1** : Clock offset non appliqué dans startAtMs (retard CLK NX1)
- [x] **BUG-TEST 2** : Playlist invité invisible → nouveau protocole playlistUpdate
- [x] **BUG-TEST 3** : Skip next hôte ne propage pas au guest
- [x] **BUG-TEST 4** : Pas de bouton stop dans UI invité
- [x] **BUG-TEST 5** : Indicateur décalage = 0 (SyncQualityChanged jamais émis)
- [x] **BUG-TEST 6** : Paramètres non persistés (SharedPreferences)
- [x] **BUG-AUDIT 1** : _cachedFilePath non réinitialisé entre sessions
- [x] **BUG-AUDIT 2** : cachePath null dans _handlePrepareCommand
- [x] **BUG-AUDIT 3** : resumePlayback envoie chemin complet au lieu du filename
- [x] **BUG-AUDIT 4** : dispose() WebSocketClient sans await
- [x] **BUG-AUDIT 5** : t2/t3 identiques dans _handleHostSyncRequest
- [x] **BUG-AUDIT 6** : Guest skip affiche mauvaise piste brièvement

---

## ✅ Tâches P0 complétées (v0.1.3)

- [x] **P0-1** : Système de queue/playlist + skip next/prev
- [x] **P0-2** : Vrai mDNS publishing (multicast_dns)
- [x] **P0-3** : Permissions runtime Android 13+ (permission_handler)
- [x] **FIX** : Export file_transfer_service.dart dans core.dart

---

*Dernière mise à jour : 29 Mars 2026*
