# MusyncMIMO — Architecture Technique

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────┐
│                        RÉSEAU LOCAL Wi-Fi                        │
│                                                                  │
│  ┌──────────┐    WebSocket     ┌──────────┐                     │
│  │  HÔTE    │◄───────────────►│ ESCLAVE 1│                     │
│  │ (Maitre) │    Clock Sync    │          │                     │
│  │          │    Audio Stream  │  🔊 Play │                     │
│  │  📱 App  │                  └──────────┘                     │
│  │          │    WebSocket     ┌──────────┐                     │
│  │          │◄───────────────►│ ESCLAVE 2│                     │
│  │  🔊 Play │    Clock Sync    │          │                     │
│  └──────────┘    Audio Stream  │  📱 App  │                     │
│                                └──────────┘                     │
│       ▲                                                       │
│       │ mDNS/Zeroconf discovery                                │
│       ▼                                                       │
│  ┌──────────┐                                                  │
│  │ ESCLAVE 3│                                                  │
│  │  📱 App  │                                                  │
│  └──────────┘                                                  │
└─────────────────────────────────────────────────────────────────┘
       │
       │ HTTPS (optionnel, pour config/licence)
       ▼
┌──────────────┐
│   BACKEND    │
│  (Firebase)  │
│  - Auth      │
│  - Config    │
│  - Analytics │
└──────────────┘
```

## 1. Front Mobile

### Framework : Flutter 3.x + Dart

**Justification** :
- Code unique Android/iOS (100% de réutilisation)
- Performance native via compilation AOT
- Écosystème audio mature (`just_audio`, `audio_session`)
- Support mDNS via `multicast_dns`
- Support WebSocket natif (`web_socket_channel`)
- Support Cast via `google_cast` (community) ou platform channels
- Hot reload pour développement rapide

### Architecture interne (Clean Architecture simplifiée)

```
lib/
├── core/
│   ├── network/
│   │   ├── clock_sync.dart          # Synchronisation NTP-like
│   │   ├── audio_stream_server.dart # Serveur audio local (hôte)
│   │   ├── audio_stream_client.dart # Client audio (esclave)
│   │   ├── websocket_manager.dart   # Gestion connexions WS
│   │   └── device_discovery.dart    # mDNS + Cast discovery
│   ├── audio/
│   │   ├── audio_engine.dart        # Moteur de lecture
│   │   ├── buffer_manager.dart      # Gestion buffer adaptatif
│   │   └── drift_compensator.dart   # Compensation de dérive
│   └── session/
│       ├── session_manager.dart     # Gestion session multi-appareils
│       └── device_registry.dart     # Registre des appareils
├── features/
│   ├── discovery/
│   │   ├── bloc/                    # État découverte
│   │   └── ui/                      # UI liste appareils
│   ├── player/
│   │   ├── bloc/                    # État lecteur
│   │   └── ui/                      # UI lecteur
│   ├── groups/
│   │   ├── bloc/                    # État groupes
│   │   └── ui/                      # UI gestion groupes
│   └── settings/
│       ├── bloc/
│       └── ui/
└── main.dart
```

### États de l'appareil

```
[Idle] ──► [Discovering] ──► [Joining] ──► [Syncing] ──► [Playing]
                │                  │             │            │
                ▼                  ▼             ▼            ▼
           [Error]           [Error]       [Reconnecting] [Paused]
                                                │
                                                ▼
                                           [Playing]
