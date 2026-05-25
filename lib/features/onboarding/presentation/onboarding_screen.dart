// =========================================================
//  onboarding_screen.dart — Première impression de l'app
// =========================================================
//  3 slides avec PageView :
//    1. Bienvenue + identité de marque
//    2. Charger une playlist IPTV
//    3. Découvrir l'expérience premium
//
//  À la fin → flag `OnboardingState.markCompleted()` + push
//  vers HomeScreen.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/onboarding_state.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onDone, super.key});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_OnboardingPage> _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.live_tv_rounded,
      title: 'Bienvenue sur TV King',
      description:
          'Le lecteur IPTV premium. Conçu pour la TV, optimisé pour ton téléphone, beau partout.',
    ),
    _OnboardingPage(
      icon: Icons.cloud_upload_outlined,
      title: 'Charge ta playlist',
      description:
          'Colle une URL M3U, ou tes identifiants Xtream. Tes chaînes apparaissent en quelques secondes.',
    ),
    _OnboardingPage(
      icon: Icons.star_rounded,
      title: 'Profite de la signature VIP',
      description:
          'Logos haute qualité, navigation Apple TV, recherche instantanée, lecteur 4K/8K.',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _finish() async {
    await OnboardingState.instance.markCompleted();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          // Halo doré derrière
          Positioned(
            top: -120,
            right: -100,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.accent.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: <Widget>[
                // ----- Bouton "Passer" en haut -----
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: _finish,
                        child: Text(
                          'Passer',
                          style: AppTextStyles.bodyLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ----- Slides -----
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (int i) => setState(() => _page = i),
                    itemCount: _pages.length,
                    itemBuilder: (BuildContext context, int index) {
                      return _SlideView(page: _pages[index]);
                    },
                  ),
                ),

                // ----- Indicateurs de page -----
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(_pages.length, (int i) {
                      final bool active = i == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin:
                            const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.accent
                              : AppColors.textMuted,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),

                // ----- CTA -----
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _page == _pages.length - 1
                            ? 'Commencer'
                            : 'Suivant',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.page});
  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
              border: Border.all(color: AppColors.accent, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.25),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              page.icon,
              color: AppColors.accent,
              size: 64,
            ),
          ),
          const SizedBox(height: 36),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLarge.copyWith(
              fontSize: 26,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
