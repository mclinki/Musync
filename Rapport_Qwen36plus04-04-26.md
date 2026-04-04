# Rapport d'Audit Code — MusyncMIMO

**Date** : 04 avril 2026  
**Auditeur** : Pepito (Qwen3.6-plus-free)  
**Projet** : MusyncMIMO — Synchronisation audio multi-appareils  
**Version auditée** : 0.1.42+42  
**Fichiers analysés** : 58 fichiers Dart (~7 500 lignes)  

---

## Résumé Exécutif

MusyncMIMO est une application Flutter de synchronisation audio multi-appareils sur réseau local. L'architecture est globalement bien structurée avec une séparation claire entre core, features, models et services. Le code montre une maturité certaine avec de nombreux correctifs documentés (CRIT-*, HIGH-*, MED-*, BUG-*). Cependant, plusieurs problèmes critiques et améliorations significatives ont été identifiés.

**Score global** : **B+** (Bon, avec des points d'amélioration importants)

| Catégorie | Score | Commentaire |
|-----------|-------|-------------|
| Architecture | A- | Bonne séparation des responsabilités, PlaybackCoordinator extrait |
| Sécurité | B | PIN auth, TLS, mais fingerprint vide et certificats auto-signés |
| Performance | B+ | Kalman filter excellent, mais timers non optimisés |
| Robustesse | B+ | Bonne gestion d'erreurs, mais quelques race conditions |
| Maintenabilité | B | SessionManager encore dense, tests à vérifier |
| Tests | B | 95 tests existants, couverture à valider |

---

## 1. CRITIQUE — Sécurité & Authentification

### 1.1. Certificat TLS sans fingerprint configuré

**Issue Description** : `AppConstants.expectedCertFingerprint` est une chaîne vide (`''`). En mode WSS, le client accepte **n'importe quel certificat** sans validation, ce qui expose l'application aux attaques Man-in-the-Middle (MITM) sur le réseau local.

**Fichier** : `lib/core/app_constants.dart:19`  
**Fichier** : `lib/core/network/websocket_client.dart:223-263`

```dart
// app_constants.dart
static const String expectedCertFingerprint = ''; // VIDE = aucune validation
```

```dart
// websocket_client.dart — badCertificateCallback
if (expectedFingerprint.isNotEmpty) {
  // ... validation
  return match;
}
// Fallback dangereux
_logger.w('⚠️ No cert fingerprint configured — accepting any certificate');
return true; // ← Accepte TOUT
```

**Suggestion** : 
1. Implémenter un mécanisme d'échange de fingerprint hors-bande (QR code, affichage du PIN + fingerprint)
2. Stocker le fingerprint du premier certificat accepté (TOFU — Trust On First Use)
3. Documenter clairement le risque dans l'UI pour l'utilisateur

**Rationale** : Sur un réseau Wi-Fi public ou compromis, un attaquant peut intercepter tout le trafic audio et les commandes de playback. Le PIN protège l'accès à la session, mais pas le canal de communication lui-même.

**Priorité** : 🔴 CRITIQUE

---

### 1.2. Génération de PIN prévisible

**Issue Description** : Le PIN de session est généré à partir du timestamp courant, ce qui le rend partiellement prévisible.

**Fichier** : `lib/core/network/websocket_server.dart:74-78`

```dart
static String _generatePin() {
  final random = DateTime.now().millisecondsSinceEpoch;
  final pin = (random % 900000 + 100000).toString(); // 6-digit PIN
  return pin;
}
```

**Suggestion** : Utiliser `dart:math` avec `Random.secure()` pour une génération cryptographiquement sûre :

```dart
import 'dart:math';

static String _generatePin() {
  final random = Random.secure();
  return List.generate(6, (_) => random.nextInt(10)).join();
}
```

**Rationale** : Un attaquant sur le même réseau peut estimer le timestamp de création du serveur et réduire l'espace de recherche du PIN de 900 000 à quelques milliers de possibilités.

**Priorité** : 🟡 ÉLEVÉ

---

### 1.3. Certificats TLS auto-signés persistés sans rotation

**Issue Description** : Les certificats TLS auto-signés sont générés une fois et persistés sur disque avec une validité de 10 ans (3650 jours). Ils ne sont jamais renouvelés.

**Fichier** : `lib/core/network/websocket_server.dart:172`

```dart
certificatePem = X509Utils.generateSelfSignedCertificate(privateKey, csr, 3650);
```

**Suggestion** : 
1. Réduire la validité à 1 an maximum
2. Implémenter une rotation automatique des certificats
3. Ajouter une vérification de date d'expiration au démarrage

**Rationale** : Un certificat compromis reste valide pendant 10 ans. Une rotation régulière limite la fenêtre d'exposition.

**Priorité** : 🟡 ÉLEVÉ

---

## 2. ÉLEVÉ — Architecture & Design

### 2.1. SessionManager encore trop volumineux (God Object partiel)

**Issue Description** : Bien que `PlaybackCoordinator` ait été extrait (CRIT-005 fix), `SessionManager` reste à **979 lignes** avec 12 contrôleurs de stream, 8 timers, et de multiples responsabilités : découverte, session, réseau, audio, contexte, Firebase, foreground service.

**Fichier** : `lib/core/session/session_manager.dart`

**Suggestion** : Extraire davantage de responsabilités :
1. **`SessionLifecycleManager`** : hostSession, joinSession, leaveSession
2. **`DeviceRegistry`** : gestion des appareils connectés/découverts
3. **`SessionEventBus`** : centraliser les streams au lieu de 12 StreamControllers
4. **`FirebaseAnalyticsBridge`** : isoler les appels Firebase

**Rationale** : Un fichier de ~1000 lignes avec autant de responsabilités est difficile à tester, à maintenir et à faire évoluer. Le pattern "Single Responsibility Principle" n'est pas encore pleinement appliqué.

**Priorité** : 🟡 ÉLEVÉ

---

### 2.2. FirebaseService en Singleton avec état mutable

**Issue Description** : `FirebaseService` utilise le pattern Singleton mais crée une nouvelle instance à chaque appel `FirebaseService()` dans les BLoCs.

**Fichier** : `lib/core/services/firebase_service.dart:24-26`

```dart
static final FirebaseService _instance = FirebaseService._internal();
factory FirebaseService() => _instance;
```

Mais dans `PlayerBloc` :
```dart
_firebase = firebase ?? FirebaseService(), // Crée une instance séparée si null
```

**Suggestion** : 
1. Rendre le constructeur privé et forcer l'utilisation du singleton
2. Ou supprimer le pattern Singleton et utiliser l'injection de dépendances via `RepositoryProvider`
3. Dans `main.dart`, toujours passer l'instance existante

**Rationale** : Le mélange de Singleton et d'injection de dépendances crée de la confusion et peut mener à des états incohérents si une instance non-initialisée est utilisée.

**Priorité** : 🟡 ÉLEVÉ

---

### 2.3. DiscoveryBloc crée sa propre instance FirebaseService

**Issue Description** : Le `DiscoveryBloc` crée sa propre instance de `FirebaseService` si aucune n'est fournie, ce qui contourne l'injection de dépendances.

**Fichier** : `lib/features/discovery/bloc/discovery_bloc.dart:308-309`

```dart
DiscoveryBloc({required this.sessionManager, FirebaseService? firebase, Logger? logger})
    : _firebase = firebase ?? FirebaseService(),
```

**Suggestion** : Rendre `firebase` obligatoire (non-nullable) et le fournir systématiquement via le BLoC provider.

**Rationale** : Cela garantit que le même service Firebase est utilisé partout et évite les incohérences d'état.

**Priorité** : 🟠 MOYEN

---

## 3. ÉLEVÉ — Performance & Mémoire

### 3.1. PositionTimer à 200ms sans throttling UI

**Issue Description** : Le `AudioEngine` émet des mises à jour de position toutes les 200ms (5Hz). Bien que le `PositionSlider` écoute directement le stream (HIGH-011 fix), le `PlayerBloc` ajoute chaque mise à jour comme un événement BLoC, ce qui déclenche un `emit` et potentiellement des rebuilds.

**Fichier** : `lib/core/audio/audio_engine.dart:93-100`  
**Fichier** : `lib/features/player/bloc/player_bloc.dart:340-344`

```dart
// AudioEngine
_positionTimer = Timer.periodic(
  const Duration(milliseconds: AppConstants.positionUpdateIntervalMs), // 200ms
  (_) {
    if (_player.playing && !_positionController.isClosed) {
      _positionController.add(_player.position);
    }
  },
);

// PlayerBloc
_positionSub = audioEngine.positionStream.listen((position) {
  if (_isClosed) return;
  add(PositionUpdated(position)); // ← Chaque tick = event BLoC = emit
});
```

**Suggestion** : 
1. Augmenter l'intervalle à 500ms pour le BLoC (suffisant pour l'UI)
2. Garder le stream direct à 200ms uniquement pour le slider
3. Ou utiliser `distinct()` pour ne pas émettre si la position n'a pas changé significativement (> 1s)