```

## 2. Backend éventuel

### Rôle : minimal, pas de streaming audio via cloud

Le backend ne transporte **jamais** le flux audio. Il sert uniquement à :
- **Authentification** : comptes utilisateurs (optionnel au MVP)
- **Configuration** : paramètres de session, préférences
- **Télémétrie** : analytics, crash reports
- **Signaling** : optionnel, pour connexions hors LAN (futur)

### Stack backend (MVP)
- **Firebase Auth** : authentification anonyme ou email
- **Firebase Firestore** : configuration sessions
- **Firebase Crashlytics** : crash reports
- **Firebase Analytics** : usage tracking

### Pourquoi pas de serveur audio cloud ?
- La latence cloud (50-200ms round-trip) rend la synchronisation impossible
- Le coût de bande passante serait prohibitif
- Le modèle peer-to-peer local est plus robuste et privé

## 3. Moteur de synchronisation audio

### Principe : NTP-like over LAN

Le protocole de synchronisation est inspiré de NTP mais simplifié pour le LAN :

```
Hôte (horloge maître)                    Esclave (horloge esclave)
      │                                        │
      │──── T1: "sync_request" ───────────────►│
      │                                        │ (enregistre T2)
      │◄─── T3: "sync_response" {T1,T2,T3} ───│
      │                                        │
      │ Calcule:                                │
      │ offset = ((T2-T1) + (T3-T4)) / 2       │
      │ delay  = (T4-T1) - (T3-T2)             │
      │                                        │
      │──── T4: "ack" + clock_adjustment ─────►│
      │                                        │ Ajuste son horloge
```

### Implémentation

```dart
class ClockSync {
  // Horloge locale ajustée
  int get syncedTimeMs {
    return DateTime.now().millisecondsSinceEpoch + _offsetMs;
  }

  // Offset calculé par échange NTP-like
  double _offsetMs = 0;
  double _driftPpm = 0; // dérive en parties par million

  // Recalibrage toutes les 30 secondes
  Future<void> calibrate() async {
    final samples = <ClockSample>[];
    for (int i = 0; i < 8; i++) {
      final t1 = DateTime.now().millisecondsSinceEpoch;
      final response = await _sendSyncRequest();
      final t4 = DateTime.now().millisecondsSinceEpoch;
      samples.add(ClockSample(t1, response.t2, response.t3, t4));
      await Future.delayed(Duration(milliseconds: 100));
    }
    // Filtrage statistique (éliminer les outliers)
    final filtered = _filterOutliers(samples);
    // Calcul offset et drift
    _offsetMs = _calculateOffset(filtered);
    _driftPpm = _calculateDrift(filtered);
  }
}
```

### Compensation de dérive (drift compensation)

Les horloges hardware dérivent de 7-40 ppm. Sur 30 secondes entre recalibrages :
- Drift max : 40 ppm × 30s = 1.2ms
- Acceptable pour la synchronisation audio

Mécanisme :
1. Mesurer le drift entre deux calibrations successives
2. Appliquer une correction linéaire continue entre les calibrations
3. Si le drift dépasse un seuil (5ms), forcer un recalibrage immédiat

### Buffer adaptatif

```dart
class AdaptiveBuffer {
  int _bufferSizeMs = 100; // Taille initiale
  final int _minBufferMs = 50;
  final int _maxBufferMs = 500;

  void adjust(NetworkStats stats) {
    if (stats.jitterMs < 10 && stats.packetLoss < 0.01) {
      _bufferSizeMs = (_bufferSizeMs * 0.9).round().clamp(_minBufferMs, _maxBufferMs);
    } else if (stats.jitterMs > 50 || stats.packetLoss > 0.05) {
      _bufferSizeMs = (_bufferSizeMs * 1.2).round().clamp(_minBufferMs, _maxBufferMs);
    }
  }
}
```

## 4. Découverte et appairage des appareils

### Protocole principal : mDNS/Zeroconf

```
Service type: _musync._tcp.local.
Port: 7890
TXT records:
  - device_name: "iPhone de Marc"
  - device_type: "phone|tablet|speaker|tv"
  - app_version: "1.0.0"
  - capabilities: "audio_play,clock_sync"
  - role: "host|slave|any"
