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
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Une piste audio ou de sous-titres proposée par le fichier en cours.
@immutable
class NativeTrack {
  const NativeTrack({
    required this.isAudio,
    required this.group,
    required this.index,
    required this.selected,
    this.language,
    this.label,
    this.channels = 0,
  });

  /// `true` = piste audio, `false` = sous-titres.
  final bool isAudio;

  /// Coordonnées de la piste côté ExoPlayer (pour [NativeVideoController.selectTrack]).
  final int group;
  final int index;

  /// Piste actuellement jouée / affichée.
  final bool selected;

  /// Code langue (ISO 639, ex. « fr », « eng », « zh ») si le fichier le donne.
  final String? language;

  /// Libellé fourni par le fichier (ex. « VF », « English SDH »).
  final String? label;

  /// Nombre de canaux audio (2 = stéréo, 6 = 5.1) ; 0 = inconnu.
  final int channels;
}

/// Moteur de lecture ALTERNATIF, hors Android (Zuno PC / Windows).
///
/// Le lecteur de la box (SurfaceView + ExoPlayer) n'existe que sur Android.
/// Sur PC, l'app enregistre au démarrage une fabrique
/// ([NativeVideoController.backendFactory]) qui fournit un moteur (media_kit /
/// libmpv). Le controller lui délègue alors toutes les commandes, et le moteur
/// renvoie son état via [NativeVideoController.applyBackendEvent] avec EXACTEMENT
/// les mêmes événements que le natif Android (`position`, `duration`,
/// `buffering`, `playing`, `firstFrame`, `ended`, `error`, `tracks`, `cues`).
/// Résultat : Direct, Films et Séries marchent sans une ligne de différence.
abstract class NativeVideoBackend {
  /// Rattache le moteur à son controller (appelé une fois).
  void bind(NativeVideoController controller);

  /// Ouvre une URL (mêmes arguments que le `setUrl` natif : url, vod,
  /// startMs, preferredAudio, preferredText).
  void open(Map<String, dynamic> args);
  void play();
  void pause();
  void seekTo(Duration position);
  void selectTrack(NativeTrack track);
  void disableSubtitles();

  /// Le widget qui affiche la vidéo.
  Widget buildView(BuildContext context);
  void dispose();
}

/// Pilote un lecteur natif et publie son état. Un controller = une vue.
class NativeVideoController extends ChangeNotifier {
  NativeVideoController({this.initialUrl}) {
    final NativeVideoBackend Function()? f = backendFactory;
    if (f != null && !Platform.isAndroid) {
      _backend = f()..bind(this);
      final String? url = initialUrl;
      if (url != null) _backend!.open(<String, dynamic>{'url': url});
    }
  }

  /// Fabrique du moteur hors Android (null sur la box : lecteur natif).
  static NativeVideoBackend Function()? backendFactory;

  NativeVideoBackend? _backend;

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

  /// Durée totale (films / épisodes). `Duration.zero` = inconnue (direct).
  Duration duration = Duration.zero;

  /// Pistes audio + sous-titres du fichier en cours (films / épisodes).
  List<NativeTrack> tracks = const <NativeTrack>[];

  /// Texte du sous-titre à afficher maintenant ('' = rien).
  String cues = '';

  // Paramètres du dernier setUrl (rejoués si la vue native arrive après).
  Map<String, dynamic>? _pendingArgs;

