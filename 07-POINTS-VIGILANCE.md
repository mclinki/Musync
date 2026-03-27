# MusyncMIMO — Points de Vigilance

## 1. Compatibilité iOS / Android

### iOS

| Problème | Impact | Mitigation |
|----------|--------|------------|
| **Background audio suspension** : iOS suspend les apps après ~30s en background | Critique (esclaves) | `audio_session` avec mode `.longFormAudio`, guide utilisateur pour garder l'écran allumé |
| **App Transport Security** : WebSocket non-chiffré bloqué par défaut | Moyen | Utiliser `ws://` avec exception ATS en dev, `wss://` en prod |
| **mDNS sur iOS** : fonctionne mais avec des restrictions de background | Élevé | Découverte en foreground uniquement, cache des appareils connus |
| **Permissions réseau** : iOS 14+ demande permission pour accès réseau local | Moyen | Info.plist : `NSLocalNetworkUsageDescription` + `NSBonjourServices` |
| **TestFlight limites** : 100 testeurs externes, builds expirent après 90 jours | Faible | Renouvellement régulier, limiter le scope beta |

### Android

| Problème | Impact | Mitigation |
|----------|--------|------------|
| **Battery optimization** : Xiaomi, Samsung, Huawei tuent les apps background | Critique | Foreground service avec notification persistante, guide de désactivation |
| **Permissions** : `NEARBY_WIFI_DEVICES` (Android 13+), `ACCESS_FINE_LOCATION` pour mDNS | Élevé | Gestion granulaire des permissions, explication claire |
| **Fragmentation audio** : latence audio variable (10-100ms) selon le device | Élevé | Mesure automatique de la latence au premier lancement, compensation |
| **WebSocket background** : Android peut fermer les connexions WebSocket en Doze mode | Élevé | Foreground service + wake lock partiel |
| **Format audio** : certains devices ne supportent pas tous les codecs | Moyen | Test de compatibilité au lancement, fallback PCM |

## 2. Restrictions système liées au son

### iOS
- **Audio Session** : L'app doit déclarer sa catégorie audio (`.playback`) et son mode (`.longFormAudio`)
- **Interruptions** : Un appel téléphonique interrompt l'audio. L'app doit gérer la reprise.
- **Mix audio** : Par défaut, iOS baisse le volume des autres apps. L'utilisateur peut vouloir désactiver cela.
- **AirPlay** : L'app peut diffuser vers AirPlay, mais le contrôle est limité au système iOS.

### Android
- **Audio Focus** : L'app doit demander et gérer le focus audio.
- **Audio Attributes** : Définir le contenu (music), l'usage (media), les flags.
- **Doze Mode** : Android 6+ restreint le réseau en veille. Foreground service nécessaire.
- **Bluetooth** : Le routing audio Bluetooth ajoute 100-300ms de latence. Avertissement utilisateur.

## 3. Permissions et arrière-plan

### Permissions requises

| Permission | Plateforme | Justification | Risque refus |
|------------|------------|---------------|--------------|
| `INTERNET` | Android | Connexion WebSocket | Faible |
| `ACCESS_WIFI_STATE` | Android | État Wi-Fi | Faible |
| `ACCESS_NETWORK_STATE` | Android | État réseau | Faible |
| `NEARBY_WIFI_DEVICES` | Android 13+ | Découverte mDNS | Moyen |
| `FOREGROUND_SERVICE` | Android | Service background | Faible |
| `WAKE_LOCK` | Android | Empêcher la veille | Faible |
| `NSLocalNetworkUsageDescription` | iOS | Accès réseau local | Moyen |
| `NSBonjourServices` | iOS | mDNS discovery | Moyen |

