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
  bool _attached = false;
  bool _disposed = false;

  /// Position de lecture courante (avance → « pas gelé », pour le watchdog).
  Duration position = Duration.zero;

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
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'buffering':
        isBuffering = call.arguments as bool;
      case 'playing':
        isPlaying = call.arguments as bool;
      case 'position':
        position = Duration(milliseconds: call.arguments as int);
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
    if (!_disposed) notifyListeners();
    if (_channel != null) {
      _channel!.invokeMethod<void>('setUrl', <String, dynamic>{'url': url});
    } else {
      _pendingUrl = url; // pas encore rattaché : on jouera ça à l'attach.
    }
  }

  void play() => _channel?.invokeMethod<void>('play');

  void pause() => _channel?.invokeMethod<void>('pause');

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
