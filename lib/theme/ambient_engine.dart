// =========================================================
//  ambient_engine.dart — Moteur de COULEUR AMBIANTE (UI « salon »)
// =========================================================
//  Service SINGLETON qui calcule la palette d'ambiance de l'app à partir du
//  contenu, façon Netflix / Apple TV :
//
//    • SOURCE A (navigation) : couleur dominante du LOGO de la chaîne mise
//      en avant (palette_generator, déjà utilisé par le hero du Direct).
//      Résultat en cache LRU (clé = URL du logo, 200 entrées max) → un logo
//      n'est JAMAIS analysé deux fois.
//    • SOURCE B (lecture) : le lecteur pousse périodiquement une FRAME
//      encodée (PNG/JPEG) via [ingestVideoFrame]. Elle est réduite à
//      64×36 px par le décodeur natif, puis QUANTIFIÉE DANS UN ISOLATE
//      (jamais sur le thread UI). ⚠️ Le moteur ne sait PAS d'où vient la
//      frame : c'est le lecteur MOBILE (media_kit.screenshot) qui l'appelle.
//      Le build TV n'embarque pas media_kit (règle absolue) — sur TV, seule
//      la Source A alimente l'ambiance. AUCUN import media_kit ici.
//
//  GARDE-FOUS (lisibilité + fluidité, non négociables) :
//    • CLAMP HSL avant toute émission : saturation ≤ 0.65, luminosité entre
//      0.15 et 0.45 pour les FONDS → le texte garde un contraste ≥ 4.5:1
//      même sur un logo rouge vif ou blanc.
//    • DÉBOUNCE : au plus UNE palette émise toutes les 2 s (la dernière
//      reçue gagne), et les variations ΔE < 10 sont IGNORÉES → pas de
//      « pompage » de couleur sur une scène stable.
//    • ÉCHEC (logo absent, frame noire, réseau) → on NE change RIEN : la
//      palette courante reste, l'UI ne « flashe » jamais. [reset] ramène la
//      palette Maison Noir (les consommateurs animent la transition).
//
//  Les consommateurs s'abonnent à [palette] (ValueNotifier) et animent
//  eux-mêmes les changements (TweenAnimationBuilder 1000 ms, Phase 2).
// =========================================================
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:palette_generator/palette_generator.dart';

import '../core/theme/app_colors.dart';

/// Les 4 couleurs d'ambiance consommées par l'UI.
@immutable
class AmbientPalette {
  const AmbientPalette({
    required this.primary,
    required this.glow,
    required this.scrim,
    required this.accent,
  });

  /// Palette de repos : l'identité Maison Noir (matte black + or). C'est le
  /// point de départ ET le repli en cas d'échec d'extraction.
  factory AmbientPalette.maisonNoir() => AmbientPalette(
        primary: AppColors.surface,
        glow: AppColors.accentMuted,
        scrim: AppColors.voidSurface,
        accent: AppColors.accent,
      );

  /// Teinte de FOND dominante (déjà clampée sombre — le noir reste maître).
  final Color primary;

  /// Halo lumineux (derrière un logo, bordure Ambilight) — jamais un fond.
  final Color glow;

  /// Voile de dégradé (haut d'écran → noir) — la plus sombre des quatre.
  final Color scrim;

  /// Accent à MÉLANGER avec l'or de la marque (barres de sélection, bouton).
  final Color accent;

  @override
  bool operator ==(Object other) =>
      other is AmbientPalette &&
      other.primary == primary &&
      other.glow == glow &&
      other.scrim == scrim &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(primary, glow, scrim, accent);
}

/// Mesures de la DERNIÈRE extraction — affichées par l'overlay AMBIENT_DEBUG.
@immutable
class AmbientDebugStats {
  const AmbientDebugStats({
    required this.source,
    required this.elapsedMs,
    required this.emitted,
  });

  /// D'où vient la palette : 'logo', 'logo (cache)', 'vidéo', 'repli'.
  final String source;

  /// Durée de l'extraction (0 pour un cache hit).
  final int elapsedMs;