**Rationale** : 5 événements BLoC par seconde pendant toute la durée d'écoute est excessif pour une mise à jour UI. Cela consomme CPU et batterie inutilement.

**Priorité** : 🟡 ÉLEVÉ

---

### 3.2. Scan subnet bloquant sur le thread principal

**Issue Description** : `scanSubnet()` itère sur 254 adresses IP avec des batches de 10. Même avec des timeouts, cette opération peut bloquer le thread principal pendant plusieurs secondes.

**Fichier** : `lib/core/network/device_discovery.dart:692-730`

```dart
for (int batch = 0; batch < 254; batch += batchSize) {
  final futures = <Future<void>>[];
  for (int i = batch + 1; i <= (batch + batchSize).clamp(1, 254); i++) {
    futures.add(_probeDevice(ip, port + 1).timeout(...));
  }
  await Future.wait(futures); // ← Bloquant par batch
}
```

**Suggestion** : 
1. Exécuter le scan dans un `compute()` (isolate séparé)
2. Ou réduire le nombre d'IP scannées en utilisant l'ARP cache du système
3. Ajouter un `await Future.delayed(Duration.zero)` entre les batches pour céder le thread

**Rationale** : Un scan subnet sur le thread principal peut causer des jank UI et des ANR (Application Not Responding) sur Android.

