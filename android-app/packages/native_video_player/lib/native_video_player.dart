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

import 'playback_lease.dart';
import 'spoken_track.dart';

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
    this.roleFlags = 0,
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

  /// Drapeaux de rôle Media3 (commentaire, audiodescription…). 0 = inconnu.
  final int roleFlags;
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

  /// Coupe le son tout de suite (volume 0 + arrêt). Un autre lecteur
  /// vient de prendre la place. Ne relance rien.
  void silence() {}

  /// Compresseur « voix claire ». Désactivé par défaut. Le PC (libmpv)
  /// n'a pas ce traitement : l'implémentation vide est voulue.
  void setClearVoice(bool enabled) {}

  /// Moteur vidéo (`hardware`, `software`, `ffmpeg`). Le PC ignore :
  /// libmpv a son propre décodeur.
  void setImageEngine(String engine) {}

  /// Caler la fréquence de l'écran sur le flux. Ignoré hors Android.
  void setFrameRateMatch(bool enabled) {}

  /// Contraste léger. Ignoré hors Android, et refusé sur la box tant
  /// que le filtre quitterait la Surface.
  void setLightContrast(bool enabled) {}

  /// Le widget qui affiche la vidéo.
  Widget buildView(BuildContext context);
  void dispose();
}

/// Pilote un lecteur natif et publie son état. Un controller = une vue.
class NativeVideoController extends ChangeNotifier {
  NativeVideoController({
    this.initialUrl,
    String? preferredAudio,
    this.openAsVod = false,
  }) {
    if (preferredAudio != null && preferredAudio.isNotEmpty) {
      _preferredAudio = preferredAudio;
    }
    _leaseId = audiblePlayers.register(_silenceFromPeer);
    final NativeVideoBackend Function()? f = backendFactory;
    if (f != null && !Platform.isAndroid) {
      _backend = f()..bind(this);
      final String? url = initialUrl;
      if (url != null) {
        audible = true;
        audiblePlayers.claim(_leaseId);
        _backend!.open(_openArgs(url));
      }
    }
  }

  /// Fabrique du moteur hors Android (null sur la box : lecteur natif).
  static NativeVideoBackend Function()? backendFactory;

  /// Langue audio de l'application (« fr », « en »…). Lue à chaque
  /// ouverture si l'appelant n'en passe pas une plus précise (film).
  static String? appAudioLanguage;

  /// Diagnostic du son envoyé par le lecteur natif à chaque ouverture de
  /// chaîne (et en cas de coupures) : l'app le range dans sa boîte noire.
  /// Plusieurs lignes séparées par « \n ». Null = ignoré.
  static void Function(String diagnostic)? onAudioDiagnostic;

  /// Sonde PCM du diagnostic. Faux par défaut : le processeur natif
  /// reste inactif (NOT_SET), le son ne change pas.
  static bool audioProbeEnabled = false;

  /// Réessayer FFmpeg à la prochaine chaîne même après un repli box.
  /// Faux par défaut : le drapeau de repli n'est pas touché.
  static bool keepFfmpegAudio = false;

  /// Essayer le décodeur AAC de la box à la prochaine chaîne.
  /// Faux par défaut : l'AAC reste sur FFmpeg.
  static bool preferPlatformAac = false;

  /// Interrupteur de REPLI du correctif « repli AAC par chaîne ».
  /// Faux par défaut : une panne FFmpeg n'envoie à la box QUE la chaîne
  /// concernée. Vrai = ancien comportement (toutes les chaînes du
  /// processus passent à la box après une seule panne).
  static bool sessionWideFallback = false;

  /// Repli du correctif « focus audio » : vrai = Media3 gère le focus
  /// (et baisse le son à 20 % quand une autre app le demande, le son
  /// « dans un trou »). Faux par défaut : Zuno gère, sans baisse.
  static bool androidAudioFocus = false;