  /// `false` = calculée mais RETENUE par le débounce / ΔE (pas de pompage).
  final bool emitted;
}

class AmbientEngine {
  AmbientEngine._();
  static final AmbientEngine instance = AmbientEngine._();

  /// Coupé par le réglage « Ambiance dynamique » (Phase 5). `false` = le
  /// moteur ignore toutes les sources et reste sur la palette courante.
  bool enabled = true;

  /// LA sortie du moteur : l'UI s'y abonne et ANIME chaque changement.
  final ValueNotifier<AmbientPalette> palette =
      ValueNotifier<AmbientPalette>(AmbientPalette.maisonNoir());

  /// Luminance moyenne (0..1) de la dernière frame vidéo analysée — consommée
  /// par le Cinema Mode (Phase 3) pour doser l'atténuation. `null` tant
  /// qu'aucune frame n'a été reçue.
  final ValueNotifier<double?> videoLuminance = ValueNotifier<double?>(null);

  /// Télémétrie de la dernière extraction (overlay AMBIENT_DEBUG uniquement).
  final ValueNotifier<AmbientDebugStats?> debugStats =
      ValueNotifier<AmbientDebugStats?>(null);

  // ---- Source A : logo de la chaîne mise en avant ------------------------

  /// Cache LRU des palettes par URL de logo. LinkedHashMap conserve l'ordre
  /// d'insertion : on ré-insère à chaque hit → le premier élément est
  /// toujours le moins récemment utilisé (évincé au-delà de 200).
  final LinkedHashMap<String, AmbientPalette> _logoCache =
      LinkedHashMap<String, AmbientPalette>();
  static const int kLogoCacheMax = 200;

  /// Coalescence des appels pendant un défilement rapide : l'extraction ne
  /// part que 300 ms après le DERNIER focusLogo — les chaînes traversées ne
  /// déclenchent aucun travail (même esprit que l'anti-rebond de l'aperçu).
  Timer? _focusDebounce;
  int _focusSeq = 0;

