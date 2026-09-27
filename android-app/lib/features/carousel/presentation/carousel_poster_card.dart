// =========================================================
//  carousel_poster_card.dart — Une affiche du carrousel, finition premium
// =========================================================
//  Rendu d'UNE carte, sans aucune notion de 3D (la 3D est appliquée par
//  l'anneau autour d'elle). Deux cas :
//    • l'affiche a une URL → image réelle, recadrée « cover » ;
//    • pas d'URL (démo, hors ligne, image cassée) → affiche GÉNÉRÉE dans
//      la charte Maison Noir : dégradé noir → or très sourd, filet or, titre
//      en capitales Oswald, année en Inter. Aucun texte à traduire : le
//      titre est un nom propre, l'année un nombre.
//
//  CHARTE « APAISER LA VISION » (appliquée ici au pixel près) :
//    • grille de 4 px : marges 20, filet 28 × 2, espacements 12 / 8 ;
//    • un seul accent (or champagne), tout le reste en neutres chauds ;
//    • titre : capitales, interlettrage +0,6, interligne 1,12, 3 lignes max,
//      coupure propre par « … » — jamais de texte tronqué au milieu d'un mot
//      sans signe ;
//    • année : chiffres TABULAIRES (même largeur pour chaque chiffre) → les
//      années ne « dansent » pas d'une carte à l'autre ;
//    • bord : filet blanc 5 % (1 px) qui détache la carte du fond sans cadre
//      visible ; ombre portée UNIQUEMENT sur la carte centrale.
// =========================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_tokens.dart';
import '../domain/carousel_item.dart';

class CarouselPosterCard extends StatelessWidget {
  const CarouselPosterCard({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    this.elevated = false,
  });

  final CarouselItem item;
  final double width;
  final double height;

  /// Carte centrale : reçoit l'ombre portée qui la « soulève » du fond.
  final bool elevated;

  static const BorderRadius _radius =
      BorderRadius.all(Radius.circular(TvDimens.cardRadius));

  @override
  Widget build(BuildContext context) {
    final String? url = item.posterUrl;
    final Widget generated = _GeneratedPoster(item: item);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          color: TvTokens.card,
          boxShadow: elevated
              ? <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: TvDimens.focusElevBlur,
                    offset: const Offset(0, TvDimens.focusElevDy),
                  ),
                ]
              : null,
        ),
        position: DecorationPosition.background,
        child: ClipRRect(
          borderRadius: _radius,
          child: DecoratedBox(
            // Filet intérieur 1 px (blanc 5 %) : dessiné PAR-DESSUS l'image
            // pour que le bord reste net même sur une affiche très sombre.
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: _radius,
              border: Border.all(color: TvTokens.tileBorder),
            ),
            child: url == null || url.isEmpty
                ? generated
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    // Décodage à 2× la taille logique : net sur une TV 4K,
                    // sans décoder une image de 2000 px pour une carte.
                    memCacheWidth: (width * 2).round(),
                    fadeInDuration: const Duration(milliseconds: 220),
                    placeholder: (BuildContext c, String u) => generated,
                    errorWidget: (BuildContext c, String u, Object e) =>
                        generated,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Affiche générée : sobre, typographique, dans la charte Zuno.
class _GeneratedPoster extends StatelessWidget {
  const _GeneratedPoster({required this.item});

  final CarouselItem item;

  /// Teinte par catégorie : une touche d'or plus ou moins présente (6 %
  /// à 26 %) mélangée au noir de carte. Les 6 catégories se distinguent
  /// sans jamais introduire une nouvelle couleur dans l'interface.
  static double _tintFor(CarouselCategory c) => 0.06 + 0.04 * c.index;

  @override
  Widget build(BuildContext context) {
    final Color top = Color.lerp(
        TvTokens.card, TvTokens.accentDeep, _tintFor(item.category))!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[top, TvTokens.bg],
        ),
      ),
      child: DecoratedBox(
        // Lumière lointaine en haut (même halo que le branding Zuno).
        decoration: const BoxDecoration(gradient: TvTokens.brandGlow),
        child: Padding(
          padding: const EdgeInsets.all(TvDimens.gutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Filet or : signature discrète, rappel du logo.
              const SizedBox(
                width: 28,
                height: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: TvTokens.accent,
                    borderRadius: BorderRadius.all(Radius.circular(1)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.title.toUpperCase(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.display(
                  TvDimens.title,
                  weight: FontWeight.w500,
                  spacing: 0.6,
                ).copyWith(height: 1.12),
              ),
              if (item.year != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '${item.year}',
                  style: TvTokens.ui(
                    TvDimens.caption,
                    weight: FontWeight.w500,
                    color: TvTokens.muted,
                    spacing: 1.2,
                  ).copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures()
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
