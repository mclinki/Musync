# MusyncMIMO — Hypothèses de Départ

## Hypothèses fonctionnelles

| # | Hypothèse | Justification | Risque si faux |
|---|-----------|---------------|----------------|
| H1 | L'utilisateur possède au moins 2 appareils avec haut-parleur sur le même réseau Wi-Fi | Cas d'usage minimal | Produit sans valeur |
| H2 | Les appareils cibles exécutent l'app MusyncMIMO (MVP) ou supportent Cast/AirPlay (post-MVP) | Contrôle nécessaire sur le récepteur | Limitation majeure du parc d'appareils |
| H3 | Le réseau Wi-Fi local offre une latence < 50ms entre appareils | Seuil de synchronisation audible | Expérience dégradée |
| H4 | L'utilisateur accepte d'installer l'app sur chaque appareil | Modèle peer-to-peer local | Friction d'adoption |
| H5 | La source audio est un fichier local ou une URL de streaming (pas de DRM) | Contournement des restrictions DRM | Catalogue limité |

## Hypothèses techniques

| # | Hypothèse | Justification | Risque si faux |
|---|-----------|---------------|----------------|
| T1 | La synchronisation par horloge NTP-like atteint ±10-30ms sur Wi-Fi local | Littérature + benchmarks (cf. CMU research : 720µs avec audio clock, 10-27ms avec NTP rapide) | Désynchronisation audible |
| T2 | Flutter permet un accès suffisamment bas niveau aux APIs audio natives | `just_audio` + platform channels | Latence ajoutée inacceptable |
| T3 | mDNS/Zeroconf fonctionne de manière fiable sur la majorité des réseaux domestiques | Protocole standard, supporté Android/iOS | Découverte d'appareils échoue |
| T4 | Le codec audio (AAC/MP3/Opus) peut être décodé en temps réel sur tous les appareils cibles | Processeurs modernes suffisants | Appareils anciens exclus |
| T5 | iOS permet le background audio avec WebSocket actif | iOS 14+ supporte background audio | iOS limité au foreground |

## Zones d'incertitude technique

1. **Drift des horloges entre appareils** : Les horloges hardware dérivent de 7-40 ppm (parties par million). Sur 1 heure, cela peut représenter 25-144ms de désynchronisation sans correction. Solution : recalibrage périodique + compensation logicielle.

2. **Latence variable du Wi-Fi** : Le jitter Wi-Fi peut atteindre 10-100ms sur réseaux domestiques. Solution : buffer adaptatif + prédiction.

3. **Restrictions iOS background** : iOS limite sévèrement les processus background. L'app peut être suspendue par le système. Solution : modes audio spécifiques + notifications de reprise.

4. **Permissions Android** : Les fabricants Android (Xiaomi, Samsung, Huawei) implémentent des optimisations batterie agressives qui tuent les apps background. Solution : guide utilisateur + foreground service.

5. **DRM et sources streaming** : Spotify, Apple Music, etc. utilisent du DRM qui empêche l'accès au flux audio brut. Impossible de rediriger leur audio vers d'autres appareils sans accord de licence.
