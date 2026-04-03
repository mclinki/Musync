# MusyncMIMO — Guide de Bonnes Pratiques Multi-Appareils & Reprise de Contexte Agentique

> **Version** : 1.0 — Avril 2026
> **Audience** : Architectes logiciels, développeurs senior, agents IA opérant sur le codebase MusyncMIMO
> **Objectif** : Fournir un cadre complet pour la gestion du contexte distribué, la synchronisation multi-appareils, et la reprise fluide de session par des agents IA.

---

## Table des Matières

1. [Normes et Patterns de Reprise de Contexte Agentique](#1-normes-et-patterns-de-reprise-de-contexte-agentique)
2. [Formats de Sérialisation et Synchronisation Multi-Appareils](#2-formats-de-sérialisation-et-synchronisation-multi-appareils)
3. [Authentification et Sécurité pour Agents Distribués](#3-authentification-et-sécurité-pour-agents-distribués)
4. [Architecture Logicielle et API de Gestion du Contexte](#4-architecture-logicielle-et-api-de-gestion-du-contexte)
5. [Guide de Bonnes Pratiques et Exemples de Code](#5-guide-de-bonnes-pratiques-et-exemples-de-code)

---

## 1. Normes et Patterns de Reprise de Contexte Agentique

### 1.1 Problématique

Quand un agent IA reprend le contrôle d'une session MusyncMIMO — que ce soit après un redémarrage, une migration d'appareil, ou un handoff entre plateformes (Android → Web → Desktop) — il doit reconstruire l'état complet du système sans perte de données ni interruption perceptible.

**Question fondamentale** : *Comment garantir qu'un agent puisse reconstituer l'intégralité du contexte de travail à partir d'un minimum d'informations persistées ?*

### 1.2 Patterns Architecturaux Recommandés

#### 1.2.1 Event Sourcing (Source d'Événements)

**Principe** : Au lieu de stocker l'état courant, on stocke la séquence complète des événements qui ont produit cet état. L'état est reconstruit par *replay*.

**Application à MusyncMIMO** :
- Chaque action (join, play, pause, seek, sync, disconnect) est un événement immuable
- Un agent reprend le contexte en rejouant les événements depuis le dernier snapshot
- L'historique complet permet le debug et l'audit

```
Événements MusyncMIMO :
  DeviceJoined(deviceId="abc", timestamp=T1)
  ClockSynced(offsetMs=12.5, jitterMs=3.2, timestamp=T2)
  TrackPrepared(source="song.mp3", timestamp=T3)
  PlaybackStarted(startAtMs=1712000000, timestamp=T4)
  VolumeAdjusted(deviceId="abc", volume=0.8, timestamp=T5)
  PlaybackPaused(positionMs=45000, timestamp=T6)
```

**Avantages** :
- Reprise complète : l'état est toujours reproductible
- Auditabilité : trace de chaque action pour le diagnostic
- Permet le *time-travel debugging* (rejouer jusqu'à un point précis)

**Limites** :
- Volume de données croissant (nécessite des snapshots périodiques)
- Latence de reconstruction si la log d'événements est longue
- Complexité d'implémentation des *snapshots* compacts

**Recommandation MusyncMIMO** : Utiliser un Event Sourcing **léger** — les événements de session sont déjà sérialisés dans `ProtocolMessage`. Ajouter un *event store* persistant (SQLite local) avec snapshot toutes les 50 actions.

#### 1.2.2 CQRS (Command Query Responsibility Segregation)

**Principe** : Séparer le modèle d'écriture (Commandes) du modèle de lecture (Requêtes). Les commandes modifient l'état via des événements ; les requêtes lisent des projections optimisées.

**Application à MusyncMIMO** :
- **Command side** : `SessionManager` traite les commandes (play, pause, join) et émet des événements
- **Query side** : Les BLoCs (`PlayerBloc`, `DiscoveryBloc`) lisent des projections de l'état pour l'UI
- Un agent IA peut lire les projections sans interférer avec les commandes

```
┌─────────────┐     Commandes      ┌──────────────────┐
│  Agent IA   │───────────────────►│  SessionManager   │
│  (lecture)  │                    │  (écriture)       │
└──────┬──────┘                    └────────┬─────────┘
       │                                     │ Événements
       │ Projections                         ▼
       │                            ┌──────────────────┐
       ◄────────────────────────────│  Event Store     │
                                    │  (SQLite)        │
                                    └──────────────────┘
```

**Avantages** :
- Un agent peut lire l'état sans verrouiller le système
- Les projections peuvent être optimisées pour différents cas d'usage
- Scalabilité : lecture et écriture peuvent être mises à l'échelle indépendamment

**Limites** :
- Consistance éventuelle (*eventual consistency*) entre lecture et écriture
- Double maintenance du modèle

**Recommandation MusyncMIMO** : Le pattern est **déjà partiellement implémenté** via les BLoCs (lecture) et `SessionManager` (écriture). Formaliser la séparation en ajoutant un `ContextSnapshotProvider` qui expose l'état courant de manière read-only.

#### 1.2.3 Machine à États Finis (FSM)

**Principe** : Modéliser explicitement les états possibles d'un appareil/session et les transitions autorisées. Aucun état illégal n'est atteignable.

**Application à MusyncMIMO** : Le code existant utilise déjà un pattern FSM :

```
[Idle] ──► [Scanning] ──► [Joining] ──► [Syncing] ──► [Playing]
                │              │             │            │
                ▼              ▼             ▼            ▼
           [Error]        [Error]     [Reconnecting]  [Paused]
                                                │
                                                ▼
                                           [Playing]
```

**Avantages** :
- États explicites : un agent sait exactement où il en est
- Transitions validées : impossible d'aller de `Idle` à `Playing` sans passer par `Syncing`
- Facilite la reprise : l'agent charge l'état et connait les transitions possibles

**Limites** :
- Rigidité : les transitions doivent être définies à l'avance
- Explosion combinatoire si trop d'états orthogonaux

**Recommandation MusyncMIMO** : Formaliser la FSM avec un package comme `state_machine` ou `xstate` (port Dart). Stocker l'état courant dans un `ContextState` sérialisé.

#### 1.2.4 Memento Pattern

**Principe** : Capturer et externaliser l'état interne d'un objet sans violer l'encapsulation, permettant de le restaurer ultérieurement.

**Application à MusyncMIMO** :

```dart
// Le ContextMemento capture l'état complet de la session
class SessionMemento {
  final String sessionId;
  final SessionState state;
  final AudioTrack? currentTrack;
  final int positionMs;
  final double volume;
  final List<DeviceInfo> connectedDevices;
  final Map<String, double> clockOffsets;
  final DateTime savedAt;

  // Sérialisation pour persistance
  Map<String, dynamic> toJson() => { ... };
  factory SessionMemento.fromJson(Map<String, dynamic> json) => ...;
}
```

**Avantages** :
- Simple à implémenter
- Encapsulation préservée : seul le `SessionManager` peut créer/restaurer un memento
- Idéal pour le *save/restore* de session

**Limites** :
- Capture d'état à un instant T (pas d'historique)
- Taille du memento peut être importante

**Recommandation MusyncMIMO** : Utiliser le Memento Pattern comme **mécanisme de base** pour la reprise de contexte. Combiné avec l'Event Sourcing, il permet des snapshots rapides.

### 1.3 Synthèse des Patterns

| Pattern | Rôle dans MusyncMIMO | Priorité |
|---------|---------------------|----------|
| **Event Sourcing** | Historique complet des actions de session | Haute |
| **CQRS** | Séparation lecture/écriture de l'état | Moyenne (déjà partiel) |
| **Machine à États** | Modélisation des transitions de session | Haute (déjà partiel) |
| **Memento** | Snapshots de reprise rapide | Haute |
| **Observer** | Notifications de changement d'état | Haute (déjà via Streams) |

### 1.4 Architecture de Reprise Recommandée

```
┌─────────────────────────────────────────────────────────────────┐
│                    COUCHE REPRISE DE CONTEXTE                    │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ EventStore   │    │ SnapshotMgr  │    │ ContextReplay│      │
│  │ (SQLite)     │◄──►│ (Memento)    │◄──►│ (Reconstruct)│      │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘      │
│         │                   │                    │               │
│         ▼                   ▼                    ▼               │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              SessionManager (existant)                    │   │
│  │  - Traite les commandes                                   │   │
│  │  - Émet des événements                                    │   │
│  │  - Expose l'état via CQRS                                 │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Formats de Sérialisation et Synchronisation Multi-Appareils

### 2.1 Formats de Sérialisation

MusyncMIMO utilise actuellement **JSON** pour ses messages de protocole (`ProtocolMessage`). Analysons les alternatives.

#### 2.1.1 JSON (actuel)

**Utilisation dans MusyncMIMO** : Tous les messages WebSocket (`join`, `play`, `pause`, `syncRequest`, etc.) sont sérialisés en JSON via `jsonEncode`/`jsonDecode`.

```dart
// Extrait de protocol_message.dart — sérialisation actuelle
String encode() {
  return jsonEncode({
    'type': type.name,
    'payload': payload,
    'ts': timestampMs,
  });
}
```

**Avantages** :
- Humainement lisible (debug facile)
- Support natif en Dart (`dart:convert`)
- Flexible : ajout de champs sans casser la compatibilité
- Écosystème universel (Firebase, REST, WebSocket)

**Limites** :
- Verbeux : ~30-50% de overhead vs binaire
- Pas de schéma strict (erreurs de typo détectées tardivement)
- Performance de parsing pour de gros volumes

**Verdict** : **Conserver JSON pour les messages de contrôle** (commandes, état). La taille est négligeable (< 1KB par message).

#### 2.1.2 Protocol Buffers (Protobuf)

**Format binaire avec schéma strict**. Idéal pour les données volumineuses ou fréquentes.

```protobuf
// Exemple de schéma Protobuf pour MusyncMIMO
syntax = "proto3";

message ProtocolMessage {
  MessageType type = 1;
  int64 timestamp_ms = 2;
  oneof payload {
    JoinPayload join = 10;
    PlayPayload play = 11;
    SyncPayload sync = 12;
    AudioChunkPayload audio_chunk = 13;
  }
}

message PlayPayload {
  int64 start_at_ms = 1;
  string track_source = 2;
  AudioSourceType source_type = 3;
  int32 seek_position_ms = 4;
}

enum MessageType {
  JOIN = 0;
  WELCOME = 1;
  PLAY = 2;
  PAUSE = 3;
  SYNC_REQUEST = 4;
  SYNC_RESPONSE = 5;
}
```

**Avantages** :
- Compact : 5-10x plus petit que JSON
- Typage strict : erreurs détectées à la compilation
- Performance : parsing 5-10x plus rapide
- Rétrocompatibilité native (champs ajoutés sans casser)

**Limites** :
- Non lisible humainement (debug plus difficile)
- Nécessite un outil de génération de code (`protoc`)
- Courbe d'apprentissage

**Verdict** : **Adopter Protobuf pour les chunks audio** (Post-MVP). Conserver JSON pour les messages de contrôle.

#### 2.1.3 MessagePack

**Format binaire compact**, similaire à JSON mais binaire.

```dart
// Exemple avec le package msgpack_dart
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

final data = {
  'type': 'play',
  'start_at_ms': 1712000000,
  'track_source': 'song.mp3',
};
final binary = msgpack.serialize(data); // ~60% de la taille JSON
final decoded = msgpack.deserialize(binary);
```

**Verdict** : **Alternative intéressante** si on veut rester sur du JSON-like sans la complexité de Protobuf. Pas prioritaire.

#### 2.1.4 Tableau Comparatif

| Format | Taille relative | Vitesse parsing | Lisibilité | Typage | Usage MusyncMIMO |
|--------|----------------|-----------------|------------|--------|------------------|
| **JSON** | 100% (référence) | Moyenne | ✅ Haute | ❌ Faible | Messages de contrôle |
| **Protobuf** | 15-25% | Rapide (5-10x) | ❌ Binaire | ✅ Fort | Chunks audio (futur) |
| **MessagePack** | 50-60% | Rapide (3-5x) | ❌ Binaire | ❌ Faible | Alternative JSON |
| **YAML** | 120-150% | Lente | ✅ Haute | ❌ Faible | Config uniquement |

### 2.2 Mécanismes de Synchronisation

#### 2.2.1 WebSocket (actuel)

MusyncMIMO utilise WebSocket en LAN pour la communication bidirectionnelle temps réel.

**Architecture actuelle** :
```
Hôte (serveur WS :7890) ◄──── TCP/WS ────► Esclave (client WS)
         │                                         │
         │  Messages JSON bidirectionnels           │
         │  - clock_sync (NTP-like)                 │
         │  - playback_control                      │
         │  - file_transfer                         │
         │  - heartbeat                             │
```

**Exemple de synchronisation de contexte via WebSocket** :

```dart
// Côté hôte : diffusion de l'état de session complet
class ContextBroadcaster {
  final WebSocketServer _server;

  /// Diffuse l'état complet de la session à tous les esclaves.
  /// Utilisé lors de la reconnexion d'un appareil.
  Future<void> broadcastFullContext(SessionContext context) async {
    final message = ProtocolMessage(
      type: MessageType.contextSync,
      payload: {
        'session_id': context.sessionId,
        'state': context.state.name,
        'current_track': context.currentTrack?.toJson(),
        'position_ms': context.positionMs,
        'volume': context.volume,
        'connected_devices': context.devices.map((d) => d.toJson()).toList(),
        'playlist': context.playlist.toJson(),
        'version': context.version, // Version du schéma de contexte
      },
    );
    await _server.broadcast(message);
  }
}

// Côté esclave : réception et restauration du contexte
class ContextReceiver {
  final SessionManager _sessionManager;

  void handleContextSync(ProtocolMessage message) {
    final payload = message.payload;

    // Validation de la version
    final version = payload['version'] as int? ?? 1;
    if (version > CURRENT_CONTEXT_VERSION) {
      _logger.w('Context version mismatch: $version vs $CURRENT_CONTEXT_VERSION');
      return;
    }

    // Restauration de l'état
    _sessionManager.restoreFromContext(
      sessionId: payload['session_id'],
      state: SessionState.values.byName(payload['state']),
      track: payload['current_track'] != null
          ? AudioTrack.fromJson(payload['current_track'])
          : null,
      positionMs: payload['position_ms'] as int? ?? 0,
    );
  }
}
```

#### 2.2.2 MQTT (évalué pour Post-MVP)

MQTT est un protocole publish/subscribe léger, conçu pour l'IoT.

**Avantages potentiels** :
- Qualité de service (QoS) : garantie de livraison
- Découplage publisher/subscriber
- Retained messages : le dernier état est toujours disponible
- Léger : header de 2 bytes

**Limites pour MusyncMIMO** :
- Nécessite un broker (Mosquitto) — complexité d'infrastructure
- Latence ajoutée vs WebSocket direct
- Overkill pour du LAN P2P

**Verdict** : **Rejeté pour le MVP**. WebSocket direct est plus simple et plus rapide en LAN. MQTT pourrait être pertinent pour un signaling cloud (Post-MVP).

#### 2.2.3 GraphQL Subscriptions (évalué)

**Avantages** : Typage fort, requêtes flexibles, écosystème riche.
**Limites** : Overkill pour un protocole de sync audio. Complexité serveur.
**Verdict** : **Rejeté**. Le protocole MusyncMIMO est simple et ne nécessite pas la flexibilité de GraphQL.

#### 2.2.4 Change Data Capture (CDC) — Firestore

Firebase Firestore offre une synchronisation temps réel native via des *listeners*.

**Utilisation actuelle dans MusyncMINO** :
- Configuration utilisateur (préférences)
- Groupes sauvegardés
- Feature flags

**Exemple de CDC pour la synchronisation de contexte** :

```dart
// Firestore : persistance du contexte de session
class FirestoreContextStore {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sauvegarde le contexte de session (appelé à chaque changement significatif)
  Future<void> saveContext(String userId, SessionContext context) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('sessions')
        .doc(context.sessionId)
        .set({
          ...context.toJson(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Écoute les changements de contexte en temps réel
  Stream<SessionContext?> watchContext(String userId, String sessionId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('sessions')
        .doc(sessionId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return SessionContext.fromJson(doc.data()!);
        });
  }
}
```

**Verdict** : **Utiliser Firestore pour la persistance longue durée** (groupes sauvegardés, historique). Pas pour la sync temps réel audio (trop lent).

### 2.3 Stratégie de Synchronisation Hybride Recommandée

```
┌─────────────────────────────────────────────────────────────────┐
│              COUCHE DE SYNCHRONISATION MUSYNCMIMO                │
│                                                                  │
│  Temps réel (< 10ms)          Persistance (secondes)            │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │ WebSocket (LAN)  │         │ Firestore (Cloud)│             │
│  │ - Clock sync     │         │ - Session state  │             │
│  │ - Playback ctrl  │         │ - Saved groups   │             │
│  │ - Context sync   │         │ - User prefs     │             │
│  │ - File transfer  │         │ - Analytics      │             │
│  └──────────────────┘         └──────────────────┘             │
│                                                                  │
│  Fichiers volumineux           Découverte                       │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │ Binary WS frames │         │ mDNS/Zeroconf    │             │
│  │ (64KB chunks)    │         │ (LAN discovery)  │             │
│  └──────────────────┘         └──────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

### 2.4 Exemple Concret : Échange de Contexte via WebSocket

Voici un scénario complet de reprise de contexte quand un appareil se reconnecte :

```dart
// ═══════════════════════════════════════════════════════════════
// SCÉNARIO : Un esclave se reconnecte après une coupure réseau
// ═══════════════════════════════════════════════════════════════

// Étape 1 : L'esclave envoie un message de reconnexion avec son dernier état
final reconnectMsg = ProtocolMessage(
  type: MessageType.join,
  payload: {
    'device': localDevice.toJson(),
    'last_known_session_id': _lastSessionId,
    'last_known_position_ms': _lastPositionMs,
    'last_known_state': _lastState?.name,
  },
);

// Étape 2 : L'hôte reconnaît la reconnexion et envoie le contexte complet
void _handleReconnection(WebSocket socket, DeviceInfo device) {
  final context = _buildCurrentContext();

  final contextMsg = ProtocolMessage(
    type: MessageType.contextSync,
    payload: {
      'session_id': context.sessionId,
      'state': context.state.name,
      'current_track': context.currentTrack?.toJson(),
      'position_ms': _audioEngine.position.inMilliseconds,
      'volume': context.volume,
      'playlist_tracks': context.playlist.map((t) => t.toJson()).toList(),
      'current_index': context.currentIndex,
      'server_time_ms': clockSync.syncedTimeMs,
      'version': 2, // Version du schéma
    },
  );
  socket.add(contextMsg.encode());

  // Si la session est en cours de lecture, envoyer aussi un play command
  if (context.state == SessionState.playing) {
    final playMsg = ProtocolMessage.play(
      startAtMs: clockSync.syncedTimeMs + 2000,
      trackSource: context.currentTrack!.source,
      sourceType: context.currentTrack!.sourceType,
      seekPositionMs: _audioEngine.position.inMilliseconds,
    );
    socket.add(playMsg.encode());
  }
}

// Étape 3 : L'esclave restaure le contexte
void _handleContextSync(ProtocolMessage message) {
  final payload = message.payload;

  // Restaurer la playlist
  final tracks = (payload['playlist_tracks'] as List?)
      ?.map((t) => AudioTrack.fromJson(t))
      .toList();

  // Restaurer la position de lecture
  final positionMs = payload['position_ms'] as int? ?? 0;

  // Mettre à jour l'UI
  _emitState(SessionManagerState.joined);

  _logger.i('Context restored: ${tracks?.length ?? 0} tracks, position=${positionMs}ms');
}
```

---

## 3. Authentification et Sécurité pour Agents Distribués

### 3.1 Mécanismes d'Authentification

#### 3.1.1 JWT (JSON Web Tokens) — Recommandé

JWT est le standard pour l'authentification stateless entre appareils.

**Principe** : Un token signé contient les claims (informations) de l'utilisateur/session. Le serveur vérifie la signature sans base de données.

**Implémentation pour MusyncMIMO** :

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : JWT pour l'authentification de session
// ═══════════════════════════════════════════════════════════════

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class AuthService {
  final String _secretKey;
  final Duration _tokenExpiry;

  AuthService({
    required String secretKey,
    Duration tokenExpiry = const Duration(hours: 24),
  })  : _secretKey = secretKey,
        _tokenExpiry = tokenExpiry;

  /// Génère un JWT pour un appareil rejoignant une session.
  /// Le token contient le contexte minimal pour la reprise.
  String generateSessionToken({
    required String deviceId,
    required String sessionId,
    required String role, // 'host' ou 'slave'
    Map<String, dynamic>? contextData,
  }) {
    final jwt = JWT(
      {
        'sub': deviceId,           // Subject : ID de l'appareil
        'sid': sessionId,          // Session ID
        'role': role,              // Rôle dans la session
        'ctx': contextData ?? {},  // Contexte minimal (position, track ID)
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      issuer: 'musync-mimo',
    );

    return jwt.sign(
      SecretKey(_secretKey),
      algorithm: JWTAlgorithm.HS256,
      expiresIn: _tokenExpiry,
    );
  }

  /// Vérifie et décode un JWT.
  /// Retourne les claims si valide, null si invalide/expiré.
  Map<String, dynamic>? verifyToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_secretKey));
      return jwt.payload as Map<String, dynamic>;
    } on JWTExpiredException {
      _logger.w('Token expired');
      return null;
    } on JWTException catch (e) {
      _logger.e('Token verification failed: $e');
      return null;
    }
  }

  /// Renouvelle un token avant expiration (refresh).
  /// Préserve le contexte utilisateur intact.
  String? refreshToken(String oldToken) {
    final claims = verifyToken(oldToken);
    if (claims == null) return null;

    return generateSessionToken(
      deviceId: claims['sub'],
      sessionId: claims['sid'],
      role: claims['role'],
      contextData: claims['ctx'],
    );
  }
}

// Utilisation dans le handshake WebSocket
void _handleJoin(WebSocket socket, ProtocolMessage message) {
  final token = message.payload['token'] as String?;

  if (token != null) {
    final claims = _authService.verifyToken(token);
    if (claims == null) {
      final reject = ProtocolMessage.reject(reason: 'Invalid or expired token');
      socket.add(reject.encode());
      return;
    }
    // Restaurer le contexte depuis les claims du token
    _restoreContextFromClaims(claims);
  }

  // ... continuer le handshake normal
}
```

**Pourquoi JWT pour MusyncMIMO ?**
- **Stateless** : pas de session côté serveur à synchroniser
- **Contexte embarqué** : le token peut contenir l'état minimal (session ID, position, rôle)
- **Sécurité** : signature HMAC garantit l'intégrité
- **Expiration** : tokens courts (15min-24h) limitent la fenêtre d'attaque
- **Refresh** : renouvellement transparent sans perte de contexte

#### 3.1.2 OAuth2 — Pour l'Intégration Cloud

OAuth2 est pertinent pour l'authentification Firebase (comptes Google, email).

**Utilisation actuelle** : Firebase Auth gère OAuth2 en interne.

```dart
// Firebase Auth : authentification anonyme ou email
class FirebaseService {
  Future<String?> signInAnonymously() async {
    final credential = await FirebaseAuth.instance.signInAnonymously();
    return credential.user?.uid;
  }

  Future<String?> signInWithEmail(String email, String password) async {
    final credential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
    return credential.user?.uid;
  }
}
```

**Verdict** : **Utiliser Firebase Auth pour l'identité utilisateur** (compte, préférences). Utiliser JWT pour l'authentification de session locale (LAN).

#### 3.1.3 API Keys — Pour le MVP

Pour le MVP en LAN, une clé de session UUID suffit.

```dart
// Actuel dans MusyncMIMO : token UUID simple
final sessionToken = const Uuid().v4(); // "550e8400-e29b-41d4-a716-446655440000"
```

**Verdict** : **Suffisant pour le MVP** (réseau local de confiance). Migrer vers JWT en Post-MVP.

### 3.2 Intégrité et Confidentialité

#### 3.2.1 Chiffrement des Données

**Niveau MVP** : Pas de chiffrement (LAN de confiance).
**Niveau Post-MVP** : TLS pour WebSocket + chiffrement des chunks audio sensibles.

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Chiffrement AES-256 pour les données sensibles
// ═══════════════════════════════════════════════════════════════

import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  final encrypt.Key _key;
  final encrypt.IV _iv;

  EncryptionService(String base64Key)
      : _key = encrypt.Key.fromBase64(base64Key),
        _iv = encrypt.IV.fromLength(16);

  /// Chiffre des données sensibles (ex: token de session)
  String encrypt(String plaintext) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    return encrypter.encrypt(plaintext, iv: _iv).base64;
  }

  /// Déchiffre les données
  String decrypt(String ciphertext) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    return encrypter.decrypt64(ciphertext, iv: _iv);
  }
}
```

#### 3.2.2 Signatures Numériques

Pour garantir l'intégrité des messages de protocole (éviter l'injection de faux chunks) :

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Signature HMAC pour l'intégrité des messages
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:crypto/crypto.dart';

class MessageSigner {
  final String _sessionSecret;

  MessageSigner(this._sessionSecret);

  /// Signe un message avec HMAC-SHA256
  String sign(Map<String, dynamic> payload) {
    final messageJson = jsonEncode(payload);
    final hmac = Hmac(sha256, utf8.encode(_sessionSecret));
    final digest = hmac.convert(utf8.encode(messageJson));
    return digest.toString();
  }

  /// Vérifie la signature d'un message
  bool verify(Map<String, dynamic> payload, String signature) {
    final expectedSignature = sign(payload);
    return expectedSignature == signature;
  }
}

// Intégration dans le protocole
extension SignedMessage on ProtocolMessage {
  ProtocolMessage withSignature(String secret) {
    final signer = MessageSigner(secret);
    final signedPayload = {
      ...payload,
      '_sig': signer.sign(payload),
    };
    return ProtocolMessage(type: type, payload: signedPayload);
  }
}
```

#### 3.2.3 Gestion des Tokens Courts et Rafraîchissement

**Question critique** : *Comment renouveler un jeton d'authentification en conservant le contexte utilisateur intact ?*

**Réponse** : Utiliser un mécanisme de *sliding window* avec refresh token.

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Refresh token avec préservation du contexte
// ═══════════════════════════════════════════════════════════════

class TokenManager {
  String? _accessToken;
  String? _refreshToken;
  DateTime? _accessTokenExpiry;
  Timer? _refreshTimer;

  final AuthService _authService;

  TokenManager(this._authService);

  /// Initialise les tokens après authentification
  void initialize({
    required String accessToken,
    required String refreshToken,
    required Duration accessTokenExpiry,
  }) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _accessTokenExpiry = DateTime.now().add(accessTokenExpiry);

    // Planifier le rafraîchissement automatique 5 minutes avant expiration
    _refreshTimer?.cancel();
    final refreshIn = accessTokenExpiry - const Duration(minutes: 5);
    if (refreshIn > Duration.zero) {
      _refreshTimer = Timer(refreshIn, _performRefresh);
    }
  }

  /// Rafraîchit le token sans interrompre la session
  Future<void> _performRefresh() async {
    if (_refreshToken == null) return;

    final newTokens = await _authService.refreshTokens(_refreshToken!);
    if (newTokens != null) {
      // Le contexte est préservé car le refresh token contient
      // les mêmes claims que le token original
      initialize(
        accessToken: newTokens.accessToken,
        refreshToken: newTokens.refreshToken,
        accessTokenExpiry: newTokens.expiresIn,
      );
      _logger.i('Token refreshed successfully, context preserved');
    } else {
      _logger.e('Token refresh failed, user must re-authenticate');
      // Ici, on pourrait sauvegarder le contexte localement
      // avant de forcer une re-authentification
    }
  }

  /// Retourne le token courant (ou null si expiré)
  String? get currentToken {
    if (_accessTokenExpiry != null &&
        DateTime.now().isAfter(_accessTokenExpiry!)) {
      return null;
    }
    return _accessToken;
  }
}
```

### 3.3 Tableau Récapitulatif Sécurité

| Couche | MVP | Post-MVP | Production |
|--------|-----|----------|------------|
| **Authentification** | UUID token | JWT | JWT + OAuth2 |
| **Transport** | ws:// (clair) | wss:// (TLS) | wss:// + certificats |
| **Données** | Non chiffrées | AES-256 chunks | AES-256 + HMAC |
| **Session** | Token simple | Token + refresh | Token court + refresh auto |
| **Découverte** | mDNS (LAN) | mDNS + PIN | mDNS + auth mutuelle |

---

## 4. Architecture Logicielle et API de Gestion du Contexte

### 4.1 Architecture Modulaire Recommandée

MusyncMIMO utilise déjà une architecture Clean Architecture simplifiée. Voici l'extension pour la gestion du contexte agentique :

```
lib/
├── core/
│   ├── context/                          # NOUVEAU : Couche de contexte
│   │   ├── context_manager.dart          # Orchestrateur principal
│   │   ├── context_snapshot.dart         # Memento / Snapshot
│   │   ├── context_replay.dart           # Reconstruction par événements
│   │   ├── event_store.dart              # Stockage des événements (SQLite)
│   │   └── context_schema.dart           # Versioning du schéma
│   ├── network/
│   │   ├── clock_sync.dart               # (existant)
│   │   ├── websocket_server.dart         # (existant)
│   │   ├── websocket_client.dart         # (existant)
│   │   └── device_discovery.dart         # (existant)
│   ├── audio/
│   │   └── audio_engine.dart             # (existant)
│   ├── session/
│   │   ├── session_manager.dart          # (existant, étendu)
│   │   └── device_registry.dart          # (existant)
│   ├── auth/                             # NOUVEAU : Authentification
│   │   ├── auth_service.dart             # JWT + refresh
│   │   ├── token_manager.dart            # Gestion tokens
│   │   └── encryption_service.dart       # Chiffrement
│   └── models/
│       ├── protocol_message.dart         # (existant)
│       ├── device_info.dart              # (existant)
│       ├── audio_session.dart            # (existant)
│       └── session_context.dart          # NOUVEAU : Modèle de contexte
├── features/
│   ├── discovery/                        # (existant)
│   ├── player/                           # (existant)
│   ├── groups/                           # (existant)
│   └── settings/                         # (existant)
└── main.dart
```

### 4.2 Modèle de Contexte Unifié

```dart
// ═══════════════════════════════════════════════════════════════
// Modèle de contexte complet pour la reprise par un agent IA
// ═══════════════════════════════════════════════════════════════

/// Version actuelle du schéma de contexte.
/// Incrémenter à chaque changement de structure.
const int CURRENT_CONTEXT_VERSION = 2;

class SessionContext {
  final int version;                    // Version du schéma
  final String sessionId;               // UUID de la session
  final SessionState state;             // État courant
  final AudioTrack? currentTrack;       // Piste en cours
  final int positionMs;                 // Position de lecture (ms)
  final double volume;                  // Volume global (0.0-1.0)
  final List<DeviceInfo> devices;       // Appareils connectés
  final List<AudioTrack> playlist;      // Playlist complète
  final int currentIndex;               // Index dans la playlist
  final Map<String, double> volumes;    // Volume par appareil
  final Map<String, double> clockOffsets; // Offset horloge par appareil
  final DateTime createdAt;
  final DateTime updatedAt;

  const SessionContext({
    this.version = CURRENT_CONTEXT_VERSION,
    required this.sessionId,
    required this.state,
    this.currentTrack,
    this.positionMs = 0,
    this.volume = 1.0,
    this.devices = const [],
    this.playlist = const [],
    this.currentIndex = 0,
    this.volumes = const {},
    this.clockOffsets = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  /// Sérialisation JSON avec versioning
  Map<String, dynamic> toJson() => {
    'version': version,
    'session_id': sessionId,
    'state': state.name,
    'current_track': currentTrack?.toJson(),
    'position_ms': positionMs,
    'volume': volume,
    'devices': devices.map((d) => d.toJson()).toList(),
    'playlist': playlist.map((t) => t.toJson()).toList(),
    'current_index': currentIndex,
    'volumes': volumes,
    'clock_offsets': clockOffsets,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Désérialisation avec migration de version
  factory SessionContext.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;

    // Migration automatique depuis les anciennes versions
    final migratedJson = _migrate(json, fromVersion: version);

    return SessionContext(
      version: CURRENT_CONTEXT_VERSION,
      sessionId: migratedJson['session_id'] as String,
      state: SessionState.values.byName(migratedJson['state'] as String),
      currentTrack: migratedJson['current_track'] != null
          ? AudioTrack.fromJson(migratedJson['current_track'])
          : null,
      positionMs: migratedJson['position_ms'] as int? ?? 0,
      volume: (migratedJson['volume'] as num?)?.toDouble() ?? 1.0,
      devices: (migratedJson['devices'] as List?)
          ?.map((d) => DeviceInfo.fromJson(d))
          .toList() ?? [],
      playlist: (migratedJson['playlist'] as List?)
          ?.map((t) => AudioTrack.fromJson(t))
          .toList() ?? [],
      currentIndex: migratedJson['current_index'] as int? ?? 0,
      volumes: Map<String, double>.from(migratedJson['volumes'] ?? {}),
      clockOffsets: Map<String, double>.from(migratedJson['clock_offsets'] ?? {}),
      createdAt: DateTime.parse(migratedJson['created_at'] as String),
      updatedAt: DateTime.parse(migratedJson['updated_at'] as String),
    );
  }

  /// Migration progressive du schéma
  static Map<String, dynamic> _migrate(
    Map<String, dynamic> json, {
    required int fromVersion,
  }) {
    var result = Map<String, dynamic>.from(json);

    // Migration v1 → v2 : ajout du champ volumes
    if (fromVersion < 2) {
      result['volumes'] = {};
      result['clock_offsets'] = {};
    }

    // Future migration v2 → v3 :
    // if (fromVersion < 3) { ... }

    return result;
  }

  /// Copie avec modifications (immutable)
  SessionContext copyWith({
    SessionState? state,
    AudioTrack? currentTrack,
    int? positionMs,
    double? volume,
    List<DeviceInfo>? devices,
    List<AudioTrack>? playlist,
    int? currentIndex,
  }) {
    return SessionContext(
      version: version,
      sessionId: sessionId,
      state: state ?? this.state,
      currentTrack: currentTrack ?? this.currentTrack,
      positionMs: positionMs ?? this.positionMs,
      volume: volume ?? this.volume,
      devices: devices ?? this.devices,
      playlist: playlist ?? this.playlist,
      currentIndex: currentIndex ?? this.currentIndex,
      volumes: volumes,
      clockOffsets: clockOffsets,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
```

### 4.3 API de Gestion du Contexte

Voici l'API interne que les agents IA peuvent utiliser pour interagir avec le contexte :

```dart
// ═══════════════════════════════════════════════════════════════
// API du ContextManager — Point d'entrée pour la reprise
// ═══════════════════════════════════════════════════════════════

class ContextManager {
  final EventStore _eventStore;
  final SessionManager _sessionManager;
  final Logger _logger;

  SessionContext? _currentContext;

  ContextManager({
    required EventStore eventStore,
    required SessionManager sessionManager,
    Logger? logger,
  })  : _eventStore = eventStore,
        _sessionManager = sessionManager,
        _logger = logger ?? Logger();

  // ── API de lecture (pour agents IA) ──

  /// Retourne le contexte courant de la session.
  SessionContext? get currentContext => _currentContext;

  /// Retourne un résumé textuel du contexte (pour agents IA).
  String getContextSummary() {
    if (_currentContext == null) return 'Aucune session active.';

    final ctx = _currentContext!;
    return '''
Session: ${ctx.sessionId}
État: ${ctx.state.label}
Piste: ${ctx.currentTrack?.title ?? 'Aucune'}
Position: ${(ctx.positionMs / 1000).toStringAsFixed(1)}s
Appareils: ${ctx.devices.length}
Playlist: ${ctx.playlist.length} pistes (index ${ctx.currentIndex})
''';
  }

  /// Retourne les événements récents (pour diagnostic).
  Future<List<SessionEvent>> getRecentEvents({
    int limit = 50,
    DateTime? since,
  }) async {
    return _eventStore.getEvents(
      sessionId: _currentContext?.sessionId,
      limit: limit,
      since: since,
    );
  }

  // ── API d'écriture (pour SessionManager) ──

  /// Enregistre un événement et met à jour le contexte.
  Future<void> recordEvent(SessionEvent event) async {
    await _eventStore.append(event);
    _currentContext = _applyEvent(_currentContext, event);
  }

  /// Crée un snapshot du contexte courant.
  Future<ContextSnapshot> createSnapshot() async {
    if (_currentContext == null) {
      throw StateError('No active context to snapshot');
    }

    final snapshot = ContextSnapshot(
      context: _currentContext!,
      eventsSinceLastSnapshot: await _eventStore.getEventsSinceLastSnapshot(),
      createdAt: DateTime.now(),
    );

    await _eventStore.saveSnapshot(snapshot);
    return snapshot;
  }

  /// Restaure le contexte depuis le dernier snapshot + événements.
  Future<SessionContext?> restoreContext(String sessionId) async {
    final snapshot = await _eventStore.getLatestSnapshot(sessionId);
    if (snapshot == null) {
      _logger.w('No snapshot found for session $sessionId');
      return null;
    }

    final events = await _eventStore.getEvents(
      sessionId: sessionId,
      since: snapshot.createdAt,
    );

    // Replay des événements sur le snapshot
    var context = snapshot.context;
    for (final event in events) {
      context = _applyEvent(context, event);
    }

    _currentContext = context;
    _logger.i('Context restored: ${events.length} events replayed');
    return context;
  }

  /// Applique un événement au contexte (pure function).
  SessionContext _applyEvent(SessionContext? context, SessionEvent event) {
    if (context == null) {
      return SessionContext(
        sessionId: event.sessionId,
        state: SessionState.waiting,
        createdAt: event.timestamp,
        updatedAt: event.timestamp,
      );
    }

    return switch (event.type) {
      EventType.deviceJoined => context.copyWith(
        state: SessionState.syncing,
      ),
      EventType.playbackStarted => context.copyWith(
        state: SessionState.playing,
        currentTrack: event.data['track'] != null
            ? AudioTrack.fromJson(event.data['track'])
            : context.currentTrack,
      ),
      EventType.playbackPaused => context.copyWith(
        state: SessionState.paused,
        positionMs: event.data['position_ms'] as int? ?? context.positionMs,
      ),
      EventType.trackChanged => context.copyWith(
        currentTrack: AudioTrack.fromJson(event.data['track']),
        positionMs: 0,
      ),
      _ => context,
    };
  }
}
```

### 4.4 Endpoints API (pour signaling cloud futur)

Bien que le MVP soit P2P en LAN, voici l'API REST qui pourrait servir pour le signaling cloud Post-MVP :

```yaml
# ═══════════════════════════════════════════════════════════════
# API REST — Gestion du Contexte (Post-MVP, signaling cloud)
# ═══════════════════════════════════════════════════════════════

openapi: 3.1.0
info:
  title: MusyncMIMO Context API
  version: 1.0.0

paths:
  /api/v1/sessions:
    post:
      summary: Créer une nouvelle session
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                device_id: { type: string }
                device_name: { type: string }
                device_type: { type: string, enum: [phone, tablet, desktop] }
      responses:
        '201':
          description: Session créée
          content:
            application/json:
              schema:
                type: object
                properties:
                  session_id: { type: string, format: uuid }
                  token: { type: string }  # JWT
                  ws_endpoint: { type: string }  # wss://...

  /api/v1/sessions/{sessionId}/context:
    get:
      summary: Récupérer le contexte d'une session
      parameters:
        - name: sessionId
          in: path
          required: true
          schema: { type: string }
      responses:
        '200':
          description: Contexte de la session
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/SessionContext'

    put:
      summary: Mettre à jour le contexte
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/SessionContext'
      responses:
        '200':
          description: Contexte mis à jour

  /api/v1/sessions/{sessionId}/context/snapshot:
    post:
      summary: Créer un snapshot du contexte
      responses:
        '201':
          description: Snapshot créé

  /api/v1/sessions/{sessionId}/context/restore:
    post:
      summary: Restaurer le contexte depuis le dernier snapshot
      responses:
        '200':
          description: Contexte restauré
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/SessionContext'

components:
  schemas:
    SessionContext:
      type: object
      properties:
        version: { type: integer }
        session_id: { type: string, format: uuid }
        state: { type: string, enum: [waiting, syncing, playing, paused, buffering, error] }
        current_track: { $ref: '#/components/schemas/AudioTrack' }
        position_ms: { type: integer }
        volume: { type: number, minimum: 0, maximum: 1 }
        devices:
          type: array
          items: { $ref: '#/components/schemas/DeviceInfo' }
        playlist:
          type: array
          items: { $ref: '#/components/schemas/AudioTrack' }
        current_index: { type: integer }
```

---

## 5. Guide de Bonnes Pratiques et Exemples de Code

### 5.1 Gestion Explicite des Versions du Contexte

**Bonne pratique** : Toujours versionner le schéma de contexte pour permettre des migrations progressives sans casser la compatibilité.

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Versioning du schéma de contexte
// ═══════════════════════════════════════════════════════════════

/// Définition des versions du schéma
class ContextSchema {
  static const int currentVersion = 2;

  /// Champs requis par version
  static const Map<int, List<String>> requiredFields = {
    1: ['session_id', 'state', 'current_track', 'position_ms'],
    2: ['session_id', 'state', 'current_track', 'position_ms', 'volumes'],
  };

  /// Valide qu'un JSON respecte le schéma pour sa version
  static ValidationResult validate(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    final required = requiredFields[version] ?? requiredFields[currentVersion]!;

    final missing = required.where((field) => !json.containsKey(field)).toList();

    if (missing.isNotEmpty) {
      return ValidationResult.invalid(
        'Missing required fields for v$version: ${missing.join(", ")}',
      );
    }

    if (version > currentVersion) {
      return ValidationResult.invalid(
        'Unknown schema version: $version (max: $currentVersion)',
      );
    }

    return ValidationResult.valid();
  }
}

class ValidationResult {
  final bool isValid;
  final String? error;

  const ValidationResult._(this.isValid, this.error);

  factory ValidationResult.valid() => const ValidationResult._(true, null);
  factory ValidationResult.invalid(String error) => ValidationResult._(false, error);
}
```

**Pourquoi ?** Quand un agent IA reprend un contexte sauvegardé il y a 3 mois avec un ancien schéma, la migration automatique garantit que les données sont toujours lisibles.

### 5.2 Transactions Atomiques pour Éviter les Conflits

**Bonne pratique** : Utiliser des verrous atomiques quand plusieurs agents ou appareils modifient le même état.

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Verrous atomiques pour les modifications concurrentes
// ═══════════════════════════════════════════════════════════════

class AtomicContextUpdater {
  final EventStore _eventStore;
  final Map<String, Completer<void>> _locks = {};

  /// Exécute une mise à jour atomique du contexte.
  /// Si deux agents tentent de modifier simultanément,
  /// le second attend que le premier ait terminé.
  Future<T> atomicUpdate<T>(
    String sessionId,
    Future<T> Function(SessionContext current) updater,
  ) async {
    // Attendre le verrou précédent s'il existe
    while (_locks.containsKey(sessionId)) {
      await _locks[sessionId]!.future;
    }

    // Acquérir le verrou
    final completer = Completer<void>();
    _locks[sessionId] = completer;

    try {
      // Charger le contexte le plus récent
      final context = await _eventStore.getLatestContext(sessionId);

      // Exécuter la mise à jour
      final result = await updater(context);

      // Libérer le verrou
      return result;
    } finally {
      _locks.remove(sessionId);
      completer.complete();
    }
  }
}

// Utilisation :
await updater.atomicUpdate(sessionId, (context) async {
  // Cette section est exécutée de manière atomique
  final newContext = context.copyWith(volume: 0.8);
  await _eventStore.saveContext(newContext);
  return newContext;
});
```

**Pourquoi ?** Dans un système multi-appareils, deux agents pourraient tenter de modifier le volume ou la position simultanément. Le verrou atomique garantit la consistance.

### 5.3 Journalisation pour la Traçabilité

**Bonne pratique** : Logger chaque action significative avec un contexte structuré pour faciliter le diagnostic.

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Journalisation structurée pour la traçabilité
// ═══════════════════════════════════════════════════════════════

import 'package:logger/logger.dart';

class ContextLogger {
  final Logger _logger;
  final String _sessionId;
  final String _deviceId;

  ContextLogger({
    required String sessionId,
    required String deviceId,
  })  : _sessionId = sessionId,
        _deviceId = deviceId,
        _logger = Logger(
          printer: PrettyPrinter(
            methodCount: 0,
            errorMethodCount: 5,
            lineLength: 80,
          ),
        );

  /// Log un événement de contexte avec métadonnées structurées
  void logContextEvent(String event, {Map<String, dynamic>? data}) {
    _logger.i({
      'event': event,
      'session_id': _sessionId,
      'device_id': _deviceId,
      'timestamp': DateTime.now().toIso8601String(),
      if (data != null) 'data': data,
    }.toString());
  }

  /// Log une erreur avec contexte complet pour le diagnostic
  void logContextError(String error, {StackTrace? stackTrace, Map<String, dynamic>? context}) {
    _logger.e({
      'error': error,
      'session_id': _sessionId,
      'device_id': _deviceId,
      'timestamp': DateTime.now().toIso8601String(),
      if (context != null) 'context': context,
    }.toString(), stackTrace: stackTrace);
  }

  /// Log la qualité de synchronisation
  void logSyncQuality({
    required double offsetMs,
    required double jitterMs,
    required String quality,
  }) {
    _logger.d({
      'event': 'sync_quality',
      'session_id': _sessionId,
      'offset_ms': offsetMs.toStringAsFixed(2),
      'jitter_ms': jitterMs.toStringAsFixed(2),
      'quality': quality,
    }.toString());
  }
}

// Utilisation dans SessionManager :
final _contextLogger = ContextLogger(
  sessionId: _currentSession!.sessionId,
  deviceId: _localDevice!.id,
);

_contextLogger.logContextEvent('playback_started', data: {
  'track': track.title,
  'start_at_ms': startAtMs,
  'device_count': _currentSession!.slaves.length,
});
```

**Pourquoi ?** Quand un agent IA diagnostique un problème (ex : désynchronisation), les logs structurés permettent de retracer exactement ce qui s'est passé, quand, et sur quel appareil.

### 5.4 Tests d'Intégration Multi-Appareils

**Bonne pratique** : Tester le scénario complet de reprise de contexte entre appareils simulés.

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Tests d'intégration pour la reprise de contexte
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Context Resume Integration', () {
    late SessionManager hostManager;
    late SessionManager slaveManager;

    setUp(() async {
      hostManager = SessionManager(logger: Logger());
      slaveManager = SessionManager(logger: Logger());

      await hostManager.initialize(
        deviceId: 'host-001',
        deviceName: 'Host Phone',
      );
      await slaveManager.initialize(
        deviceId: 'slave-001',
        deviceName: 'Slave Phone',
      );
    });

    test('Slave can resume context after reconnection', () async {
      // 1. Host démarre une session
      final sessionId = await hostManager.hostSession();

      // 2. Slave rejoint
      final joined = await slaveManager.joinSession(
        hostIp: hostManager.localIp!,
      );
      expect(joined, isTrue);

      // 3. Host lance une piste
      final track = AudioTrack.fromUrl('https://example.com/song.mp3');
      await hostManager.playTrack(track);

      // 4. Simuler une déconnexion du slave
      await slaveManager.leaveSession();

      // 5. Vérifier que le contexte est sauvegardé
      final savedContext = slaveManager.currentSession;
      expect(savedContext, isNotNull);

      // 6. Slave se reconnecte
      final rejoined = await slaveManager.joinSession(
        hostIp: hostManager.localIp!,
      );
      expect(rejoined, isTrue);

      // 7. Vérifier que le contexte est restauré
      // (Le slave devrait recevoir le contexte de l'hôte)
      await Future.delayed(Duration(seconds: 2));
      expect(slaveManager.stateStream, emits(SessionManagerState.playing));
    });

    test('Context version migration works correctly', () {
      // Simuler un contexte v1 (sans le champ volumes)
      final v1Json = {
        'version': 1,
        'session_id': 'test-session',
        'state': 'playing',
        'current_track': null,
        'position_ms': 45000,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // La migration devrait ajouter les champs v2
      final context = SessionContext.fromJson(v1Json);
      expect(context.version, equals(2));
      expect(context.volumes, isEmpty); // Champ ajouté par migration
      expect(context.positionMs, equals(45000)); // Champ préservé
    });
  });
}
```

### 5.5 Sérialisation Robuste avec Gestion d'Erreurs

**Bonne pratique** : Toujours gérer les erreurs de sérialisation gracieusement.

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Sérialisation defensive
// ═══════════════════════════════════════════════════════════════

class SafeSerializer {
  /// Encode un message avec validation préalable
  static String? encodeMessage(ProtocolMessage message) {
    try {
      final json = {
        'type': message.type.name,
        'payload': message.payload,
        'ts': message.timestampMs,
      };

      // Validation : vérifier que le JSON est sérialisable
      final encoded = jsonEncode(json);

      // Validation : vérifier la taille (limite à 1MB)
      if (encoded.length > 1024 * 1024) {
        throw FormatException('Message too large: ${encoded.length} bytes');
      }

      return encoded;
    } catch (e) {
      // Fallback : message d'erreur minimal
      return jsonEncode({
        'type': 'error',
        'payload': {'message': 'Serialization failed: $e'},
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// Décode un message avec validation et fallback
  static ProtocolMessage decodeMessage(String data) {
    try {
      final decoded = jsonDecode(data);

      if (decoded is! Map<String, dynamic>) {
        return ProtocolMessage.error(message: 'Invalid message format');
      }

      final type = MessageType.values.firstWhere(
        (e) => e.name == decoded['type'],
        orElse: () => MessageType.error,
      );

      final payload = decoded['payload'];
      if (payload is! Map<String, dynamic>) {
        return ProtocolMessage(type: type, payload: {});
      }

      return ProtocolMessage(
        type: type,
        payload: Map<String, dynamic>.from(payload),
        timestampMs: (decoded['ts'] as num?)?.toInt() ?? 0,
      );
    } on FormatException catch (e) {
      return ProtocolMessage.error(message: 'JSON parse error: $e');
    } catch (e) {
      return ProtocolMessage.error(message: 'Unexpected error: $e');
    }
  }
}
```

### 5.6 Pattern de Reprise Automatique après Coupure

**Bonne pratique** : Implémenter un mécanisme de reprise automatique qui ne nécessite aucune intervention utilisateur.

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Reprise automatique avec backoff exponentiel
// ═══════════════════════════════════════════════════════════════

class AutoRecoveryManager {
  final SessionManager _sessionManager;
  final ContextManager _contextManager;
  final Logger _logger;

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  Timer? _reconnectTimer;

  AutoRecoveryManager({
    required SessionManager sessionManager,
    required ContextManager contextManager,
    Logger? logger,
  })  : _sessionManager = sessionManager,
        _contextManager = contextManager,
        _logger = logger ?? Logger();

  /// Démarre la surveillance de la connexion
  void startMonitoring() {
    _sessionManager.stateStream.listen((state) {
      if (state == SessionManagerState.error ||
          state == SessionManagerState.idle) {
        _attemptRecovery();
      }
    });
  }

  /// Tente de récupérer la session avec backoff exponentiel
  Future<void> _attemptRecovery() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.e('Max reconnect attempts reached, giving up');
      return;
    }

    _reconnectAttempts++;
    final delayMs = _calculateBackoff(_reconnectAttempts);

    _logger.i('Recovery attempt $_reconnectAttempts in ${delayMs}ms');

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      try {
        // 1. Restaurer le contexte depuis le dernier snapshot
        final context = await _contextManager.restoreContext(
          _sessionManager.currentSession?.sessionId ?? '',
        );

        if (context == null) {
          _logger.w('No context to restore, starting fresh');
          return;
        }

        // 2. Tenter de rejoindre la session précédente
        final rejoined = await _sessionManager.joinSession(
          hostIp: context.devices
              .firstWhere((d) => d.role == DeviceRole.host)
              .ip,
        );

        if (rejoined) {
          _logger.i('Session recovered successfully');
          _reconnectAttempts = 0; // Reset counter
        } else {
          _logger.w('Recovery failed, will retry');
          _attemptRecovery(); // Retry with increased backoff
        }
      } catch (e) {
        _logger.e('Recovery error: $e');
        _attemptRecovery();
      }
    });
  }

  /// Backoff exponentiel : 1s, 2s, 4s, 8s, 16s, 30s (max)
  int _calculateBackoff(int attempt) {
    final baseDelay = 1000 * pow(2, attempt - 1).toInt();
    return baseDelay.clamp(1000, 30000);
  }

  void dispose() {
    _reconnectTimer?.cancel();
  }
}
```

### 5.7 Gestion du Contexte pour les Agents IA

**Bonne pratique** : Fournir une interface claire permettant à un agent IA de comprendre et manipuler le contexte sans connaître l'implémentation interne.

```dart
// ═══════════════════════════════════════════════════════════════
// BONNE PRATIQUE : Interface agent-friendly pour le contexte
// ═══════════════════════════════════════════════════════════════

/// Interface simplifiée pour les agents IA.
/// Cache la complexité interne et expose uniquement les actions pertinentes.
class AgentContextInterface {
  final ContextManager _contextManager;
  final SessionManager _sessionManager;

  AgentContextInterface(this._contextManager, this._sessionManager);

  /// Retourne un résumé textuel du contexte pour l'agent.
  String getSummary() {
    return _contextManager.getContextSummary();
  }

  /// Retourne les actions possibles dans l'état courant.
  List<String> getAvailableActions() {
    final state = _contextManager.currentContext?.state;
    return switch (state) {
      SessionState.waiting => ['start_hosting', 'scan_devices', 'join_session'],
      SessionState.syncing => ['wait', 'cancel'],
      SessionState.playing => ['pause', 'seek', 'skip_next', 'skip_prev', 'adjust_volume'],
      SessionState.paused => ['resume', 'seek', 'skip_next', 'skip_prev'],
      SessionState.error => ['retry', 'leave_session'],
      null => ['initialize', 'scan_devices'],
      _ => [],
    };
  }

  /// Exécute une action et retourne le résultat.
  Future<ActionResult> executeAction(String action, {Map<String, dynamic>? params}) async {
    try {
      switch (action) {
        case 'pause':
          await _sessionManager.pausePlayback();
          return ActionResult.success('Playback paused');

        case 'resume':
          await _sessionManager.resumePlayback();
          return ActionResult.success('Playback resumed');

        case 'adjust_volume':
          final volume = params?['volume'] as double? ?? 0.5;
          // ... ajuster le volume
          return ActionResult.success('Volume set to $volume');

        default:
          return ActionResult.failure('Unknown action: $action');
      }
    } catch (e) {
      return ActionResult.failure('Action failed: $e');
    }
  }
}

class ActionResult {
  final bool success;
  final String message;

  const ActionResult._(this.success, this.message);

  factory ActionResult.success(String message) => ActionResult._(true, message);
  factory ActionResult.failure(String message) => ActionResult._(false, message);
}
```

### 5.8 Récapitulatif des Bonnes Pratiques

| # | Bonne Pratique | Impact | Complexité |
|---|---------------|--------|------------|
| 1 | **Versionner le schéma de contexte** | ★★★★★ | ★★☆☆☆ |
| 2 | **Utiliser des verrous atomiques** | ★★★★☆ | ★★★☆☆ |
| 3 | **Journaliser structuré** | ★★★★★ | ★☆☆☆☆ |
| 4 | **Tests d'intégration multi-appareils** | ★★★★☆ | ★★★☆☆ |
| 5 | **Sérialisation defensive** | ★★★★☆ | ★★☆☆☆ |
| 6 | **Reprise automatique avec backoff** | ★★★★★ | ★★★☆☆ |
| 7 | **Interface agent-friendly** | ★★★★☆ | ★★☆☆☆ |
| 8 | **Event Sourcing léger** | ★★★★☆ | ★★★★☆ |
| 9 | **Snapshots périodiques** | ★★★☆☆ | ★★☆☆☆ |
| 10 | **JWT pour l'auth de session** | ★★★★☆ | ★★☆☆☆ |

---

## Annexes

### A. Glossaire

| Terme | Définition |
|-------|------------|
| **Agent IA** | Entité logicielle capable de reprendre et manipuler le contexte de travail |
| **Contexte** | Ensemble de l'état du système nécessaire pour reprendre une session |
| **Event Sourcing** | Pattern stockant les événements au lieu de l'état courant |
| **CQRS** | Séparation entre le modèle de lecture et d'écriture |
| **Memento** | Pattern capturant l'état interne pour restauration ultérieure |
| **Snapshot** | Point de sauvegarde complet de l'état (Memento persisté) |
| **Backoff exponentiel** | Stratégie de retry avec délai croissant (1s, 2s, 4s, 8s...) |
| **Kalman Filter** | Filtre statistique pour estimer l'état d'un système bruité |

### B. Références

- **Event Sourcing** : Martin Fowler, "Event Sourcing" (2005)
- **CQRS** : Greg Young, "CQRS Documents" (2010)
- **State Machines** : David Harel, "Statecharts: A Visual Formalism for Complex Systems" (1987)
- **JWT** : RFC 7519, "JSON Web Token" (2015)
- **WebSocket** : RFC 6455, "The WebSocket Protocol" (2011)
- **NTP** : RFC 5905, "Network Time Protocol" (2010)
- **Kalman Filter** : R.E. Kalman, "A New Approach to Linear Filtering and Prediction" (1960)

### C. Checklist de Mise en Œuvre

Pour un agent IA reprenant le codebase MusyncMIMO :

- [ ] Lire `SessionContext` et comprendre le schéma versionné
- [ ] Vérifier la version du schéma et appliquer les migrations si nécessaire
- [ ] Charger le dernier snapshot depuis `EventStore`
- [ ] Rejouer les événements post-snapshot via `ContextReplay`
- [ ] Valider l'état restauré (FSM : transitions valides)
- [ ] Reconnecter au WebSocket avec le token JWT
- [ ] Synchroniser l'horloge (NTP-like + Kalman)
- [ ] Restaurer la position de lecture et la playlist
- [ ] Reprendre la lecture si l'état était `playing`
- [ ] Logger chaque étape pour traçabilité

---

> **Ce guide est un document vivant.** Il doit être mis à jour à chaque changement significatif de l'architecture MusyncMIMO. Les agents IA qui opèrent sur ce codebase sont encouragés à contribuer à ce guide en documentant les patterns qu'ils découvrent.

*Dernière mise à jour : 2026-04-01*
*Prochaine révision : Post-MVP (intégration Protobuf, JWT, signaling cloud)*
