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

/// Chemin de RENDU vidéo — le correctif « l'image ne vient pas » (terrain) :
/// aucun chemin unique n'affiche l'image sur 100 % des box.
///   • `texture`  : la vidéo est décodée vers une texture Flutter et rendue
///     par le MÊME pipeline que l'interface → partout où l'app s'affiche,
///     l'image vient. DÉFAUT.
///   • `surface`  : PlatformView + SurfaceView Android (chemin historique) —
///     secours pour les box où la texture resterait noire.
/// Le choix est MÉMORISÉ nativement (SharedPreferences) par box ; le widget
/// [NativeVideoView] bascule automatiquement (watchdog « lecture en cours
/// mais aucune 1re trame ») et persiste le chemin qui marche.
class NativeVideoRender {
  const NativeVideoRender._();
  static const MethodChannel _channel =
      MethodChannel('native_video_player/info');

  static const String texture = 'texture';
  static const String surface = 'surface';

  /// Cache mémoire : évite un aller-retour canal à CHAQUE création de vue
  /// (zap, aperçus). Rempli au 1er accès, mis à jour par [setMode].
  static String? _cached;

  /// Chemin de rendu à utiliser (mémorisé pour cette box). Ne lève jamais :
  /// en cas d'échec canal (tests, plateforme sans plugin), défaut `texture`.
  static Future<String> mode() async {
    final String? c = _cached;
    if (c != null) return c;
    try {
      final String? m = await _channel
          .invokeMethod<String>('getRenderMode')
          .timeout(const Duration(milliseconds: 800));
      final String v = (m == surface) ? surface : texture;
      _cached = v;
      return v;
    } catch (_) {
      return texture;
    }
  }

  /// Mémorise [m] comme chemin de rendu de cette box (best-effort).
  static Future<void> setMode(String m) async {
    _cached = m;
    try {
      await _channel.invokeMethod<void>(
          'setRenderMode', <String, dynamic>{'mode': m});
    } catch (_) {
      // Préférence non persistée : la bascule reste valable pour la session.
    }
  }
}

/// Piste (audio ou sous-titres) exposée par le lecteur natif.
class TrackInfo {
  const TrackInfo({
    required this.label,
    required this.selected,
    this.language = '',
    this.codec = '',
    this.sampleRate = -1,
    this.channels = -1,
    this.bitrate = -1,
  });
  final String label;
  final bool selected;

  /// Code langue BRUT remonté par ExoPlayer (fr, eng, spa…) — vide si
  /// le flux ne le déclare pas. L'UI le traduit en libellé localisé.
  final String language;

  //  FORMAT RÉEL DE LA PISTE — ajouté le 30/08/2026.
  //
  //  Signalement : « le son n'est pas HD, on dirait une vieille cassette
  //  radio ». On ne pouvait pas répondre : le lecteur ne remontait que le
  //  libellé et la langue. Or DEUX causes très différentes s'entendent
  //  exactement pareil :
  //     • la SOURCE est pauvre — MP2 96 kb/s en 32 kHz, très courant en
  //       IPTV live. Rien à corriger dans le code : il faut un autre flux ;
  //     • le LECTEUR choisit mal — mauvaise piste, downmix inutile. Là,
  //       on corrige.
  //  Sans ces chiffres, on change du code au hasard. Avec, on sait en
  //  trois secondes.
  //
  //  `-1` = le flux ne déclare pas l'information (Format.NO_VALUE côté
  //  Android). L'affichage doit alors SE TAIRE, pas écrire « -1 ».

  /// Type MIME du codec : `audio/mp4a-latm` (AAC), `audio/ac3`,
  /// `audio/eac3`, `audio/mpeg-L2` (MP2)…
  final String codec;

  /// Fréquence d'échantillonnage en Hz. 48 000 = norme télévision.
  /// 32 000 ou moins = le haut du spectre est coupé, la voix devient
  /// sourde. C'est LE chiffre qui explique l'effet « vieille cassette ».
  final int sampleRate;

  /// Nombre de canaux. 1 = mono, 2 = stéréo, 6 = 5.1.
  final int channels;

  /// Débit en bits par seconde. Souvent absent sur un live MPEG-TS.
  final int bitrate;

