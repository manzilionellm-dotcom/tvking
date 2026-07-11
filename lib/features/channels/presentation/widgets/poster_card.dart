// =========================================================
//  poster_card.dart — Carte affiche portrait 2:3 (direction
//  "Poster-forward" Netflix 2025)
// =========================================================
//  Phase 1.5 (2026-06-01) — refonte accueil demandée par
//  l'utilisateur : look "poster-forward" type Netflix/Disney+.
//
//  Pour la VOD (Films / Séries / Docs), `logoUrl` contient en
//  général une VRAIE affiche portrait (cover Xtream `movie_image`).
//  On l'affiche donc en `BoxFit.cover` plein cadre 2:3 — c'est ce
//  qui donne le mur d'affiches premium.
//
//  Si pas d'affiche (ou 404) → fallback ÉLÉGANT et sobre : dégradé
//  charbon + grandes initiales + icône de genre. Cohérent sur
//  20 000 entrées, jamais de couleurs aléatoires criardes (on
//  reste fidèle à la charte Maison Noir).
//
//  Le nom vit SOUS l'affiche (lisibilité maximale sur téléphone),
//  pas par-dessus — l'affiche parle d'elle-même.
// =========================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/channel.dart';
import 'channel_logo.dart' show ChannelQualityBadge;

class PosterCard extends StatefulWidget {
  const PosterCard({
    required this.channel,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Largeur recommandée pour les rangées portrait. ~3 affiches
  /// visibles sur un téléphone standard (≈360-390 dp de large).
  static const double cardWidth = 120;

  /// Hauteur de l'affiche seule (ratio 2:3).
  static const double posterHeight = cardWidth * 3 / 2;

  /// Hauteur totale carte = affiche + nom + métadonnée + espacements.
  /// Exposée pour `itemExtent` côté rangée (scroll fluide).
  static const double totalHeight = posterHeight + 48;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  /// Focus visuel + scroll-on-focus (D-pad / clavier). Même pédagogie
  /// que premium_channel_card.dart : le postFrameCallback évite le saut
  /// saccadé d'ensureVisible avant mesure de la ListView.
  void _onFocusChange(bool focused) {
    if (!mounted) return;
    setState(() => _focused = focused);
    if (focused) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Channel ch = widget.channel;

    return FocusableActionDetector(
      onShowFocusHighlight: _onFocusChange,
      mouseCursor: SystemMouseCursors.click,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        label: ch.cleanName,
        focusable: true,
        focused: _focused,
        child: MouseRegion(
          onEnter: (_) => _onFocusChange(true),
          onExit: (_) => _onFocusChange(false),
          child: GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: AnimatedScale(
              scale: _focused ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // ----- Affiche 2:3 -----
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _focused
                            ? <BoxShadow>[
                                BoxShadow(
                                  color:
                                      AppColors.accent.withValues(alpha: 0.30),
                                  blurRadius: 22,
                                  spreadRadius: 1,
                                ),
                              ]
                            : const <BoxShadow>[],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            _poster(ch),

                            // Scrim bas pour lisibilité d'éventuels badges.
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: AppColors.cardScrim,
                              ),
                            ),

                            // Badge LIVE haut-gauche.
                            if (ch.isLive)
                              const Positioned(
                                top: 8,
                                left: 8,
                                child: _LivePill(),
                              ),

                            // Badge qualité haut-droite.
                            if (ch.quality != ChannelQuality.sd)
                              Positioned(
                                top: 8,
                                right: 8,
                                child:
                                    ChannelQualityBadge(quality: ch.quality),
                              ),

                            // Anneau de focus (D-pad TV).
                            if (_focused)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.accent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ----- Nom sous l'affiche -----
                  const SizedBox(height: 8),
                  Text(
                    ch.cleanName,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Métadonnée — contraste relevé (textTertiary au lieu de
                  // textMuted qui échouait WCAG sur fond charbon).
                  Text(
                    ch.country != null
                        ? '${ch.country!.flag} ${ch.genre.localizedLabel}'
                        : ch.genre.localizedLabel,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// L'affiche elle-même : image distante en `cover` si dispo, sinon
  /// fallback dégradé + initiales.
  Widget _poster(Channel ch) {
    if (!ch.hasLogo) return _PosterFallback(channel: ch);
    return CachedNetworkImage(
      imageUrl: ch.logoUrl!,
      fit: BoxFit.cover,
      placeholder: (BuildContext context, String url) =>
          _PosterFallback(channel: ch),
      errorWidget: (BuildContext context, String url, dynamic error) =>
          _PosterFallback(channel: ch),
      memCacheWidth: (PosterCard.cardWidth * 2).toInt(),
      fadeInDuration: const Duration(milliseconds: 220),
    );
  }
}

/// Fallback sobre quand pas d'affiche : dégradé charbon + grandes
/// initiales + icône de genre discrète. Uniforme sur tout le catalogue.
class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.slate, AppColors.midnight],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            right: 10,
            bottom: 10,
            child: Icon(
              channel.genre.icon,
              color: AppColors.textMuted.withValues(alpha: 0.45),
              size: 26,
            ),
          ),
          Text(
            channel.initials,
            style: AppTextStyles.channelInitials.copyWith(
              fontSize: 40,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill rouge "LIVE" compact (même langage visuel que les autres cartes).
class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.live,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        context.l10n.badgeLive,
        style: AppTextStyles.labelSmall.copyWith(
          color: Colors.white,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
