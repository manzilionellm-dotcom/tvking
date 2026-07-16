// =========================================================
//  tv_poster_prefetch.dart — Pré-chargement des jaquettes de la rangée
//  suivante (défilement Cinéma sans trou d'image)
// =========================================================
//  Pendant qu'on navigue une rangée au D-pad, la rangée SUIVANTE se
//  pré-charge en silence : quand le focus descend, les jaquettes sont déjà
//  décodées → zéro carte grise, zéro à-coup (le pattern Netflix).
//
//  Points clés anti-jank :
//    - decodage BORNÉ ([cacheWidth]) : une vignette 132 px n'a aucune raison
//      de décoder un poster 2000×3000 (mémoire + CPU gaspillés) ;
//    - anti-redite : un LRU mémorise les URLs déjà demandées cette session —
//      re-focus sur la même rangée = AUCUN travail ;
//    - fail-open : une jaquette 404 est ignorée en silence (le repli
//      monogramme des cartes fait le reste) ;
//    - budget borné : au plus [maxPerRow] images par rangée (les premières
//      visibles), jamais toute la rangée de 500 films.
// =========================================================

import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

abstract final class TvPosterPrefetch {
  /// Nombre d'images pré-chargées par rangée (ce qui rentre à l'écran + 2).
  static const int maxPerRow = 10;

  /// Anti-redite (LRU borné — de simples URLs, quelques Ko au pire).
  static final LinkedHashSet<String> _seen = LinkedHashSet<String>();
  static const int _seenCap = 600;

  /// Pré-charge (mémoire + disque) les [maxPerRow] premières jaquettes de
  /// [urls], décodées à [cacheWidth] px de large. À appeler quand la rangée
  /// PRÉCÉDENTE gagne le focus. Sans effet si déjà fait cette session.
  static void prefetchRow(
    BuildContext context,
    List<String?> urls, {
    int cacheWidth = 264, // posterW (132) × 2 (écrans denses)
  }) {
    int done = 0;
    for (final String? url in urls) {
      if (done >= maxPerRow) break;
      if (url == null || url.isEmpty) continue;
      if (_seen.contains(url)) {
        done++; // déjà chaud — compte quand même dans le budget de rangée
        continue;
      }
      _remember(url);
      done++;
      final ImageProvider<Object> provider = ResizeImage(
        CachedNetworkImageProvider(url),
        width: cacheWidth,
        policy: ResizeImagePolicy.fit,
      );
      // fail-open : l'erreur est avalée (offline, 404…) — le repli visuel
      // des cartes (monogramme/dégradé) couvre déjà ce cas.
      precacheImage(provider, context, onError: (Object e, StackTrace? s) {});
    }
  }

  /// Oublie tout (changement de source) — les URLs d'une ancienne playlist
  /// n'ont aucune raison de bloquer le pré-chargement de la nouvelle.
  static void reset() => _seen.clear();

  static void _remember(String url) {
    _seen.remove(url); // ré-insertion en tête = « récemment utilisé »
    _seen.add(url);
    if (_seen.length > _seenCap) {
      _seen.remove(_seen.first);
    }
  }
}
