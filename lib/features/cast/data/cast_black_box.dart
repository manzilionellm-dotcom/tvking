// =========================================================
//  cast_black_box.dart — Boîte noire du pipeline Google Cast
// =========================================================
//  Même philosophie que StreamDiagnostics (branche m3u) mais pour le
//  CAST : un singleton qui enregistre TOUT ce qui se passe pendant une
//  tentative de cast, lisible en temps réel dans l'écran debug
//  (Réglages → Diagnostic cast → section « Boîte noire ») et copiable
//  en un rapport JSON pour le support.
//
//  Ce qu'on capture, étape par étape (brief diagnostic 2026-07-08) :
//    - DÉCOUVERTE : combien d'appareils vus (SSDP + mDNS), quand.
//    - ROUTAGE : chemin choisi (cast_proxy / local_hls_relay / direct),
//      statut HTTP de /cast-sign, statut du GET de vérification
//      /cast-proxy + X-Upstream-Status (le VRAI code du fournisseur).
//    - RECEIVER : App ID demandé (5BDFD969 custom / CC1AD845 Default),
//      résultat de la bascule (ok/switching/unavailable), App ID
//      RÉELLEMENT connecté (métadonnées de session), URL de la page
//      receiver.
//    - SESSION : étapes connecting → connected → loading → playing /
//      failed, erreurs du framework Cast avec leur CODE NUMÉRIQUE
//      (start_failed / resume_failed / load_failed).
//    - MEDIA : URL exacte transmise à loadMedia (identifiants et token
//      HMAC MASQUÉS), contentType déclaré.
//
//  Les identifiants sont masqués À L'ENTRÉE (au moment d'enregistrer),
//  jamais à l'affichage : aucune URL en clair ne vit dans la boîte.
//
//  NOTE nommage : le fichier `cast_diagnostics.dart` héberge déjà le
//  batch runner (DiagnosticBatchRunner) — d'où `cast_black_box.dart`
//  pour la classe CastDiagnostics demandée par le brief.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/cast_device.dart';
import 'cast_diagnostics.dart' show kBuildCommit;
import 'cast_session_diagnostic.dart' show redactStreamUrl;
import 'google_cast_api.dart';

/// Masque credentials (chemin Xtream + query) ET le token HMAC `t=` du
/// proxy Cast. C'est LA fonction à utiliser avant tout enregistrement
/// d'URL dans la boîte noire.
String redactCastUrl(String url) {
  final String base = redactStreamUrl(url);
  // Le token signé du proxy (`t=`) n'est pas couvert par
  // redactStreamUrl (qui ne masque que password/token/pass/pwd).
  // replaceAllMapped obligatoire : replaceAll ne substitue PAS `$1`.
  return base.replaceAllMapped(
    RegExp(r'([?&]t=)[^&]*'),
    (Match m) => '${m[1]}***',
  );
}

enum CastBlackBoxLevel { info, warn, error }

/// Une ligne du journal borné. Le message est déjà masqué par l'appelant.
@immutable
class CastBlackBoxEvent {
  const CastBlackBoxEvent({
    required this.at,
    required this.kind,
    required this.message,
    this.level = CastBlackBoxLevel.info,
  });

  final DateTime at;

  /// Slug court stable (`discovery.start`, `worker.sign`, `session.event`…)
  /// — filtrable dans un rapport collé dans une issue.
  final String kind;
  final String message;
  final CastBlackBoxLevel level;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'at': at.toIso8601String(),
        'kind': kind,
        if (level != CastBlackBoxLevel.info) 'level': level.name,
        'message': message,
      };
}

/// Instantané d'UNE tentative de cast, enrichi au fil des étapes par
/// CastManager / GoogleCastTransport. Mutable pendant la tentative,
/// archivé (10 dernières) quand elle se termine.
class CastAttemptSnapshot {
  CastAttemptSnapshot({
    required this.startedAt,
    required this.deviceName,
    required this.deviceKind,
    required this.deviceHost,
    required this.originalUrlRedacted,
    this.channelName,
  });

  final DateTime startedAt;
  final String deviceName;
  final String deviceKind;
  final String deviceHost;
  final String? channelName;

  /// URL de la chaîne telle que castTo l'a reçue (déjà masquée).
  final String originalUrlRedacted;

  // ----- Routage -----

  /// 'cast_proxy' | 'local_hls_relay' | 'direct' — décidé par playStream.
  String? castPath;

