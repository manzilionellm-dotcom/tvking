// =========================================================
//  source_calibrator.dart — « Optimiser la source » (calibration auto)
// =========================================================
//  Orchestre en UNE passe ce que le lecteur sait déjà faire au coup
//  par coup (RÉUTILISE l'existant, ne duplique aucune logique) :
//
//    1/4  COMPTE     (Xtream) player_api.php → statut, expiration,
//                    connexions. Compte mort = on s'arrête là.
//    2/4  FORMAT     cascade de variantes d'URL (XtreamUrlVariants) sur
//                    3 chaînes échantillon (début / milieu / fin de la
//                    liste) → format gagnant persisté PAR SOURCE
//                    (XtreamUrlFormatStore) → zapping sans cascade.
//    3/4  SIGNATURE  sonde des User-Agent connus (StreamProbe) sur
//                    l'échantillon → signature gagnante persistée pour
//                    la source (et appliquée).
//    4/4  DÉMARRAGE  moyenne des temps de 1re réponse (TTFB) observés
//                    sur les sondes réussies — l'indicateur « ta source
//                    démarre en X s » de l'écran de synthèse.
//
//  CONTRAT UX : annulable à tout moment, ~20 s MAX au total (timeouts
//  courts), progression rapportée étape par étape. Tous les détails
//  techniques partent dans StreamDiagnostics (identifiants masqués) ;
// l'écran de synthèse ne montre que des ✓ / compréhensibles.
//
//  TESTABILITÉ : toutes les E/S (compte, échantillon, sonde,
//  persistance) sont injectables — l'orchestrateur se teste sans
//  réseau ni base (cf. source_calibrator_test.dart).
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../cast/data/stream_probe.dart';
import '../../player/data/player_settings.dart';
import '../../player/data/stream_diagnostics.dart';
import '../../player/data/xtream_url_variants.dart';
import '../domain/playlist.dart';
import 'playlist_database.dart';
import 'xtream_client.dart';
import 'xtream_url_format_store.dart';

/// Verdict global — pilote le message simple montré à l'utilisateur.
enum CalibrationVerdict {
  /// Tout est réglé (ou rien à changer) : la source est prête.
  ok,

  /// Compte Xtream expiré / banni / désactivé — inutile d'aller plus loin.
  accountExpired,

  /// Le serveur ne répond pas (API et/ou flux) — réseau ou serveur mort.
  serverUnreachable,

  /// Le serveur répond mais AUCUN format/signature ne débloque les flux
  /// échantillon → suggérer un VPN (blocage FAI probable).
  allFormatsRefused,

  /// La source n'a aucune chaîne à sonder.
  noChannels,

  /// L'utilisateur a annulé en cours de route.
  cancelled,
}

/// Progression rapportée à l'UI (« étape 2/4 : format… »).
@immutable
class CalibrationProgress {
  const CalibrationProgress(this.step, this.total, this.label);

  final int step;
  final int total;
  final String label;
}

/// Résultat complet de la calibration — l'écran de synthèse s'affiche
/// entièrement à partir de ça.
@immutable
class CalibrationReport {
  const CalibrationReport({
    required this.verdict,
    this.account,
    this.accountChecked = false,
    this.winningFormat,
    this.formatChecked = false,
    this.winningUserAgent,
    this.signatureChecked = false,
    this.avgStartupMs,
  });

  final CalibrationVerdict verdict;

  /// Photo du compte Xtream (null pour une source M3U).
  final XtreamAccountInfo? account;

  /// `true` si l'étape compte a été exécutée (source Xtream).
  final bool accountChecked;

  /// Code de format persisté (`live:m3u8`…), null = format d'origine
  /// déjà bon (rien à persister) ou étape non applicable.
  final String? winningFormat;
  final bool formatChecked;

  /// Signature persistée pour la source, null = l'actuelle convient.
  final String? winningUserAgent;
  final bool signatureChecked;

