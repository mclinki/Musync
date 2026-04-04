import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/core.dart';
import '../../onboarding/ui/onboarding_screen.dart';
import '../bloc/settings_bloc.dart';

/// Settings screen for app configuration.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SettingsView();
  }
}

class _SettingsView extends StatefulWidget {
  const _SettingsView();

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  // CRASH-2 fix: Track whether we've already scheduled a SnackBar callback
  // to prevent Duplicate GlobalKeys from multiple addPostFrameCallback calls
  bool _snackBarScheduled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.errorMessage != null && !_snackBarScheduled) {
            _snackBarScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _snackBarScheduled = false;
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.errorMessage!)),
                );
              }
            });
          }

          return ListView(
            children: [
              // ── Apparence ──
              _SectionHeader(title: 'Apparence'),
              ListTile(
                leading: const Icon(Icons.palette),
                title: const Text('Thème'),
                subtitle: Text(_themeModeLabel(state.themeMode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showThemeDialog(context, state.themeMode),
              ),

              const Divider(height: 1),

              // ── Appareil ──
              _SectionHeader(title: 'Appareil'),
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('Nom de l\'appareil'),
                subtitle: Text(state.deviceName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDeviceNameDialog(context, state.deviceName),
              ),
              ListTile(
                leading: const Icon(Icons.volume_up),
                title: const Text('Volume par défaut'),
                subtitle: Text('${(state.defaultVolume * 100).round()}%'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Slider(
                  value: state.defaultVolume,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  label: '${(state.defaultVolume * 100).round()}%',
                  onChanged: (value) {
                    context
                        .read<SettingsBloc>()
                        .add(DefaultVolumeChanged(value));
                  },
                ),
              ),

              const Divider(height: 1),

              // ── Stockage ──
              _SectionHeader(title: 'Stockage'),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Vider le cache'),
                subtitle: const Text(
                    'Supprime les fichiers audio transférés'),
                onTap: () => _confirmClearCache(context),
              ),

              const Divider(height: 1),

              // ── Notifications ──
              _SectionHeader(title: 'Notifications'),
              SwitchListTile(
                secondary: const Icon(Icons.person_add),
                title: const Text('Notification d\'arrivée'),
                subtitle: const Text('Vibrer et afficher une alerte quand un invité rejoint'),
                value: state.joinNotificationEnabled,
                onChanged: (value) {
                  context.read<SettingsBloc>().add(JoinNotificationToggled(value));
                },
              ),

              const Divider(height: 1),

              // ── Réseau ──
              _SectionHeader(title: 'Réseau'),
              ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Port du serveur'),
                subtitle: Text('${AppConstants.defaultWebSocketPort}'),
              ),
              ListTile(
                leading: const Icon(Icons.security),
                title: const Text('Chiffrement WebSocket'),
                subtitle: Text(state.useTls ? 'Activé (wss://)' : 'Désactivé (ws://)'),
                trailing: Switch(
                  value: state.useTls,
                  onChanged: (value) {
                    context.read<SettingsBloc>().add(TlsToggled(value));
                  },
                ),
              ),

              const Divider(height: 1),

              // ── Partager l'application ──
              _SectionHeader(title: 'Partager l\'application'),
              _buildApkShareSection(context, state),

              const Divider(height: 1),

              // ── Mise à jour ──
              _SectionHeader(title: 'Mise à jour'),
              _buildUpdateSection(context, state),

              const Divider(height: 1),

              // ── Avancé ──
              _SectionHeader(title: 'Avancé'),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('Délai de lecture'),
                subtitle: Text('${state.playDelayMs}ms'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showPlayDelayDialog(context, state.playDelayMs),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.restore),
                title: const Text('Rejoindre automatiquement'),
                subtitle: const Text('Rejoindre la dernière session au démarrage'),
                value: state.autoRejoinLastSession,
                onChanged: (value) {
                  context.read<SettingsBloc>().add(AutoRejoinToggled(value));
                },
              ),

              const Divider(height: 1),

              // ── À propos ──
              _SectionHeader(title: 'À propos'),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Tutoriel'),
                subtitle: const Text('Revoir les instructions de démarrage'),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => OnboardingScreen(onComplete: () => Navigator.of(context).pop()),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Version'),
                subtitle: Text(AppConstants.appVersion),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('Source'),
                subtitle: const Text('github.com/mclinki/Musync'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () {
                  const url = 'https://github.com/mclinki/Musync';
                  Clipboard.setData(const ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Lien copié dans le presse-papiers'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Signaler un problème'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  const url = 'https://github.com/mclinki/Musync/issues';
                  Clipboard.setData(const ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Lien copié dans le presse-papiers'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  /// Build the APK share section: toggle + URL display.
  Widget _buildApkShareSection(BuildContext context, SettingsState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle to start/stop the share server
        SwitchListTile(
          secondary: const Icon(Icons.share),
          title: const Text('Partager l\'APK'),
          subtitle: Text(
            state.isApkShareRunning
                ? 'Serveur actif — partagez le lien ci-dessous'
                : 'Démarrer un serveur pour que d\'autres appareils puissent télécharger l\'app',
          ),
          value: state.isApkShareRunning,
          onChanged: (value) {
            if (value) {
              context.read<SettingsBloc>().add(const ApkShareStartRequested());
            } else {
              context.read<SettingsBloc>().add(const ApkShareStopRequested());
            }
          },
        ),

        // Show the share URL when server is running
        if (state.isApkShareRunning && state.apkShareUrl != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link,
                            size: 18,
                            color: Theme.of(context).colorScheme.onPrimaryContainer),
                        const SizedBox(width: 8),
                        Text(
                          'Lien de téléchargement',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      state.apkShareUrl!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: state.apkShareUrl!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Lien copié !')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copier le lien'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () {
                            Share.share(
                              state.apkShareUrl!,
                              subject: 'Télécharger MusyncMIMO v${AppConstants.appVersion}',
                            );
                          },
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Partager'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ouvrez ce lien dans le navigateur de l\'appareil cible pour télécharger et installer MusyncMIMO.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Build the update section: check button + download + install.
  Widget _buildUpdateSection(BuildContext context, SettingsState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Check for updates button
        ListTile(
          leading: state.isCheckingUpdate
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update),
          title: const Text('Vérifier les mises à jour'),
          subtitle: state.updateInfo != null
              ? Text('Version ${state.updateInfo!.latestVersion} disponible')
              : null,
          trailing: state.isCheckingUpdate ? null : const Icon(Icons.chevron_right),
          onTap: state.isCheckingUpdate
              ? null
              : () {
                  context.read<SettingsBloc>().add(const UpdateCheckRequested());
                },
        ),

        // Show update info card when an update is available
        if (state.updateInfo != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.new_releases,
                            size: 18,
                            color: Theme.of(context).colorScheme.onSecondaryContainer),
                        const SizedBox(width: 8),
                        Text(
                          'v${state.updateInfo!.latestVersion} — ${state.updateInfo!.fileSizeFormatted}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                        ),
                      ],
                    ),
                    if (state.updateInfo!.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.updateInfo!.releaseNotes.length > 200
                            ? '${state.updateInfo!.releaseNotes.substring(0, 200)}...'
                            : state.updateInfo!.releaseNotes,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer
                                  .withValues(alpha: 0.8),
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (state.isDownloadingUpdate)
                      Column(
                        children: [
                          LinearProgressIndicator(value: state.downloadProgress > 0 ? state.downloadProgress : null),
                          const SizedBox(height: 4),
                          Text(
                            'Téléchargement... ${(state.downloadProgress * 100).round()}%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      )
                    else if (state.downloadedApkPath != null)
                      FilledButton.icon(
                        onPressed: () {
                          // Open the downloaded APK for installation
                          _installApk(context, state.downloadedApkPath!);
                        },
                        icon: const Icon(Icons.install_mobile),
                        label: const Text('Installer la mise à jour'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: () {
                          context.read<SettingsBloc>().add(const UpdateDownloadRequested());
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Télécharger'),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Open a downloaded APK for installation via platform channel.
  void _installApk(BuildContext context, String apkPath) {
    // On Android, use the install_plugin or platform channel.
    // For now, copy the path to clipboard as a fallback.
    Clipboard.setData(ClipboardData(text: apkPath));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chemin de l\'APK copié. Ouvrez-le depuis votre gestionnaire de fichiers.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  static String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Système';
      case ThemeMode.light:
        return 'Clair';
      case ThemeMode.dark:
        return 'Sombre';
    }
  }

  void _showThemeDialog(BuildContext context, ThemeMode currentMode) {
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Thème'),
        children: [
          _themeOption(context, dialogContext, currentMode, ThemeMode.system,
              'Système', Icons.settings),
          _themeOption(context, dialogContext, currentMode, ThemeMode.light,
              'Clair', Icons.light_mode),
          _themeOption(context, dialogContext, currentMode, ThemeMode.dark,
              'Sombre', Icons.dark_mode),
        ],
      ),
    );
  }

  Widget _themeOption(
    BuildContext blocContext,
    BuildContext dialogContext,
    ThemeMode currentMode,
    ThemeMode mode,
    String label,
    IconData icon,
  ) {
    final isSelected = currentMode == mode;
    return SimpleDialogOption(
      onPressed: () {
        blocContext.read<SettingsBloc>().add(ThemeChanged(mode));
        Navigator.pop(dialogContext);
      },
      child: Row(
        children: [
          Icon(icon,
              color: isSelected
                  ? Theme.of(blocContext).colorScheme.primary
                  : null),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          if (isSelected)
            Icon(Icons.check,
                color: Theme.of(blocContext).colorScheme.primary, size: 20),
        ],
      ),
    );
  }

  void _showDeviceNameDialog(BuildContext context, String currentName) {
    // CRASH-4A fix: Controller created OUTSIDE builder to avoid recreation on rebuild
    final controller = TextEditingController(text: currentName);
    var disposed = false;
    void safeDispose() {
      if (!disposed) {
        disposed = true;
        controller.dispose();
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nom de l\'appareil'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Mon téléphone',
              border: OutlineInputBorder(),
            ),
            maxLength: 30,
          ),
          actions: [
            TextButton(
              onPressed: () {
                safeDispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  context
                      .read<SettingsBloc>()
                      .add(DeviceNameChanged(name));
                }
                safeDispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ).then((_) => safeDispose()); // CRASH-4A fix: Always dispose, even on barrier tap
  }

  void _confirmClearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vider le cache'),
        content: const Text(
            'Cela supprimera tous les fichiers audio transférés. Continuer ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              context.read<SettingsBloc>().add(const CacheCleared());
              Navigator.pop(dialogContext);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache vidé')),
                  );
                }
              });
            },
            child: const Text('Vider'),
          ),
        ],
      ),
    );
  }

  void _showPlayDelayDialog(BuildContext context, int currentDelay) {
    var delay = currentDelay.toDouble();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Délai de lecture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${delay.round()}ms',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Slider(
                value: delay,
                min: 1000,
                max: 10000,
                divisions: 18,
                label: '${delay.round()}ms',
                onChanged: (v) => setDialogState(() => delay = v),
              ),
              Text(
                'Plus le délai est long, plus les esclaves ont de temps pour charger le morceau.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                context.read<SettingsBloc>().add(PlayDelayChanged(delay.round()));
                Navigator.pop(dialogContext);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