  /// contentType déclaré dans le MediaInfo envoyé au receiver.
  String? contentType;

  /// URL exacte transmise à loadMedia (credentials + token masqués).
  String? mediaUrlRedacted;

  // ----- Worker (réponses HTTP réelles) -----

  /// Statut HTTP de GET /cast-sign (200 = URL signée obtenue,
  /// 503 = CAST_PROXY_SECRET absent côté Worker, null = injoignable).
  int? castSignStatus;
  bool? castSignOk;

  /// Statut HTTP du GET de vérification /cast-proxy (2xx = le proxy
  /// délivre ; 502 = upstream KO ; null = pas vérifié / injoignable).
  int? proxyVerifyStatus;

  /// En-tête X-Upstream-Status renvoyé par le Worker : le VRAI code du
  /// fournisseur IPTV vu depuis l'IP Cloudflare (456/403 = IP
  /// datacenter refusée, 404 = token périmé, 0 = connexion coupée).
  String? proxyUpstreamStatus;

  // ----- Receiver -----

  /// App ID demandé pour CETTE session (5BDFD969 custom / CC1AD845).
  String? requestedAppId;

  /// Résultat de la bascule dynamique : ok / switching / unavailable /
  /// skipped (flag custom receiver désactivé).
  String? receiverSwitchOutcome;

  /// App ID RÉELLEMENT connecté, lu dans les métadonnées de la session
  /// active juste avant le loadMedia. Diverge de [requestedAppId] =
  /// la bascule n'a pas pris (ou métadonnées pas remontées → null).
  String? connectedAppId;

  /// Page receiver custom servie par le Worker (constante, pour que le
  /// rapport soit auto-porteur).
  String receiverPageUrl = 'https://app.7themotion.com/cast-receiver';

  // ----- Session -----

  /// Étape courante : routing → connecting → connected → loading →
  /// playing | failed. Suffisant pour voir OÙ ça casse d'un coup d'œil.
  String stage = 'routing';

  /// `true` dès que RemoteMediaClient.load a été ACCEPTÉ (load_ok) —
  /// distinct de « la vidéo joue ».
  bool? loadAccepted;

  /// Code numérique exact remonté par le framework Cast natif
  /// (CastStatusCodes) pour start_failed / resume_failed / load_failed.
  int? frameworkErrorCode;

  /// Événement porteur du code : 'start_failed', 'load_failed'…
  String? frameworkErrorKind;

  bool success = false;
  String? finalError;
  int? totalDurationMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'startedAt': startedAt.toIso8601String(),
        'device': <String, dynamic>{
          'name': deviceName,
          'kind': deviceKind,
          'host': deviceHost,
        },
        if (channelName != null) 'channelName': channelName,
        'originalUrl': originalUrlRedacted,
        'stage': stage,
        if (castPath != null) 'castPath': castPath,
        if (contentType != null) 'contentType': contentType,
        if (mediaUrlRedacted != null) 'mediaUrl': mediaUrlRedacted,
        if (castSignStatus != null) 'castSignStatus': castSignStatus,
        if (castSignOk != null) 'castSignOk': castSignOk,
        if (proxyVerifyStatus != null) 'proxyVerifyStatus': proxyVerifyStatus,
        if (proxyUpstreamStatus != null)
          'proxyUpstreamStatus': proxyUpstreamStatus,
        if (requestedAppId != null) 'requestedAppId': requestedAppId,
        if (receiverSwitchOutcome != null)
          'receiverSwitchOutcome': receiverSwitchOutcome,
        if (connectedAppId != null) 'connectedAppId': connectedAppId,
        'receiverPageUrl': receiverPageUrl,
        if (loadAccepted != null) 'loadAccepted': loadAccepted,
        if (frameworkErrorCode != null)
          'frameworkErrorCode': frameworkErrorCode,
        if (frameworkErrorKind != null)
          'frameworkErrorKind': frameworkErrorKind,
        'success': success,
        if (finalError != null) 'finalError': finalError,
        if (totalDurationMs != null) 'totalDurationMs': totalDurationMs,
      };
}