```

### Flux de découverte

```
1. Hôte publie le service mDNS _musync._tcp.local.
2. Esclaves scannent pour _musync._tcp.local.
3. Esclave trouve l'hôte → connexion WebSocket
4. Échange de clé de session (simple token UUID)
5. Calibration d'horloge (NTP-like)
6. Prêt à recevoir le flux audio
```

### Appairage

```
Hôte                          Esclave
  │                              │
  │◄── WS connect ──────────────│
  │                              │
  │── "hello" {session_id} ────►│
  │                              │ Vérifie session_id
  │◄── "join" {device_info} ────│
  │                              │
  │── "welcome" {role: slave} ──►│
  │                              │
  │◄──► Clock Sync (NTP-like) ──│
  │                              │
  │── "ready" ──────────────────►│
  │                              │ Commence à jouer
```

## 5. Gestion des sessions multi-appareils

### Modèle de session

```dart
class AudioSession {
  final String sessionId;       // UUID
  final DeviceInfo hostDevice;  // Appareil maître
  final List<DeviceInfo> slaves; // Appareils esclaves
  final SessionState state;
  final AudioTrack? currentTrack;
  final DateTime startedAt;
}

enum SessionState {
  waiting,    // En attente d'esclaves
  syncing,    // Calibration en cours
  playing,    // Lecture en cours
  paused,     // Pause
  buffering,  // Rechargement buffer
  error,      // Erreur
}
```

### Gestion des déconnexions

```
Si esclave perdu < 5 secondes :
  → Pause locale de l'esclave
  → Tentative de reconnexion automatique
  → Re-calibration
  → Reprise

Si esclave perdu > 5 secondes :
  → Retrait du groupe
  → Notification à l'hôte
  → L'utilisateur peut inviter à rejoindre

Si hôte perdu :
  → Tous les esclaves passent en mode "attente"
  → Tentative de reconnexion pendant 30 secondes
  → Si échec : arrêt de la session
```

## 6. Stratégie de diffusion audio

### Architecture : Push from Host

L'hôte lit le fichier audio et envoie des chunks aux esclaves via WebSocket :

```
┌──────────┐     Audio chunks (PCM/AAC)     ┌──────────┐
│  HÔTE    │────────────────────────────────►│ ESCLAVE  │
│          │     + timestamps de lecture      │          │
│  Decode  │                                  │  Buffer  │
│  → Chunk │                                  │  → Play  │
│  → Send  │                                  │  @ T_sync│
└──────────┘                                  └──────────┘
```

### Format de transport

```dart
class AudioChunk {
  final int sequenceNumber;    // Ordre du chunk
  final int playbackTimeMs;    // Timestamp de lecture cible (horloge sync)
  final Uint8List audioData;   // Données audio (PCM 16-bit 44100Hz ou AAC)
  final int sampleRate;        // 44100
  final int channels;          // 2 (stéréo)
}
```

### Pourquoi push et non pull ?

- **Push** : L'hôte contrôle le timing. Plus simple, plus prévisible.
- **Pull** : Chaque esclave demande les chunks. Plus complexe, risque de désynchronisation.

Le modèle push est utilisé par AirPlay 2 et est plus adapté à notre cas.

### Compression

- **MVP** : PCM 16-bit 44100Hz stéréo = ~176 KB/s par appareil
  - Sur Wi-Fi 5GHz : largement suffisant pour 5-8 appareils
- **Post-MVP** : Opus codec à 128kbps = ~16 KB/s par appareil
  - Réduit la bande passante de 10x

## 7. Mécanisme de synchronisation

### Principe : "Play at time T"

L'hôte décide d'un timestamp de démarrage commun :

```
1. Hôte prépare le fichier audio
2. Hôte calcule : T_start = syncedTime + 2000ms (2 secondes dans le futur)
3. Hôte envoie à chaque esclave : "start_at" {T_start, track_info}
4. Chaque esclave :
   a. Charge le fichier audio (URL ou fichier local)
   b. Se positionne au bon offset
   c. Attend que son horloge sync atteigne T_start
   d. Commence la lecture simultanément
