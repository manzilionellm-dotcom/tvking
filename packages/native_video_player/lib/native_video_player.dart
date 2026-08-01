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
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Infos APPAREIL fournies par le natif (canal 'native_video_player/info').
/// Sert au mode « petite box » : l'app s'allège toute seule sur un Fire TV
/// Stick / box 1 Go (caches réduits, aperçus plus prudents).
class NativeDeviceInfo {
  const NativeDeviceInfo._();
  static const MethodChannel _channel =
      MethodChannel('native_video_player/info');

  /// RAM totale (octets) + drapeau « appareil à faible RAM » d'Android.
  /// Ne lève JAMAIS : en cas d'échec (plateforme sans plugin, test), renvoie
  /// des valeurs neutres (pas de mode léger à tort).
  static Future<({int totalMem, bool isLowRamDevice})> query() async {
    try {
      final Map<dynamic, dynamic>? m = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('deviceInfo')
          .timeout(const Duration(milliseconds: 600));
      return (
        totalMem: (m?['totalMem'] as int?) ?? 0,
        isLowRamDevice: (m?['isLowRamDevice'] as bool?) ?? false,
      );
    } catch (_) {
      return (totalMem: 0, isLowRamDevice: false);
    }
  }
}

/// Piste (audio ou sous-titres) exposée par le lecteur natif.
class TrackInfo {
  const TrackInfo({
    required this.label,
    required this.selected,
    this.language = '',
  });
  final String label;
  final bool selected;

  /// Code langue BRUT remonté par ExoPlayer (fr, eng, spa…) — vide si
  /// le flux ne le déclare pas. L'UI le traduit en libellé localisé.
  final String language;
}

/// Pilote un lecteur natif et publie son état. Un controller = une vue.
class NativeVideoController extends ChangeNotifier {
  NativeVideoController({this.initialUrl, this.preview = false});

  /// URL jouée dès que la vue native est prête (1re chaîne).
  final String? initialUrl;

  /// Mode APERÇU (vignette muette) : le lecteur natif utilise des tampons
  /// RÉDUITS (~8 Mo au lieu de 18-32 Mo) — indispensable sur les box à
  /// faible RAM quand un aperçu tourne en plus de l'UI.
  final bool preview;

  MethodChannel? _channel;
  String? _pendingUrl;
  String? _pendingUserAgent;
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

  /// Détail de la DERNIÈRE erreur native (diagnostic terrain — le message brut
  /// est souvent vague ; `errorCodeName` est une constante Media3 stable, ex.
  /// "ERROR_CODE_IO_BAD_HTTP_STATUS", qui distingue un codec non supporté
  /// d'un timeout réseau sans lire le logcat de la box). `null` tant qu'aucune
  /// erreur fatale n'est survenue.
  String? lastErrorMessage;
  String? lastErrorCodeName;
  int? lastErrorCode;

  /// Message de la CAUSE RACINE (souvent plus parlant que le message de
  /// façade — ex. « Response code: 456 » y transporte le code HTTP réel).
  /// Déjà émis par le natif (NativeVideoView.kt) ; capturé ici pour le
  /// journal des échecs de lecture (Boîte noire des Réglages).
  String? lastErrorCauseMessage;

  /// Flux terminé (rare en direct, mais on reconnecte si ça arrive).
  bool isEnded = false;

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

  /// Rattachement FORCÉ pour les tests (aucune PlatformView en widget test) :
  /// permet de vérifier le contrat « setUrl ⇒ la lecture repart » sur un
  /// MethodChannel simulé.
  @visibleForTesting
  void attachForTest(int viewId) => _attach(viewId);

