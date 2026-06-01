// =========================================================
//  hero_section.dart — Bannière cinéma edge-to-edge (Phase 1
//                      redesign)
// =========================================================
//  Refonte design Phase 1 :
//
//  AVANT : une "card" rectangle compacte avec logo à gauche,
//          texte à droite, halo radial discret. Esthétique
//          dashboard SaaS, pas cinéma.
//
//  APRÈS : une bannière edge-to-edge qui occupe TOUTE la
//          largeur disponible, avec :
//            - l'artwork de la chaîne en pleine étendue,
//              dupliqué en ARRIÈRE-PLAN avec un blur fort
//              et une saturation amortie → "backdrop blur"
//              à la Apple TV+ (l'image teinte l'écran sans
//              le couvrir),
//            - l'artwork NET au premier plan dans une zone
//              centrée/à gauche selon proportions,
//            - un scrim noir-en-bas pour la lisibilité du
//              texte (style Netflix/HBO),
//            - eyebrow champagne (PAS rouge — on a réduit
//              le red usage de 65 % comme demandé),
//            - title display cinéma (Inter 600 / -1.0 ls),
//            - métadonnées discrètes (genre · pays · qualité),
//            - CTAs flottants (Lecture en ember critique +
//              Détails translucide glass).
//
//  C'est l'incarnation du principe "content is the hero" du
//  brief : aucun container visible, aucune bordure, aucune
//  card. L'image règne, le texte habite l'image.
// =========================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/cinematic_spacing.dart';
import '../../../../core/widgets/live_badge.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../domain/channel.dart';

class HeroSection extends StatelessWidget {
  const HeroSection({
    required this.channel,
    required this.onWatch,
    required this.onInfo,
    super.key,
  });

  final Channel channel;
  final VoidCallback onWatch;
  final VoidCallback onInfo;

  /// Hauteur cible du hero. Calée pour que la composition
  /// title + meta + CTAs respire sans pousser le premier rail
  /// hors-écran sur un téléphone standard (≈ 6.1").
  static const double _heroHeight = 360.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CinematicSpacing.radiusXL),
      child: SizedBox(
        height: _heroHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // --- Couche 1 : backdrop blur (artwork géant flou) ---
            _AmbientBackdrop(channel: channel),

            // --- Couche 2 : scrim bottom → lisibilité texte ---
            const _BottomScrim(),

            // (Ancienne couche 3 "artwork net centré à gauche"
            //  SUPPRIMÉE 2026-06-01 : elle chevauchait le titre dès
            //  que celui-ci faisait 2 lignes — "les mots se croisent".
            //  L'artwork reste visible en fond flou ambiant ; le texte
            //  habite l'image, à la Netflix. Plus de collision possible.)

            // --- Couche 4 : badge LIVE en haut à gauche ---
            if (channel.isLive)
              const Positioned(
                top: CinematicSpacing.m,
                left: CinematicSpacing.m,
                child: LiveBadge(),
              ),

            // --- Couche 5 : texte + CTAs (bas du hero) ---
            Positioned(
              left: CinematicSpacing.l,
              right: CinematicSpacing.l,
              bottom: CinematicSpacing.l,
              child: _HeroCopy(
                channel: channel,
                onWatch: onWatch,
                onInfo: onInfo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
//  COUCHE 1 — Backdrop ambiant (artwork géant + blur fort)
// =========================================================
//  Le logo de la chaîne (souvent carré, basse résolution) est
//  étiré en plein cadre, puis flouté agressivement. Résultat :
//  une lueur colorée qui teinte l'arrière-plan sans qu'on
//  reconnaisse l'image — exactement le truc d'Apple TV+ et de
//  Spotify. Si pas de logo, on tombe sur un dégradé neutre
//  obsidian → midnight (jamais d'écran vide moche).
class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    if (!channel.hasLogo) {
      return const _NeutralBackdrop();
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 1) Logo étiré, fortement saturé en sombre.
        Image.network(
          channel.logoUrl!,
          fit: BoxFit.cover,
          // L'image sert UNIQUEMENT de fond coloré. Si elle échoue
          // (404, timeout, format non géré), on retombe sur le
          // dégradé neutre — l'écran ne doit jamais avoir l'air cassé.
          errorBuilder: (_, __, ___) => const _NeutralBackdrop(),
        ),
        // 2) Blur cinéma + voile sombre pour ramener au charbon.
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: Container(color: Colors.black.withValues(alpha: 0.55)),
        ),
      ],
    );
  }
}

