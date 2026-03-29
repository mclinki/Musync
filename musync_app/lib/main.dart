import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'core/core.dart';
import 'core/services/permission_service.dart';
import 'features/discovery/ui/discovery_screen.dart';
import 'features/player/ui/player_screen.dart';
import 'features/settings/bloc/settings_bloc.dart';
import 'features/settings/ui/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Request runtime permissions (Android 13+)
  final permissions = PermissionService();
  await permissions.requestAllPermissions();

  // 2. Initialize Firebase (optional - app works without it)
  final firebase = FirebaseService();
  try {
    await firebase.initialize();
  } catch (_) {
    // Firebase not configured - app continues without it
  }

  // 3. Create session manager
  final sessionManager = SessionManager();

  // Wire Firebase analytics to SessionManager (optional)
  if (firebase.isInitialized) {
    sessionManager.setFirebaseService(firebase);
  }

  // 4. Generate device ID
  final deviceId = const Uuid().v4();

  // 5. Initialize session manager
  await sessionManager.initialize(
    deviceId: deviceId,
    deviceName: 'MusyncMIMO Device',
    deviceType: 'phone',
  );

  // 5. Log device info to Crashlytics (if available)
  if (firebase.isInitialized) {
    await firebase.setCustomKey('device_id', deviceId);
    await firebase.setCustomKey('platform', 'flutter');
  }

  // 6. Get SharedPreferences
  final prefs = await SharedPreferences.getInstance();

  // 7. Run app
  runApp(MusyncApp(
    sessionManager: sessionManager,
    firebaseService: firebase,
    prefs: prefs,
  ));
}

class MusyncApp extends StatelessWidget {
  final SessionManager sessionManager;
  final FirebaseService firebaseService;
  final SharedPreferences prefs;

  const MusyncApp({
    super.key,
    required this.sessionManager,
    required this.firebaseService,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SessionManager>.value(value: sessionManager),
        RepositoryProvider<FirebaseService>.value(value: firebaseService),
      ],
      child: BlocProvider(
        create: (_) => SettingsBloc(
          prefs: prefs,
          sessionManager: sessionManager,
        )..add(const LoadSettings()),
        child: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            return MaterialApp(
              title: 'MusyncMIMO',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF6750A4),
                  brightness: Brightness.light,
                ),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF6750A4),
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
              ),
              themeMode: settingsState.themeMode,
              initialRoute: '/',
              routes: {
                '/': (context) => const HomeScreen(),
                '/discovery': (context) => const DiscoveryScreen(),
                '/player': (context) => const PlayerScreen(),
                '/settings': (context) => const SettingsScreen(),
              },
              // Firebase Analytics observer
              navigatorObservers: <NavigatorObserver>[
                if (firebaseService.isInitialized && firebaseService.analytics != null)
                  FirebaseAnalyticsObserver(
                    analytics: firebaseService.analytics!,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Home / landing screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Logo / title
              Icon(
                Icons.surround_sound,
                size: 100,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'MusyncMIMO',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Synchronisez votre musique\nsur tous vos appareils',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),

              const Spacer(),

              // Main action buttons
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    // Log analytics event
                    context.read<FirebaseService>().logEvent(
                          'tap_create_group',
                        );
                    Navigator.of(context).pushNamed('/discovery');
                  },
                  icon: const Icon(Icons.cast_connected),
                  label: const Text('Créer ou rejoindre un groupe'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.read<FirebaseService>().logEvent(
                          'tap_solo_player',
                        );
                    Navigator.of(context).pushNamed('/player');
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Lecteur solo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // Info text
              Text(
                'Connectez-vous au même Wi-Fi\npour synchroniser vos appareils',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