  /// Nom court et lisible du codec, pour l'affichage.
  String get codecLabel {
    switch (codec) {
      case 'audio/mp4a-latm':
        return 'AAC';
      case 'audio/ac3':
        return 'Dolby Digital';
      case 'audio/eac3':
      case 'audio/eac3-joc':
        return 'Dolby Digital+';
      case 'audio/vnd.dts':
      case 'audio/vnd.dts.hd':
        return 'DTS';
      case 'audio/mpeg-L2':
        return 'MP2';
      case 'audio/mpeg':
        return 'MP3';
      case 'audio/opus':
        return 'Opus';
      case 'audio/flac':
        return 'FLAC';
      default:
        // Codec inconnu : on montre le sous-type brut plutôt que rien —
        // « eac3-atmos » reste plus parlant qu'une case vide.
        final int i = codec.indexOf('/');
        return i < 0 ? codec : codec.substring(i + 1);
    }
  }

  /// Disposition des canaux, telle qu'un client la comprend.
  String get channelsLabel {
    switch (channels) {
      case 1:
        return 'Mono';
      case 2:
        return 'Stéréo';
      case 6:
        return '5.1';
      case 8:
        return '7.1';
      default:
        return channels > 0 ? '$channels canaux' : '';
    }
  }

  /// Résumé technique — « AAC · 48 kHz · Stéréo · 128 kb/s ».
  /// Chaque morceau INCONNU est simplement omis : mieux vaut une ligne
  /// courte qu'une ligne remplie de valeurs inventées.
  String get formatLabel {
    final List<String> parts = <String>[];
    if (codec.isNotEmpty) parts.add(codecLabel);
    if (sampleRate > 0) {
      final double khz = sampleRate / 1000;
      parts.add(khz == khz.roundToDouble()
          ? '${khz.round()} kHz'
          : '${khz.toStringAsFixed(1)} kHz');
    }
    if (channels > 0) parts.add(channelsLabel);
    if (bitrate > 0) parts.add('${(bitrate / 1000).round()} kb/s');
    return parts.join(' · ');
  }

  /// `true` quand la piste est objectivement de basse qualité. Sert à
  /// signaler au propriétaire que le problème vient de la SOURCE.
  ///
  /// Seuils choisis pour ne PAS crier au loup : 44,1 kHz (qualité CD) et
  /// 96 kb/s en stéréo restent acceptables. En dessous, le haut du
  /// spectre est réellement absent et la voix s'entend « radio AM ».
  bool get isLowQuality =>
      (sampleRate > 0 && sampleRate < 44100) ||
      (bitrate > 0 && bitrate < 96000 && channels <= 2) ||
      channels == 1;
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
  List<String>? _pendingFallbackUrls;
  // Dernière URL/signature demandées — REJOUÉES quand la vue se re-rattache
  // après une bascule de chemin de rendu (texture ⇄ surface) : la lecture
  // reprend seule sur le nouveau chemin, l'écran n'a rien à faire.
  String? _lastUrl;
  String? _lastUserAgent;
  List<String>? _lastFallbackUrls;
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

  /// Texte des sous-titres COURANTS (mode TEXTURE uniquement — sur le chemin
  /// SurfaceView, la SubtitleView native les dessine elle-même). Vide quand
  /// aucun sous-titre n'est à l'écran.
  String subtitleText = '';

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
  void _attach(int viewId) => _attachChannel('native_video_player/$viewId');

  /// TESTS UNIQUEMENT : simule le rattachement de la vue native (ce que fait
  /// la PlatformView à sa création). Verrouille par test le contrat « ce qui
  /// se joue à l'attach » : `_pendingUrl ?? _lastUrl ?? initialUrl`. C'est ce
  /// contrat qui a mordu sur les lignes 1-connexion (19/08) : un controller
  /// créé avec [initialUrl] = l'URL panel DIRECTE la jouait dès l'attach,
  /// AVANT que l'écran ait obtenu le créneau réseau et choisi l'URL du
  /// relais — deux connexions amont se chevauchaient.
  @visibleForTesting
  void debugAttachChannel(String name) => _attachChannel(name);

