import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.wifi,
      title: 'Connectez vos appareils',
      description: 'Assurez-vous que tous vos appareils sont sur le même réseau Wi-Fi. Musync les détectera automatiquement.',
    ),
    _OnboardingPage(
      icon: Icons.group_add,
      title: 'Créez ou rejoignez un groupe',
      description: 'L\'hôte crée un groupe et les autres appareils le rejoignent en un tap. Jusqu\'à 8 appareils synchronisés.',
    ),
    _OnboardingPage(
      icon: Icons.music_note,
      title: 'Jouez en parfaite synchronisation',
      description: 'Chargez vos fichiers audio et lancez la lecture. Tous les appareils jouent en même temps, sans décalage perceptible.',
    ),
    _OnboardingPage(
      icon: Icons.sync,
      title: 'Synchronisation automatique',
      description: 'Musync synchronise les horloges de tous les appareils automatiquement. La qualité de sync est affichée en temps réel.',
    ),
  ];

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (mounted) {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: Text('Passer', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 120, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 32),
                        Text(page.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Text(page.description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            ),
            const SizedBox(height: 32),

            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _currentPage == _pages.length - 1 ? _completeOnboarding : () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                  icon: Icon(_currentPage == _pages.length - 1 ? Icons.check : Icons.arrow_forward),
                  label: Text(_currentPage == _pages.length - 1 ? 'Commencer' : 'Suivant'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  const _OnboardingPage({required this.icon, required this.title, required this.description});
}
