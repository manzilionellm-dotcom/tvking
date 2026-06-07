// =========================================================
//  vip_help_card.dart — Carte "Aide VIP" très premium
// =========================================================
//  Carte de support visuellement luxueuse — gradient ember,
//  bordure accentEmber, halo cuivré pulsant, icône couronne,
//  badge VIP en eyebrow. Tap ouvre WhatsApp avec un message
//  pré-rempli.
//
//  Trois variantes pour s'adapter au contexte d'affichage :
//    - .full     : grande carte avec description (Settings, About)
//    - .compact  : ligne fine pour les listes denses
//    - .floating : pastille flottante pour l'écran vide
// =========================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'support_choice_sheet.dart';

enum VipHelpVariant { full, compact, floating }

class VipHelpCard extends StatefulWidget {
  const VipHelpCard({super.key, this.variant = VipHelpVariant.full});

  const VipHelpCard.full({super.key}) : variant = VipHelpVariant.full;
  const VipHelpCard.compact({super.key}) : variant = VipHelpVariant.compact;
  const VipHelpCard.floating({super.key})
      : variant = VipHelpVariant.floating;

  final VipHelpVariant variant;

  @override
  State<VipHelpCard> createState() => _VipHelpCardState();
}

class _VipHelpCardState extends State<VipHelpCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Au tap, on n'ouvre PLUS WhatsApp directement — on présente
  /// d'abord un bottom sheet à 2 choix (message ou appel). C'est
  /// plus pro et ça donne le choix au client selon son contexte
  /// (en transports → message, dans son canapé → appel direct).
  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    await showSupportChoiceSheet(context);
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    switch (widget.variant) {
      case VipHelpVariant.full:
        return _buildFull(reduceMotion);
      case VipHelpVariant.compact:
        return _buildCompact();
      case VipHelpVariant.floating:
        return _buildFloating(reduceMotion);
    }
  }

  // ============================================================
  //  Variante FULL — pour Settings, About
  // ============================================================

  Widget _buildFull(bool reduceMotion) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (BuildContext context, Widget? child) {
            final double glow = reduceMotion
                ? 0.32
                : 0.18 + 0.22 * _pulse.value;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    AppColors.surface,
                    AppColors.surfaceHigh,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.55),
                  width: 1.4,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.emberHalo.withValues(alpha: glow),
                    blurRadius: 32,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: _fullInner(),
        ),
      ),
    );
  }

  Widget _fullInner() {
    return Row(
      children: <Widget>[
        // ----- Couronne premium -----
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.premiumGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.emberGlowShadow,
          ),
          child: const Icon(
            Icons.workspace_premium_rounded,
            color: AppColors.voidSurface,
            size: 30,
          ),
        ),
        const SizedBox(width: 14),
        // ----- Texte -----
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'AIDE',
                    style: AppTextStyles.eyebrow,
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.premiumGradient,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'VIP',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.voidSurface,
                        fontSize: 9,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Une question ? On te répond.',
                style: AppTextStyles.headlineMedium.copyWith(
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                // On évite délibérément de nommer WhatsApp ici. Le
                // user veut un bouton qui SE PRÉSENTE comme un
                // concierge privé / support haut de gamme, et qui
                // ouvre WhatsApp en silence quand tapé.
                'Concierge privé · Réponse 7j/7.',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // ----- CTA neutre (ember, pas vert WhatsApp) -----
        // Box ember + icône casque support — signale "support
        // premium" sans révéler la techno derrière (WhatsApp).
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.55),
            ),
          ),
          child: _opening
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.support_agent_rounded,
                  color: AppColors.accent,
                  size: 22,
                ),
        ),
      ],
    );
  }

  // ============================================================
  //  Variante COMPACT — pour les listes denses
  // ============================================================

  Widget _buildCompact() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.premiumGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: AppColors.voidSurface,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Plus d'icône verte WhatsApp à côté du titre —
                    // on veut un branding "Aide VIP" sobre, agnostique
                    // de la techno derrière.
                    Text(
                      'Aide VIP',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Concierge dédié · Réponse 7j/7.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.accent,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  //  Variante FLOATING — pastille pour l'empty state, etc.
  // ============================================================

  Widget _buildFloating(bool reduceMotion) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(28),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (BuildContext context, Widget? child) {
            final double glow = reduceMotion
                ? 0.30
                : 0.18 + 0.22 * _pulse.value;
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                gradient: AppColors.premiumGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.emberHalo.withValues(alpha: glow),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.workspace_premium_rounded,
                color: AppColors.voidSurface,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Aide VIP',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.voidSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