  /// Rattache ce controller au canal [name] (PlatformView OU lecteur texture).
  void _attachChannel(String name) {
    if (_attached || _disposed) return;
    _attached = true;
    final MethodChannel ch = MethodChannel(name);
    _channel = ch;
    ch.setMethodCallHandler(_onNativeCall);
    final String? url = _pendingUrl ?? _lastUrl ?? initialUrl;
    final String? ua = _pendingUrl != null ? _pendingUserAgent : _lastUserAgent;
    final List<String>? fallbacks =
        _pendingUrl != null ? _pendingFallbackUrls : _lastFallbackUrls;
    if (url != null) {
      // La signature (User-Agent) demandée AVANT le rattachement est rejouée
      // ici — sinon un setUrl(url, userAgent:…) émis pendant la création de la
      // PlatformView (cas de l'aperçu « En direct ») perdrait sa signature.
      // Après une bascule de rendu, c'est _lastUrl qui relance la lecture.
      ch.invokeMethod<void>('setUrl', <String, dynamic>{
        'url': url,
        if (ua != null) 'userAgent': ua,
        if (fallbacks != null && fallbacks.isNotEmpty) 'fallbackUrls': fallbacks,
      });
    }
    // Réapplique le volume voulu dès le rattachement (utile en multi-vue où une
    // tuile démarre muette).
    if (_volume != 1.0) {
      ch.invokeMethod<void>('setVolume', <String, dynamic>{'volume': _volume});
    }
  }

  /// Détache le controller de son instance native SANS le disposer — utilisé
  /// UNIQUEMENT par la bascule de chemin de rendu du widget : l'instance
  /// native courante va être détruite, une nouvelle sera créée puis
  /// [_attachChannel] rejouera [_lastUrl]. L'état d'affichage repart au logo
  /// (firstFrame=false) le temps que la 1re trame arrive par le NOUVEAU chemin.
  void _detach() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _attached = false;
    firstFrame = false;
    isBuffering = true;
    if (!_disposed) notifyListeners();
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
      case 'cueText':
        // Mode TEXTURE uniquement : le natif remonte le TEXTE des sous-titres
        // (la SubtitleView Android n'existe pas sur ce chemin) — le widget
        // les dessine en overlay Flutter.
        subtitleText = (call.arguments as String?) ?? '';
      case 'netActive':
        // Enquête « limite 1/1 » (20/08) : le natif signale les VRAIES
        // ouvertures/fermetures de sockets réseau (TransferListener Media3,
        // émis au close() effectif de la source). C'est la seule preuve
        // fiable que ce lecteur ne tient plus AUCUNE connexion — la réponse
        // du canal `stop` ne prouve que l'exécution de la commande, pas la
        // fermeture (stop() Media3 est asynchrone en interne).
        netActive = call.arguments as bool;
        if (!netActive) {
          lastNetIdleAt = DateTime.now();
          for (final Completer<bool> w in _netIdleWaiters) {
            if (!w.isCompleted) w.complete(true);
          }
          _netIdleWaiters.clear();
        }
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
              // `num?` et non `int?` : le canal de plateforme peut
              // remonter un entier en double selon les box. Un cast
              // strict planterait l'écran entier pour un chiffre.
              codec: (t['codec'] as String?) ?? '',
              sampleRate: (t['sampleRate'] as num?)?.toInt() ?? -1,
              channels: (t['channels'] as num?)?.toInt() ?? -1,
              bitrate: (t['bitrate'] as num?)?.toInt() ?? -1,
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
  /// [fallbackUrls] : URLs de REPLI du même contenu (autre variante, autre
  /// serveur). Le natif les essaie EN CASCADE, silencieusement, quand la
  /// source courante a épuisé son budget de reconnexions — l'erreur ne
  /// remonte ici qu'après épuisement de TOUTES les sources.
  void setUrl(String url,
      {String? userAgent, bool silent = false, List<String>? fallbackUrls}) {
    isStopped = false; // nouvelle source → le lecteur n'est plus « arrêté »
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
    subtitleText = '';
    // Mémorisées pour le re-rattachement après une bascule de chemin de rendu.
    _lastUrl = url;
    _lastUserAgent = userAgent;
    _lastFallbackUrls = fallbackUrls;
    if (!_disposed) notifyListeners();
    if (_channel != null) {
      _fire('setUrl', <String, dynamic>{
        'url': url,
        if (userAgent != null) 'userAgent': userAgent,
        if (fallbackUrls != null && fallbackUrls.isNotEmpty)
          'fallbackUrls': fallbackUrls,
      });
    } else {
      // Pas encore rattaché : on jouera ça (URL + signature) à l'attach.
      _pendingUrl = url;
      _pendingUserAgent = userAgent;
      _pendingFallbackUrls = fallbackUrls;
    }
  }

