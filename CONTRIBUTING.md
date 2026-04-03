# MusyncMIMO — Standards de Contribution

> Ce document définit les conventions pour toute contribution au projet.
> **Applicable aux agents IA comme aux développeurs humains.**

---

## 1. Conventions Git

### Messages de commit

Format : `catégorie: description courte`

```
fix: corriger crash RenderFlex overflow sur player_screen
feat: ajouter système de queue avec skip next/prev
refactor: extraire formatDuration dans utilitaire commun
test: ajouter tests BLoC pour DiscoveryBloc
docs: mettre à jour CHANGELOG pour v0.1.16
chore: bump version 0.1.15 → 0.1.16
optim: implémenter filtre de Kalman pour clock sync
```

**Catégories** : `fix` `feat` `refactor` `test` `docs` `chore` `optim`

### Branches

- `main` — code stable, toujours compilable
- `feature/nom-feature` — nouvelles fonctionnalités
- `fix/nom-bug` — corrections de bugs
- `refactor/nom` — refactoring

---

## 2. Conventions de Code Dart/Flutter

### Structure des fichiers

```
lib/
├── core/
│   ├── models/        ← Modèles de données purs (Equatable)
│   ├── network/       ← Logique réseau (WebSocket, mDNS, clock sync)
│   ├── audio/         ← Logique audio (just_audio)
│   ├── session/       ← Orchestration de session
│   └── services/      ← Services externes (Firebase, permissions)
├── features/
│   ├── feature_name/
│   │   ├── bloc/      ← BLoC + Events + States
│   │   └── ui/        ← Widgets d'écran
│   └── ...
└── main.dart
```

### Nommage

| Élément | Convention | Exemple |
|---------|-----------|---------|
| Fichiers | `snake_case.dart` | `session_manager.dart` |
| Classes | `PascalCase` | `SessionManager` |
| Variables | `camelCase` | `syncedTimeMs` |
| Constantes | `camelCase` ou `kPrefix` | `kDefaultPort` |
| Enums | `PascalCase` values `camelCase` | `SessionState.playing` |
| Privés | `_prefix` | `_offsetMs` |

### Typage

```dart
// ✅ Bon : typage explicite
final List<DeviceInfo> devices = [];
final Map<String, double> offsets = {};
String get sessionId => _sessionId;

// ❌ Mauvais : dynamic
final devices = [];
dynamic get sessionId => _sessionId;
```

### Null safety

```dart
// ✅ Bon : vérification null avant accès
if (_server != null) {
  await _server!.broadcast(message);
}

// ❌ Mauvais : accès direct sans vérification
await _server!.broadcast(message); // peut throw si null
```

### Logging

```dart
// ✅ Bon : utiliser le logger
_logger.i('Session started: $sessionId');
_logger.w('Clock sync failed, continuing anyway');
_logger.e('Failed to start server: $e');

// ❌ Mauvais : print
print('Session started: $sessionId');
```

### Gestion d'erreurs

```dart
// ✅ Bon : try-catch avec logging
try {
  await riskyOperation();
} catch (e, stack) {
  _logger.e('Operation failed: $e');
  _firebase?.recordError(e, stack, reason: 'riskyOperation');
}

// ❌ Mauvais : catch silencieux
try {
  await riskyOperation();
} catch (_) {}
```

---

## 3. Conventions BLoC

### Structure d'un BLoC

```dart
// events.dart
abstract class MyEvent {}
class MyActionRequested extends MyEvent { ... }

// state.dart
abstract class MyState {}
class MyInitial extends MyState {}
class MyLoaded extends MyState { ... }

// bloc.dart
class MyBloc extends Bloc<MyEvent, MyState> {
  MyBloc() : super(MyInitial()) {
    on<MyActionRequested>(_onAction);
  }

  Future<void> _onAction(MyActionRequested event, Emitter<MyState> emit) async {
    emit(MyLoading());
    try {
      final result = await _doSomething();
      emit(MyLoaded(result));
    } catch (e) {
      emit(MyError(e.toString()));
    }
  }
}
```

### Règles BLoC

1. **Pas de `setState()`** dans les features — utiliser `emit()`
2. **Pas de logique UI** dans les BLoCs — les BLoCs gèrent l'état, pas le rendu
3. **Toujours émettre un état** avant et après une opération async
4. **Gérer les erreurs** — jamais de crash silencieux

---

## 4. Conventions de Tests

### Structure des tests

```
test/
├── models/
│   ├── audio_session_test.dart
│   └── protocol_message_test.dart
├── bloc/
│   ├── player_bloc_test.dart
│   └── discovery_bloc_test.dart
├── network/
│   └── clock_sync_test.dart
└── widget_test.dart
```

### Format d'un test

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioTrack', () {
    test('should create from file path', () {
      final track = AudioTrack.fromFilePath('/path/to/song.mp3');
      expect(track.title, equals('song'));
      expect(track.sourceType, equals(AudioSourceType.localFile));
    });

    test('should serialize to JSON', () {
      final track = AudioTrack.fromUrl('https://example.com/stream.mp3');
      final json = track.toJson();
      expect(json['source'], equals('https://example.com/stream.mp3'));
    });
  });
}
```

### Objectifs de couverture

- **Modèles** : 100% (tests unitaires simples)
- **BLoCs** : 80%+ (tests avec `bloc_test`)
- **Services** : 60%+ (tests avec mocks)
- **UI** : Smoke tests (pas de couverture exigée)

---

## 5. Conventions de Documentation

### CHANGELOG.md

Chaque session de travail produit une entrée :

```markdown
## Session du YYYY-MM-DD (vX.Y.Z) — Titre

### Contexte
1-2 phrases expliquant pourquoi ces changements.

### Modifications

| # | Catégorie | Description | Fichiers |
|---|-----------|-------------|----------|
| 1 | `FIX` | Description | `file.dart` |
```

### TASKS_BACKLOG.md

- Cocher `[x]` quand une tâche est terminée
- Ajouter de nouvelles tâches avec priorité (P0/P1/P2/P3)
- Lister les fichiers suspects pour chaque bug
- Documenter la cause probable quand elle est identifiée

### README.md

Mettre à jour si :
- La roadmap change
- De nouvelles fonctionnalités sont ajoutées
- La version change
- Les instructions d'installation changent

---

## 6. Checklist avant commit

- [ ] `flutter test` → 95/95 (ou plus)
- [ ] `flutter analyze` → pas d'erreurs
- [ ] `CHANGELOG.md` mis à jour
- [ ] `TASKS_BACKLOG.md` mis à jour (tâches cochées)
- [ ] `app_constants.dart` version à jour si nécessaire
- [ ] Pas de `print()` (utiliser `Logger`)
- [ ] Pas de `dynamic` sans justification
- [ ] Pas de code mort (imports inutiles, variables non utilisées)
- [ ] Tests ajoutés pour les nouvelles fonctionnalités

---

## 7. Gestion des versions

Format : `MAJOR.MINOR.PATCH+BUILD`

- **MAJOR** : Changement d'API incompatible
- **MINOR** : Nouvelle fonctionnalité rétrocompatible
- **PATCH** : Bug fix rétrocompatible
- **BUILD** : Numéro de build incrémental

Exemple : `0.1.17+17`

Fichiers à mettre à jour :
- `pubspec.yaml` → `version: 0.1.17+17`
- `app_constants.dart` → `static const String appVersion = '0.1.17';`

---

*Dernière mise à jour : 2026-04-01*