  /// Signale que la chaîne mise en avant a changé. Sans effet si [enabled]
  /// est faux ou si l'URL est vide (on GARDE la palette courante — pas de
  /// flash). L'extraction réelle est coalescée (300 ms) et mise en cache.
  void focusLogo(String? logoUrl) {
    if (!enabled) return;
    final String? url = (logoUrl != null && logoUrl.isNotEmpty) ? logoUrl : null;
    if (url == null) return;
    final int seq = ++_focusSeq;
    // Cache hit → émission immédiate (0 ms), pas de timer.
    final AmbientPalette? cached = _logoCache.remove(url);
    if (cached != null) {
      _logoCache[url] = cached; // ré-insertion = « récemment utilisé »
      _focusDebounce?.cancel();
      _maybeEmit(cached, source: 'logo (cache)', elapsedMs: 0);
      return;
    }
    _focusDebounce?.cancel();
    _focusDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_extractFromLogo(url, seq));
    });
  }

  Future<void> _extractFromLogo(String url, int seq) async {
    final Stopwatch sw = Stopwatch()..start();
    PaletteGenerator? pal;
    try {
      // CachedNetworkImageProvider = le MÊME cache disque/mémoire que les
      // tuiles de chaînes → le logo est déjà là, aucun re-téléchargement.
      pal = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url),
        size: const Size(100, 100), // downscale = quantification rapide
        maximumColorCount: 12,
        timeout: const Duration(seconds: 4),
      );
    } catch (_) {
      // Logo illisible / réseau : on ne change RIEN (repli gracieux).
      return;
    }
    if (seq != _focusSeq) return; // le focus est déjà reparti ailleurs
    final Color? dominant = pal.dominantColor?.color ??
        pal.vibrantColor?.color ??
        pal.mutedColor?.color;
    if (dominant == null) return; // image vide/transparente → rien
    final Color vibrant = pal.vibrantColor?.color ??
        pal.lightVibrantColor?.color ??
        dominant;
    final Color dark = pal.darkMutedColor?.color ??
        pal.darkVibrantColor?.color ??
        dominant;
    final AmbientPalette p =
        compose(dominant: dominant, vibrant: vibrant, dark: dark);
    _logoCache[url] = p;
    if (_logoCache.length > kLogoCacheMax) {
      _logoCache.remove(_logoCache.keys.first); // évince le plus ancien
    }
    _maybeEmit(p, source: 'logo', elapsedMs: sw.elapsedMilliseconds);
  }

  // ---- Source B : frame vidéo (poussée par le lecteur MOBILE) ------------

  bool _frameBusy = false;

  /// Analyse une frame ENCODÉE (PNG/JPEG). Le décodage est fait par le codec
  /// natif directement à 64×36 px (targetWidth/Height → on ne décode jamais
  /// la frame pleine taille), puis la quantification part dans un ISOLATE
  /// via [compute] : le thread UI ne fait que ~2 allers-retours async.
  Future<void> ingestVideoFrame(Uint8List encodedImage) async {
    if (!enabled || _frameBusy) return; // jamais 2 analyses en parallèle
    _frameBusy = true;
    final Stopwatch sw = Stopwatch()..start();
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        encodedImage,
        targetWidth: 64,
        targetHeight: 36,
        allowUpscaling: false,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ByteData? bytes =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();
      if (bytes == null) return;
      final Int32List res = await compute(
          quantizeRgbaForAmbient, bytes.buffer.asUint8List());
      if (res[0] == 0) return; // frame vide (tout transparent/noir pur)
      videoLuminance.value = res[3] / 1000.0;
      final AmbientPalette p = compose(
        dominant: Color(res[0]),
        vibrant: Color(res[1]),
        dark: Color(res[2]),
      );
      _maybeEmit(p, source: 'vidéo', elapsedMs: sw.elapsedMilliseconds);
    } catch (_) {
      // Frame illisible → on garde la palette courante (pas de flash).
    } finally {
      _frameBusy = false;
    }
  }

  // ---- Émission : débounce 2 s + seuil ΔE --------------------------------

  /// Écart perceptuel minimal (CIE76) pour qu'un changement soit émis.
  static const double kMinDeltaE = 10;

  /// Intervalle minimal entre deux émissions.
  static const Duration kEmitInterval = Duration(seconds: 2);

  DateTime? _lastEmitAt;
  AmbientPalette? _pendingPalette;
  String _pendingSource = '';
  Timer? _pendingTimer;

  void _maybeEmit(AmbientPalette next,
      {required String source, required int elapsedMs}) {
    // Variation imperceptible (ΔE < 10 sur la teinte de fond) → retenue :
    // pas de pompage de couleur quand la scène / le logo est stable.
    if (deltaE76(palette.value.primary, next.primary) < kMinDeltaE) {
      debugStats.value = AmbientDebugStats(
          source: source, elapsedMs: elapsedMs, emitted: false);
      return;
    }
    final DateTime now = clock.now(); // clock = testable (fake_async)
    final DateTime? last = _lastEmitAt;
    if (last == null || now.difference(last) >= kEmitInterval) {
      _pendingTimer?.cancel();
      _pendingPalette = null;
      _lastEmitAt = now;
      palette.value = next;
      debugStats.value = AmbientDebugStats(
          source: source, elapsedMs: elapsedMs, emitted: true);
      return;
    }
    // Trop tôt : on mémorise la DERNIÈRE palette reçue et on l'émettra à la
    // fin de la fenêtre de 2 s (la plus récente gagne, jamais de rafale).
    _pendingPalette = next;
    _pendingSource = source;
    debugStats.value = AmbientDebugStats(
        source: source, elapsedMs: elapsedMs, emitted: false);
    _pendingTimer ??= Timer(kEmitInterval - now.difference(last), () {
      _pendingTimer = null;
      final AmbientPalette? pending = _pendingPalette;
      _pendingPalette = null;
      if (pending == null) return;
      // Re-passe par le seuil ΔE (la palette courante a pu changer).
      if (deltaE76(palette.value.primary, pending.primary) < kMinDeltaE) {
        return;
      }
      _lastEmitAt = clock.now();
      palette.value = pending;
      debugStats.value = AmbientDebugStats(
          source: _pendingSource, elapsedMs: 0, emitted: true);
    });
  }

  /// Soumet une palette au pipeline débounce/ΔE comme le ferait une source
  /// réelle — UNIQUEMENT pour les tests (le débounce est intestable via les
  /// sources publiques : logo = réseau, frame = codec natif).
  @visibleForTesting
  void debugSubmit(AmbientPalette next, {String source = 'test'}) {
    _maybeEmit(next, source: source, elapsedMs: 0);
  }

  /// Retour IMMÉDIAT à l'identité Maison Noir (sortie d'écran, réglage OFF).
  /// Les consommateurs animent la transition (1 s) → aucun flash.
  void reset() {
    _focusDebounce?.cancel();
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingPalette = null;
    _focusSeq++;
    _lastEmitAt = clock.now();
    videoLuminance.value = null;
    palette.value = AmbientPalette.maisonNoir();
    debugStats.value =
        const AmbientDebugStats(source: 'repli', elapsedMs: 0, emitted: true);
  }

  // ---- Briques PURES (testées unitairement) ------------------------------

  /// Assemble la palette finale à partir des 3 couleurs extraites, chacune
  /// clampée pour son rôle (fond sombre, halo, accent).
  static AmbientPalette compose({
    required Color dominant,
    required Color vibrant,
    required Color dark,
  }) =>
      AmbientPalette(
        // FOND : règle de contraste du cahier des charges (S ≤ 0.65,
        // L ∈ [0.15, 0.45]) — le texte clair reste lisible dessus.
        primary: clampSurface(dominant),
        // VOILE : encore plus sombre — il se fond dans le noir de la marque.
        scrim: clampSurface(dark, minLightness: 0.08, maxLightness: 0.22,
            maxSaturation: 0.55),
        // HALO : peut être plus lumineux (jamais un fond de texte).
        glow: clampSurface(vibrant, minLightness: 0.30, maxLightness: 0.60),
        // ACCENT : mélangé à l'or par l'UI — borné pour rester chaleureux.
        accent: clampSurface(vibrant, minLightness: 0.35, maxLightness: 0.65),
      );

  /// CLAMP HSL de sécurité : désature et assombrit/éclaircit une couleur
  /// extraite pour qu'elle respecte son rôle (défauts = règle des FONDS :
  /// saturation ≤ 0.65, luminosité ∈ [0.15, 0.45] → contraste ≥ 4.5:1 avec
  /// le texte clair de la marque).
  static Color clampSurface(
    Color c, {
    double maxSaturation = 0.65,
    double minLightness = 0.15,
    double maxLightness = 0.45,
  }) {
    final HSLColor hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation(math.min(hsl.saturation, maxSaturation))
        .withLightness(hsl.lightness.clamp(minLightness, maxLightness))
        .withAlpha(1.0)
        .toColor();
  }

  /// Écart perceptuel CIE76 (distance euclidienne dans l'espace Lab).
  /// ~2 = imperceptible, ~10 = nettement visible. Suffisant pour un seuil
  /// anti-pompage (les formules plus récentes, CIEDE2000, coûtent cher pour
  /// un gain inutile ici).
  static double deltaE76(Color a, Color b) {
    final List<double> la = _lab(a);
    final List<double> lb = _lab(b);
    final double dl = la[0] - lb[0];
    final double da = la[1] - lb[1];
    final double db = la[2] - lb[2];
    return math.sqrt(dl * dl + da * da + db * db);
  }

  /// sRGB → CIE Lab (illuminant D65). Étapes classiques :
  /// délinéarisation inverse (gamma) → matrice XYZ → f(t) → Lab.
  static List<double> _lab(Color c) {
    double lin(double ch) => ch <= 0.04045
        ? ch / 12.92
        : math.pow((ch + 0.055) / 1.055, 2.4).toDouble();
    final double r = lin(c.r), g = lin(c.g), b = lin(c.b);
    // Matrice sRGB→XYZ (D65), normalisée par le blanc de référence.
    final double x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
    final double y = (0.2126 * r + 0.7152 * g + 0.0722 * b);
    final double z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
    double f(double t) => t > 0.008856
        ? math.pow(t, 1 / 3).toDouble()
        : (7.787 * t) + (16 / 116);
    final double fx = f(x), fy = f(y), fz = f(z);
    return <double>[116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
  }
}