  /// Appel « tire-et-oublie » vers le canal natif, ERREUR AVALÉE. Sur une
  /// vue déjà détruite, le canal `native_video_player/tN` n'a plus de
  /// handler → `invokeMethod` lève une `MissingPluginException`. Sans ce
  /// filet, cette exception remontait NON RATTRAPÉE jusqu'à la zone globale
  /// (crash.error de la Boîte noire, terrain 20/08 : « dispose on channel
  /// native_video_player/t1 »). Un appel de commande raté sur un lecteur
  /// mort est sans conséquence : la vue est partie, il n'y a rien à piloter.
  void _fire(String method, [Map<String, dynamic>? args]) {
    _channel?.invokeMethod<void>(method, args).catchError((Object _) {});
  }

  void play() => _fire('play');

  void pause() => _fire('pause');

  /// Recrée la piste audio Android sous le lecteur.
  ///
  /// À APPELER AU RETOUR AU PREMIER PLAN, et là seulement.
  ///
  /// POURQUOI (signalement du 30/08) : « si j'écoutais autre chose et que
  /// j'ouvre l'app, le son n'est pas normal ; si on m'appelle et que je
  /// reviens, pareil ; ça redevient normal SEULEMENT si je redémarre
  /// l'application ». Ce « seulement au redémarrage » désigne un état qui
  /// survit à tout sauf à la mort du processus.
  ///
  /// La piste de sortie Android est ouverte une fois et gardée tant que le
  /// FORMAT du flux ne change pas. Mais la sortie de l'appareil, elle, a pu
  /// changer entre-temps : un appel bascule le système sur le chemin VOIX
  /// (bande étroite — d'où le son de « vieille radio »), une autre
  /// application a pu ouvrir la sortie à une autre fréquence, un casque a
  /// pu être branché. Rouvrir le FLUX n'y change rien : c'est la piste de
  /// SORTIE qui est périmée.
  ///
  /// Coût : quelques dizaines de millisecondes de silence. Négligeable au
  /// moment où l'on revient sur l'application — inacceptable en pleine
  /// lecture, d'où la consigne d'appel.
  void refreshAudio() => _fire('refreshAudio');

  /// ARRÊT COMPLET : libère la source et FERME la connexion au serveur, sans
  /// détruire la vue — un [setUrl] ultérieur relance proprement.
  ///
  /// À préférer à [pause] sur un DIRECT quand l'app part en arrière-plan :
  /// un lecteur en pause GARDE la session ouverte vers le panel, ce qui
  /// bloque les abonnements à 1 connexion alors que plus personne ne
  /// regarde. Sur un FILM, garder [pause] (la position doit survivre).
  /// ATTENDABLE : la Future ne se resout qu'une fois la socket REELLEMENT
  /// fermee cote natif (le natif ne repond qu'apres execution sur son thread
  /// lecteur). C'est ce qui permet a l'appelant de n'ouvrir le flux suivant
  /// qu'ensuite -- sans quoi les deux connexions se croisent et un compte
  /// 1-connexion refuse la seconde.
  Future<void> stop() async {
    isStopped = true;
    isBuffering = false;
    firstFrame = false;
    try {
      await _channel?.invokeMethod<void>('stop');
    } catch (_) {
      // Canal deja mort (vue detruite) : la connexion est fermee de toute
      // facon. Ne JAMAIS propager -- un arret rate ne doit pas bloquer
      // l'ouverture suivante.
    }
  }

  /// La source a-t-elle été LIBÉRÉE par [stop] ? Un lecteur arrêté n'a plus
  /// de média chargé : [play] n'y ferait rien, il faut repasser par [setUrl].
  /// Les écrans qui gardent un lecteur en réserve (aperçu d'accueil) doivent
  /// consulter ce drapeau avant de tenter une simple reprise.
  bool isStopped = false;

  /// Vrai tant qu'AU MOINS une socket réseau du lecteur natif est OUVERTE
  /// (transferts Media3 comptés au niveau DataSource : ouverture réelle →
  /// fermeture réelle). C'est l'état que le panel « voit » : un compte
  /// 1-connexion n'est libéré qu'une fois ce drapeau retombé à false.
  bool netActive = false;

  /// Dernier instant où le natif a confirmé « plus aucune socket réseau »
  /// (à la milliseconde — l'enquête « connexion fantôme » se joue là).
  DateTime? lastNetIdleAt;

  /// Attentes en cours sur la fermeture réelle des sockets (cf.
  /// [awaitNetworkIdle]) — complétées par l'événement natif `netActive:false`,
  /// ou à false par le timeout de l'appelant / le [dispose].
  final List<Completer<bool>> _netIdleWaiters = <Completer<bool>>[];