**Priorité** : 🟡 ÉLEVÉ

---

### 3.3. _IncomingTransfer garde les chunks en mémoire (fallback)

**Issue Description** : Bien que le chemin principal utilise des écritures directes sur disque (`RandomAccessFile`), le fallback base64 garde tous les chunks en mémoire dans `List<Uint8List> chunks`.

**Fichier** : `lib/core/services/file_transfer_service.dart:515-537`

```dart
class _IncomingTransfer {
  RandomAccessFile? _fileHandle;
  final List<Uint8List> chunks; // ← En mémoire si pas de fileHandle
```

**Suggestion** : 
1. Supprimer complètement le chemin base64 (les transferts binaires sont maintenant le standard)
2. Ou forcer systématiquement l'ouverture d'un `RandomAccessFile`
3. Ajouter une garde de mémoire maximale (ex: refuser si > 50MB en mémoire)

**Rationale** : Pour un fichier de 100MB (maxFileSizeBytes), le fallback mémoire causerait un OOM (Out Of Memory) sur la plupart des appareils mobiles.

**Priorité** : 🟠 MOYEN

---

## 4. MOYEN — Robustesse & Gestion d'Erreurs

### 4.1. Race condition dans _handleServerBinaryMessage

**Issue Description** : `_handleServerBinaryMessage` dans `SessionManager` est un placeholder vide. Les chunks binaires reçus par le serveur ne sont jamais routés vers le `FileTransferService`.

**Fichier** : `lib/core/session/session_manager.dart:703-707`

```dart
Future<void> _handleServerBinaryMessage(String deviceId, List<int> data) async {
  _logger.d('Received binary message from $deviceId (${data.length} bytes)');
  // Binary chunks are handled by the file transfer service
  // This is a placeholder - actual handling is done in the file transfer service
}
```

**Suggestion** : 
1. Soit implémenter le routage vers `FileTransferService` côté serveur
2. Soit supprimer ce handler et documenter que le serveur n'a pas besoin de recevoir de fichiers (seul le slave en reçoit)
3. Actuellement, le code suggère une fonctionnalité qui n'existe pas

**Rationale** : Un handler vide qui prétend déléguer à un service crée de la confusion et peut masquer un bug si le routage binaire est un jour nécessaire côté serveur.

