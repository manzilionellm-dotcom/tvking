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

/// Piste (audio ou sous-titres) exposée par le lecteur natif.
class TrackInfo {
  const TrackInfo({required this.label, required this.selected});
  final String label;
  final bool selected;
}

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

  /// Durée totale connue (VOD / replay / enregistrement) ; zéro en live.
  Duration duration = Duration.zero;

  /// Pistes audio / sous-titres disponibles (remplies par le natif).
  List<TrackInfo> audioTracks = <TrackInfo>[];
  List<TrackInfo> textTracks = <TrackInfo>[];

  /// Taille réelle de la vidéo (pour les formats d'image). Null tant
  /// qu'aucune trame n'a été décodée.
  int? videoWidth;
  int? videoHeight;

  /// Ratio réel de la vidéo (ex : 1.78 pour du 16:9), null si inconnu.
  double? get videoAspectRatio =>
      (videoWidth != null && videoHeight != null && videoHeight! > 0)
          ? videoWidth! / videoHeight!
          : null;

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
        duration = Duration(milliseconds: call.arguments as int);
      case 'firstFrame':
        firstFrame = true;
        isBuffering = false;
      case 'ended':
        isEnded = true;
      case 'error':
        hasError = true;
      case 'videoSize':
        final Map<dynamic, dynamic> m = call.arguments as Map<dynamic, dynamic>;
        videoWidth = m['width'] as int?;
        videoHeight = m['height'] as int?;
      case 'tracks':
        final Map<dynamic, dynamic> m = call.arguments as Map<dynamic, dynamic>;
        audioTracks = _parseTracks(m['audio']);
        textTracks = _parseTracks(m['text']);
    }
    if (!_disposed) notifyListeners();
    return null;
  }

  static List<TrackInfo> _parseTracks(dynamic raw) {
    if (raw is! List) return <TrackInfo>[];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> t) => TrackInfo(
              label: (t['label'] as String?) ?? '',
              selected: (t['selected'] as bool?) ?? false,
            ))
        .toList();
  }

  /// Charge (ou recharge) une URL : zap vers une autre chaîne, ou reconnexion
  /// sur la MÊME URL. Réinitialise l'état d'affichage (logo le temps que la
  /// nouvelle 1re trame arrive).
  ///
  /// [silent] = RÉCUPÉRATION INVISIBLE (façon Netflix) : on recharge le flux
  /// SANS remettre [firstFrame] à false → l'écran garde la dernière image
  /// affichée (la SurfaceView native la conserve) au lieu de repasser par
  /// l'écran de marque plein écran. À utiliser pour les reconnexions et les
  /// bascules de variante d'URL sur la MÊME chaîne — jamais pour un zap.
  void setUrl(String url, {bool silent = false}) {
    hasError = false;
    isEnded = false;
    isBuffering = true;
    if (!silent) {
      firstFrame = false;
      // Nouvelle chaîne : les pistes / la taille vidéo seront renvoyées par
      // le natif pour le nouveau média.
      audioTracks = <TrackInfo>[];
      textTracks = <TrackInfo>[];
      videoWidth = null;
      videoHeight = null;
    }
    position = Duration.zero;
    duration = Duration.zero;
    if (!_disposed) notifyListeners();
    if (_channel != null) {
      _channel!.invokeMethod<void>('setUrl', <String, dynamic>{'url': url});
    } else {
      _pendingUrl = url; // pas encore rattaché : on jouera ça à l'attach.
    }
  }

  void play() => _channel?.invokeMethod<void>('play');

  void pause() => _channel?.invokeMethod<void>('pause');

  /// Avance/retour (replay, VOD, enregistrement). Sans effet en live pur.
  void seekTo(Duration position) => _channel?.invokeMethod<void>(
      'seekTo', <String, dynamic>{'ms': position.inMilliseconds});

  /// Sélectionne la [index]-ième piste audio (ordre de [audioTracks]).
  void setAudioTrack(int index) => _channel?.invokeMethod<void>(
      'setAudioTrack', <String, dynamic>{'index': index});

  /// Sélectionne la [index]-ième piste de sous-titres, ou -1 = désactivés.
  void setSubtitleTrack(int index) => _channel?.invokeMethod<void>(
      'setSubtitleTrack', <String, dynamic>{'index': index});

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
