import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'core/core.dart';
import 'features/discovery/ui/discovery_screen.dart';
import 'features/player/bloc/player_bloc.dart';
import 'features/player/ui/player_screen.dart';
import 'features/settings/bloc/settings_bloc.dart';
import 'features/settings/ui/settings_screen.dart';
import 'features/groups/ui/groups_screen.dart';
import 'features/onboarding/ui/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Request runtime permissions (Android 13+) — with timeout to prevent ANR
  final permissions = PermissionService();
  try {
    await permissions.requestAllPermissions().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false, // Continue without permissions
    );
  } catch (e) {
    // Permissions not critical for startup
    debugPrint('Permission request failed: $e');
  }

  // 2. Initialize Firebase (optional - app works without it) — with timeout
  final firebase = FirebaseService();
  try {
    await firebase.initialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        // Continue without Firebase - return void
        return;
      },
    );
  } catch (e) {
    // Firebase not configured - app continues without it
    debugPrint('Firebase initialization failed: $e');
  }

  // 3. Get SharedPreferences (BEFORE session manager init — needed for device name)
  final prefs = await SharedPreferences.getInstance();

  // 4. Create session manager
  final sessionManager = SessionManager();

  // Wire Firebase analytics to SessionManager (optional)
  if (firebase.isInitialized) {
    sessionManager.setFirebaseService(firebase);
  }

  // 5. Generate device ID
  final deviceId = const Uuid().v4();

  // 6. Read custom device name from prefs (BUG-6 FIX)
  final deviceName = prefs.getString('device_name') ?? 'MusyncMIMO Device';

  // 7. Initialize session manager — with timeout to prevent ANR
  try {
    await sessionManager.initialize(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceType: 'phone',
    ).timeout(
      const Duration(seconds: 30), // Increased from 10s — audio/network init can be slow on cold start
      onTimeout: () {
        debugPrint('⚠️ SessionManager init timed out after 30s');
      },
    );
    if (!sessionManager.isInitialized) {
      debugPrint('⚠️ SessionManager initialized flag is false after timeout');
    }
  } catch (e) {
    debugPrint('⚠️ SessionManager init failed: $e');
  }

  // 5. Log device info to Crashlytics (if available)
  if (firebase.isInitialized) {
    await firebase.setCustomKey('device_id', deviceId);
    await firebase.setCustomKey('platform', 'flutter');
  }

  // 8. Run app
  runApp(MusyncApp(
    sessionManager: sessionManager,
    firebaseService: firebase,
    prefs: prefs,
  ));
}

class MusyncApp extends StatefulWidget {
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
  State<MusyncApp> createState() => _MusyncAppState();
}

class _MusyncAppState extends State<MusyncApp> {
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final completed = widget.prefs.getBool('onboarding_completed') ?? false;
    if (mounted) {
      setState(() => _showOnboarding = !completed);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (_showOnboarding!) {
      return MaterialApp(
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
        home: OnboardingScreen(onComplete: () => setState(() => _showOnboarding = false)),
      );
    }

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SessionManager>.value(value: widget.sessionManager),
        RepositoryProvider<FirebaseService>.value(value: widget.firebaseService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => SettingsBloc(
              prefs: widget.prefs,
              sessionManager: widget.sessionManager,
            )..add(const LoadSettings()),
          ),
          BlocProvider(
            create: (_) => PlayerBloc(
              sessionManager: widget.sessionManager,
              prefs: widget.prefs,
            ),
          ),
        ],
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
              onGenerateRoute: (settings) {
                Widget? target;
                switch (settings.name) {
                  case '/':
                    target = const HomeScreen();
                    break;
                  case '/discovery':
                    target = const DiscoveryScreen();
                    break;
                  case '/player':
                    target = const PlayerScreen();
                    break;
                  case '/settings':
                    target = const SettingsScreen();
                    break;
                  case '/groups':
                    target = const GroupsScreen();
                    break;
                }
                if (target != null) {
                  return _animatedRoute(child: target, settings: settings);
                }
                return null;
              },
              // Firebase Analytics observer
              navigatorObservers: <NavigatorObserver>[
                if (widget.firebaseService.isInitialized && widget.firebaseService.analytics != null)
                  FirebaseAnalyticsObserver(
                    analytics: widget.firebaseService.analytics!,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

PageRouteBuilder _animatedRoute({required Widget child, RouteSettings? settings}) {
  return PageRouteBuilder(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeInOutCubic;

      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
      var offsetAnimation = animation.drive(tween);
      var fadeAnimation = animation.drive(Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve)));

      return FadeTransition(
        opacity: fadeAnimation,
        child: SlideTransition(
          position: offsetAnimation,
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
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
                    Navigator.of(context).pushNamed('/groups');
                  },
                  icon: const Icon(Icons.group),
                  label: const Text('Groupes sauvegardés'),
                  style: OutlinedButton.styleFrom(
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
