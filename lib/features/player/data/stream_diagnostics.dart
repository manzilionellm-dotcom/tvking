// =========================================================
//  stream_diagnostics.dart — Boîte noire de la lecture d'un flux
// =========================================================
//  OBJECTIF : ne plus JAMAIS avoir un écran noir muet sans info.
//
//  Chaque acteur de la chaîne de lecture écrit ici ce qu'il sait :
//    - le lecteur (video_player_screen) : URL ouverte, User-Agent
//      envoyé, erreurs libmpv EXACTES (y compris les warnings
//      filtrés de l'UI), codecs vidéo/audio détectés, résolution ;
//    - le mini-relais (local_stream_relay) : statut HTTP RÉEL de la
//      connexion upstream, URL finale après redirections, MIME ;
//    - la sonde multi-signatures (_declareChannelBlocked) : le
//      résultat de chaque User-Agent essayé.
//
//  Tout est consultable dans l'écran caché `StreamDebugScreen`
//  (appui LONG sur la version, écran À propos) : instantané de la
//  session courante + journal des ~120 derniers événements.
//
//  AUCUNE dépendance vers le player ni le cast : ce fichier ne fait
//  que stocker des chaînes de caractères — les producteurs viennent
//  à lui, jamais l'inverse. Zéro risque de régression.
// =========================================================

import 'package:flutter/foundation.dart';

/// Une ligne du journal de diagnostic.
@immutable
class StreamDiagEvent {
  StreamDiagEvent({
    required this.tag,
    required this.message,
    this.level = 'info',
  }) : time = DateTime.now();

  final DateTime time;

  /// 'info' | 'warn' | 'error'.
  final String level;

  /// Origine courte : 'player', 'relay', 'probe', 'http', 'watchdog'…
  final String tag;

  final String message;

  @override
  String toString() {
    final String h = time.hour.toString().padLeft(2, '0');
    final String m = time.minute.toString().padLeft(2, '0');
    final String s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s [$tag] $message';
  }
}

/// Boîte noire singleton. Les écrans s'abonnent (ChangeNotifier) pour
/// se rafraîchir en direct pendant qu'un flux joue.
class StreamDiagnostics extends ChangeNotifier {
  StreamDiagnostics._();
  static final StreamDiagnostics instance = StreamDiagnostics._();

  /// Taille max du journal (ring buffer — les plus vieux sortent).
  static const int _kMaxEvents = 120;

  // ----- Instantané de la session de lecture courante -----

  /// URL réelle du flux (telle qu'ouverte par le lecteur, PAS l'URL
  /// du relais local).
  String? streamUrl;

  /// User-Agent envoyé au serveur pour cette session.
  String? userAgent;

  /// Titre lisible (nom de chaîne / film) pour se repérer.
  String? title;

  /// Statut HTTP réellement observé sur la connexion upstream
  /// (rempli par le relais pour le live ; par la sonde sinon).
  int? httpStatus;

  /// URL finale après suivi des redirections 301/302/307/308.
  String? httpFinalUrl;

  /// Content-Type renvoyé par le serveur.
  String? httpMime;

  /// Codecs détectés par le moteur de lecture (une fois le flux ouvert).
  String? videoCodec;
  String? audioCodec;
  String? resolution;

  /// Dernière erreur EXACTE remontée par le moteur (libmpv/ExoPlayer),
  /// sans reformulation « friendly ».
  String? lastPlayerError;

  DateTime? sessionStart;

  final List<StreamDiagEvent> _events = <StreamDiagEvent>[];

  /// Journal, du plus récent au plus ancien.
  List<StreamDiagEvent> get events =>
      List<StreamDiagEvent>.unmodifiable(_events.reversed);

  // ----- Producteurs -----

  /// Nouvelle tentative d'ouverture d'un flux. Réinitialise
  /// l'instantané (le journal, lui, est conservé).
  void beginSession({
    required String url,
    required String userAgent,
    String? title,
  }) {
    streamUrl = url;
    this.userAgent = userAgent;
    this.title = title;
    httpStatus = null;
    httpFinalUrl = null;
    httpMime = null;
    videoCodec = null;
    audioCodec = null;
    resolution = null;
    lastPlayerError = null;
    sessionStart = DateTime.now();
    _add('player', 'Ouverture ${maskCredentials(url)} (UA: $userAgent)');
  }

  /// Résultat HTTP observé sur la connexion upstream (relais ou sonde).
  void recordHttp({
    int? status,
    String? finalUrl,
    String? mime,
    String? error,
    String source = 'http',
  }) {
    if (status != null) httpStatus = status;
    if (finalUrl != null) httpFinalUrl = finalUrl;
    if (mime != null) httpMime = mime;
    final StringBuffer b = StringBuffer();
    if (status != null) b.write('HTTP $status');
    if (mime != null && mime.isNotEmpty) b.write(' · $mime');
    if (finalUrl != null && finalUrl != streamUrl) {
      b.write(' · redirigé → ${maskCredentials(finalUrl)}');
    }
    if (error != null && error.isNotEmpty) {
      b.write(b.isEmpty ? error : ' · $error');
    }
    if (b.isNotEmpty) {
      _add(source, b.toString(),
          level: (status != null && status >= 400) || error != null
              ? 'error'
              : 'info');
    }
    notifyListeners();
  }

