// =========================================================
//  native_video_player.dart — API Dart du lecteur natif SurfaceView
// =========================================================
//  Expose :
//    - NativeVideoController : pilote le lecteur + expose l'état (position,
//      buffering, playing, erreur, fin, 1re trame). C'est un ChangeNotifier :
//      l'écran s'y abonne avec addListener et appelle setState.
//    - NativeVideoView : le widget à poser dans l'arbre. Il crée une
//      PlatformView Android en HYBRID COMPOSITION (la SurfaceView native est
//      rendue dans une vraie fenêtre, pas dans une texture Flutter) puis
//      rattache le controller à l'instance native.
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Pilote un lecteur natif et publie son état. Un controller = une vue.
class NativeVideoController extends ChangeNotifier {
  NativeVideoController({this.initialUrl});

  /// URL jouée dès que la vue native est prête (1re chaîne).
  final String? initialUrl;

  MethodChannel? _channel;
  String? _pendingUrl;
  double _volume = 1.0; // multi-vue : 0 = muet (tuile inactive), 1 = son actif
  bool _attached = false;
  bool _disposed = false;

  /// Position de lecture courante (avance → « pas gelé », pour le watchdog).
  Duration position = Duration.zero;

  /// Durée totale du média — connue UNIQUEMENT pour un contenu SEEKABLE
  /// (film / VOD / catch-up). Reste `Duration.zero` pour un DIRECT (durée
  /// « infinie » côté ExoPlayer) → l'UI n'affiche la barre de progression /
  /// n'autorise le seek QUE si `duration > 0`.
  Duration duration = Duration.zero;

  /// Avance déjà CHARGÉE en mémoire tampon (façon YouTube) : jusqu'où le
  /// lecteur a bufferisé EN AVANT de [position]. Sert à dessiner la « ligne
  /// grise » de la barre VOD. Reste `Duration.zero` pour un direct.
  Duration buffered = Duration.zero;

  /// Raccourci : le média est-il seekable (film/VOD) ? Faux pour le direct.
  bool get isSeekable => duration > Duration.zero;

  /// True tant qu'ExoPlayer met en mémoire tampon (STATE_BUFFERING).
  bool isBuffering = true;

  /// True quand le lecteur joue effectivement (playWhenReady && ready).
  bool isPlaying = false;

  /// Passe à true au 1er onRenderedFirstFrame → on peut masquer le logo.
  bool firstFrame = false;

  /// Erreur de lecture remontée par ExoPlayer (l'écran déclenche _recover).
  bool hasError = false;

  /// Flux terminé (rare en direct, mais on reconnecte si ça arrive).
  bool isEnded = false;

  /// Appelé par [NativeVideoView] quand la PlatformView native est créée.
  void _attach(int viewId) {
    if (_attached || _disposed) return;
    _attached = true;
    final MethodChannel ch = MethodChannel('native_video_player/$viewId');
    _channel = ch;
    ch.setMethodCallHandler(_onNativeCall);
    final String? url = _pendingUrl ?? initialUrl;
    if (url != null) {
      ch.invokeMethod<void>('setUrl', <String, dynamic>{'url': url});
    }
    // Réapplique le volume voulu dès le rattachement (utile en multi-vue où une
    // tuile démarre muette).
    if (_volume != 1.0) {
      ch.invokeMethod<void>('setVolume', <String, dynamic>{'volume': _volume});
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'buffering':
        isBuffering = call.arguments as bool;
      case 'playing':
        isPlaying = call.arguments as bool;
      case 'position':
        position = Duration(milliseconds: call.arguments as int);
      case 'duration':
        // Émise par le natif quand la durée est connue (média seekable).
        final int ms = call.arguments as int;
        duration = ms > 0 ? Duration(milliseconds: ms) : Duration.zero;
      case 'buffered':
        // Avance chargée (ligne grise). Le natif ne l'émet que pour un média
        // seekable ; on ignore une valeur négative par prudence.
        final int bms = call.arguments as int;
        buffered = bms > 0 ? Duration(milliseconds: bms) : Duration.zero;
      case 'firstFrame':
        firstFrame = true;
        isBuffering = false;
      case 'ended':
        isEnded = true;
      case 'error':
        hasError = true;
    }
    if (!_disposed) notifyListeners();
    return null;
  }

  /// Charge (ou recharge) une URL : zap vers une autre chaîne, ou reconnexion
  /// sur la MÊME URL. Réinitialise l'état d'affichage (logo le temps que la
  /// nouvelle 1re trame arrive).
  void setUrl(String url) {
    hasError = false;
    isEnded = false;
    isBuffering = true;
    firstFrame = false;
    position = Duration.zero;
    buffered = Duration.zero;
    if (!_disposed) notifyListeners();
    if (_channel != null) {
      _channel!.invokeMethod<void>('setUrl', <String, dynamic>{'url': url});
    } else {
      _pendingUrl = url; // pas encore rattaché : on jouera ça à l'attach.
    }
  }

  void play() => _channel?.invokeMethod<void>('play');

  void pause() => _channel?.invokeMethod<void>('pause');

  /// Va à une position absolue (film / VOD / catch-up). Sans effet sur un
  /// direct non-seekable. On borne à [0, duration] pour ne jamais demander
  /// une position invalide à ExoPlayer. Met à jour `position` localement
  /// tout de suite → la barre répond instantanément (avant l'écho natif).
  void seekTo(Duration target) {
    if (_channel == null) return;
    Duration t = target;
    if (t < Duration.zero) t = Duration.zero;
    if (duration > Duration.zero && t > duration) t = duration;
    position = t;
    if (!_disposed) notifyListeners();
    _channel!.invokeMethod<void>('seekTo', <String, dynamic>{'ms': t.inMilliseconds});
  }

  /// Avance/recule de [delta] (Netflix : ±10 s) depuis la position courante.
  void seekBy(Duration delta) => seekTo(position + delta);

  /// Règle le volume (0.0 = muet, 1.0 = plein). Sert à la MULTI-VUE : seule la
  /// tuile active garde le son. Conservé pour ré-application au rattachement.
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _channel?.invokeMethod<void>('setVolume', <String, dynamic>{'volume': _volume});
  }

  @override
  void dispose() {
    _disposed = true;
    _channel?.invokeMethod<void>('dispose');
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}

/// Widget qui héberge la SurfaceView native plein écran.
///
/// On utilise [PlatformViewLink] + [PlatformViewsService.initExpensiveAndroidView]
/// = HYBRID COMPOSITION : la SurfaceView est composée dans une vraie fenêtre
/// Android (pas re-routée par une texture Flutter). C'est ce qui débloque le
/// rendu des trames HEVC sur les box où la texture restait noire.
class NativeVideoView extends StatelessWidget {
  const NativeVideoView({super.key, required this.controller});

  final NativeVideoController controller;

  static const String _viewType = 'native_video_player/view';

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (BuildContext context, PlatformViewController controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        );
      },
      onCreatePlatformView: (PlatformViewCreationParams params) {
        final AndroidViewController viewController =
            PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        viewController
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(controller._attach)
          ..create();
        return viewController;
      },
    );
  }
}