### Stratégie de demande
1. Demander les permissions au moment du besoin (pas au lancement)
2. Expliquer pourquoi chaque permission est nécessaire
3. Fournir un mode dégradé si une permission est refusée (saisie manuelle d'IP)

## 4. Synchronisation temps réel

### Sources de désynchronisation

| Source | Amplitude | Fréquence | Compensation |
|--------|-----------|-----------|--------------|
| Dérive horloge hardware | 7-40 ppm (0.25-1.4ms/min) | Continue | Recalibrage NTP-like toutes les 30s |
| Jitter Wi-Fi | 1-100ms | Variable | Buffer adaptatif (50-500ms) |
| Latence de décodage | 5-50ms | Constante par device | Mesure initiale + compensation |
| Latence de sortie audio | 5-50ms | Constante par device | Mesure initiale + compensation |
| Congestion réseau | 10-500ms | Intermittente | Buffer adaptatif + alerte |

### Seuils de qualité

| Skew perçu | Perception humaine | Action |
|------------|-------------------|--------|
| < 15ms | Imperceptible | ✅ Optimal |
| 15-30ms | Très difficile à percevoir | ✅ Acceptable |
| 30-50ms | Perceptible si appareils proches | ⚠️ Limite |
| 50-100ms | Écho perceptible | ❌ Inacceptable |
| > 100ms | Double son distinct | ❌ Critique |

### Stratégie de compensation

```
1. Calibration initiale (NTP-like, 8 échantillons)
2. Recalibrage périodique (toutes les 30s)
3. Monitoring continu du skew
4. Si skew < 20ms : pas d'action
5. Si skew 20-50ms : micro-ajustement (seek progressif)
6. Si skew 50-100ms : seek silencieux
7. Si skew > 100ms : pause, resync complet, reprise
```

## 5. Consommation batterie

### Estimation

| Mode | Consommation | Durée estimée (batterie 4000mAh) |
|------|-------------|----------------------------------|
| Hôte (lecture + serveur WS + mDNS) | ~300-500mA | 8-13h |
| Esclave (client WS + décodage) | ~150-250mA | 16-26h |
| Background (esclave, attente) | ~50-100mA | 40-80h |

### Optimisations
- Utiliser le codec le plus efficace (Opus > AAC > MP3 > PCM)
- Réduire la fréquence de heartbeat (1Hz suffit)
- Éviter le wake lock permanent (partiel seulement)
- Mettre en veille l'écran des esclaves

## 6. Stabilité réseau

### Scénarios réseau

| Scénario | Probabilité | Impact | Mitigation |
|----------|-------------|--------|------------|
| Wi-Fi stable, faible charge | Élevée | Aucun | Cas nominal |
| Wi-Fi instable, micro-coupures | Moyenne | Désynchronisation | Buffer adaptatif, reconnexion |
| Wi-Fi congestionné (beaucoup d'appareils) | Moyenne | Latence variable | Avertissement, réduction qualité |
| Changement de réseau (Wi-Fi → 4G) | Faible | Arrêt session | Détection, notification |
| Mesh Wi-Fi avec handoff | Moyenne | Micro-coupures | Buffer + reconnexion |
| VPN actif | Faible | Latence ajoutée | Détection, avertissement |

### Recommandations réseau
- Wi-Fi 5GHz recommandé (moins de congestion que 2.4GHz)
- Éviter les réseaux avec beaucoup d'appareils (> 20)
- Éviter les VPN pendant les sessions
- Router avec QoS activé si disponible

## 7. Qualité audio

### Formats supportés (MVP)

| Format | Débit | Qualité | Support | Recommandation |
|--------|-------|---------|---------|----------------|
| MP3 128kbps | 16 KB/s | Bon | Universel | ✅ Défaut |
| MP3 320kbps | 40 KB/s | Excellent | Universel | ✅ Si bande passante OK |
| AAC 128kbps | 16 KB/s | Très bon | Universel | ✅ Alternative |
| FLAC | 50-100 KB/s | Lossless | Majorité | ⚠️ Bande passante élevée |
| Opus 128kbps | 16 KB/s | Excellent | Majorité | ✅ Post-MVP (meilleur ratio) |
| PCM 16-bit 44.1kHz | 176 KB/s | Lossless | Universel | ❌ Trop lourd pour streaming |

### Qualité de sortie
- Fréquence d'échantillonnage : 44100 Hz (CD quality)
- Profondeur : 16 bits
- Canaux : Stéréo (2)
- Pas de traitement audio au MVP (pas d'EQ, pas de compression)

## 8. Confidentialité et sécurité

### Données collectées

| Donnée | Justification | Stockage | Partage |
|--------|---------------|----------|---------|
| Device ID (anonyme) | Identifier l'appareil en session | Local | Non |
| Nom de l'appareil | Affichage dans la liste | Local | Oui (LAN uniquement) |
| Adresse IP locale | Connexion WebSocket | Local | Oui (LAN uniquement) |
| Fichiers audio | Lecture | Local | Oui (LAN, pendant la session) |
| Analytics d'usage | Amélioration produit | Firebase | Oui (agrégé, anonyme) |
| Crash reports | Stabilité | Firebase Crashlytics | Oui (anonyme) |

### Données NON collectées
- ❌ Données de localisation GPS
- ❌ Contacts
- ❌ Contenu des fichiers audio (métadonnées seulement)
- ❌ Historique de navigation
- ❌ Identifiants personnels (au MVP, auth anonyme)

### Conformité RGPD
- Authentification anonyme au MVP (pas de données personnelles)
- Analytics anonymisées (Firebase)
- Pas de transfert de données hors UE nécessaire (Firebase est configurable)
- Politique de confidentialité requise pour les stores

## 9. Conformité Store / Publication

### Apple App Store

| Exigence | Statut | Action |
|----------|--------|--------|
| Privacy Policy URL | Requis | Créer une page web |
| App Privacy (nutrition labels) | Requis | Déclarer les données collectées |
| Local Network permission usage | Requis | Info.plist configuré |
| Background audio justification | Requis | Description claire dans la review |
| No private API usage | Requis | Vérifier les plugins Flutter |
| IPv6 compatibility | Requis | Tester sur réseau IPv6 |

### Google Play Store

| Exigence | Statut | Action |
|----------|--------|--------|
| Data Safety section | Requis | Déclarer les données |
| Target API level | Requis | API 34+ (Android 14) |
| Permissions declarations | Requis | Justifier chaque permission |
| Privacy Policy | Requis | Même que iOS |
| Content rating | Requis | Questionnaire IARC |

## 10. Dette technique potentielle

### Zones à risque

| Zone | Dette potentielle | Prévention |
|------|-------------------|------------|
| **Moteur de sync** | Complexité croissante avec les optimisations | Module isolé, tests unitaires, documentation |
| **Gestion des erreurs réseau** | Multiplication des cas d'erreur | State machine centralisée, tests de chaos |
| **UI cross-platform** | Divergence iOS/Android au fil du temps | Design system partagé, tests golden |
| **Dépendances Flutter** | Mises à jour cassantes | Pin des versions, CI avec vérification |
| **Firebase** | Vendor lock-in | Abstraction des services Firebase derrière des interfaces |
| **Protocole WebSocket** | Évolution du protocole | Versioning des messages, backward compatibility |

### Règles d'or pour limiter la dette
1. **Tests avant features** : chaque nouvelle fonctionnalité a ses tests
2. **Documentation vivante** : les décisions d'architecture sont documentées
3. **Revue de code** : pas de merge sans review
4. **Refactoring régulier** : 20% du temps dédié au refactoring
5. **Monitoring** : métriques de qualité en continu
