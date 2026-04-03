# Changelog

All notable changes to MusyncMIMO will be documented in this file.

## [0.1.36] - 2026-04-03 — Build Fix + Pure Dart ID3

### Changed
- **REPLACED** `flutter_media_metadata` (abandoned, native code, build broken) → `audio_metadata_reader` (pure Dart, cross-platform, actively maintained)
- No more local cache patches needed — builds cleanly on any machine
- APK release: 58.6MB (down from 163MB debug)

## [0.1.35] - 2026-04-03 — Audit & Security Release

### Added
- **AUDIT** — Full codebase audit completed (38 files, ~8,500 lines). Score: 62/100
- **SECURITY** — WebSocket message size validation (1MB max) to prevent OOM attacks
- **SECURITY** — File name sanitization in file transfer service (path traversal prevention)
- **SECURITY** — `.gitignore` updated to exclude `firebase_options.dart`
- **SECURITY** — `maxFileSizeBytes` (100MB) and `maxMessageSizeBytes` (1MB) constants added
- **DRY** — `extractFileName()` utility function replaces 8 duplicated occurrences across 6 files
- **README** — Security section added with Firebase setup instructions
- **AUDIT_REPORT.md** — Full audit report with findings and action plan

### Fixed
- **DRY** — `path.split('/').last.split('\\').last` extracted to `extractFileName()` in `core/utils/format.dart`
- **SECURITY** — File transfer now sanitizes filenames (replaces `./\` and non-alphanumeric chars)
- **SECURITY** — ProtocolMessage.decode rejects messages > 1MB

## [0.1.34] - 2026-04-03

### Added
- **P2 3.9** — Settings avancés : délai de lecture personnalisable (1-10s, slider) + toggle auto-rejoin dernière session. Persistance SharedPreferences.
- **P2 4.6** — Renommer la session : bouton edit dans le host dashboard, dialog avec TextField pré-rempli, `sessionManager.renameSession()`.
- **P2 6.2** — Buffering adaptatif : compensation automatique du jitter réseau dans `broadcastPlay`. Si jitter > 5ms, ajoute 2× le jitter au délai de lecture.

### Fixed
- **P2 3.9** — Handlers `PlayDelayChanged` et `AutoRejoinToggled` ajoutés au SettingsBloc (events/state existaient mais pas les handlers).

## [0.1.32] - 2026-04-03

### Fixed
- **CRASH-10** : `InheritedElement.debugDeactivated` (47 events, 7 users) — `_GuestJoinNotifier` stream subscription jamais annulé dans `dispose()`. Fix : ajout `StreamSubscription` + `cancel()` dans `dispose()` + double guard `mounted` après `context.read<SettingsBloc>()`. Autres guards ajoutés : `discovery_screen.dart` (context.mounted après Navigator.pop), `onboarding_screen.dart` (mounted après SharedPreferences), `groups_screen.dart` (BLoC capturé avant showDialog au lieu de context.read dans callback)

## [0.1.31] - 2026-04-03

### Added
- **P2 5.2** — Contrôle du volume à distance : l'hôte peut maintenant contrôler le volume des slaves via broadcast WebSocket
- **P2 9.2** — Animations de transition entre écrans (slide + fade, 300ms)
- **P2 9.2** — Animations subtiles sur le lecteur : titre (fade + slide up), contrôles (scale au tap), file d'attente (staggered slide-in)

## [0.1.30] - 2026-04-03

### Added
- **P2 3.8** — Notification d'arrivée d'invité : vibration + snack bar quand un invité rejoint la session (paramétrable dans les paramètres)
- **P2 5.9** — Indicateur visuel "Tous prêts" / "Chargement..." dans le host dashboard (déjà présent, consolidé)

### Changed
- **P2 1.7** — Tous les `.withOpacity()` remplacés par `.withValues(alpha: ...)` (déjà fait, vérifié)
- **P2 1.8** — Vérification des `use_key_in_widget_constructors` : aucun widget manquant (déjà conforme)

## [0.1.29] - 2026-04-02

### Fixed
- Corrections de bugs mineurs et améliorations de performance