/// Boîte noire singleton. ChangeNotifier pour que la section « Cast »
/// de l'écran debug se rafraîchisse en direct pendant une tentative.
class CastDiagnostics extends ChangeNotifier {
  CastDiagnostics._() {
    // Toutes les erreurs du framework natif (avec leur code numérique)
    // passent par sessionEventStream — on journalise TOUT, y compris en
    // dehors d'une tentative (ex. session tuée par la TV). try/catch :
    // en test pur sans binding, GoogleCastApi reste inerte mais
    // constructible.
    try {
      GoogleCastApi.instance.sessionEventStream
          .listen(_onNativeSessionEvent);
      GoogleCastApi.instance.mediaStateStream.listen(_onNativeMediaState);
    } catch (e) {
      if (kDebugMode) debugPrint('[CastBlackBox] attach streams: $e');
    }
  }

  static final CastDiagnostics instance = CastDiagnostics._();

  // ----- Journal borné -----

  static const int _kMaxEvents = 150;
  final List<CastBlackBoxEvent> _events = <CastBlackBoxEvent>[];
  List<CastBlackBoxEvent> get events =>
      List<CastBlackBoxEvent>.unmodifiable(_events);

  /// Enregistre une ligne de journal. [message] doit DÉJÀ être masqué
  /// (passer toute URL par [redactCastUrl] avant).
  void logEvent(
    String kind,
    String message, {
    CastBlackBoxLevel level = CastBlackBoxLevel.info,
  }) {
    _events.add(CastBlackBoxEvent(
      at: DateTime.now(),
      kind: kind,
      message: message,
      level: level,
    ));
    while (_events.length > _kMaxEvents) {
      _events.removeAt(0);
    }
    notifyListeners();
  }

  // ----- Découverte -----

  DateTime? _lastDiscoveryStartedAt;
  DateTime? _lastDiscoveryEndedAt;
  int _devicesSeenTotal = 0;
  int _devicesSeenChromecast = 0;

  DateTime? get lastDiscoveryStartedAt => _lastDiscoveryStartedAt;
  DateTime? get lastDiscoveryEndedAt => _lastDiscoveryEndedAt;

  /// Nombre d'appareils dans la liste découverte au dernier scan clos.
  int get devicesSeenTotal => _devicesSeenTotal;

  /// Dont Chromecast / Google TV (mDNS `_googlecast._tcp`).
  int get devicesSeenChromecast => _devicesSeenChromecast;

  void discoveryStarted() {
    _lastDiscoveryStartedAt = DateTime.now();
    logEvent('discovery.start', 'scan SSDP + mDNS lancé');
  }

  void discoveryDevice(CastDevice d) {
    logEvent(
      'discovery.device',
      '${d.kind.name} « ${d.name} » (${d.host})',
    );
  }

  void discoveryEnded({required int total, required int chromecast}) {
    _lastDiscoveryEndedAt = DateTime.now();
    _devicesSeenTotal = total;
    _devicesSeenChromecast = chromecast;
    logEvent(
      'discovery.end',
      '$total appareil(s) visible(s), dont $chromecast Google Cast',
      level: total == 0 ? CastBlackBoxLevel.warn : CastBlackBoxLevel.info,
    );
  }

  // ----- Tentatives -----

  static const int _kMaxAttempts = 10;
  CastAttemptSnapshot? _current;
  final List<CastAttemptSnapshot> _attempts = <CastAttemptSnapshot>[];

  /// Tentative EN COURS (null hors cast). L'UI l'affiche en tête.
  CastAttemptSnapshot? get current => _current;

  /// Tentatives terminées, la plus récente d'abord.
  List<CastAttemptSnapshot> get attempts =>
      List<CastAttemptSnapshot>.unmodifiable(_attempts);

  /// La donnée la plus utile à l'écran : la tentative en cours, sinon
  /// la dernière terminée.
  CastAttemptSnapshot? get latest =>
      _current ?? (_attempts.isEmpty ? null : _attempts.first);

  CastAttemptSnapshot beginAttempt({
    required CastDevice device,
    required String streamUrl,
    String? channelName,
  }) {
    // Une tentative précédente jamais clôturée (crash, hot-restart) est
    // archivée telle quelle plutôt que perdue.
    final CastAttemptSnapshot? orphan = _current;
    if (orphan != null) _archive(orphan);
    final CastAttemptSnapshot snap = CastAttemptSnapshot(
      startedAt: DateTime.now(),
      deviceName: device.name,
      deviceKind: device.kind.name,
      deviceHost: device.host,
      channelName: channelName,
      originalUrlRedacted: redactCastUrl(streamUrl),
    );
    _current = snap;
    logEvent(
      'attempt.start',
      '${device.kind.name} « ${device.name} » ← '
          '${snap.originalUrlRedacted}',
    );
    notifyListeners();
    return snap;
  }

