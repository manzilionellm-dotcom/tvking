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

  /// Le codec du flux n'est PAS décodable sur cet appareil (ex. H.265/HEVC sans
  /// décodeur matériel). Distinct de [hasError] : réessayer la MÊME chaîne ne
  /// changera rien → l'écran affiche « Format non supporté » plutôt que de
  /// tenter des reconnexions en boucle.
  bool unsupportedCodec = false;

  /// Détails techniques du dernier échec de décodage (modèle d'appareil,
  /// version Android, codec demandé, décodeurs matériels disponibles). Affichés
  /// en petit sous le message d'erreur ET loggués pour le diagnostic à distance.
  Map<String, Object?>? diagnostics;

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
    applyNativeEvent(call.method, call.arguments);
    if (!_disposed) notifyListeners();
    return null;
  }

  /// Applique un évènement natif à l'état (SANS notifier). Isolé du
  /// MethodChannel pour être testable directement (cf. test du controller).
  @visibleForTesting
  void applyNativeEvent(String method, Object? arguments) {
    switch (method) {
      case 'buffering':
        isBuffering = arguments as bool;
      case 'playing':
        isPlaying = arguments as bool;
      case 'position':
        position = Duration(milliseconds: arguments as int);
      case 'firstFrame':
        firstFrame = true;
        isBuffering = false;
      case 'ended':
        isEnded = true;
      case 'unsupportedCodec':
        // Codec non décodable : on marque l'erreur ET le drapeau dédié pour que
        // l'écran montre « Format non supporté » au lieu de reconnecter à vide.
        unsupportedCodec = true;
        hasError = true;
        if (arguments is Map) {
          diagnostics = arguments.map<String, Object?>(
              (Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v));
        }
      case 'error':
        hasError = true;
    }
  }

  /// Charge (ou recharge) une URL : zap vers une autre chaîne, ou reconnexion
  /// sur la MÊME URL. Réinitialise l'état d'affichage (logo le temps que la
  /// nouvelle 1re trame arrive).
  void setUrl(String url) {
    hasError = false;
    unsupportedCodec = false;
    diagnostics = null;
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
