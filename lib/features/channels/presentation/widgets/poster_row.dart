// =========================================================
//  poster_row.dart — Rangée horizontale d'affiches portrait
// =========================================================
//  Phase 1.5 (2026-06-01) — direction "Poster-forward".
//
//  Deux modes :
//    - standard : rail d'affiches 2:3 (Films, Séries, Docs…)
//    - numbered : rail "Top 10" avec gros chiffre stroké à gauche
//      de chaque affiche (signature Netflix).
//
//  En-tête identique à PremiumRow pour la cohérence (titre +
//  sous-titre + "Voir tout"). Perf : ListView.builder + itemExtent
//  fixe + RepaintBoundary par carte.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../domain/channel.dart';
import 'poster_card.dart';

class PosterRow extends StatelessWidget {
  const PosterRow({
    required this.title,
    required this.channels,
    required this.onChannelTap,
    this.onChannelLongPress,
    this.onSeeAll,
    this.subtitle,
    this.numbered = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Channel> channels;
  final void Function(Channel) onChannelTap;
  final void Function(Channel)? onChannelLongPress;
  final VoidCallback? onSeeAll;

  /// Si `true`, rail "Top 10" avec gros chiffre à gauche de chaque carte.
  final bool numbered;

  /// Largeur réservée au gros chiffre Top 10 (1-10). Le chiffre est
  /// mis à l'échelle dans cette boîte via FittedBox (cf. _RankNumber)
  /// donc il ne déborde jamais, même à deux chiffres ("10").
  static const double _numberWidth = 52;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    // En "numbered", on plafonne à 10 (c'est un Top 10).
    final List<Channel> items =
        numbered ? channels.take(10).toList(growable: false) : channels;

    final double itemExtent = numbered
        ? PosterCard.cardWidth + _numberWidth + 12
        : PosterCard.cardWidth + 12;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ----- En-tête -----
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTextStyles.headlineMedium.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (onSeeAll != null)
                TvFocusable(
                  onTap: onSeeAll!,
                  borderRadius: BorderRadius.circular(8),
                  showGlow: false,
                  semanticsLabel: context.l10n.seeAllOf(title),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          context.l10n.buttonSeeAll,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.accent,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ----- Liste horizontale d'affiches -----
        SizedBox(
          height: PosterCard.totalHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            itemExtent: itemExtent,
            cacheExtent: 800,
            itemBuilder: (BuildContext context, int index) {
              final Channel ch = items[index];
              final Widget card = SizedBox(
                width: PosterCard.cardWidth,
                child: PosterCard(
                  channel: ch,
                  onTap: () => onChannelTap(ch),
                  onLongPress: onChannelLongPress != null
                      ? () => onChannelLongPress!(ch)
                      : null,
                ),
              );
              return RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: numbered
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: _numberWidth,
                              height: PosterCard.posterHeight,
                              child: _RankNumber(rank: index + 1),
                            ),
                            card,
                          ],
                        )
                      : card,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Gros chiffre "Top 10" stroké (contour ember), aligné en bas de
/// l'affiche — signature visuelle Netflix. On dessine deux Text
/// superposés : un en contour (stroke) + un en remplissage charbon,
/// pour l'effet "chiffre découpé" lisible sur n'importe quelle affiche.
class _RankNumber extends StatelessWidget {
  const _RankNumber({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final String n = '$rank';
    // Base SANS couleur : indispensable pour pouvoir alterner `color`
    // (remplissage) et `foreground` (contour) sans déclencher l'assert
    // TextStyle "Cannot provide both a color and a foreground". On
    // réutilise la famille Inter de displayLarge pour rester cohérent.
    final TextStyle base = TextStyle(
      fontSize: 92,
      height: 0.9,
      fontWeight: FontWeight.w800,
      letterSpacing: -4,
      fontFamily: AppTextStyles.displayLarge.fontFamily,
      fontFamilyFallback: AppTextStyles.displayLarge.fontFamilyFallback,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      // FittedBox : met le chiffre à l'échelle de la boîte réservée
      // (jamais de débordement, y compris pour "10").
      child: FittedBox(
        fit: BoxFit.contain,
        child: Stack(
          children: <Widget>[
            // Contour ember.
            Text(
              n,
              style: base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2.5
                  ..color = AppColors.accent.withValues(alpha: 0.85),
              ),
            ),
            // Remplissage charbon (donne l'effet "creux").
            Text(
              n,
              style: base.copyWith(color: AppColors.background),
            ),
          ],
        ),
      ),
    );
  }
}