```

### Synchronisation continue

Pendant la lecture :
1. L'hôte envoie périodiquement (toutes les 500ms) le timestamp de lecture actuel
2. Chaque esclave compare sa position de lecture avec la cible
3. Si l'écart dépasse 20ms :
   - < 50ms : ajustement progressif (légère accélération/ralentissement)
   - 50-100ms : seek silencieux
   - > 100ms : pause, resync, reprise

### Ajustement progressif (pitch-free)

```dart
void adjustPlayback(double offsetMs) {
  if (offsetMs.abs() < 50) {
    // Ajustement par micro-seek imperceptible
    final correction = offsetMs * 0.1; // 10% par cycle
    _player.seek(_player.position + Duration(milliseconds: correction.round()));
  } else if (offsetMs.abs() < 100) {
    // Seek direct mais silencieux
    _player.seek(_targetPosition);
  } else {
    // Resync complet
    _player.pause();
    _player.seek(_targetPosition);
    // Attendre le prochain "play" de l'hôte
  }
}
```

## 8. Compensation de latence et de dérive

### Latence réseau
- Mesurée lors de la calibration NTP-like
- Typiquement 1-10ms sur Wi-Fi local
- Compensée dans le calcul du timestamp de démarrage

### Latence audio (output latency)
- Android : 10-50ms selon le device et le mode audio
- iOS : 5-15ms (Core Audio plus déterministe)
- Mesurée au premier lancement via test de latence
- Stockée dans les préférences de l'appareil

### Dérive horloge
- Mesurée entre calibrations successives
- Compensée par ajustement linéaire
- Recalibrage forcé si dérive > 5ms

### Buffer de sécurité
- Taille initiale : 100ms
- Adaptatif selon la qualité du réseau
- Minimum : 50ms, maximum : 500ms

## 9. Reprise après coupure

### Scénarios

| Scénario | Durée | Action |
|----------|-------|--------|
| Micro-coupure Wi-Fi | < 1s | Buffer absorbe, pas d'action |
| Coupure courte | 1-5s | Pause, tentative reconnexion, resync |
| Coupure longue | 5-30s | Retrait du groupe, notification |
| Changement de réseau | N/A | Arrêt session, nouvelle découverte |
| App mise en background (iOS) | Variable | Foreground service (Android), audio session (iOS) |
| App tuée par OS | N/A | Reconnexion au lancement, reprise si session active |

### Implémentation

```dart
class ConnectionRecovery {
  Timer? _heartbeatTimer;
  int _missedHeartbeats = 0;

  void startHeartbeat() {
    _heartbeatTimer = Timer.periodic(Duration(seconds: 1), (_) {
      if (_lastHeartbeatAck == null || 
          DateTime.now().difference(_lastHeartbeatAck!) > Duration(seconds: 2)) {
        _missedHeartbeats++;
        if (_missedHeartbeats > 3) {
          _onConnectionLost();
        }
      }
    });
  }

  void _onConnectionLost() {
    _player.pause();
    _attemptReconnection(maxAttempts: 5, interval: Duration(seconds: 2));
  }
}
```

## 10. Sécurité des flux et des sessions

### MVP (sécurité basique)
- **Session token** : UUID v4 généré par l'hôte, échangé à la connexion
- **Réseau local uniquement** : Pas d'exposition internet
- **Pas de chiffrement audio** : Le flux reste sur le LAN

### Post-MVP (sécurité renforcée)
- **TLS pour WebSocket** : wss:// au lieu de ws://
- **Authentification mutuelle** : Certificats éphémères
- **Chiffrement audio** : AES-256 pour les chunks audio
- **PIN de session** : Code à 4 chiffres pour rejoindre un groupe

### Menaces identifiées

| Menace | Impact | Mitigation MVP | Mitigation Post-MVP |
|--------|--------|----------------|---------------------|
| Écoute du flux audio sur le LAN | Faible | Réseau local de confiance | Chiffrement AES |
| Rejoindre une session non autorisée | Moyen | Token UUID (obscurité) | PIN + authentification |
| Injection de faux chunks audio | Faible | Validation sequence number | Signature HMAC |
| Attaque DoS sur l'hôte | Faible | Limite de connexions (8) | Rate limiting |
