// =========================================================
//  tv_promo_banner.dart — Une bannière image du panel, sur l'accueil
// =========================================================
//  Comme la bande « vitrine » d'une box Android ou d'un Fire TV, en
//  plus sobre : UNE image à la fois, pleine largeur, 150 px de haut,
//  son libellé (« Publicité ») toujours visible en haut à gauche,
//  le titre en bas à gauche, les boutons en bas à droite.
//
//  Jamais de son, jamais de vidéo, jamais plein écran, jamais sur
//  l'image en lecture. « Fermer » l'éloigne 7 jours. Si l'image ne
//  charge pas, la carte reste lisible (fond sombre + textes).
// =========================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../box_extras/box_text.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_tokens.dart';
import '../domain/panel_board.dart';
import 'panel_button.dart';

class TvPromoBanner extends StatelessWidget {
  const TvPromoBanner({
    super.key,
    required this.banner,
    required this.channelFound,
    required this.onWatch,
    required this.onClose,
  });

  final PromoBanner banner;

  /// La chaîne nommée par la bannière existe dans la liste de la box.
  final bool channelFound;

  final VoidCallback onWatch;
  final VoidCallback onClose;

  /// Hauteur de la bande (px logiques du canevas TV).
  static const double height = 150;

  @override
  Widget build(BuildContext context) {
    final bool hasQr = banner.url.isNotEmpty;
    final String watchLabel = banner.cta.trim().isNotEmpty
        ? banner.cta.trim()
        : boxText(context, 'Regarder', 'Watch');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // L'image, décodée à la largeur de l'écran TV (jamais plus).
              CachedNetworkImage(
                imageUrl: banner.image,
                fit: BoxFit.cover,
                memCacheWidth: 1280,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, __) => const ColoredBox(color: TvTokens.card),
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: TvTokens.card),
              ),
              // Voile gauche → droite pour garder les textes lisibles.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[
                      Color(0xCC070708),
                      Color(0x66070708),
                      Color(0x33070708),
                    ],
                  ),
                ),
              ),
              // Libellé légal : toujours là, toujours lisible.
              Positioned(
                left: 14,
                top: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: TvTokens.bg.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(TvTokens.rSmall),
                    border: Border.all(color: TvTokens.line),
                  ),
                  child: Text(
                    banner.label.toUpperCase(),
                    style: TvTokens.ui(
                      TvDimens.caption,
                      weight: FontWeight.w700,
                      color: TvTokens.muted,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: hasQr ? 300 : 16,
                bottom: 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (banner.title.isNotEmpty)
                      Text(
                        banner.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(
                          TvDimens.title,
                          weight: FontWeight.w800,
                          color: TvTokens.text,
                        ),
                      ),
                    if (banner.subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        banner.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(TvDimens.label, color: TvTokens.muted),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        if (channelFound) ...<Widget>[
                          PanelButton(
                            label: watchLabel,
                            icon: Icons.play_arrow_rounded,
                            onSelect: onWatch,
                          ),
                          const SizedBox(width: 10),
                        ],
                        PanelButton(
                          label: boxText(context, 'Fermer', 'Close'),
                          icon: Icons.close_rounded,
                          onSelect: onClose,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasQr)
                Positioned(
                  right: 16,
                  top: 12,
                  bottom: 12,
                  child: Row(
                    children: <Widget>[
                      Text(
                        boxText(context, 'Téléphone', 'Phone'),
                        style: TvTokens.ui(TvDimens.caption,
                            color: TvTokens.mutedDim),
                      ),
                      const SizedBox(width: 10),
                      PanelQr(data: banner.url, size: 104),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