**Priorité** : 🟠 MOYEN

---

### 4.2. _recalibrationTimer utilise async dans Timer callback sans gestion d'erreur complète

**Issue Description** : Le callback de `_recalibrationTimer` est `async` mais l'erreur n'est capturée que partiellement.

**Fichier** : `lib/core/session/session_manager.dart:403-414`

```dart
_recalibrationTimer = Timer(const Duration(seconds: 3), () async {
  if (_client != null && _client!.isConnected) {
    try {
      await _client!.synchronize();
      _emitSyncQuality();
    } catch (e) {
      _logger.w('Post-connection recalibration failed: $e');
    }
  }
  _recalibrationTimer = null;
});
```

**Suggestion** : Utiliser `unawaited()` explicitement pour les callbacks async de Timer, et ajouter un guard `_isClosed` :

```dart
_recalibrationTimer = Timer(const Duration(seconds: 3), () {
  unawaited(_recalibrateAfterConnection());
});

Future<void> _recalibrateAfterConnection() async {
  if (_client == null || !_client!.isConnected) return;
  // ...
}
```

**Rationale** : Les exceptions non capturées dans les callbacks async de Timer sont silencieusement ignorées, ce qui peut masquer des problèmes de synchronisation.

**Priorité** : 🟠 MOYEN

---

### 4.3. DeviceDiscovery ne nettoie pas les sockets mDNS sur Windows

**Issue Description** : Sur Windows, `_startMdnsPublisher` retourne immédiatement sans rien faire, mais `_startMdnsDiscovery` aussi. Cependant, `stopScanning()` appelle `_mdnsClient?.stop()` qui pourrait être null, et `dispose()` appelle les deux sans vérification d'état.

**Fichier** : `lib/core/network/device_discovery.dart:270-275, 549-553`

**Suggestion** : Ajouter des guards cohérents pour Windows dans toutes les méthodes mDNS et documenter clairement le comportement par plateforme.

**Rationale** : L'incohérence entre les chemins Windows/non-Windows peut causer des fuites de ressources ou des comportements inattendus.

**Priorité** : 🟢 FAIBLE

---

### 4.4. AudioTrack.fromFilePathWithMetadata ne lit pas la durée

**Issue Description** : La méthode `fromFilePathWithMetadata` extrait le titre, l'artiste et l'album, mais `durationMs` est toujours `null` car `audio_metadata_reader` ne fournit pas la durée.

**Fichier** : `lib/core/models/audio_session.dart:197-198`

```dart
// audio_metadata_reader doesn't provide duration
durationMs = null;
```

**Suggestion** : 
1. Utiliser `just_audio` pour obtenir la durée après chargement du fichier
2. Ou utiliser une autre librairie comme `on_audio_query` pour les métadonnées complètes
3. Documenter cette limitation

**Rationale** : La durée nulle affecte l'affichage UI et peut causer des problèmes avec le slider de position.

**Priorité** : 🟢 FAIBLE

---

## 5. MOYEN — Qualité du Code & Bonnes Pratiques

### 5.1. Incohérence de gestion des erreurs entre host et slave

**Issue Description** : Côté slave, `handlePlayCommand` dans `PlaybackCoordinator` contient une gestion d'erreur très détaillée avec logging extensif, tandis que côté host, `playTrack` dans le même fichier a une gestion d'erreur minimale.

**Fichier** : `lib/core/session/playback_coordinator.dart:72-171 vs 344-499`

**Suggestion** : Uniformiser la gestion d'erreurs des deux côtés avec le même niveau de détail et de logging.

**Rationale** : L'asymétrie rend le debugging difficile quand un problème se produit côté host.

**Priorité** : 🟠 MOYEN

---

### 5.2. Magic numbers résiduels dans le code

**Issue Description** : Malgré l'utilisation de `AppConstants`, plusieurs magic numbers persistent :

**Fichiers** : Multiples

```dart
// clock_sync.dart:206
if (_jitterMs < 5) return const Duration(seconds: 3);
if (_jitterMs < 15) ...
if (_jitterMs < 30) ...

// playback_coordinator.dart:316
for (int i = 0; i < 5; i++) { // retry count

// websocket_server.dart:76
final pin = (random % 900000 + 100000).toString();
```

