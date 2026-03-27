# MusyncMIMO — Analyse Produit

## 1. Cas d'usage prioritaires

### CU1 — Soirée / rassemblement (priorité HAUTE)
> "Je lance une playlist sur mon téléphone et tous les téléphones + enceintes de la pièce jouent en même temps."
- Source : fichier local ou URL streaming (radio, podcast)
- Cible : 2-8 appareils sur le même Wi-Fi
- Critère qualité : pas d'écho perceptible (< 30ms de skew)

### CU2 — Ambiance multi-pièces (priorité MOYENNE)
> "Je diffuse de la musique dans le salon ET la chambre en même temps."
- Source : idem
- Cible : 2-4 appareils dans des pièces différentes
- Tolérance : skew jusqu'à 50ms acceptable (pièces séparées)

### CU3 — Renforcement sonore (priorité MOYENNE)
> "Je mets mon téléphone et ma tablette côte à côte pour avoir plus de volume."
- Source : fichier local
- Cible : 2-3 appareils proches
- Tolérance : skew < 15ms (appareils proches, écho immédiat)

### CU4 — Contrôle depuis un appareil maître (priorité HAUTE)
> "Je contrôle la lecture (play/pause/skip/volume) depuis mon téléphone, les autres suivent."
- UX : interface simple type "télécommande"
- Latence de commande : < 500ms

## 2. Persona cible

### Persona principal : "L'organisateur"
- **Âge** : 22-40 ans
- **Profil** : Tech-comfortable, possède 3-5 appareils connectés
- **Contexte** : Soirées, BBQ, travail à la maison, voyage
- **Motivation** : Plus de volume, ambiance collective, pas d'achat de matériel
- **Frustration** : Enceintes Bluetooth chères, écosystèmes fermés (Sonos), pas de multi-room simple

### Persona secondaire : "Le mélomane pragmatique"
- **Âge** : 25-45 ans
- **Profil** : Collection de musique locale (FLAC, MP3), pas d'abonnement streaming
- **Motivation** : Valoriser ses appareils existants
- **Frustration** : Pas de solution simple pour diffuser sur plusieurs appareils

## 3. Proposition de valeur

**En une phrase** : Transformez tous vos appareils en système audio multi-room synchronisé, sans matériel supplémentaire.

**Piliers** :
1. **Simplicité** : 3 taps pour lancer un groupe
2. **Compatibilité** : Fonctionne avec les appareils que vous avez déjà
3. **Qualité** : Synchronisation imperceptible (< 30ms)
4. **Gratuité** : Pas de matériel à acheter

## 4. Besoins utilisateurs

| Besoin | Priorité | Difficulté technique |
|--------|----------|---------------------|
| Lancer une musique sur N appareils | P0 | Moyenne |
| Découvrir les appareils disponibles | P0 | Haute |
| Synchroniser la lecture | P0 | Très haute |
| Contrôler play/pause/skip | P0 | Faible |
| Gérer le volume par appareil | P1 | Faible |
| Sauvegarder des groupes | P1 | Faible |
| Reprise après coupure réseau | P1 | Haute |
| Support fichiers locaux (MP3, AAC, FLAC) | P0 | Moyenne |
| Support streaming URL (radio, podcast) | P1 | Moyenne |
| Support services streaming (Spotify...) | P2 | Bloqué (DRM) |
| Spatial audio / effet stéréo étendu | P3 | Très haute |

## 5. Limites fonctionnelles et techniques

### Limites dures (incontournables)
- **DRM** : Impossible de rediriger l'audio de Spotify, Apple Music, Deezer, etc. sans licence. Le MVP se limite aux fichiers locaux et URLs de streaming libres.
- **Bluetooth** : Latence inhérente de 100-300ms. Inacceptable pour la synchronisation. Exclu du MVP.
- **Contrôle natif appareils tiers** : Impossible de piloter une enceinte Sonos, HomePod ou TV Samsung sans leur SDK. Le MVP se limite aux appareils exécutant MusyncMIMO.
- **iOS background** : L'app peut être suspendue par iOS. Limitation pour l'appareil "esclave".

### Limites souples (atténuables)
- **Latence Wi-Fi** : Variable selon le réseau. Atténuable par buffer adaptatif.
- **Drift horloge** : Corrigible par recalibrage périodique.
- **Fragmentation Android** : Gérable par foreground service + documentation.

## 6. Risques majeurs

| Risque | Impact | Probabilité | Mitigation |
|--------|--------|-------------|------------|
| Synchronisation inaudible impossible | Critique | Moyenne | Buffer adaptatif, recalibrage fréquent, seuil de tolérance utilisateur |
| iOS tue l'app en background | Élevé | Haute | Foreground service, audio session, guide utilisateur |
| Aucun service streaming supporté au lancement | Élevé | Certaine | Positionner comme "lecteur local multi-room", pas comme concurrent Spotify |
| Réseau Wi-Fi domestique trop instable | Élevé | Moyenne | Détection qualité réseau, avertissement utilisateur, fallback |
| Faible adoption (besoin d'installer sur chaque appareil) | Élevé | Haute | UX ultra-simple, onboarding en < 30s, intégration Cast/AirPlay post-MVP |