  /// Arrière-plan : vrai = ancienne pause (décodeur et sortie son gardés
  /// vivants hors de l'app). Faux par défaut : arrêt propre, réouverture
  /// au retour.
  static bool backgroundPauseOnly = false;

  /// Passage d'une chaîne à l'autre : vrai = on n'attend pas que
  /// l'AudioTrack précédent soit rendu (deux pistes peuvent se
  /// chevaucher, l'ancien défaut). Faux par défaut : on attend.
  static bool immediateHandoff = false;

  /// Essai « Type : film / musique / parole ». `off` par défaut :
  /// le lecteur dit « film » (ou « parole » si la voix claire est
  /// allumée), comme avant. `movie`, `music` ou `speech` seulement
  /// quand on tourne le bouton du diagnostic.
  static String audioContentType = 'off';

  static final List<MethodChannel> _audioFlagChannels = <MethodChannel>[];

  /// Pousse les réglages audio vers les vues déjà ouvertes. Sans vue,
  /// le prochain [_attach] les enverra avant l'URL.
  static void pushAudioDiagFlags() {
    for (final MethodChannel ch in List<MethodChannel>.of(_audioFlagChannels)) {
      ch.invokeMethod<void>('setAudioProbe', audioProbeEnabled);
      ch.invokeMethod<void>('setKeepFfmpeg', keepFfmpegAudio);
      ch.invokeMethod<void>('setPreferPlatformAac', preferPlatformAac);
      ch.invokeMethod<void>('setSessionWideFallback', sessionWideFallback);
      ch.invokeMethod<void>('setAndroidFocus', androidAudioFocus);
      ch.invokeMethod<void>('setImmediateHandoff', immediateHandoff);
      ch.invokeMethod<void>('setAudioContentType', audioContentType);
    }
  }

  /// Tous les controllers vivants. Un zap ou une ouverture « prend »
  /// le son et fait taire les autres avant de démarrer.
  static final ExclusiveAudio audiblePlayers = ExclusiveAudio();

  NativeVideoBackend? _backend;

  late final int _leaseId;

  /// true tant que CE controller a le droit de sortir du son.
  bool audible = false;

  /// URL jouée dès que la vue native est prête (1re chaîne).
  final String? initialUrl;

  /// Fichier fini (film, enregistrement) : la reprise après coupure ou
  /// après un retour dans l'app repart de la position, pas du bord du direct.
  final bool openAsVod;

  MethodChannel? _channel;
  String? _pendingUrl;
  bool _attached = false;
  bool _disposed = false;

  /// Génération du dernier [setUrl]. Les événements natifs d'une génération
  /// précédente (zap très rapide) sont ignorés jusqu'à l'accusé `ack`.
  /// Sans ça, la position de l'ancienne chaîne faisait croire que la nouvelle
  /// jouait, ou le logo restait devant une image déjà à l'écran.
  int _epoch = 0;

  /// Dernier ack reçu. Tant qu'il ne rattrape pas [_epoch], on n'applique
  /// pas les événements. Égal à [_epoch] tout de suite sur PC (pas d'ack natif).
  int _ackedEpoch = 0;

  /// true une fois le natif libéré : [dispose] ne le libère pas une 2e fois.
  bool _nativeReleased = false;

  /// true après [ChangeNotifier.dispose] : on ne le rappelle pas.
  bool _notifierClosed = false;

  /// Langue demandée pour CETTE lecture (film) ou, à défaut, celle de l'app.
  String? _preferredAudio;

  /// true dès que la personne choisit une piste à la main.
  /// L'automatisme ne la contredit plus jusqu'au prochain [setUrl].
  bool _userPickedAudio = false;

  /// true après le premier choix automatique de cette lecture.
  bool _audioAutoDone = false;

  String? get preferredAudio => _preferredAudio ?? appAudioLanguage;

  bool get _acceptEvents => _backend != null || _ackedEpoch == _epoch;

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