  /// Appelé par [NativeVideoView] quand la PlatformView native est créée.
  void _attach(int viewId) {
    if (_attached || _disposed) return;
    _attached = true;
    final MethodChannel ch = MethodChannel('native_video_player/$viewId');
    _channel = ch;
    ch.setMethodCallHandler(_onNativeCall);
    final String? url = _pendingUrl ?? initialUrl;
    if (url != null) {
      // La signature (User-Agent) demandée AVANT le rattachement est rejouée
      // ici — sinon un setUrl(url, userAgent:…) émis pendant la création de la
      // PlatformView (cas de l'aperçu « En direct ») perdrait sa signature.
      ch.invokeMethod<void>('setUrl', <String, dynamic>{
        'url': url,
        if (_pendingUserAgent != null) 'userAgent': _pendingUserAgent,
      });
      // Même garantie qu'au setUrl direct : une URL en attente rejouée au
      // rattachement doit PARTIR (un pause() antérieur ne doit pas geler la
      // vue toute neuve).
      ch.invokeMethod<void>('play');
    }
    // Réapplique le volume voulu dès le rattachement (utile en multi-vue où une
    // tuile démarre muette).
    if (_volume != 1.0) {
      ch.invokeMethod<void>('setVolume', <String, dynamic>{'volume': _volume});
    }
    // Idem pour la vitesse (VOD) : demandée avant le rattachement → rejouée.
    if (playbackSpeed != 1.0) {
      ch.invokeMethod<void>(
          'setSpeed', <String, dynamic>{'speed': playbackSpeed});
    }
    // Idem pour le mode radio (piste vidéo coupée).
    if (!videoEnabled) {
      ch.invokeMethod<void>(
          'setVideoEnabled', <String, dynamic>{'enabled': false});
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
        final Object? args = call.arguments;
        if (args is Map) {
          lastErrorMessage = args['message'] as String?;
          lastErrorCodeName = args['errorCodeName'] as String?;
          lastErrorCode = args['errorCode'] as int?;
          lastErrorCauseMessage = args['causeMessage'] as String?;
        }
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

  /// Décode la liste de pistes remontée par le natif. Public pour les
  /// tests (visibleForTesting) : le format du contrat MethodChannel
  /// (label/language/selected, valeurs manquantes tolérées) est
  /// verrouillé par test — le Kotlin et le Dart doivent rester alignés.
  @visibleForTesting
  static List<TrackInfo> parseTracks(dynamic raw) => _parseTracks(raw);

  static List<TrackInfo> _parseTracks(dynamic raw) {
    if (raw is! List) return <TrackInfo>[];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> t) => TrackInfo(
              label: (t['label'] as String?) ?? '',
              language: (t['language'] as String?) ?? '',
              selected: (t['selected'] as bool?) ?? false,
            ))
        .toList();
  }

