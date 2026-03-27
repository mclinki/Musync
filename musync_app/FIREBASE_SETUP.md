# MusyncMIMO — Configuration Firebase

## Étape 1 : Créer le projet Firebase

1. Aller sur https://console.firebase.google.com/
2. Cliquer **Créer un projet**
3. Nom : `musync-mimo`
4. Activer Google Analytics (recommandé)
5. Choisir un compte Analytics ou créer un nouveau
6. Cliquer **Créer le projet**

## Étape 2 : Ajouter l'app Android

1. Dans la console Firebase, cliquer l'icône **Android**
2. **Nom du package Android** : `com.musync.mimo`
   - (Vérifier dans `android/app/build.gradle` → `applicationId`)
3. **Nom de l'app** : `MusyncMIMO`
4. **SHA-1** : (optionnel au MVP, nécessaire pour Auth plus tard)
   - Obtenir via : `cd android && ./gradlew signingReport`
5. Cliquer **Enregistrer l'application**

## Étape 3 : Télécharger google-services.json

1. Télécharger le fichier `google-services.json`
2. Le placer dans : `musync_app/android/app/google-services.json`
   - **PAS** dans `musync_app/android/` (ce serait trop haut)
   - **PAS** dans `musync_app/android/app/src/` (ce serait trop bas)
   - Le bon chemin est : `musync_app/android/app/google-services.json`

## Étape 4 : Configurer build.gradle

### android/build.gradle (racine)
Ajouter dans `dependencies` :
```gradle
buildscript {
    dependencies {
        // ... autres dépendances
        classpath 'com.google.gms:google-services:4.4.2'
    }
}
```

### android/app/build.gradle
Ajouter en haut du fichier :
```gradle
apply plugin: 'com.google.gms.google-services'
```

Et dans `android > defaultTargetPlatform` :
```gradle
minSdkVersion 23  // Firebase requiert au moins 21
```

## Étape 5 : Ajouter l'app iOS (optionnel)

1. Dans Firebase, cliquer l'icône **iOS**
2. **Bundle ID** : `com.musync.mimo`
   - (Vérifier dans `ios/Runner.xcodeproj` → Bundle Identifier)
3. Télécharger `GoogleService-Info.plist`
4. L'ajouter dans Xcode dans le dossier `Runner/`

## Étape 6 : Activer les services Firebase

Dans la console Firebase :

### Crashlytics
1. **Build → Crashlytics → Get started**
2. Pas de configuration supplémentaire nécessaire

### Analytics
1. Déjà activé si vous avez coché Google Analytics à la création
2. Les événements personnalisés sont envoyés via `FirebaseService.logEvent()`

### Auth (optionnel au MVP)
1. **Build → Authentication → Get started**
3. Activer **Anonymous** (connexion anonyme)
4. C'est tout — l'app utilise l'auth anonyme

### Firestore (optionnel au MVP)
1. **Build → Firestore Database → Create database**
2. Choisir **Start in test mode** (pour le développement)
3. Région : choisir la plus proche (europe-west1)
4. Les règles de sécurité seront configurées plus tard

## Étape 7 : Lancer l'app

```bash
cd musync_app
flutter pub get
flutter run
```

Si Firebase est bien configuré, vous verrez dans la console :
```
I/flutter: Firebase Core initialized
I/flutter: Crashlytics initialized
I/flutter: Analytics initialized
I/flutter: Auth initialized (user: abc123...)
I/flutter: Firestore initialized
I/flutter: Firebase fully initialized
```

## Vérification

Pour vérifier que Crashlytics fonctionne :
1. Dans la console Firebase → **Crashlytics**
2. Forcer un crash temporairement dans `main()` :
```dart
// À retirer après le test
FirebaseCrashlytics.instance.crash();
```
3. Relancer l'app
4. Attendre quelques minutes
5. Le crash apparaît dans la console Firebase

## Dépannage

| Problème | Solution |
|----------|----------|
| `google-services.json not found` | Vérifier le chemin : `android/app/google-services.json` |
| `No Firebase App '[DEFAULT]'` | Vérifier que `Firebase.initializeApp()` est appelé avant `runApp()` |
| `DEVELOPER_ERROR` | Vérifier que le package name correspond dans Firebase et `build.gradle` |
| Crashlytics ne reçoit rien | Forcer un crash, relancer, attendre 5 min |
| Analytics ne reçoit rien | Vérifier la connexion internet, attendre 24h (délai Google) |