  /// Mutation générique du snapshot courant + notification UI. No-op si
  /// aucune tentative en cours (appels tardifs après clôture).
  void updateCurrent(void Function(CastAttemptSnapshot snap) mutate) {
    final CastAttemptSnapshot? snap = _current;
    if (snap == null) return;
    mutate(snap);
    notifyListeners();
  }

  void endAttempt({required bool success, String? error}) {
    final CastAttemptSnapshot? snap = _current;
    if (snap == null) return;
    snap.success = success;
    snap.finalError = error;
    snap.stage = success ? 'playing' : 'failed';
    snap.totalDurationMs =
        DateTime.now().difference(snap.startedAt).inMilliseconds;
    _current = null;
    _archive(snap);
    logEvent(
      'attempt.end',
      success
          ? 'SUCCÈS en ${snap.totalDurationMs} ms (${snap.castPath ?? '?'})'
          : 'ÉCHEC en ${snap.totalDurationMs} ms — ${error ?? 'inconnu'}',
      level: success ? CastBlackBoxLevel.info : CastBlackBoxLevel.error,
    );
  }

  void _archive(CastAttemptSnapshot snap) {
    _attempts.insert(0, snap);
    while (_attempts.length > _kMaxAttempts) {
      _attempts.removeLast();
    }
  }

  // ----- Événements natifs (codes numériques du framework) -----

  void _onNativeSessionEvent(CastNativeSessionEvent evt) {
    final bool isError = evt.kind == 'start_failed' ||
        evt.kind == 'resume_failed' ||
        evt.kind == 'load_failed';
    logEvent(
      'session.event',
      evt.errorCode != 0 ? '${evt.kind} code=${evt.errorCode}' : evt.kind,
      level: isError ? CastBlackBoxLevel.error : CastBlackBoxLevel.info,
    );
    final CastAttemptSnapshot? snap = _current;
    if (snap == null) return;
    switch (evt.kind) {
      case 'started':
      case 'resumed':
        snap.stage = 'connected';
        break;
      case 'load_ok':
        snap.loadAccepted = true;
        break;
      case 'start_failed':
      case 'resume_failed':
      case 'load_failed':
        if (evt.kind == 'load_failed') snap.loadAccepted = false;
        snap.frameworkErrorKind = evt.kind;
        snap.frameworkErrorCode = evt.errorCode;
        break;
    }
    notifyListeners();
  }

  void _onNativeMediaState(CastNativeMediaState state) {
    final CastAttemptSnapshot? snap = _current;
    if (snap == null) return;
    if (state.playerState == CastNativePlayerState.playing) {
      snap.stage = 'playing';
      notifyListeners();
    } else if (state.playerState == CastNativePlayerState.idle &&
        state.idleReason == 'error') {
      logEvent('media.idle_error', 'receiver → IDLE (idleReason=error)',
          level: CastBlackBoxLevel.error);
    }
  }

  // ----- Rapport copiable -----

  /// Rapport JSON complet : méta build, état découverte, 10 dernières
  /// tentatives, journal. Toutes les URLs sont déjà masquées à l'entrée.
  String exportReport() {
    final Map<String, dynamic> report = <String, dynamic>{
      'meta': <String, dynamic>{
        'generatedAt': DateTime.now().toIso8601String(),
        'app': '7 MOTION',
        'buildCommit': kBuildCommit,
        'report': 'cast_black_box',
      },
      'discovery': <String, dynamic>{
        if (_lastDiscoveryStartedAt != null)
          'lastStartedAt': _lastDiscoveryStartedAt!.toIso8601String(),
        if (_lastDiscoveryEndedAt != null)
          'lastEndedAt': _lastDiscoveryEndedAt!.toIso8601String(),
        'devicesSeenTotal': _devicesSeenTotal,
        'devicesSeenChromecast': _devicesSeenChromecast,
      },
      if (_current != null) 'currentAttempt': _current!.toJson(),
      'attempts': _attempts
          .map((CastAttemptSnapshot a) => a.toJson())
          .toList(growable: false),
      'journal': _events
          .map((CastBlackBoxEvent e) => e.toJson())
          .toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(report);
  }
}
