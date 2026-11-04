// =========================================================
//  box_memory_budget.dart — Empreinte selon la RAM de la box
// =========================================================
//  Une seule échelle, déjà utilisée pour le cache d'images
//  (guarded_main) :
//    • ≤ 1 Go, ou le flag Android « low RAM »  → palier serré
//    • > 1 Go et ≤ 2 Go                        → palier équilibré
//      (une RAM lue à 0 Mo tombe ici : c'est le comportement
//      historique du cache, on ne le change pas)
//    • > 2 Go                                  → palier large
//
//  Le palier large garde le rendu d'aujourd'hui (lueur au focus,
//  fondu des logos, fond d'accueil en taille fichier, marge de
//  liste de 250 px — le défaut de Flutter).
//
//  Les deux autres paliers coupent seulement ce qui coûte un
//  flou GPU ou une bitmap trop grande. Le contour or du focus
//  reste : c'est lui qui se voit à 3 mètres, pas l'ombre.
//
//  Tant que la RAM n'a pas été lue, on reste au palier serré.
//  Une box inconnue ne paie pas le flou. Le PC n'a pas ce plugin :
//  `useDesktop` le remet au palier large, comme
//  CinemaRepository.useDesktopMemory le fait pour son index.
// =========================================================

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Palier mémoire d'une box. Les noms suivent les trois branches
/// déjà écrites pour le cache d'images.
enum BoxRamTier {
  /// ≤ 1 Go, ou `ActivityManager.isLowRamDevice`.
  tight,

  /// > 1 Go et ≤ 2 Go, ou total annoncé à 0.
  balanced,

  /// > 2 Go.
  roomy,
}

/// Décision partagée. Posée avant `runApp` sur la box, pour que
/// le premier écran soit déjà au bon palier.
abstract final class BoxMemoryBudget {
  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/device');

  /// Palier réel, après lecture. Défaut prudent.
  static BoxRamTier tier = BoxRamTier.tight;

  /// Fige le palier dans les tests. `null` = on suit [tier].
  @visibleForTesting
  static BoxRamTier? debugTier;

  static BoxRamTier get current => debugTier ?? tier;

  /// `true` seulement au-dessus de 2 Go : la lueur (deux flous de
  /// 32 et 40 px) est un calque de plus à chaque flèche.
  static bool get paintFocusGlow => current == BoxRamTier.roomy;

  /// Marge autour de la grille / de la liste de chaînes, en pixels.
  /// 250 est le défaut de Flutter : on le garde tel quel au palier large.
  static double get liveListCacheExtent {
    switch (current) {
      case BoxRamTier.tight:
        return 96;
      case BoxRamTier.balanced:
        return 160;
      case BoxRamTier.roomy:
        return 250;
    }
  }

  /// Largeur de décodage du fond d'accueil (JPEG 1920×1080, ~8 Mo
  /// une fois décompressé). `null` = taille du fichier, palier large.
  static int? get hubBackgroundCacheWidth {
    switch (current) {
      case BoxRamTier.tight:
        return 960;
      case BoxRamTier.balanced:
        return 1280;
      case BoxRamTier.roomy:
        return null;
    }
  }

  /// Le fond est sous un voile : sur une petite box, le filtre bas
  /// suffit et coûte moins au redimensionnement.
  static FilterQuality get hubBackgroundFilter =>
      paintFocusGlow ? FilterQuality.medium : FilterQuality.low;

  /// Fondu d'un logo. Au palier large on garde la durée déjà choisie
  /// par l'écran ([whenRoomy]). En dessous, apparition nette : un
  /// fondu, c'est une couche d'opacité par logo qui entre à l'écran.
  static Duration logoFade(Duration whenRoomy) =>
      paintFocusGlow ? whenRoomy : Duration.zero;

  /// Même arithmétique que l'ancien `_tuneImageCacheForRam`.
  static BoxRamTier classify({required int totalMb, required bool lowRam}) {
    if (lowRam || (totalMb > 0 && totalMb <= 1024)) {
      return BoxRamTier.tight;
    }
    if (totalMb <= 2048) return BoxRamTier.balanced;
    return BoxRamTier.roomy;
  }

  /// Nombre d'images et octets du cache Flutter pour ce palier.
  /// Serré : 60 images / 24 Mo. Équilibré : 120 / 48 Mo.
  /// Large : 220 / 96 Mo.
  static ({int count, int bytes}) imageCacheFor(BoxRamTier tier) {
    switch (tier) {
      case BoxRamTier.tight:
        return (count: 60, bytes: 24 << 20);
      case BoxRamTier.balanced:
        return (count: 120, bytes: 48 << 20);
      case BoxRamTier.roomy:
        return (count: 220, bytes: 96 << 20);
    }
  }

  static void note({required int totalMb, required bool lowRam}) {
    if (debugTier != null) return;
    tier = classify(totalMb: totalMb, lowRam: lowRam);
  }

  /// Applique le cache d'images du palier courant. Le boot a déjà
  /// posé un défaut (90 images / 40 Mo) ; cet appel le remplace
  /// seulement quand la RAM a été lue.
  static void applyImageCache() {
    final ({int count, int bytes}) slot = imageCacheFor(current);
    PaintingBinding.instance.imageCache
      ..maximumSize = slot.count
      ..maximumSizeBytes = slot.bytes;
  }

  /// Lecture Android (`getMemoryInfo`). Échec ou réponse vide :
  /// on ne change rien (défaut serré, cache du boot inchangé).
  static Future<void> load() async {
    if (debugTier != null) return;
    try {
      final Object? raw = await _channel.invokeMethod<Object?>('getMemoryInfo');
      if (raw is! Map) return;
      final int totalMb = (raw['totalMb'] as num?)?.toInt() ?? 0;
      final bool lowRam = raw['lowRam'] == true;
      note(totalMb: totalMb, lowRam: lowRam);
      applyImageCache();
    } catch (_) {
      // Plugin absent (test, PC) ou binder occupé : palier prudent.
    }
  }

  /// PC : pas de lecture de RAM. Le focus reprend le palier large.
  /// Le cache d'images reste celui du boot (la lecture a échoué,
  /// on n'élargit pas en silence).
  static void useDesktop() {
    if (debugTier != null) return;
    tier = BoxRamTier.roomy;
  }

  @visibleForTesting
  static void resetForTest() {
    debugTier = null;
    tier = BoxRamTier.tight;
  }
}
