# MusyncMIMO — Stack Recommandée

## Tableau récapitulatif

| Brique | Option principale | Alternative | Justification |
|--------|-------------------|-------------|---------------|
| Framework mobile | **Flutter 3.x** | React Native, Kotlin Multiplatform | 100% code share Android/iOS, performance native AOT, écosystème audio mature |
| Langage | **Dart 3.x** | Kotlin, Swift | Imposé par Flutter, bon support async/await, isolates pour performance |
| Audio local | **just_audio 0.10+** | `audioplayers`, `media_kit` | Meilleur contrôle bas niveau, support seek précis, buffer control, multi-platform |
| Session audio | **audio_session** | — | Gestion des interruptions audio, mix avec autres apps, background audio iOS |
| Réseau / transport | **WebSocket (LAN)** | WebRTC, gRPC | Simple, fiable, bidirectionnel, supporté nativement, suffisant pour le LAN |
| Clock sync | **Custom NTP-like** | PTP, NTP standard | PTP nécessite hardware spécialisé, NTP standard trop imprécis (10-20ms). Custom permet optimisation spécifique |
| Découverte appareils | **multicast_dns** | NSD (Android native), Bonjour (iOS) | Cross-platform, supporte mDNS/Zeroconf, détection LAN |
| Stockage local | **sqflite + path_provider** | Hive, Isar | SQL pour requêtes complexes, fiable, mature |
| Stockage distant | **Firebase Firestore** | Supabase, PocketBase | Temps réel, offline-first, scalabilité, écosystème Firebase complet |
| Authentification | **Firebase Auth** | — | Auth anonyme + email, simple, gratuit au MVP |
| Crash reporting | **Firebase Crashlytics** | Sentry, Bugsnag | Intégration Flutter native, gratuit |
| Analytics | **Firebase Analytics** | Mixpanel, Amplitude | Gratuit, intégré, suffisant au MVP |
| State management | **Bloc/Cubit** | Riverpod, Provider | Prévisible, testable, séparation UI/logique |
| CI/CD | **Codemagic** | GitHub Actions, Bitrise | Spécialisé Flutter, builds iOS sans Mac |
| Tests | **flutter_test + integration_test** | Patrol, Patrol | Standard Flutter, suffisant au MVP |

## Détail par brique

### 1. Framework mobile : Flutter 3.x

**Pourquoi Flutter et pas React Native ?**
- Performance audio : Flutter compile en code natif (AOT), pas de bridge JS
- Contrôle bas niveau : accès aux APIs natives via platform channels sans overhead
- Écosystème audio : `just_audio` est le package audio le plus mature et maintenu
- Hot reload : développement rapide du moteur de synchronisation

**Pourquoi Flutter et pas Kotlin Multiplatform ?**
- iOS : KMP nécessite du Swift/ObjC pour l'UI iOS
- Time-to-market : Flutter permet un seul codebase pour UI + logique
- Équipe : un développeur Flutter peut livrer les deux plateformes

**Risques Flutter** :
- Taille du binaire : ~15-20MB (acceptable)
- Accès bas niveau audio : nécessite platform channels pour les optimisations avancées
- Mise à jour iOS : parfois en retard sur les nouvelles APIs iOS

### 2. Audio local : just_audio

```dart
// Configuration typique
final player = AudioPlayer();

// Configuration session audio
await player.setAudioSession(AudioSession(
  androidAudioAttributes: AndroidAudioAttributes(
    contentType: AndroidAudioContentType.music,
    usage: AndroidAudioUsage.media,
  ),
  androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  androidWillPauseWhenDucked: false,
));

// Lecture avec seek précis
await player.setUrl(audioUrl);
await player.seek(Duration(milliseconds: targetStartMs), 
    position: Duration(milliseconds: targetStartMs));
await player.play();
```

**Capacités clés** :
- Seek précis au millisecond
- Buffer configurable
- Support PCM, AAC, MP3, Opus, FLAC
- Position de lecture en temps réel (stream)
- Gestion des interruptions audio

### 3. Réseau : WebSocket local

**Pourquoi WebSocket et pas WebRTC ?**
- WebRTC est conçu pour le peer-to-peer avec NAT traversal (pas nécessaire en LAN)
- WebSocket est plus simple à implémenter et à déboguer
- La latence WebSocket en LAN est < 1ms (suffisant)
- WebRTC ajoute de la complexité (ICE, STUN, DTLS) sans bénéfice en LAN

**Pourquoi WebSocket et pas gRPC ?**
- gRPC nécessite HTTP/2, plus complexe à faire tourner en local
- WebSocket est bidirectionnel nativement
- gRPC streaming est plus verbeux