  /// Codecs / résolution détectés par le moteur de lecture.
  void recordCodecs({String? video, String? audio, String? resolution}) {
    bool changed = false;
    if (video != null && video.isNotEmpty && video != videoCodec) {
      videoCodec = video;
      changed = true;
    }
    if (audio != null && audio.isNotEmpty && audio != audioCodec) {
      audioCodec = audio;
      changed = true;
    }
    if (resolution != null &&
        resolution.isNotEmpty &&
        resolution != this.resolution) {
      this.resolution = resolution;
      changed = true;
    }
    if (changed) {
      _add('player',
          'Codecs: vidéo=${videoCodec ?? '?'} audio=${audioCodec ?? '?'} '
          '${this.resolution ?? ''}');
      notifyListeners();
    }
  }

  /// Erreur du moteur de lecture, TELLE QUELLE. [fatal] = elle a
  /// interrompu la lecture (sinon simple warning filtré par l'UI).
  void recordPlayerError(String message, {bool fatal = true}) {
    if (fatal) lastPlayerError = message;
    _add('player', message, level: fatal ? 'error' : 'warn');
    notifyListeners();
  }

  /// Événement libre (watchdog, relais, sonde…).
  void recordEvent(String tag, String message, {String level = 'info'}) {
    _add(tag, message, level: level);
    notifyListeners();
  }

  void _add(String tag, String message, {String level = 'info'}) {
    _events.add(StreamDiagEvent(tag: tag, message: message, level: level));
    if (_events.length > _kMaxEvents) _events.removeAt(0);
    notifyListeners();
  }

  // ----- Rapport texte (copiable) -----

  /// Rapport complet, prêt à coller dans un ticket de support.
  /// Les identifiants Xtream sont masqués.
  String buildReport() {
    final StringBuffer b = StringBuffer()
      ..writeln('=== DIAGNOSTIC FLUX — 7 MOTION ===')
      ..writeln('Généré : ${DateTime.now()}')
      ..writeln('')
      ..writeln('Titre        : ${title ?? '—'}')
      ..writeln('URL          : '
          '${streamUrl == null ? '—' : maskCredentials(streamUrl!)}')
      ..writeln('User-Agent   : ${userAgent ?? '—'}')
      ..writeln('HTTP         : ${httpStatus?.toString() ?? '—'}')
      ..writeln('MIME         : ${httpMime ?? '—'}')
      ..writeln('URL finale   : '
          '${httpFinalUrl == null ? '—' : maskCredentials(httpFinalUrl!)}')
      ..writeln('Codec vidéo  : ${videoCodec ?? '—'}')
      ..writeln('Codec audio  : ${audioCodec ?? '—'}')
      ..writeln('Résolution   : ${resolution ?? '—'}')
      ..writeln('Erreur player: ${lastPlayerError ?? '—'}')
      ..writeln('')
      ..writeln('--- Journal (récent → ancien) ---');
    for (final StreamDiagEvent e in events) {
      b.writeln(e.toString());
    }
    return b.toString();
  }

  /// Masque les identifiants dans une URL Xtream pour l'affichage /
  /// les rapports (un screenshot du debug ne doit pas fuiter le compte).
  ///
  ///   http://host/live/USER/PASS/123.ts  → http://host/live/•••/•••/123.ts
  ///   http://host/USER/PASS/123.ts       → http://host/•••/•••/123.ts
  ///   …?username=U&password=P&token=T    → valeurs remplacées par •••
  static String maskCredentials(String url) {
    final Uri? u = Uri.tryParse(url);
    if (u == null) return url;

    // 1. Query : masque les paramètres sensibles connus.
    Map<String, String>? q;
    if (u.queryParameters.isNotEmpty) {
      const Set<String> sensitive = <String>{
        'username', 'password', 'token', 'u', 'p', 'pass', 'user',
      };
      q = <String, String>{};
      u.queryParameters.forEach((String k, String v) {
        q![k] = sensitive.contains(k.toLowerCase()) ? '•••' : v;
      });
    }

    // 2. Chemin : sur .../SEG/SEG/fichier.ext (schéma Xtream), masque
    //    les 2 segments juste avant le fichier (user/pass).
    List<String> segs = u.pathSegments.toList();
    if (segs.length >= 3 && segs.last.contains('.')) {
      segs[segs.length - 2] = '•••';
      segs[segs.length - 3] = '•••';
      // Ne pas masquer les préfixes structurels connus par erreur :
      // si le segment masqué était live/movie/series, on le restaure.
      const Set<String> structural = <String>{'live', 'movie', 'series'};
      final String original3 = u.pathSegments[segs.length - 3];
      if (structural.contains(original3.toLowerCase())) {
        segs[segs.length - 3] = original3;
      }
    }

    return u
        .replace(
          pathSegments: segs,
          queryParameters: q,
        )
        .toString();
  }
}