  /// Temps de démarrage moyen observé (ms), null si aucune sonde
  /// n'a abouti.
  final int? avgStartupMs;

  bool get accountOk =>
      account == null || !_isBlockedAccount(account!);

  static bool _isBlockedAccount(XtreamAccountInfo a) {
    const Set<String> blocked = <String>{
      'banned', 'disabled', 'expired', 'suspended', 'blocked', 'inactive',
    };
    final String status = (a.status ?? '').trim().toLowerCase();
    if (blocked.contains(status)) return true;
    final DateTime? exp = a.expDate;
    return exp != null && exp.isBefore(DateTime.now());
  }
}

/// Orchestrateur de calibration d'UNE source.
class SourceCalibrator {
  SourceCalibrator({
    required this.playlist,
    this.onProgress,
    Future<XtreamAccountInfo> Function()? accountFetcher,
    Future<List<String>> Function()? sampleUrls,
    Future<UserAgentProbeResult> Function(
      String url, {
      required List<String> candidates,
      Duration timeout,
    })? probeUserAgents,
    Future<StreamProbeResult> Function(
      String url, {
      Duration timeout,
      String? userAgent,
    })? probeOnce,
    Future<void> Function(int playlistId, XtreamContentType type, String code)?
        persistFormat,
    Future<void> Function(int playlistId, String ua)? persistUserAgent,
  })  : _accountFetcher = accountFetcher,
        _sampleUrls = sampleUrls,
        _probeUserAgents = probeUserAgents,
        _probeOnce = probeOnce,
        _persistFormat = persistFormat,
        _persistUserAgent = persistUserAgent;

  final Playlist playlist;
  final ValueChanged<CalibrationProgress>? onProgress;

  final Future<XtreamAccountInfo> Function()? _accountFetcher;
  final Future<List<String>> Function()? _sampleUrls;
  final Future<UserAgentProbeResult> Function(
    String url, {
    required List<String> candidates,
    Duration timeout,
  })? _probeUserAgents;
  final Future<StreamProbeResult> Function(
    String url, {
    Duration timeout,
    String? userAgent,
  })? _probeOnce;
  final Future<void> Function(int, XtreamContentType, String)? _persistFormat;
  final Future<void> Function(int, String)? _persistUserAgent;

  /// Timeout d'UNE sonde de flux — court : le budget TOTAL est ~20 s.
  static const Duration kProbeTimeout = Duration(milliseconds: 2500);

  /// Timeout de l'appel compte (player_api.php).
  static const Duration kAccountTimeout = Duration(seconds: 6);

  /// Budget GLOBAL de l'étape signature (la sonde multi-UA peut essayer
  /// jusqu'à ~9 signatures — on coupe avant de crever le budget).
  static const Duration kSignatureBudget = Duration(seconds: 8);

  bool _cancelled = false;

  /// Annule la calibration : l'étape en cours se termine, les suivantes
  /// ne démarrent pas. Le rapport sort avec verdict `cancelled`.
  void cancel() => _cancelled = true;

  void _step(int n, String label) {
    onProgress?.call(CalibrationProgress(n, 4, label));
    StreamDiagnostics.instance
        .recordEvent('calibrate', 'Étape $n/4 — $label');
  }

  // ---------------------------------------------------------------
  //  E/S par défaut (production) — remplacées dans les tests
  // ---------------------------------------------------------------

  Future<XtreamAccountInfo> _fetchAccount() {
    if (_accountFetcher != null) return _accountFetcher();
    return XtreamClient(
      serverUrl: playlist.xtreamServer ?? '',
      username: playlist.xtreamUsername ?? '',
      password: playlist.xtreamPassword ?? '',
      timeout: kAccountTimeout,
    ).fetchAccountInfo();
  }