**Suggestion** : Extraire ces valeurs dans `AppConstants` avec des noms descriptifs :

```dart
static const int jitterExcellentThresholdMs = 5;
static const int jitterGoodThresholdMs = 15;
static const int jitterAcceptableThresholdMs = 30;
static const int cacheFileRetryCount = 5;
static const int pinMinValue = 100000;
static const int pinMaxRange = 900000;
```

**Rationale** : Les magic numbers rendent le code difficile à maintenir et à configurer.

**Priorité** : 🟢 FAIBLE

---

### 5.3. PlayerState.copyWith a une logique ambiguë pour currentTrack

**Issue Description** : Le paramètre `clearCurrentTrack` utilise une logique conditionnelle qui peut être source de confusion :

**Fichier** : `lib/features/player/bloc/player_bloc.dart:230`

```dart
currentTrack: clearCurrentTrack ? null : (currentTrack ?? this.currentTrack),
```

Si `clearCurrentTrack` est `false` et `currentTrack` est `null`, on garde l'ancien track. Si `clearCurrentTrack` est `true`, on force `null`. Cette logique n'est pas intuitive.

**Suggestion** : Utiliser un type `Option<AudioTrack>` ou séparer en deux méthodes :
- `copyWith({AudioTrack? currentTrack})` — met à jour si non-null
- `clearTrack()` — force à null

**Rationale** : La logique actuelle est correcte mais difficile à comprendre au premier coup d'œil, ce qui augmente le risque de bugs lors de modifications futures.

**Priorité** : 🟢 FAIBLE

---

### 5.4. Absence de validation d'entrée dans les BLoC events

**Issue Description** : Les événements BLoC ne valident pas leurs entrées avant traitement. Par exemple, `VolumeChanged` accepte n'importe quelle valeur `double`.

**Fichier** : `lib/features/player/bloc/player_bloc.dart:79-86`

```dart
class VolumeChanged extends PlayerEvent {
  final double volume; // Aucune validation
```

**Suggestion** : Ajouter des assertions ou des validations dans les constructeurs d'événements :

```dart
class VolumeChanged extends PlayerEvent {
  final double volume;
  const VolumeChanged(this.volume) : assert(volume >= 0.0 && volume <= 1.0);
```

**Rationale** : La validation précoce (fail-fast) permet de détecter les bugs plus tôt dans le cycle de vie de l'application.

**Priorité** : 🟢 FAIBLE

---

## 6. FAIBLE — UI & Expérience Utilisateur

### 6.1. _VolumeControlState ne dispose pas son subscription

**Issue Description** : Le `_VolumeControlState` s'abonne au `systemVolumeStream` dans `initState` mais ne dispose jamais la subscription.

**Fichier** : `lib/features/player/ui/player_screen.dart:548-552`

```dart
@override
void initState() {
  super.initState();
  _currentVolume = widget.volume;
  widget.systemVolumeStream.listen((volume) { // ← Pas de subscription stockée
    if (!_isDragging && mounted) {
      setState(() => _currentVolume = volume);
    }
  });
}
// Pas de dispose() pour annuler la subscription
```

**Suggestion** : Stocker la subscription et la disposer :

```dart
StreamSubscription<double>? _volumeSub;

@override
void initState() {
  super.initState();
  _volumeSub = widget.systemVolumeStream.listen((volume) {
    if (!_isDragging && mounted) {
      setState(() => _currentVolume = volume);
    }
  });
}

@override
void dispose() {
  _volumeSub?.cancel();
  super.dispose();
}
```

**Rationale** : Les subscriptions non disposées causent des fuites de mémoire et peuvent appeler `setState` sur un widget démonté.

**Priorité** : 🟠 MOYEN

---

### 6.2. HomeScreen utilise context.read<FirebaseService>() sans vérification

**Issue Description** : Le `HomeScreen` appelle `context.read<FirebaseService>().logEvent()` sans vérifier si Firebase est initialisé.

**Fichier** : `lib/main.dart:338-341, 373-376`

```dart
context.read<FirebaseService>().logEvent('tap_create_group');
```

Bien que `FirebaseService.logEvent` vérifie `if (!_initialized) return;`, l'appel direct depuis l'UI sans vérification préalable est une mauvaise pratique.