  /// true : le natif garde la dernière image. L'écran ne pose pas
  /// de panneau opaque par-dessus (ce panneau faisait un écran noir
  /// à chaque coupure).
  bool holdFrame = false;

  /// true : le natif a déjà programmé une ré-ouverture (attente
  /// croissante). L'écran ne doit pas en lancer une autre.
  bool nativeRetrying = false;

  /// Flux terminé (rare en direct, mais on reconnecte si ça arrive).
  bool isEnded = false;

  /// Durée totale (films / épisodes). `Duration.zero` = inconnue (direct).
  Duration duration = Duration.zero;

  /// Pistes audio + sous-titres du fichier en cours (films / épisodes).
  List<NativeTrack> tracks = const <NativeTrack>[];

  /// Texte du sous-titre à afficher maintenant ('' = rien).
  String cues = '';

  /// Moteur vidéo en cours (`hardware` / `software` / `ffmpeg`).
  String imageEngineWire = 'hardware';

  /// Le .so sait décoder la vidéo. Faux avec le binaire audio de la v104.
  bool ffmpegVideoReady = false;

  /// Le matériel accepte un filtre de contraste sans quitter la Surface.
  /// Faux dans cette version.
  bool contrastHardware = false;

  /// Dernier appui « FFmpeg » refusé parce que la vidéo n'est pas dans le .so.
  bool engineRejectedFfmpeg = false;

  /// Plus aucun moteur vidéo n'a donné d'image. L'écran s'arrête
  /// (pas de reconnexion qui remettrait le même décodeur).
  bool engineExhausted = false;

  /// Nombre de réouvertures faites par le natif (repli décodeur).
  /// L'écran remet son délai « image figée » à chaque cran.
  int reopenCount = 0;

  /// Nom du décodeur vidéo créé (pour l'écran, pas une mesure de qualité).
  String videoDecoderName = '';

  String _imageEngine = 'hardware';
  bool _frameRateMatch = false;

  // Paramètres du dernier setUrl (rejoués si la vue native arrive après).
  Map<String, dynamic>? _pendingArgs;

  /// Appelé par [NativeVideoView] quand la PlatformView native est créée.
  void _attach(int viewId) {
    if (_attached || _disposed) return;
    _attached = true;
    final MethodChannel ch = MethodChannel('native_video_player/$viewId');
    _channel = ch;
    ch.setMethodCallHandler(_onNativeCall);
    _audioFlagChannels.add(ch);
    // Avant l'URL : le premier décodeur est déjà le bon (pas un
    // second démarrage si le choix n'est pas le matériel).
    ch.invokeMethod<void>('setEngine', _imageEngine);
    ch.invokeMethod<void>('setFrameRateMatch', _frameRateMatch);
    // Diagnostic audio. Tout est faux par défaut : sonde inactive,
    // AAC toujours sur FFmpeg, pas d'essai du décodeur de la box.
    ch.invokeMethod<void>('setAudioProbe', audioProbeEnabled);
    ch.invokeMethod<void>('setKeepFfmpeg', keepFfmpegAudio);
    ch.invokeMethod<void>('setPreferPlatformAac', preferPlatformAac);
    ch.invokeMethod<void>('setSessionWideFallback', sessionWideFallback);
    ch.invokeMethod<void>('setAndroidFocus', androidAudioFocus);
    ch.invokeMethod<void>('setImmediateHandoff', immediateHandoff);
    ch.invokeMethod<void>('setAudioContentType', audioContentType);
    final String? url = _pendingUrl ?? initialUrl;
    if (url != null) {
      audible = true;
      audiblePlayers.claim(_leaseId);
      ch.invokeMethod<void>(
          'setUrl', _pendingArgs ?? _openArgs(url));
    }
  }

