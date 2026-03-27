# MusyncMIMO — Guide Android Studio

## Prérequis

### 1. Installer Flutter SDK

1. Télécharger Flutter SDK : https://docs.flutter.dev/get-started/install/windows/mobile
2. Extraire dans `C:\src\flutter` (ou `C:\Users\<you>\flutter`)
3. Ajouter `C:\src\flutter\bin` au PATH système
4. Ouvrir un **nouveau** terminal et vérifier :
```bash
flutter --version
```

### 2. Configurer Android Studio

Android Studio est déjà installé (`C:\Program Files\Android\Android Studio`).

1. Ouvrir Android Studio
2. **File → Settings → Plugins** → Installer le plugin **Flutter** (installe aussi Dart)
3. Redémarrer Android Studio
4. **File → Settings → Languages & Frameworks → Flutter**
   - Vérifier que le **Flutter SDK path** pointe vers `C:\src\flutter`
5. **File → Settings → Languages & Frameworks → Android SDK**
   - Si aucun SDK n'est installé, cliquer **Edit** à côté du SDK path
   - Sélectionner **Android 14 (API 34)** et installer

### 3. Créer l'émulateur Android

1. **Tools → Device Manager → Create Device**
2. Choisir **Pixel 7** ou **Pixel 8**
3. Sélectionner **API 34** (Android 14)
4. Finish → Lancer l'émulateur

### 4. Ouvrir le projet MusyncMIMO

1. **File → Open**
2. Naviguer vers : `C:\Users\frade\AppData\Roaming\com.differentai.openwork\workspaces\starter\MusyncMIMO\musync_app`
3. Cliquer **OK**
4. Attendre l'indexation Dart/Flutter
5. En bas, vérifier que l'émulateur est sélectionné dans le sélecteur de device

### 5. Lancer le projet

- Cliquer le bouton **▶ Run** (vert) en haut
- Ou **Run → Run 'main.dart'**
- Ou raccourci : **Shift+F10**

### 6. Lancer les tests

- **Run → Edit Configurations → + → Flutter Test**
- Name: `All Tests`
- Test scope: `All in directory` → `test/`
- Cliquer **▶ Run**

---

## Structure du projet dans Android Studio

```
musync_app/
├── lib/                          ← Code Dart (votre app)
│   ├── main.dart                 ← Entry point
│   ├── core/                     ← Moteur (sync, audio, réseau)
│   └── features/                 ← UI (discovery, player)
├── test/                         ← Tests unitaires
├── android/                      ← Config Android native
│   └── app/src/main/
│       ├── AndroidManifest.xml   ← Permissions
│       └── google-services.json  ← Firebase (à ajouter)
├── ios/                          ← Config iOS native
├── pubspec.yaml                  ← Dépendances
└── bin/                          ← Outils CLI
```

## Raccourcis utiles

| Action | Raccourci |
|--------|-----------|
| Run | Shift+F10 |
| Debug | Shift+F9 |
| Hot Reload | Ctrl+\ (ou clic sur 🔥) |
| Hot Restart | Ctrl+Shift+\ |
| Ouvrir terminal | Alt+F12 |
| Chercher partout | Shift+Shift |
| Format code | Ctrl+Alt+L |