  /// Attend que le lecteur natif ne tienne PLUS AUCUNE socket réseau.
  ///
  /// Renvoie `true` dès la fermeture réelle (immédiatement si aucune socket
  /// n'est ouverte), `false` si [timeout] expire — auquel cas l'appelant DOIT
  /// le dire (journal) au lieu de prétendre que la connexion est rendue.
  /// C'est le chaînon mesurable qui manquait au scénario « je quitte le
  /// film, je lance une chaîne » : la réponse de [stop] prouve l'exécution
  /// de la commande sur le thread lecteur, PAS la fermeture de la socket
  /// (Media3 stop() est asynchrone en interne — la fermeture survient après,
  /// sur le thread de chargement).
  Future<bool> awaitNetworkIdle(
      {Duration timeout = const Duration(seconds: 3)}) {
    if (!netActive || _disposed || _channel == null) {
      return Future<bool>.value(true);
    }
    final Completer<bool> waiter = Completer<bool>();
    _netIdleWaiters.add(waiter);
    return waiter.future.timeout(timeout, onTimeout: () => false);
  }

  /// TÉLÉMÉTRIE SILENCIEUSE : instantané des compteurs natifs (frames
  /// perdues, underruns audio, reconnexions, bascules de source, violations
  /// de la garde d'états) + drain du journal d'événements (les événements
  /// lus sont consommés côté natif). À appeler par la Boîte noire quand la
  /// connexion est stable — jamais en continu pendant la lecture.
  Future<Map<String, dynamic>> getStats() async {
    final MethodChannel? ch = _channel;
    if (ch == null) return <String, dynamic>{};
    final Object? raw = await ch.invokeMethod<Object?>('getStats');
    if (raw is! Map) return <String, dynamic>{};
    return raw.map((Object? k, Object? v) => MapEntry(k.toString(), v));
  }

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
    _fire('seekTo', <String, dynamic>{'ms': t.inMilliseconds});
  }

  /// Avance/recule de [delta] (Netflix : ±10 s) depuis la position courante.
  void seekBy(Duration delta) => seekTo(position + delta);

  /// Sélectionne la [index]-ième piste audio (ordre de [audioTracks]).
  void setAudioTrack(int index) =>
      _fire('setAudioTrack', <String, dynamic>{'index': index});

  /// Sélectionne la [index]-ième piste de sous-titres, ou -1 = désactivés.
  void setSubtitleTrack(int index) =>
      _fire('setSubtitleTrack', <String, dynamic>{'index': index});

  /// Règle le volume (0.0 = muet, 1.0 = plein). Sert à la MULTI-VUE : seule la
  /// tuile active garde le son. Conservé pour ré-application au rattachement.
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _fire('setVolume', <String, dynamic>{'volume': _volume});
  }

  @override
  void dispose() {
    _disposed = true;
    // Attentes de fermeture réseau encore en vol : le canal va mourir, le
    // signal `netActive:false` n'arrivera jamais → on répond `false` (état
    // inconnu) TOUT DE SUITE plutôt que de laisser l'appelant attendre son
    // timeout complet (le release natif ferme les sockets de toute façon).
    for (final Completer<bool> w in _netIdleWaiters) {
      if (!w.isCompleted) w.complete(false);
    }
    _netIdleWaiters.clear();
    // ERREUR AVALÉE (cf. _fire) : sur une vue déjà détruite, `dispose`
    // levait une MissingPluginException NON RATTRAPÉE — c'était le crash
    // « dispose on channel native_video_player/t1 » du 20/08.
    _fire('dispose');
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

  static const MethodChannel _infoChannel =
      MethodChannel('native_video_player/info');

  /// Chemin de rendu de CETTE vue (`null` tant que la préférence n'est pas
  /// lue — un frame ou deux, on affiche un fond noir).
  String? _mode;

  /// Id de texture Flutter (mode texture uniquement, une fois créé).
  int? _textureId;

  /// WATCHDOG « l'image ne vient pas » : toutes les 3 s, si la lecture est
  /// EN COURS (le son joue, la position avance) mais qu'AUCUNE 1re trame n'a
  /// été rendue, on cumule ; à ~6 s on bascule sur l'AUTRE chemin de rendu et
  /// on MÉMORISE. Une seule bascule par vue (anti ping-pong) ; la préférence
  /// étant persistée, toutes les vues suivantes naissent sur le bon chemin.
  Timer? _watchdog;
  int _stalledTicks = 0;
  bool _switchedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRenderPath();
    _watchdog = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _switchedOnce) return;
      if (controller.firstFrame) {
        _stalledTicks = 0;
        return;
      }
      if (controller.isPlaying && !controller.hasError) {
        _stalledTicks++;
        if (_stalledTicks >= 2) _switchRenderPath();
      }
    });
  }

  Future<void> _initRenderPath() async {
    final String m = await NativeVideoRender.mode();
    if (!mounted) return;
    setState(() => _mode = m);
    if (m == NativeVideoRender.texture) {
      await _createTexturePlayer();
    }
    // Mode surface : la PlatformView se crée dans build() et _attach suit.
  }

  Future<void> _createTexturePlayer() async {
    try {
      final Map<dynamic, dynamic>? r = await _infoChannel
          .invokeMethod<Map<dynamic, dynamic>>('createTexturePlayer',
              <String, dynamic>{'preview': controller.preview});
      final int? id = (r?['textureId'] as num?)?.toInt();
      if (id == null) throw StateError('createTexturePlayer sans textureId');
      if (!mounted) {
        // La vue a disparu pendant la création : on libère tout de suite.
        _infoChannel.invokeMethod<void>(
            'disposeTexturePlayer', <String, dynamic>{'textureId': id});
        return;
      }
      setState(() => _textureId = id);
      controller._attachChannel('native_video_player/t$id');
    } catch (_) {
      // Création texture impossible (plateforme sans registre, test) →
      // repli immédiat sur le chemin SurfaceView, sans compter de bascule.
      if (!mounted) return;
      setState(() => _mode = NativeVideoRender.surface);
    }
  }

  /// Bascule texture ⇄ surface : détruit l'instance native courante, mémorise
  /// le nouveau chemin, recrée la vue — le controller rejoue la dernière URL.
  Future<void> _switchRenderPath() async {
    if (_switchedOnce || !mounted) return;
    _switchedOnce = true;
    final String next = (_mode == NativeVideoRender.texture)
        ? NativeVideoRender.surface
        : NativeVideoRender.texture;
    await NativeVideoRender.setMode(next);
    controller._detach();
    final int? oldTexture = _textureId;
    if (oldTexture != null) {
      _infoChannel.invokeMethod<void>(
          'disposeTexturePlayer', <String, dynamic>{'textureId': oldTexture});
    }
    if (!mounted) return;
    setState(() {
      _textureId = null;
      _mode = next;
    });
    if (next == NativeVideoRender.texture) {
      await _createTexturePlayer();
    }
    // Mode surface : le build() recrée la PlatformView (clé unique par mode),
    // Flutter dispose l'ancienne vue texture côté natif est déjà fait.
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final int? id = _textureId;
    if (id != null) {
      // Le lecteur texture n'a pas de PlatformView pour le libérer : c'est la
      // disparition du widget qui déclenche son teardown natif.
      _infoChannel.invokeMethod<void>(
          'disposeTexturePlayer', <String, dynamic>{'textureId': id});
    }
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
    final String? mode = _mode;
    // Préférence pas encore lue (1-2 frames) : fond noir neutre.
    if (mode == null) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    if (mode == NativeVideoRender.texture) {
      return _buildTexture();
    }
    return _buildPlatformView();
  }

  /// Chemin TEXTURE : la vidéo est rendue par le pipeline de l'UI Flutter.
  /// Les sous-titres (texte remonté par le natif) sont dessinés en overlay —
  /// styles volontairement autonomes (ce package ne dépend pas du thème de
  /// l'app) : blanc ombré, taille lisible à 3 m, standard des sous-titres TV.
  Widget _buildTexture() {
    final int? id = _textureId;
    if (id == null) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Texture(textureId: id),
        ListenableBuilder(
          listenable: controller,
          builder: (BuildContext context, Widget? _) {
            final String text = controller.subtitleText;
            if (text.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32, left: 48, right: 48),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 28,
                    height: 1.3,
                    shadows: <Shadow>[
                      Shadow(blurRadius: 4, color: Color(0xF0000000)),
                      Shadow(
                          blurRadius: 2,
                          offset: Offset(1, 1),
                          color: Color(0xF0000000)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Chemin SURFACEVIEW (historique) : PlatformView en hybrid composition.
  Widget _buildPlatformView() {
    return PlatformViewLink(
      // Clé par mode : après une bascule texture → surface, Flutter doit
      // créer une NOUVELLE PlatformView (pas réutiliser un état périmé).
      key: const ValueKey<String>('nvp-surface'),
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