  /// Arguments d'ouverture. La langue part toujours avec, pour que le
  /// natif choisisse la voix avant la première image.
  Map<String, dynamic> _openArgs(String url) {
    final String? lang = preferredAudio;
    return <String, dynamic>{
      'url': url,
      'epoch': _epoch,
      if (openAsVod) 'vod': true,
      if (lang != null && lang.isNotEmpty) 'preferredAudio': lang,
    };
  }

  /// Un AUTRE lecteur a pris le son. On se tait tout de suite et on
  /// invalide la session : un callback tardif ne doit plus passer
  /// pour « la chaîne en cours ».
  void _silenceFromPeer() {
    if (_disposed) return;
    audible = false;
    _epoch++;
    _backend?.silence();
    _channel?.invokeMethod<void>('silence');
    if (!_disposed) notifyListeners();
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    applyBackendEvent(call.method, call.arguments);
    return null;
  }

  /// Applique un événement d'état (natif Android OU moteur PC).
  void applyBackendEvent(String method, Object? arguments) {
    if (_disposed) return;
    // Accusé du setUrl en cours. Un ack d'un zap déjà remplacé est ignoré,
    // sinon les événements de l'ancienne chaîne passeraient.
    if (method == 'ack') {
      final int got = arguments is num ? arguments.toInt() : -1;
      if (got == _epoch) _ackedEpoch = got;
      return;
    }
    // Ces messages décrivent le moteur, pas une image de l'ancienne
    // chaîne : on les prend même entre deux zap.
    if (method == 'engine' || method == 'imageCaps' || method == 'contrast') {
      _readEngine(arguments);
      if (!_disposed) notifyListeners();
      return;
    }
    if (!_acceptEvents) return;
    final _Ev call = _Ev(method, arguments);
    switch (call.method) {
      case 'buffering':
        isBuffering = call.arguments as bool;
      case 'playing':
        isPlaying = call.arguments as bool;
      case 'position':
        {
          // Certaines box ne rappellent pas « firstFrame » quand on réutilise
          // la même surface (zap). La lecture n'avance que si ExoPlayer joue
          // vraiment : on retire alors le logo, sinon il masquerait une chaîne
          // déjà lancée (l'écran a l'air bloqué). On ne le fait pas à 0 ms :
          // ce n'est pas encore une image.
          final int ms = call.arguments as int;
          position = Duration(milliseconds: ms);
          if (isPlaying && ms > 0 && !firstFrame) {
            firstFrame = true;
            isBuffering = false;
          }
        }
      case 'firstFrame':
        firstFrame = true;
        isBuffering = false;
        holdFrame = false;
        nativeRetrying = false;
      case 'ended':
        isEnded = true;
      case 'error':
        hasError = true;
        nativeRetrying = false;
      case 'holdFrame':
        holdFrame = call.arguments == true;
        if (holdFrame) isBuffering = false;
      case 'reconnecting':
        nativeRetrying = call.arguments == true;
      case 'duration':
        duration = Duration(milliseconds: call.arguments as int);
      case 'cues':
        cues = (call.arguments as String?) ?? '';
      case 'reopen':
        firstFrame = false;
        isBuffering = true;
        hasError = false;
        reopenCount++;
      case 'engineExhausted':
        engineExhausted = true;
        isBuffering = false;
      case 'videoDecoder':
        videoDecoderName = (call.arguments as String?) ?? '';
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
                roleFlags: (t['roleFlags'] as int?) ?? 0,
              ),
        ];
        _autoAudio();
      case 'audioDiag':
        // Diagnostic du son (ce qui entre, qui décode, ce qui sort) : ne
        // change rien à l'état du lecteur, on le passe à l'app (boîte noire).
        final String line = (call.arguments as String?) ?? '';
        if (line.isNotEmpty) onAudioDiagnostic?.call(line);
        return;
    }
    if (!_disposed) notifyListeners();
  }

  /// Premier paquet de pistes : on force la voix de la langue, pas le
  /// commentaire. Une seule fois, pour ne pas contredire un choix manuel
  /// ni relancer le décodeur à chaque image.
  void _autoAudio() {
    if (_userPickedAudio || _audioAutoDone) return;
    _audioAutoDone = true;
    final List<SpokenTrack> audio = <SpokenTrack>[
      for (final NativeTrack track in tracks)
        if (track.isAudio)
          SpokenTrack(
            group: track.group,
            index: track.index,
            language: track.language,
            label: track.label,
            channels: track.channels,
            selected: track.selected,
            roleFlags: track.roleFlags,
          ),
    ];
    final SpokenTrack? pick = chooseSpokenTrack(audio, preferredAudio);
    if (pick == null) return;
    for (final NativeTrack track in tracks) {
      if (track.isAudio && track.group == pick.group && track.index == pick.index) {
        _sendTrack(track);
        return;
      }
    }
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
    bool keepPicture = false,
  }) {
    if (_disposed) return;
    // On prend le son AVANT d'ouvrir : les autres lecteurs sont coupés
    // tout de suite (volume 0 + arrêt), puis seulement on charge.
    audible = true;
    audiblePlayers.claim(_leaseId);
    // Nouvelle génération : les événements encore en route (ancienne chaîne)
    // seront ignorés jusqu'à l'ack natif de CELLE-CI.
    _epoch++;
    _userPickedAudio = false;
    _audioAutoDone = false;
    // Une langue explicite (film) remplace celle de l'app pour CETTE
    // lecture. Sans argument, on revient à la langue de l'app.
    if (preferredAudio != null && preferredAudio.isNotEmpty) {
      _preferredAudio = preferredAudio;
    } else {
      _preferredAudio = null;
    }
    final String? lang = _preferredAudio ?? appAudioLanguage;
    hasError = false;
    engineExhausted = false;
    engineRejectedFfmpeg = false;
    isEnded = false;
    nativeRetrying = false;
    // Reconnexion de la MÊME lecture : on ne remet pas firstFrame à
    // false. Sinon l'écran croit qu'il n'y a plus d'image et pose un
    // panneau opaque (noir) le temps du nouveau flux.
    final bool keep = keepPicture && (firstFrame || holdFrame);
    if (keep) {
      holdFrame = true;
      isBuffering = false;
    } else {
      holdFrame = false;
      isBuffering = true;
      firstFrame = false;
      position = startAt;
      duration = Duration.zero;
      tracks = const <NativeTrack>[];
      cues = '';
    }
    notifyListeners();
    final Map<String, dynamic> args = <String, dynamic>{
      'url': url,
      'epoch': _epoch,
      if (vod) 'vod': true,
      if (startAt > Duration.zero) 'startMs': startAt.inMilliseconds,
      if (lang != null && lang.isNotEmpty) 'preferredAudio': lang,
      if (preferredText != null) 'preferredText': preferredText,
    };
    if (_backend != null) {
      // PC : pas d'ack. On accepte les événements tout de suite.
      _ackedEpoch = _epoch;
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
  ///
  /// Un choix audio manuel bloque l'automatisme jusqu'au prochain zap.
  void selectTrack(NativeTrack t) {
    if (t.isAudio) _userPickedAudio = true;
    _sendTrack(t);
  }

  void _sendTrack(NativeTrack t) {
    if (_backend != null) {
      _backend!.selectTrack(t);
      return;
    }
    _channel?.invokeMethod<void>(
        'selectTrack', <String, dynamic>{'group': t.group, 'index': t.index});
  }

  /// Voix claire (compresseur). Le natif l'applique au prochain décodage
  /// PCM. Le passthrough (AC-3 vers une barre de son) n'est pas compressé :
  /// Media3 ne traite pas ces flux en PCM.
  void setClearVoice(bool enabled) {
    if (_backend != null) {
      _backend!.setClearVoice(enabled);
      return;
    }
    _channel?.invokeMethod<void>('setClearVoice', enabled);
  }

  /// `hardware`, `software` ou `ffmpeg`. Mémorisé pour la vue pas
  /// encore créée, envoyé tout de suite si elle l'est.
  void setImageEngine(String engine) {
    final String wire = engine.isEmpty ? 'hardware' : engine;
    _imageEngine = wire;
    imageEngineWire = wire;
    if (_backend != null) {
      _backend!.setImageEngine(wire);
      return;
    }
    _channel?.invokeMethod<void>('setEngine', wire);
  }

  void setFrameRateMatch(bool enabled) {
    _frameRateMatch = enabled;
    if (_backend != null) {
      _backend!.setFrameRateMatch(enabled);
      return;
    }
    _channel?.invokeMethod<void>('setFrameRateMatch', enabled);
  }

  void setLightContrast(bool enabled) {
    if (_backend != null) {
      _backend!.setLightContrast(enabled);
      return;
    }
    _channel?.invokeMethod<void>('setContrast', enabled);
  }

  void _readEngine(Object? arguments) {
    if (arguments is! Map) return;
    final String? name = arguments['name'] as String? ?? arguments['engine'] as String?;
    if (name != null && name.isNotEmpty) {
      imageEngineWire = name;
      _imageEngine = name;
    }
    if (arguments.containsKey('ffmpegVideo')) {
      ffmpegVideoReady = arguments['ffmpegVideo'] == true;
    }
    if (arguments.containsKey('contrastHardware')) {
      contrastHardware = arguments['contrastHardware'] == true;
    }
    engineRejectedFfmpeg = arguments['rejected'] == 'ffmpeg';
  }

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

  /// App en arrière-plan (Home, multitâche) : ARRÊT, pas pause. Le natif
  /// rend le décodeur, l'AudioTrack et le focus audio. Hors Android, une
  /// pause suffit.
  void suspendForBackground() =>
      _backend != null ? _backend!.pause() : _channel?.invokeMethod<void>('suspend');

  /// Retour au premier plan après [suspendForBackground] : la chaîne est
  /// rouverte au direct (un film, à sa position), comme un zap.
  void resumeFromBackground() =>
      _backend != null ? _backend!.play() : _channel?.invokeMethod<void>('resume');

  /// Libère le décodeur natif et ATTEND qu'il ait rendu la surface.
  ///
  /// À appeler avant d'ouvrir un autre lecteur (l'aperçu, puis le plein
  /// écran). Une box bas de gamme n'a souvent qu'UN décodeur matériel :
  /// le second reste noir, et un abonnement à 1 connexion refuse la chaîne.
  /// Le [ChangeNotifier] reste vivant : le widget retire son écouteur avant
  /// [dispose].
  Future<void> releaseNative() async {
    if (_nativeReleased) return;
    _nativeReleased = true;
    _disposed = true;
    audible = false;
    audiblePlayers.unregister(_leaseId);
    _backend?.dispose();
    final MethodChannel? ch = _channel;
    _channel = null;
    if (ch != null) _audioFlagChannels.remove(ch);
    ch?.setMethodCallHandler(null);
    if (ch == null) return;
    try {
      await ch.invokeMethod<void>('dispose');
    } catch (e) {
      // La vue a pu partir en même temps : la libération Kotlin est
      // idempotente, ce n'est pas une panne de lecture.
      if (kDebugMode) debugPrint('[NativeVideo] libération: $e');
    }
  }

  @override
  void dispose() {
    if (_notifierClosed) return;
    _notifierClosed = true;
    _disposed = true;
    audible = false;
    if (!_nativeReleased) {
      audiblePlayers.unregister(_leaseId);
      _nativeReleased = true;
      _backend?.dispose();
      final MethodChannel? ch = _channel;
      _channel = null;
      if (ch != null) _audioFlagChannels.remove(ch);
      ch?.setMethodCallHandler(null);
      ch?.invokeMethod<void>('dispose');
    }
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
