import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/core.dart';

/// Settings screen for app configuration.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatefulWidget {
  const _SettingsView();

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  ThemeMode _themeMode = ThemeMode.system;
  double _defaultVolume = 1.0;
  String _deviceName = 'MusyncMIMO Device';

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // ── Apparence ──
        _SectionHeader(title: 'Apparence'),
        ListTile(
          leading: const Icon(Icons.palette),
          title: const Text('Thème'),
          subtitle: Text(_themeModeLabel(_themeMode)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showThemeDialog(),
        ),

        const Divider(height: 1),

        // ── Appareil ──
        _SectionHeader(title: 'Appareil'),
        ListTile(
          leading: const Icon(Icons.phone_android),
          title: const Text('Nom de l\'appareil'),
          subtitle: Text(_deviceName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDeviceNameDialog(),
        ),
        ListTile(
          leading: const Icon(Icons.volume_up),
          title: const Text('Volume par défaut'),
          subtitle: Text('${(_defaultVolume * 100).round()}%'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: _defaultVolume,
            min: 0,
            max: 1,
            divisions: 10,
            label: '${(_defaultVolume * 100).round()}%',
            onChanged: (value) {
              setState(() => _defaultVolume = value);
            },
          ),
        ),

        const Divider(height: 1),

        // ── Stockage ──
        _SectionHeader(title: 'Stockage'),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Vider le cache'),
          subtitle: const Text('Supprime les fichiers audio transférés'),
          onTap: () => _confirmClearCache(),
        ),

        const Divider(height: 1),

        // ── Réseau ──
        _SectionHeader(title: 'Réseau'),
        ListTile(
          leading: const Icon(Icons.wifi),
          title: const Text('Port du serveur'),
          subtitle: const Text('7890'),
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
          subtitle: const Text('0.1.3'),
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
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Système';
      case ThemeMode.light:
        return 'Clair';
      case ThemeMode.dark:
        return 'Sombre';
    }
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Thème'),
        children: [
          _themeOption(context, ThemeMode.system, 'Système', Icons.settings),
          _themeOption(context, ThemeMode.light, 'Clair', Icons.light_mode),
          _themeOption(context, ThemeMode.dark, 'Sombre', Icons.dark_mode),
        ],
      ),
    );
  }

  Widget _themeOption(
      BuildContext context, ThemeMode mode, String label, IconData icon) {
    final isSelected = _themeMode == mode;
    return SimpleDialogOption(
      onPressed: () {
        setState(() => _themeMode = mode);
        Navigator.pop(context);
      },
      child: Row(
        children: [
          Icon(icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : null),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          if (isSelected)
            Icon(Icons.check,
                color: Theme.of(context).colorScheme.primary, size: 20),
        ],
      ),
    );
  }

  void _showDeviceNameDialog() {
    final controller = TextEditingController(text: _deviceName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() => _deviceName = name);
              }
              Navigator.pop(context);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _confirmClearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vider le cache'),
        content: const Text(
            'Cela supprimera tous les fichiers audio transférés. Continuer ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final fileTransfer = context.read<SessionManager>().fileTransfer;
              fileTransfer.cleanup();
              Navigator.pop(context);
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
