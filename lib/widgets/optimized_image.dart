// =========================================================
//  optimized_image.dart — UNE seule façon d'afficher une image
// =========================================================
//  Demandé par le client (2026-08-01) : au lieu de répéter les mêmes
//  réglages à 31 endroits — et d'en oublier —, un widget unique qui
//  garantit partout :
//    • placeholder INSTANTANÉ (jamais de roue qui tourne, jamais de trou
//      gris) : BlurHash si on en a un, sinon un fond neutre ou le repli
//      fourni par l'appelant ;
//    • fondu doux à l'arrivée, fondu court à la sortie ;
//    • décodage MÉMOIRE borné — une box TV ne décode pas un poster de
//      2000 px pour l'afficher en 480 ;
//    • stockage DISQUE borné — sur un catalogue de 100 000 titres, garder
//      les originaux, ce sont des gigaoctets pour rien sur une box.
//
//  Les bornes se DÉDUISENT de la taille d'affichage quand l'appelant ne
//  les précise pas : impossible d'oublier de les mettre.
//
//  BlurHash : le paramètre existe et fonctionne, mais AUCUN panel IPTV ne
//  fournit de hash aujourd'hui — le repli reste donc la règle en pratique
//  (et le monogramme des chaînes, lui, est déjà instantané).
// =========================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

class OptimizedImage extends StatelessWidget {
  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.blurHash,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.memCacheWidth,
    this.maxWidthDiskCache,
    this.fallback,
    this.fadeInDuration = const Duration(milliseconds: 280),
  });

  final String imageUrl;

  /// Aperçu flou instantané fourni par le serveur (aucun panel IPTV n'en
  /// produit à ce jour — laissé pour le jour où une source en donnera).
  final String? blurHash;

  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Largeur de décodage. Déduite de [width] si absente (× 2 pour rester
  /// net sur une dalle 4K), plafonnée pour ne jamais exploser la mémoire.
  final int? memCacheWidth;

  /// Largeur de stockage disque. Déduite de [memCacheWidth] si absente.
  final int? maxWidthDiskCache;

  /// Ce qu'on montre AVANT l'image et EN CAS D'ÉCHEC (logo de chaîne,
  /// monogramme…). Par défaut : un fond neutre, jamais un vide.
  final Widget? fallback;

  final Duration fadeInDuration;

  /// Borne de décodage déduite : 2× la taille affichée (netteté 4K), avec
  /// un plafond dur — au-delà, aucun gain visible sur une TV.
  static const int _kHardCap = 1400;

  int _decodeWidth() {
    final int? explicit = memCacheWidth;
    if (explicit != null) return explicit;
    final double? w = width;
    if (w != null && w.isFinite && w > 0) {
      final int doubled = (w * 2).round();
      return doubled > _kHardCap ? _kHardCap : doubled;
    }
    return _kHardCap;
  }

  @override
  Widget build(BuildContext context) {
    final int decode = _decodeWidth();
    final int disk = maxWidthDiskCache ?? decode;
    final Widget repli = fallback ??
        (blurHash != null && blurHash!.isNotEmpty
            ? BlurHash(hash: blurHash!, imageFit: fit)
            : const ColoredBox(color: Color(0xFF1A1A1A)));
    final Widget image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: const Duration(milliseconds: 80),
      memCacheWidth: decode,
      maxWidthDiskCache: disk,
      placeholder: (BuildContext _, String __) => repli,
      errorWidget: (BuildContext _, String __, Object ___) => repli,
    );
    final BorderRadius? r = borderRadius;
    if (r == null) return image;
    return ClipRRect(borderRadius: r, child: image);
  }
}