/// QUANTIFICATION d'une frame RGBA 64×36 — TOP-LEVEL pour être exécutable
/// dans un isolate via [compute] (les closures ne traversent pas les
/// isolates). Histogramme à 4 bits/canal (4096 seaux, ~2300 px) :
///   [0] dominante (ARGB)   — le seau le plus peuplé ;
///   [1] vibrante  (ARGB)   — saturation × poids, la couleur « qui vit » ;
///   [2] sombre    (ARGB)   — le seau peuplé le plus foncé ;
///   [3] luminance moyenne × 1000 (0..1000) — pour le Cinema Mode.
/// Renvoie [0,0,0,0] si la frame est vide (transparente).
Int32List quantizeRgbaForAmbient(Uint8List rgba) {
  final Map<int, List<int>> buckets = <int, List<int>>{}; // clé → [n, Σr, Σg, Σb]
  double lumSum = 0;
  int counted = 0;
  for (int i = 0; i + 3 < rgba.length; i += 4) {
    final int r = rgba[i], g = rgba[i + 1], b = rgba[i + 2], a = rgba[i + 3];
    if (a < 128) continue; // pixels transparents (logos) ignorés
    counted++;
    lumSum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
    final int key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
    final List<int> bucket =
        buckets.putIfAbsent(key, () => <int>[0, 0, 0, 0]);
    bucket[0]++;
    bucket[1] += r;
    bucket[2] += g;
    bucket[3] += b;
  }
  if (counted == 0) return Int32List.fromList(<int>[0, 0, 0, 0]);

  int argbOf(List<int> b) {
    final int n = b[0];
    return 0xFF000000 | ((b[1] ~/ n) << 16) | ((b[2] ~/ n) << 8) | (b[3] ~/ n);
  }

  // (saturation, luminosité) HSL approximées d'un seau moyen — assez précis
  // pour départager vibrant/sombre sans convertir chaque pixel.
  (double, double) satLight(List<int> b) {
    final int n = b[0];
    final double r = (b[1] / n) / 255, g = (b[2] / n) / 255, bl = (b[3] / n) / 255;
    final double hi = math.max(r, math.max(g, bl));
    final double lo = math.min(r, math.min(g, bl));
    final double l = (hi + lo) / 2;
    final double d = hi - lo;
    final double s =
        d == 0 ? 0 : d / (1 - (2 * l - 1).abs()).clamp(1e-6, 1.0);
    return (s, l);
  }

  List<int>? dominant, vibrant, dark;
  double vibrantScore = -1;
  int dominantCount = -1, darkCount = -1;
  for (final List<int> b in buckets.values) {
    final int n = b[0];
    if (n > dominantCount) {
      dominantCount = n;
      dominant = b;
    }
    final (double s, double l) = satLight(b);
    // Vibrante : saturée, ni cramée ni noire, pondérée par sa présence
    // (racine → une petite zone très saturée peut gagner sur un aplat terne).
    if (s >= 0.35 && l >= 0.25 && l <= 0.75) {
      final double score = s * math.sqrt(n.toDouble());
      if (score > vibrantScore) {
        vibrantScore = score;
        vibrant = b;
      }
    }
    if (l <= 0.35 && n > darkCount) {
      darkCount = n;
      dark = b;
    }
  }
  final int domArgb = argbOf(dominant!);
  return Int32List.fromList(<int>[
    domArgb,
    vibrant != null ? argbOf(vibrant) : domArgb,
    dark != null ? argbOf(dark) : domArgb,
    ((lumSum / counted) * 1000).round(),
  ]);
}
