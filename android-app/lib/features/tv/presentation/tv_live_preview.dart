// =========================================================
//  tv_live_preview.dart — Aperçu vidéo de la chaîne focalisée (écran Direct)
// =========================================================
//  Petite fenêtre de PRÉ-VISUALISATION à droite de la liste des chaînes,
//  comme sur les lecteurs de box classiques :
//    • moteur : le plugin local `native_video_player` (ExoPlayer/Media3 sur
//      SurfaceView native) — EXACTEMENT le même que le plein écran, donc la
//      même qualité d'image ;
//    • repli : le logo de la chaîne reste affiché tant que la 1re image n'est
//      pas rendue, et si le flux échoue on reste sur le logo (jamais de cadre
//      noir vide).
//
//  RÈGLE DE FLUIDITÉ (25/09/2026, sourcée — doc Flutter « platform views ») :
//  une vue native en Hybrid Composition « fusionne les threads raster et
//  plateforme, ce qui dégrade le FPS de Flutter ». Tant qu'une SurfaceView est
//  dans l'arbre, TOUTE la liste de gauche défile moins bien. Donc :
//    • pendant le défilement, il n'y a AUCUNE vue native dans l'arbre : on
//      affiche le logo (un simple widget Flutter) ;
//    • la vue native (et son ExoPlayer) n'est CRÉÉE que lorsque le focus est
//      resté immobile [debounce] (1,5 s) ; au prochain changement de chaîne
//      elle est DÉTRUITE immédiatement (flux coupé, mémoire rendue) ;
//    • jamais deux lecteurs d'aperçu en même temps.
//  Coût : ~100-300 ms pour recréer le lecteur à chaque arrêt — invisible,
//  puisqu'on n'attend de toute façon 1,5 s. Gain : défilement à pleine
//  fluidité, et zéro décodage vidéo pendant qu'on zappe dans la liste.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:native_video_player/playback_lease.dart';

import '../../player/data/image_prefs.dart';
import '../../channels/domain/channel.dart';
import '../core/tv_tokens.dart';

class TvLivePreview extends StatefulWidget {
  const TvLivePreview({
    super.key,
    required this.channel,
    this.debounce = const Duration(milliseconds: 1500),
  });

  /// Aperçu actuellement à l'écran (un seul). Le plein écran l'appelle
  /// AVANT de s'ouvrir : on rend le décodeur et la connexion IPTV, sinon
  /// la chaîne plein écran reste noire ou est refusée (1 seule connexion).
  static _TvLivePreviewState? _active;

  static Future<void> releaseActive() async {
    await _active?._releaseNow();
  }

  /// Chaîne à prévisualiser (celle qui a le focus dans la liste).
  final Channel channel;

  /// Temps d'immobilité du focus avant de créer le lecteur d'aperçu.
  final Duration debounce;

  @override
  State<TvLivePreview> createState() => _TvLivePreviewState();
}

class _TvLivePreviewState extends State<TvLivePreview> {
  /// Non-null ⇔ la vue native est dans l'arbre (lecteur vivant).
  NativeVideoController? _ctrl;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    TvLivePreview._active = this;
    _schedule();
  }

  @override
  void didUpdateWidget(covariant TvLivePreview old) {
    super.didUpdateWidget(old);
    if (old.channel.id != widget.channel.id) {
      _stop(); // coupe et DÉTRUIT le lecteur tout de suite (défilement)
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.debounce, _start);
  }

  /// Retire la vue native de l'arbre ET rend le décodeur tout de suite.
  /// (Attendre que Flutter détruise la PlatformView laissait le codec
  /// occupé : l'image suivante était noire ou verte.)
  void _stop() {
    final NativeVideoController? c = _ctrl;
    if (c == null) return;
    _ctrl = null;
    unawaited(c.releaseNative());
    if (mounted) setState(() {});
    // Le notifier est disposé APRÈS la frame : ListenableBuilder retire
    // son écouteur avant. Le faire avant lève en debug.
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  }

  /// Variante attendue, appelée avant d'ouvrir le plein écran.
  Future<void> _releaseNow() async {
    // Même si l'aperçu n'a pas encore démarré : on annule le délai, sinon
    // il créerait un 2e lecteur pendant que le plein écran s'ouvre.
    _timer?.cancel();
    final NativeVideoController? c = _ctrl;
    if (c == null) return;
    _ctrl = null;
    final Future<void> done = c.releaseNative();
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    await done;
  }

  /// Focus immobile depuis [debounce] : on crée UN lecteur pour cette chaîne.
  /// Pas pendant un plein écran : ce second lecteur est la cause du
  /// double son (l'ancien n'était pas encore libéré).
  void _start() {
    if (!mounted || ForegroundPlayback.locked) return;
    final String url = widget.channel.streamUrl;
    if (url.isEmpty) return;
    _stop();
    final NativeVideoController created = NativeVideoController(initialUrl: url);
    setState(() => _ctrl = created);
    unawaited(ImagePrefs.load().then((_) {
      created.setImageEngine(ImagePrefs.engine.wire);
      created.setFrameRateMatch(ImagePrefs.frameRateMatch);
    }));
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (identical(TvLivePreview._active, this)) TvLivePreview._active = null;
    // Enfants déjà démontés (écouteur retiré) : on peut disposer le notifier.
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NativeVideoController? c = _ctrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(TvTokens.rCard),
      child: ColoredBox(
        color: TvTokens.bg,
        child: c == null
            // Défilement / attente : AUCUNE vue native, juste le logo.
            ? _LogoFallback(channel: widget.channel)
            : Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  NativeVideoView(controller: c),
                  // Logo par-dessus tant qu'aucune image n'est rendue (ou en erreur).
                  ListenableBuilder(
                    listenable: c,
                    builder: (BuildContext context, Widget? _) {
                      final bool showLogo = !c.firstFrame || c.hasError;
                      return showLogo
                          ? _LogoFallback(channel: widget.channel)
                          : const SizedBox.shrink();
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

/// Logo centré sur fond sombre (repli visuel de l'aperçu).
class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final String? url = channel.logoUrl;
    return ColoredBox(
      color: TvTokens.tile,
      child: Center(
        child: (url == null || url.isEmpty)
            ? const Icon(Icons.live_tv_rounded, size: 56, color: TvTokens.mutedDim)
            : Padding(
                padding: const EdgeInsets.all(28),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  // Décodage borné (l'aperçu fait ~470×265 px à l'écran) :
                  // un logo 2000×2000 ne coûte plus 16 Mo de RAM.
                  cacheWidth: 480,
                  errorBuilder: (_, __, ___) => const Icon(Icons.live_tv_rounded,
                      size: 56, color: TvTokens.mutedDim),
                ),
              ),
      ),
    );
  }
}