  /// Charge (ou recharge) une URL : zap vers une autre chaîne, ou reconnexion
  /// sur la MÊME URL. Réinitialise l'état d'affichage (logo le temps que la
  /// nouvelle 1re trame arrive).
  /// [userAgent] : signature de lecteur CUSTOM pour cet appel (diagnostic
  /// multi-UA — "ça marche sur IBO, pas chez nous"). `null` = signature par
  /// défaut du plugin natif. Ignoré si la vue n'est pas encore attachée (le
  /// 1er channel n'a jamais besoin d'un diagnostic, il n'a pas encore pu
  /// échouer).
  ///
  /// [silent] = RÉCUPÉRATION INVISIBLE (façon Netflix) : on recharge le flux
  /// SANS remettre [firstFrame] à false → l'écran garde la dernière image
  /// affichée (la SurfaceView native la conserve) au lieu de repasser par
  /// l'écran de marque plein écran. À utiliser pour les reconnexions et les
  /// bascules de variante d'URL sur la MÊME chaîne — jamais pour un zap.
  void setUrl(String url, {String? userAgent, bool silent = false}) {
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
    buffered = Duration.zero;
    duration = Duration.zero;
    if (!_disposed) notifyListeners();
    if (_channel != null) {
      _channel!.invokeMethod<void>('setUrl', <String, dynamic>{
        'url': url,
        if (userAgent != null) 'userAgent': userAgent,
      });
      // REPRISE DE LECTURE (bug terrain 2026-08-01, photos box) : `pause()`
      // pose `playWhenReady = false` côté ExoPlayer, et `setUrl` ne le
      // relève PAS — un `pause()` suivi d'un `setUrl` (exactement ce que
      // fait l'aperçu quand on zappe : il met en pause pendant la
      // navigation puis charge la nouvelle chaîne) préparait le média
      // sans jamais le jouer : aucune 1re image, cadre d'aperçu figé,
      // « l'image ne vient plus en direct ». Charger une URL veut TOUJOURS
      // dire la jouer — on le redemande explicitement.
      _channel!.invokeMethod<void>('play');
    } else {
      // Pas encore rattaché : on jouera ça (URL + signature) à l'attach.
      _pendingUrl = url;
      _pendingUserAgent = userAgent;
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

  /// Sélectionne la [index]-ième piste audio (ordre de [audioTracks]).
  void setAudioTrack(int index) => _channel?.invokeMethod<void>(
      'setAudioTrack', <String, dynamic>{'index': index});

  /// Sélectionne la [index]-ième piste de sous-titres, ou -1 = désactivés.
  void setSubtitleTrack(int index) => _channel?.invokeMethod<void>(
      'setSubtitleTrack', <String, dynamic>{'index': index});

  /// Piste VIDÉO active ? false = MODE RADIO (le son continue, le décodeur
  /// vidéo est coupé). Mémorisé pour être rejoué au rattachement.
  bool videoEnabled = true;

  /// Coupe/rétablit la piste vidéo (mode radio TV). Le son n'est jamais
  /// interrompu ; ExoPlayer relance le décodage vidéo au rétablissement.
  void setVideoEnabled(bool enabled) {
    videoEnabled = enabled;
    _channel?.invokeMethod<void>(
        'setVideoEnabled', <String, dynamic>{'enabled': enabled});
    if (!_disposed) notifyListeners();
  }

  /// Vitesse de lecture courante (1.0 = normale). Pilotée par l'UI VOD ;
  /// mémorisée ici pour être rejouée si la PlatformView se rattache.
  double playbackSpeed = 1.0;

  /// Règle la vitesse de lecture (ExoPlayer setPlaybackSpeed — le pitch
  /// audio est corrigé par Media3). Bornée [0.25, 3.0]. Le DIRECT n'a pas
  /// à l'utiliser (l'UI ne la propose qu'en VOD, et le zap remet 1.0).
  void setPlaybackSpeed(double speed) {
    playbackSpeed = speed.clamp(0.25, 3.0);
    _channel?.invokeMethod<void>(
        'setSpeed', <String, dynamic>{'speed': playbackSpeed});
    if (!_disposed) notifyListeners();
  }

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
class NativeVideoView extends StatefulWidget {
  const NativeVideoView({super.key, required this.controller});

  final NativeVideoController controller;

  static const String _viewType = 'native_video_player/view';

  @override
  State<NativeVideoView> createState() => _NativeVideoViewState();
}

class _NativeVideoViewState extends State<NativeVideoView>
    with WidgetsBindingObserver {
  NativeVideoController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// DÉFENSE DE FOND (terrain 2026-07-16) : « on quitte l'app TV et
  /// l'audio continue en arrière-plan ». Ce plugin n'équipe QUE les
  /// surfaces TV (le mobile lit via media_kit et garde son mode
  /// « Écouteurs » volontaire) — sur TV, quitter l'app = silence.
  /// PAUSE UNIQUEMENT, jamais de reprise automatique : chaque écran
  /// décide lui-même de reprendre au retour (lecteur → play, aperçu →
  /// ré-armement). Couvre aussi toute surface future qui oublierait
  /// son propre observer.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        controller.pause();
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: NativeVideoView._viewType,
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
          viewType: NativeVideoView._viewType,
          layoutDirection: TextDirection.ltr,
          // Transporte le mode APERÇU jusqu'au natif (tampons réduits).
          creationParams: <String, dynamic>{'preview': controller.preview},
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