  /// 3 chaînes LIVE échantillon : début / milieu / fin de la liste —
  /// trois zones différentes du bouquet pour ne pas calibrer sur une
  /// seule chaîne potentiellement morte.
  Future<List<String>> _fetchSampleUrls() async {
    if (_sampleUrls != null) return _sampleUrls();
    final int? pid = playlist.id;
    if (pid == null) return <String>[];
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> countRows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM channels '
      'WHERE playlist_id = ? AND is_live = 1',
      <Object>[pid],
    );
    final int n = (countRows.first['n'] as int?) ?? 0;
    if (n == 0) return <String>[];
    final Set<int> offsets = <int>{0, n ~/ 2, n - 1};
    final List<String> urls = <String>[];
    for (final int off in offsets) {
      final List<Map<String, Object?>> rows = await db.query(
        'channels',
        columns: <String>['stream_url'],
        where: 'playlist_id = ? AND is_live = 1',
        whereArgs: <Object>[pid],
        orderBy: 'local_id ASC',
        limit: 1,
        offset: off,
      );
      final Object? url = rows.isEmpty ? null : rows.first['stream_url'];
      if (url is String && url.isNotEmpty) urls.add(url);
    }
    return urls;
  }

  Future<UserAgentProbeResult> _runUaProbe(
    String url, {
    required List<String> candidates,
    Duration timeout = kProbeTimeout,
  }) {
    if (_probeUserAgents != null) {
      return _probeUserAgents(url, candidates: candidates, timeout: timeout);
    }
    return StreamProbe.instance
        .probeUserAgents(url, candidates: candidates, timeout: timeout);
  }

  Future<StreamProbeResult> _runProbe(
    String url, {
    Duration timeout = kProbeTimeout,
    String? userAgent,
  }) {
    if (_probeOnce != null) {
      return _probeOnce(url, timeout: timeout, userAgent: userAgent);
    }
    return StreamProbe.instance
        .probe(url, timeout: timeout, dnsRetries: 0, userAgent: userAgent);
  }

  Future<void> _saveFormat(
      int playlistId, XtreamContentType type, String code) {
    if (_persistFormat != null) return _persistFormat(playlistId, type, code);
    return XtreamUrlFormatStore.instance
        .saveWinningFormat(playlistId, type, code);
  }

  Future<void> _saveUserAgent(int playlistId, String ua) async {
    if (_persistUserAgent != null) {
      return _persistUserAgent(playlistId, ua);
    }
    await XtreamUrlFormatStore.instance.saveSourceUserAgent(playlistId, ua);
    // Appliquée tout de suite : le relais et mpv lisent PlayerSettings
    // au prochain open. C'est le même geste que la bascule automatique
    // du lecteur (_declareChannelBlocked).
    await PlayerSettings.instance.setUserAgent(ua);
  }

  // ---------------------------------------------------------------
  //  Orchestration
  // ---------------------------------------------------------------

  Future<CalibrationReport> run() async {
    final bool isXtream = playlist.type == PlaylistType.xtream;
    StreamDiagnostics.instance.recordEvent(
      'calibrate',
      'Calibration de « ${playlist.name} » '
          '(${isXtream ? 'Xtream' : 'M3U'})…',
    );

    // ----- 1/4 : compte (Xtream uniquement) -----
    XtreamAccountInfo? account;
    bool accountChecked = false;
    if (isXtream) {
      _step(1, 'Vérification du compte');
      accountChecked = true;
      try {
        account = await _fetchAccount().timeout(kAccountTimeout);
      } catch (e) {
        StreamDiagnostics.instance.recordEvent(
            'calibrate', 'Compte injoignable : $e',
            level: 'error');
        return const CalibrationReport(
          verdict: CalibrationVerdict.serverUnreachable,
          accountChecked: true,
        );
      }
      if (CalibrationReport._isBlockedAccount(account)) {
        StreamDiagnostics.instance.recordEvent(
            'calibrate',
            'Compte NON ACTIF (${account.status ?? 'expiré'}) '
                '— calibration arrêtée',
            level: 'error');
        return CalibrationReport(
          verdict: CalibrationVerdict.accountExpired,
          account: account,
          accountChecked: true,
        );
      }
    }
    if (_cancelled) return _cancelledReport(account, accountChecked);

    // ----- Échantillon -----
    final List<String> samples = await _fetchSampleUrls();
    if (samples.isEmpty) {
      return CalibrationReport(
        verdict: CalibrationVerdict.noChannels,
        account: account,
        accountChecked: accountChecked,
      );
    }
    if (_cancelled) return _cancelledReport(account, accountChecked);

    final List<int> startupSamplesMs = <int>[];
    bool sawNonNetworkFailure = false;
    // Échec de niveau RÉSEAU (DNS/timeout/connexion) vs refus APPLICATIF
    // (4xx/5xx/page HTML) : c'est ce qui départage « serveur injoignable »
    // de « formats refusés → suggérer un VPN » dans le verdict final.
    bool looksNetworkLevel(StreamProbeResult r) {
      if (r.errorCode != null) return false; // le serveur a RÉPONDU
      final String reason = (r.errorReason ?? '').toLowerCase();
      return reason.contains('ne répond pas') ||
          reason.contains('connexion impossible') ||
          reason.contains('hostname') ||
          reason.contains('no address') ||
          reason.contains('failed host lookup');
    }

    void collect(StreamProbeResult r) {
      if (r.success && r.timeToFirstByte != null) {
        startupSamplesMs.add(r.timeToFirstByte!);
      }
      if (!r.success && !looksNetworkLevel(r)) {
        sawNonNetworkFailure = true;
      }
    }

    // ----- 2/4 : format (cascade, sources Xtream uniquement) -----
    String currentUa = PlayerSettings.instance.userAgent;
    String? winningFormat;
    bool anySuccess = false;
    bool formatChecked = false;
    if (isXtream && playlist.id != null) {
      _step(2, 'Détection du format optimal');
      formatChecked = true;
      final List<XtreamUrlCandidate> cascade = XtreamUrlVariants.cascadeFor(
          samples.first, XtreamContentType.live);
      for (final XtreamUrlCandidate candidate in cascade) {
        if (_cancelled) return _cancelledReport(account, accountChecked);
        final StreamProbeResult r =
            await _runProbe(candidate.url, userAgent: currentUa);
        collect(r);
        StreamDiagnostics.instance.recordEvent(
          'calibrate',
          'Format ${candidate.formatCode} → '
              '${r.success ? 'OK' : 'HTTP ${r.errorCode ?? '—'} '
                  '(${r.errorReason ?? 'échec'})'}',
          level: r.success ? 'info' : 'warn',
        );
        if (!r.success) continue;
        anySuccess = true;
        // Valide le format sur le RESTE de l'échantillon (en parallèle)
        // — un format qui ne marche que sur une chaîne n'est pas « le
        // format de la source ».
        final List<StreamProbeResult> others = await Future.wait(
          samples.skip(1).map((String u) {
            final String applied =
                XtreamUrlVariants.applyFormat(u, candidate.formatCode) ?? u;
            return _runProbe(applied, userAgent: currentUa);
          }),
        );
        others.forEach(collect);
        final int okCount =
            1 + others.where((StreamProbeResult r) => r.success).length;
        if (okCount * 2 >= samples.length + 1) {
          // Majorité de l'échantillon OK → format retenu. On ne persiste
          // que si ce n'est PAS déjà le format des URLs de la source.
          final String? originalCode =
              XtreamUrlVariants.formatCodeOf(samples.first);
          if (candidate.formatCode != originalCode) {
            winningFormat = candidate.formatCode;
            await _saveFormat(
                playlist.id!, XtreamContentType.live, candidate.formatCode);
          }
          StreamDiagnostics.instance.recordEvent(
            'calibrate',
            'Format retenu : ${candidate.formatCode} '
                '($okCount/${samples.length} chaînes échantillon OK)'
                '${winningFormat == null ? ' — déjà celui de la source' : ' — persisté'}',
          );
          break;
        }
      }
    }
    if (_cancelled) return _cancelledReport(account, accountChecked);

    // ----- 3/4 : signature (User-Agent) -----
    _step(3, 'Réglage de la signature de lecture');
    String? winningUa;
    // Sonde la 1re chaîne échantillon (au format retenu si applicable)
    // avec la signature ACTIVE d'abord, puis tous les préréglages.
    final String uaProbeUrl = winningFormat == null
        ? samples.first
        : (XtreamUrlVariants.applyFormat(samples.first, winningFormat) ??
            samples.first);
    try {
      final UserAgentProbeResult uaProbe = await _runUaProbe(
        uaProbeUrl,
        candidates: <String>[
          currentUa,
          ...PlayerSettings.userAgentPresets.values,
        ],
      ).timeout(kSignatureBudget);
      uaProbe.attempts.values.forEach(collect);
      for (final MapEntry<String, StreamProbeResult> e
          in uaProbe.attempts.entries) {
        StreamDiagnostics.instance.recordEvent(
          'calibrate',
          'Signature "${e.key}" → '
              '${e.value.success ? 'OK' : (e.value.errorReason ?? 'refusée')}',
          level: e.value.success ? 'info' : 'warn',
        );
      }
      if (uaProbe.workingUserAgent != null) {
        anySuccess = true;
        if (uaProbe.workingUserAgent != currentUa &&
            playlist.id != null) {
          winningUa = uaProbe.workingUserAgent;
          currentUa = winningUa!;
          await _saveUserAgent(playlist.id!, winningUa);
          StreamDiagnostics.instance.recordEvent(
              'calibrate', 'Signature retenue et persistée : "$winningUa"');
        }
      }
    } on TimeoutException {
      StreamDiagnostics.instance.recordEvent(
          'calibrate', 'Étape signature : budget dépassé, on garde l\'actuelle',
          level: 'warn');
    }
    if (_cancelled) return _cancelledReport(account, accountChecked);

    // ----- 4/4 : temps de démarrage moyen -----
    _step(4, 'Mesure du démarrage');
    final int? avgMs = startupSamplesMs.isEmpty
        ? null
        : (startupSamplesMs.reduce((int a, int b) => a + b) ~/
            startupSamplesMs.length);
    if (avgMs != null) {
      StreamDiagnostics.instance.recordEvent(
          'calibrate',
          'Démarrage moyen : $avgMs ms '
              '(${startupSamplesMs.length} mesures)');
    }

    // ----- Verdict -----
    final CalibrationVerdict verdict;
    if (anySuccess) {
      verdict = CalibrationVerdict.ok;
    } else if (sawNonNetworkFailure) {
      // Le serveur RÉPOND (4xx/5xx/HTML) mais refuse tout → un VPN peut
      // débloquer si c'est le FAI qui interfère, sinon source morte.
      verdict = CalibrationVerdict.allFormatsRefused;
    } else {
      verdict = CalibrationVerdict.serverUnreachable;
    }
    StreamDiagnostics.instance.recordEvent(
      'calibrate',
      'Calibration terminée — verdict : ${verdict.name}',
      level: verdict == CalibrationVerdict.ok ? 'info' : 'error',
    );
    return CalibrationReport(
      verdict: verdict,
      account: account,
      accountChecked: accountChecked,
      winningFormat: winningFormat,
      formatChecked: formatChecked,
      winningUserAgent: winningUa,
      signatureChecked: true,
      avgStartupMs: avgMs,
    );
  }

  CalibrationReport _cancelledReport(
          XtreamAccountInfo? account, bool accountChecked) =>
      CalibrationReport(
        verdict: CalibrationVerdict.cancelled,
        account: account,
        accountChecked: accountChecked,
      );
}