**Architecture WebSocket** :

```
Hôte (serveur WS)                    Esclave (client WS)
  │                                        │
  │◄─── TCP connect ──────────────────────│
  │◄─── WS upgrade ───────────────────────│
  │                                        │
  │◄──► Messages JSON/Protobuf ──────────►│
  │     - clock_sync                       │
  │     - audio_chunk                      │
  │     - playback_control                 │
  │     - heartbeat                        │
```

### 4. Découverte : multicast_dns

```dart
// Côté hôte : publier le service
final MDnsClient client = MDnsClient();
await client.start();
// Publication via platform channel ou plugin

// Côté esclave : scanner
final client = MDnsClient();
await client.start();
await for (final PtrResourceRecord ptr in client
    .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer('_musync._tcp.local'))) {
  await for (final SrvResourceRecord srv in client
      .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
    // Appareil trouvé : srv.target, srv.port
  }
}
```

### 5. Stockage

**Local (sqflite)** :
- Historique des sessions
- Préférences appareil (latence audio mesurée)
- Groupes sauvegardés
- Cache des métadonnées audio

**Distant (Firebase Firestore)** :
- Configuration utilisateur
- Groupes synchronisés entre appareils
- Analytics d'usage
- Feature flags

### 6. State management : Bloc

```dart
// Exemple : DeviceDiscoveryBloc
class DeviceDiscoveryBloc extends Bloc<DiscoveryEvent, DiscoveryState> {
  final DeviceDiscovery _discovery;
  
  DeviceDiscoveryBloc(this._discovery) : super(DiscoveryInitial()) {
    on<StartDiscovery>(_onStart);
    on<DeviceFound>(_onDeviceFound);
    on<StopDiscovery>(_onStop);
  }
  
  void _onStart(StartDiscovery event, Emitter<DiscoveryState> emit) async {
    emit(DiscoveryScanning());
    await for (final device in _discovery.scan()) {
      add(DeviceFound(device));
    }
  }
}
```

## Protocoles évalués et rejetés

### Bluetooth
- **Latence** : 100-300ms (SBC), 40-100ms (aptX Low Latency)
- **Verdict** : REJETÉ pour la synchronisation. Trop de latence.
- **Usage possible** : connexion à une enceinte Bluetooth unique (mode non-synchronisé, futur)

### DLNA/UPnP
- **Problème** : Pas de synchronisation multi-appareils native
- **Complexité** : Protocole lourd, XML parsing, SOAP
- **Verdict** : REJETÉ au MVP. Trop complexe, pas de sync native.
- **Usage possible** : Envoi vers un appareil DLNA unique (futur)

### AirPlay 2
- **Avantage** : Excellente synchronisation (< 25ms), supporté par enceintes Apple/Sonos
- **Problème** : SDK fermé, iOS/macOS uniquement, pas d'implémentation Android légale
- **Verdict** : INTÉGRATION POST-MVP via platform channel iOS uniquement
- **Usage** : L'hôte iOS peut caster vers des enceintes AirPlay 2

### Chromecast (Google Cast)
- **Avantage** : Large parc d'appareils, SDK disponible Android/iOS
- **Problème** : Synchronisation moins précise qu'AirPlay 2 (25-100ms), nécessite un receiver app
- **Verdict** : INTÉGRATION POST-MVP
- **Usage** : L'hôte peut caster vers des appareils Cast (Chromecast Audio, enceintes Google)

### WebRTC
- **Avantage** : Ultra-low latency, P2P natif
- **Problème** : Complexité (ICE/STUN/DTLS), overkill pour LAN
- **Verdict** : REJETÉ au MVP. WebSocket suffit en LAN.
- **Usage possible** : Connexions hors LAN (futur lointain)

### RTP/RTSP
- **Avantage** : Protocole standard pour streaming temps réel
- **Problème** : Pas de synchronisation native, nécessite un serveur RTSP
- **Verdict** : REJETÉ. WebSocket + custom sync est plus simple et plus précis.

## Infrastructure

### MVP (gratuit)
- Firebase Spark Plan (gratuit) : Auth, Firestore, Crashlytics, Analytics
- Pas de serveur dédié (tout est P2P en LAN)
- Distribution : Google Play Store + Apple App Store

### Post-MVP (si nécessaire)
- Firebase Blaze Plan (pay-as-you-go) : si dépassement des limites gratuites
- Serveur WebSocket cloud (optionnel) : pour connexions hors LAN
- CDN pour les mises à jour de l'app
