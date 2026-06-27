// =========================================================
//  tv_logo.dart — Logo de chaîne + MONOGRAMME de repli (§5.1 / §6)
// =========================================================
//  Brique UI PARTAGÉE : affiche le logo distant d'une chaîne, NORMALISÉ
//  (contain) sur une tuile premium. Si le logo est absent / illisible / en
//  erreur → on ne montre JAMAIS une carte grise vide : on rend un
//  MONOGRAMME (initiales or sur dégradé sombre dérivé du nom). Réutilisé par
//  la grille Direct, le Guide, les Films/Séries.
//
//  PERF (§4) : zéro flou, zéro animation. Le dégradé du monogramme est calculé
//  une fois par nom (déterministe) — aucun coût au focus.
// =========================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'tv_dimens.dart';
import 'tv_tokens.dart';

class TvChannelLogo extends StatelessWidget {
  const TvChannelLogo({
    super.key,
    required this.logoUrl,
    required this.label,
    this.size = 72,
    this.radius = 12,
  });

  /// URL distante du logo (peut être null/vide → monogramme).
  final String? logoUrl;

  /// Nom de la chaîne : sert aux initiales et à la teinte du monogramme.
  final String label;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String? url = logoUrl;
    final Widget mono = _Monogram(label: label, size: size, radius: radius);
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: (url == null || url.isEmpty)
            ? mono
            : CachedNetworkImage(
                imageUrl: url,
                // Le logo est posé SUR le monogramme : si l'image est
                // transparente/petite, le fond premium reste visible (jamais
                // de carte vide). Contain = logo normalisé, jamais déformé.
                fit: BoxFit.contain,
                memCacheWidth: (size * 2.2).round(),
                memCacheHeight: (size * 2.2).round(),
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => mono,
                errorWidget: (_, __, ___) => mono,
                imageBuilder: (BuildContext context, ImageProvider img) =>
                    DecoratedBox(
                  decoration: BoxDecoration(
                    color: TvTokens.tile,
                    image: DecorationImage(image: img, fit: BoxFit.contain),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Monogramme premium : initiales OR sur dégradé sombre dérivé du nom.
class _Monogram extends StatelessWidget {
  const _Monogram(
      {required this.label, required this.size, required this.radius});
  final String label;
  final double size;
  final double radius;

  /// Initiales (1–2 lettres) à partir du nom nettoyé.
  static String _initials(String name) {
    final List<String> words = name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '•';
    if (words.length == 1) {
      final String w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final String ini = _initials(label);
    // Teinte déterministe (déterminée par le nom) MAIS toujours sombre/matte :
    // on ne fait varier qu'une légère nuance entre 2 surfaces sombres → premium,
    // jamais criard. Calcul O(1), pas de cache nécessaire.
    final int h = label.hashCode;
    final double t = ((h & 0xFF) / 255.0); // 0..1
    final Color a = Color.lerp(TvTokens.card, TvTokens.surface3, t)!;
    final Color b = Color.lerp(TvTokens.bg, TvTokens.card, t)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[a, b],
        ),
        border: Border.all(color: TvTokens.hairline),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Text(
          ini,
          maxLines: 1,
          style: TvTokens.display(
            size * 0.42,
            weight: FontWeight.w600,
            color: TvTokens.gold,
            spacing: 1,
          ),
        ),
      ),
    );
  }
}
