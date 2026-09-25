// =========================================================
//  tv_live_preview.dart — Aperçu vidéo de la chaîne focalisée (écran Direct)
// =========================================================
//  Petite fenêtre de PRÉ-VISUALISATION à droite de la liste des chaînes,
//  comme sur les lecteurs de box classiques :
//    • moteur : le plugin local `native_video_player` (ExoPlayer/Media3 sur
//      SurfaceView native) — EXACTEMENT le même que le plein écran, donc la
//      même qualité d'image ;
//    • anti-rebond : le flux ne s'ouvre que ~600 ms après que le focus s'est
//      posé sur une chaîne → zapper vite dans la liste n'ouvre aucune
//      connexion pour les chaînes traversées ;
//    • UNE seule vue native, réutilisée : changer de chaîne = `setUrl`, jamais
//      deux lecteurs d'aperçu en même temps ;
//    • repli : le logo de la chaîne reste affiché tant que la 1re image n'est
//      pas rendue, et si le flux échoue on reste sur le logo (jamais de cadre
//      noir vide).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../channels/domain/channel.dart';
import '../core/tv_tokens.dart';

class TvLivePreview extends StatefulWidget {
  const TvLivePreview({
    super.key,
    required this.channel,
    this.debounce = const Duration(milliseconds: 600),
  });

  /// Chaîne à prévisualiser (celle qui a le focus dans la liste).
  final Channel channel;

  /// Délai avant d'ouvrir le flux après un changement de chaîne.
  final Duration debounce;

  @override
  State<TvLivePreview> createState() => _TvLivePreviewState();
}

class _TvLivePreviewState extends State<TvLivePreview> {
  NativeVideoController? _ctrl;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant TvLivePreview old) {
    super.didUpdateWidget(old);
    if (old.channel.id != widget.channel.id) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.debounce, _start);
  }

  void _start() {
    if (!mounted) return;
    final String url = widget.channel.streamUrl;
    if (url.isEmpty) return;
    if (_ctrl == null) {
      // 1re ouverture : le contrôleur joue l'URL dès que la vue native est prête.
      setState(() => _ctrl = NativeVideoController(initialUrl: url));
    } else {
      _ctrl!.setUrl(url);
    }
    _ctrl!.play();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (c != null) NativeVideoView(controller: c),
            // Logo par-dessus tant qu'aucune image n'est rendue (ou en erreur).
            if (c == null)
              _LogoFallback(channel: widget.channel)
            else
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
                  errorBuilder: (_, __, ___) => const Icon(Icons.live_tv_rounded,
                      size: 56, color: TvTokens.mutedDim),
                ),
              ),
      ),
    );
  }
}
