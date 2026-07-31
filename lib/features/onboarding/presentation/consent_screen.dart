// =========================================================
//  consent_screen.dart — Porte de consentement (CGU)
// =========================================================
//  Écran BLOQUANT du premier lancement : l'app ne s'utilise
//  qu'après acceptation des conditions. Quatre engagements
//  numérotés (lecteur sans contenu, liens = responsabilité de
//  l'utilisateur, vérification des liens, jamais d'attente sans
//  fin), un bouton « J'accepte », un bouton « Refuser » qui ne
//  ferme RIEN : il affiche seulement un bandeau expliquant que
//  sans acceptation l'app ne peut pas être utilisée. Aucune
//  autre issue — pas de « plus tard », pas de croix.
//
//  Persistance : ConsentState (version des conditions acceptée).
//  Design Maison Noir / The Few, même squelette que les écrans
//  d'onboarding (halo ember, header brand, gros titre).
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/branding/verified_badge.dart';
import '../../../core/flavor/flavor.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/consent_state.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({required this.onAccepted, super.key});

  /// Appelé une fois les conditions acceptées et persistées.
  final VoidCallback onAccepted;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _saving = false;
  // Passe à true après un appui sur « Refuser » : on affiche alors le
  // bandeau rouge explicatif. La porte reste ouverte (aucune fermeture).
  bool _refused = false;

  Future<void> _accept() async {
    if (_saving) return;
    setState(() => _saving = true);
    await ConsentState.instance.markAccepted();
    if (!mounted) return;
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    // Les 4 engagements, numérotés 01…04 comme sur l'écran d'origine.
    final List<({String title, String body})> terms =
        <({String title, String body})>[
      (
        title: context.l10n.consentTerm1Title,
        body: context.l10n.consentTerm1Body,
      ),
      (
        title: context.l10n.consentTerm2Title,
        body: context.l10n.consentTerm2Body,
      ),
      (
        title: context.l10n.consentTerm3Title,
        body: context.l10n.consentTerm3Body,
      ),
      (
        title: context.l10n.consentTerm4Title,
        body: context.l10n.consentTerm4Body,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          // Halo ember en arrière-plan (même décor que l'onboarding).
          Positioned(
            top: -160,
            right: -120,
            child: Container(
              width: 420,
              height: 420,
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // ----- Header brand -----
                  Row(
                    children: <Widget>[
                      const BrandLogo.compact(),
                      const SizedBox(width: 12),
                      Text(
                        FlavorConfig.current.appName,
                        style: AppTextStyles.headlineLarge.copyWith(
                          fontSize: 18,
                          letterSpacing: 3.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const VerifiedBadge.small(),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // ----- Titre -----
                  Text(
                    context.l10n.consentEyebrow.toUpperCase(),
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 12,
                      letterSpacing: 2.4,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    FlavorConfig.current.appName,
                    style: AppTextStyles.displayLarge.copyWith(
                      fontSize: 34,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.consentSubtitle,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ----- Les 4 conditions (scrollables sur petit écran) -----
                  Expanded(
                    child: ListView.separated(
                      itemCount: terms.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (BuildContext context, int i) {
                        final ({String title, String body}) t = terms[i];
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '0${i + 1}',
                                style: AppTextStyles.headlineLarge.copyWith(
                                  fontSize: 16,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      t.title,
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      t.body,
                                      style:
                                          AppTextStyles.bodyMedium.copyWith(
                                        fontSize: 13,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // ----- Bandeau refus (visible après « Refuser ») -----
                  if (_refused) ...<Widget>[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.live.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.live.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        context.l10n.consentRefusedNotice,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 13,
                          color: AppColors.live,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ----- Boutons -----
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _accept,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.background,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        context.l10n.consentAccept,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.background,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _refused = true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        context.l10n.consentRefuse,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
