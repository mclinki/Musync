import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/core.dart';
import '../bloc/settings_bloc.dart';

/// Settings screen for app configuration.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SettingsView();
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

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

          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!)),
            );
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
                subtitle: const Text('Désactivé (ws://)'),
                trailing: Switch(
                  value: false,
                  onChanged: null, // Disabled for now
                ),
              ),

              const Divider(height: 1),

              // ── À propos ──
              _SectionHeader(title: 'À propos'),
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
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Signaler un problème'),
                trailing: const Icon(Icons.chevron_right),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
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
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
              Navigator.pop(dialogContext);
              controller.dispose();
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
              Navigator.pop(dialogContext);
              controller.dispose();
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache vidé')),
              );
            },
            child: const Text('Vider'),
          ),
        ],
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