  /// Appelé par [NativeVideoView] quand la PlatformView native est créée.
  void _attach(int viewId) {
    if (_attached || _disposed) return;
    _attached = true;
    final MethodChannel ch = MethodChannel('native_video_player/$viewId');
    _channel = ch;
    ch.setMethodCallHandler(_onNativeCall);
    final String? url = _pendingUrl ?? initialUrl;
    if (url != null) {
      ch.invokeMethod<void>(
          'setUrl', _pendingArgs ?? <String, dynamic>{'url': url});
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    applyBackendEvent(call.method, call.arguments);
    return null;
  }

  /// Applique un événement d'état (natif Android OU moteur PC).
  void applyBackendEvent(String method, Object? arguments) {
    if (_disposed) return;
    final _Ev call = _Ev(method, arguments);
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
      case 'duration':
        duration = Duration(milliseconds: call.arguments as int);
      case 'cues':
        cues = (call.arguments as String?) ?? '';
      case 'tracks':
        final List<dynamic> raw = call.arguments as List<dynamic>;
        tracks = <NativeTrack>[
          for (final dynamic t in raw)
            if (t is Map)
              NativeTrack(
                isAudio: t['type'] == 'audio',
                group: (t['group'] as int?) ?? 0,
                index: (t['index'] as int?) ?? 0,
                selected: t['selected'] == true,
                language: t['language'] as String?,
                label: t['label'] as String?,
                channels: (t['channels'] as int?) ?? 0,
              ),
        ];
    }
    if (!_disposed) notifyListeners();
  }

  /// Charge (ou recharge) une URL : zap vers une autre chaîne, ou reconnexion
  /// sur la MÊME URL. Réinitialise l'état d'affichage (logo le temps que la
  /// nouvelle 1re trame arrive).
  ///
  /// Film / épisode : [vod] = true active la reprise à la même seconde en cas
  /// de coupure, [startAt] démarre directement à une position (« Reprendre »),
  /// [preferredAudio] / [preferredText] choisissent d'office la piste dans la
  /// langue de l'utilisateur si le fichier la propose.
  void setUrl(
    String url, {
    bool vod = false,
    Duration startAt = Duration.zero,
    String? preferredAudio,
    String? preferredText,
  }) {
    hasError = false;
    isEnded = false;
    isBuffering = true;
    firstFrame = false;
    position = startAt;
    duration = Duration.zero;
    tracks = const <NativeTrack>[];
    cues = '';
    if (!_disposed) notifyListeners();
    final Map<String, dynamic> args = <String, dynamic>{
      'url': url,
      if (vod) 'vod': true,
      if (startAt > Duration.zero) 'startMs': startAt.inMilliseconds,
      if (preferredAudio != null) 'preferredAudio': preferredAudio,
      if (preferredText != null) 'preferredText': preferredText,
    };
    if (_backend != null) {
      _backend!.open(args);
    } else if (_channel != null) {
      _channel!.invokeMethod<void>('setUrl', args);
    } else {
      _pendingUrl = url; // pas encore rattaché : on jouera ça à l'attach.
      _pendingArgs = args;
    }
  }

  /// Saute à [to] (bornée à la durée côté natif). Films / épisodes.
  void seekTo(Duration to) {
    final Duration t = to < Duration.zero ? Duration.zero : to;
    position = t;
    if (!_disposed) notifyListeners();
    if (_backend != null) {
      _backend!.seekTo(t);
      return;
    }
    _channel?.invokeMethod<void>(
        'seekTo', <String, dynamic>{'ms': t.inMilliseconds});
  }

  /// Choisit une piste audio ou de sous-titres (cf. [tracks]).
  void selectTrack(NativeTrack t) => _backend != null
      ? _backend!.selectTrack(t)
      : _channel?.invokeMethod<void>(
          'selectTrack', <String, dynamic>{'group': t.group, 'index': t.index});

  /// Coupe les sous-titres.
  void disableSubtitles() {
    cues = '';
    if (!_disposed) notifyListeners();
    if (_backend != null) {
      _backend!.disableSubtitles();
      return;
    }
    _channel?.invokeMethod<void>('disableText');
  }

  void play() => _backend != null ? _backend!.play() : _channel?.invokeMethod<void>('play');

  void pause() => _backend != null ? _backend!.pause() : _channel?.invokeMethod<void>('pause');

  @override
  void dispose() {
    _disposed = true;
    _backend?.dispose();
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
    // Hors Android (PC) : le moteur alternatif fournit sa propre vue.
    final NativeVideoBackend? backend = controller._backend;
    if (backend != null) return backend.buildView(context);
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

/// Petit porteur (méthode, arguments) partagé par le natif et le moteur PC.
class _Ev {
  const _Ev(this.method, this.arguments);
  final String method;
  final Object? arguments;
}
