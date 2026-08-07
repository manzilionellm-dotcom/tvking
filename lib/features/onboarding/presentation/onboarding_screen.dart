// =========================================================
//  onboarding_screen.dart — Première impression de l'app
// =========================================================
//  4 slides avec PageView :
//    1. Bienvenue + identité de marque
//    2. Identifiant The Few (MAC) + envoi WhatsApp au revendeur
//       — c'est LA slide critique pour les utilisateurs qui
//       passent par un revendeur. Ils voient leur ID, l'envoient
//       par WhatsApp en 2 taps, puis attendent que leurs chaînes
//       arrivent automatiquement.
//    3. Charger une playlist manuellement (optionnel)
//    4. Découvrir l'expérience premium
//
//  À la fin → flag `OnboardingState.markCompleted()` + push
//  vers HomeScreen.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/flavor/flavor.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/support/support_choice_sheet.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/update/build_flags.dart';
import '../../device/data/device_identity.dart';
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

  /// Slides d'onboarding.
  ///
  /// Note : getter d'INSTANCE (et plus `static const`) parce que
  /// les textes viennent d'AppLocalizations (langue du téléphone)
  /// et que la premiere slide affiche le nom du flavor courant
  /// (The Few ou Red Room) lu via `FlavorConfig.current.appName`,
  /// inconnu a la compilation. `context` est celui du State, valide
  /// des que le widget est monte. La perf reste OK : 5 elements
  /// crees a chaque acces du getter, negligeable.
  ///
  /// La slide 'Apporte ton fournisseur — nous ne vendons aucun flux'
  /// a ete retiree (post virage utilisateur vers la posture
  /// revendeur : le serveur est hardcode dans FlavorConfig et
  /// l'utilisateur ne voit que le formulaire identifiant/code).
  List<_OnboardingPage> get _pages {
    final String appName = FlavorConfig.current.appName;
    return <_OnboardingPage>[
      _OnboardingPage(
        icon: Icons.local_movies_rounded,
        title: context.l10n.onboardingWelcomeAppTitle(appName),
        description: context.l10n.onboardingWelcomeDesc,
      ),
      _OnboardingPage(
        icon: Icons.cloud_upload_outlined,
        title: context.l10n.onboardingChannelsTitle,
        description: context.l10n.onboardingChannelsDesc,
      ),
      // BUILD APP STORE iOS : pas de diapo « numéro de référence →
      // activation à distance » (déblocage par code externe = 3.1.1).
      if (!kIsIosStoreBuild)
        _OnboardingPage(
          icon: Icons.fingerprint_rounded,
          title: context.l10n.onboardingActivateTitle,
          description: context.l10n.onboardingActivateDesc,
          isMacSlide: true,
        ),
      // BUILD APP STORE iOS : pas de diapo « premium » non plus — elle
      // vante le cast et l'enregistrement, dont les ponts natifs sont
      // Android-only pour l'instant. Vanter une fonction absente = motif
      // de rejet Apple 2.3.1 (metadata trompeuse).
      if (!kIsIosStoreBuild)
        _OnboardingPage(
          icon: Icons.workspace_premium_rounded,
          title: context.l10n.onboardingPremiumTitle,
          description: context.l10n.onboardingPremiumDesc,
        ),
      // BUILD GOOGLE PLAY : pas de diapo « essai gratuit puis 5 €/an » —
      // elle cite des prix payés hors Google Play Billing (violation
      // Paiements du Store). L'APK sideload GitHub la garde.
      if (!kIsStoreBuild)
        _OnboardingPage(
          icon: Icons.celebration_outlined,
          title: context.l10n.paywallFreeTrialTitle,
          description: context.l10n.onboardingTrialDesc,
        ),
    ];
  }

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
          // Halo ember derrière
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
                          context.l10n.onboardingSkip,
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
                      final _OnboardingPage page = _pages[index];
                      if (page.isMacSlide) {
                        return _MacHandoffSlide(page: page);
                      }
                      return _SlideView(page: page);
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
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(
                        _page == _pages.length - 1
                            ? context.l10n.onboardingStart
                            : context.l10n.onboardingNext,
                        style: AppTextStyles.bodyLarge.copyWith(
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
    this.isMacSlide = false,
  });

  final IconData icon;
  final String title;
  final String description;

  /// Marque la slide qui montre le MAC + actions Copier / WhatsApp.
  /// Si `true`, on rend `_MacHandoffSlide` au lieu de `_SlideView`.
  final bool isMacSlide;
}

// ============================================================
//  Slide standard — icône + titre + description
// ============================================================

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

// ============================================================
//  Slide MAC handoff — MAC géant + Copier + Envoyer WhatsApp
// ============================================================

class _MacHandoffSlide extends StatefulWidget {
  const _MacHandoffSlide({required this.page});
  final _OnboardingPage page;

  @override
  State<_MacHandoffSlide> createState() => _MacHandoffSlideState();
}

class _MacHandoffSlideState extends State<_MacHandoffSlide> {
  String? _mac;

  @override
  void initState() {
    super.initState();
    // Code NU (sans « MK: ») pour l'affichage/copie/envoi : le panel du
    // revendeur préfixe déjà « MK » → « MK:… » collé le doublerait.
    DeviceIdentity.instance.mac.then((String value) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(value));
    });
  }

  Future<void> _copy() async {
    if (_mac == null) return;
    await Clipboard.setData(ClipboardData(text: _mac!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(context.l10n.idCopied(_mac!),
            style: AppTextStyles.bodyMedium),
      ),
    );
  }

  /// Au tap, sheet à 2 choix (message ou appel) avec le MAC
  /// pré-rempli côté messagerie. Le sheet gère lui-même les
  /// fallbacks d'erreur (toast 'impossible d'ouvrir...').
  Future<void> _activate() async {
    if (_mac == null) return;
    // Message d'activation a destination du support — le nom du
    // flavor est injecte dynamiquement pour que Red Room ne signe
    // pas 'Bonjour The Few' a tes clients. Localise : le message
    // pre-rempli est visible par l'utilisateur dans WhatsApp.
    final String appName = FlavorConfig.current.appName;
    final String msg =
        context.l10n.onboardingActivationMessage(appName, _mac!);
    await showSupportChoiceSheet(context, customMessage: msg);
  }

  @override
  Widget build(BuildContext context) {
    final String display = _mac ?? '??:??:??:??:??';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(height: 8),
            // ----- Pastille fingerprint -----
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.accent, width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.25),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                widget.page.icon,
                color: AppColors.accent,
                size: 42,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.page.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineLarge.copyWith(
                fontSize: 24,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            // ----- MAC en GROS au centre -----
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.5),
                  width: 1.4,
                ),
                boxShadow: AppColors.emberGlowShadow,
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    context.l10n.onboardingYourId,
                    style: AppTextStyles.eyebrow,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    display,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text(
              widget.page.description,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),

            // ----- CTA primaire : activation -----
            // Bouton ember (plus de vert WhatsApp). Tap → WhatsApp
            // s'ouvre en silence avec l'identifiant pré-rempli.
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _mac == null ? null : _activate,
                icon: const Icon(Icons.bolt_rounded, size: 22),
                label: Text(context.l10n.onboardingActivateChannels),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.voidSurface,
                  textStyle: AppTextStyles.button.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ----- Bouton secondaire : copier dans le presse-papier -----
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _mac == null ? null : _copy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(context.l10n.onboardingCopyId),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