class _NeutralBackdrop extends StatelessWidget {
  const _NeutralBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.midnight, AppColors.obsidian],
        ),
      ),
    );
  }
}

// =========================================================
//  COUCHE 2 — Bottom scrim (dégradé sombre vers le bas)
// =========================================================
//  Sans ce voile, le texte blanc en bas du hero serait
//  illisible sur des artworks clairs. C'est le standard
//  Netflix / Disney+ / HBO Max.
class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0x00000000),
              Color(0x33000000),
              Color(0xCC050507),
            ],
            stops: <double>[0.35, 0.65, 1.0],
          ),
        ),
      ),
    );
  }
}

// =========================================================
//  COUCHE 5 — Texte + CTAs (bas du hero)
// =========================================================
//  Composition typographique :
//    - eyebrow champagne ("À LA UNE")
//    - titre display cinéma (38px, w600, ls -1.0)
//    - row de meta (genre · pays · qualité)
//    - CTAs flottants : Lecture (ember) + Détails (glass)
//
//  Aucune card, aucune bordure : on est posé DIRECTEMENT sur
//  l'artwork, le scrim fait son travail de lisibilité.
class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.channel,
    required this.onWatch,
    required this.onInfo,
  });

  final Channel channel;
  final VoidCallback onWatch;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // --- Eyebrow champagne ---
        // Non plus un chip avec fond rouge : juste deux lettres
        // crème espacées, à la Apple TV+ / Criterion.
        Text(
          'À LA UNE',
          style: AppTextStyles.eyebrowChampagne,
        ),
        const SizedBox(height: CinematicSpacing.s),

        // --- Title display cinéma ---
        Text(
          channel.cleanName,
          style: AppTextStyles.displayHero,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: CinematicSpacing.s),

        // --- Métadonnées discrètes ---
        _MetaLine(channel: channel),

        // --- Programme courant si disponible ---
        if (channel.currentProgram != null) ...<Widget>[
          const SizedBox(height: CinematicSpacing.xs),
          Text(
            channel.currentProgram!,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: CinematicSpacing.m),

        // --- CTAs flottants ---
        Row(
          children: <Widget>[
            _PlayCta(onPressed: onWatch),
            const SizedBox(width: CinematicSpacing.s),
            _InfoCta(onPressed: onInfo),
          ],
        ),
      ],
    );
  }
}

/// Ligne de métadonnées sous le titre. Pas de chips encadrés
/// (lourd) : juste des fragments séparés par des points
/// médians, à la manière des génériques de film.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final List<String> parts = <String>[
      channel.genre.label,
      if (channel.country != null) channel.country!.name,
      if (channel.quality != ChannelQuality.sd) channel.quality.badge,
    ];
    return Text(
      parts.join('   ·   '),
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.textSecondary,
        fontSize: 11,
        letterSpacing: 1.6,
      ),
    );
  }
}

// =========================================================
//  CTA "LECTURE" — rouge ember (l'UN des rares endroits où
//  le rouge survit après la coupe à 35 % du brief).
//  Bouton plein, texte noir, accessible aux télécommandes via
//  TvFocusable.
// =========================================================
class _PlayCta extends StatelessWidget {
  const _PlayCta({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(CinematicSpacing.radiusM),
      semanticsLabel: 'Lecture',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(CinematicSpacing.radiusM),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.black),
            const SizedBox(width: 6),
            Text(
              'Lecture',
              style: AppTextStyles.button.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
//  CTA "DÉTAILS" — glass translucide, plus du tout en bordure
//  rouge (avant : `AppColors.border` mélangeait blanc et accent).
//  Maintenant : voile glass + texte ivoire. Le rouge ne survit
//  QUE sur le bouton Lecture, conformément à la doctrine
//  "red = focus/CTA/LIVE uniquement".
// =========================================================
class _InfoCta extends StatelessWidget {
  const _InfoCta({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(CinematicSpacing.radiusM),
      showGlow: false,
      semanticsLabel: 'Détails',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CinematicSpacing.radiusM),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(CinematicSpacing.radiusM),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Détails',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