**Suggestion** : Créer un helper ou vérifier `firebaseService.isInitialized` avant d'appeler.

**Priorité** : 🟢 FAIBLE

---

## 7. OBSERVATIONS POSITIVES

Plusieurs aspects du code méritent d'être soulignés :

### 7.1. Filtre de Kalman pour la synchronisation d'horloge
L'implémentation du filtre de Kalman dans `ClockSyncEngine` est excellente. Elle fournit des estimations d'offset et de drift bien plus stables qu'une simple médiane, surtout en cas de jitter réseau élevé.

### 7.2. Calibration adaptative
Le système de calibration adaptative basé sur le jitter (1s/3s/10s/15s) est une approche intelligente qui équilibre précision et consommation de ressources.

### 7.3. Transfert de fichiers binaire
Le passage des transferts Base64 aux frames binaires WebSocket (QWEN-P1-2 fix) avec écriture directe sur disque via `RandomAccessFile` est une excellente optimisation mémoire.

### 7.4. Pattern Event Sourcing
L'utilisation de l'Event Sourcing avec `EventStore` (SQLite) et `ContextManager` pour la reconstruction d'état est une architecture robuste pour la reprise après reconnexion.

### 7.5. Gestion des interruptions audio
La gestion des interruptions audio (appels, alarmes) avec vérification que le même track est toujours chargé avant reprise (MED-001 fix) est bien pensée.

### 7.6. Découverte multi-méthode
La combinaison mDNS + TCP subnet scan + TCP probe server assure une découverte robuste même sur des réseaux restrictifs.

---

## 8. RECOMMANDATIONS PRIORITAIRES

### P0 — À corriger immédiatement
1. **Générer le PIN avec `Random.secure()`** (1.2) — 15 min
2. **Implémenter TOFU pour les certificats TLS** (1.1) — 2-3h
3. **Stocker et disposer la subscription `_VolumeControlState`** (6.1) — 10 min

### P1 — À corriger dans la prochaine itération
4. **Réduire la fréquence des events BLoC de position** (3.1) — 30 min
5. **Exécuter le scan subnet dans un isolate** (3.2) — 1-2h
6. **Uniformiser la gestion d'erreurs host/slave** (5.1) — 1h
7. **Rendre FirebaseService obligatoire dans les BLoCs** (2.3) — 30 min

### P2 — Améliorations à planifier
8. **Extraire SessionLifecycleManager de SessionManager** (2.1) — 4-6h
9. **Implémenter la rotation des certificats TLS** (1.3) — 2h
10. **Supprimer le fallback mémoire du file transfer** (3.3) — 1h
11. **Implémenter le routage binaire côté serveur** (4.1) — 1h
12. **Extraire les magic numbers restants** (5.2) — 30 min

---

## 9. MÉTRIQUES DU CODEBASE

| Métrique | Valeur | Cible |
|----------|--------|-------|
| Fichiers Dart | 58 | — |
| Lignes de code (est.) | ~7 500 | — |
| Fichier le plus long | `session_manager.dart` (979 lignes) | < 500 |
| Fichiers > 500 lignes | 7 | < 3 |
| StreamControllers | 12 (SessionManager) + autres | < 8 par classe |
| Timers actifs simultanés | 6+ | < 4 |
| Services avec Singleton | 1 (FirebaseService) | 0 |
| Magic numbers restants | ~15 | 0 |
| Tests | 95 | > 100 |

---

## 10. CONCLUSION

MusyncMIMO est un projet techniquement solide avec une architecture bien pensée pour la synchronisation audio multi-appareils. Les points forts (filtre de Kalman, Event Sourcing, transfert binaire) démontrent une expertise technique réelle.

Les principales préoccupations sont :
1. **Sécurité** : Le PIN prévisible et l'absence de validation de certificat TLS sont les risques les plus importants
2. **Performance** : Le scan subnet et la fréquence des events BLoC peuvent causer des problèmes sur appareil réel
3. **Architecture** : SessionManager reste le point de convergence de trop de responsabilités

Avec les corrections P0 et P1, le projet atteindrait un niveau de qualité **A-** prêt pour une utilisation en production sur réseau local de confiance.

---

*Rapport généré le 04/04/2026 par Pepito — Qwen3.6-plus-free*
