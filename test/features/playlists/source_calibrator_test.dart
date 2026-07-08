// =========================================================
//  source_calibrator_test.dart — Orchestrateur « Optimiser la source »
// =========================================================
//  Toutes les E/S (compte, échantillon, sondes, persistance) sont
//  injectées : on teste la LOGIQUE d'orchestration pure — ordre des
//  étapes, arrêt sur compte mort, choix + persistance du format et de
//  la signature, verdicts, moyenne de démarrage, annulation.
// =========================================================

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/player/data/xtream_url_variants.dart';
import 'package:tv_king/features/playlists/data/source_calibrator.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

Playlist _xtream({int id = 1}) => Playlist(
      id: id,
      name: 'Source test',
      type: PlaylistType.xtream,
      createdAt: 0,
      xtreamServer: 'http://host.tv:8080',
      xtreamUsername: 'U',
      xtreamPassword: 'P',
    );

Playlist _m3u() => const Playlist(
      id: 2,
      name: 'M3U test',
      type: PlaylistType.m3u,
      createdAt: 0,
      m3uUrl: 'http://cdn.tv/list.m3u',
    );

StreamProbeResult _ok(String url, {int ttfb = 500}) => StreamProbeResult(
      originalUrl: url,
      finalUrl: url,
      success: true,
      mime: 'video/mp2t',
      timeToFirstByte: ttfb,
    );

StreamProbeResult _http404(String url) => StreamProbeResult(
      originalUrl: url,
      finalUrl: url,
      success: false,
      errorCode: 404,
      errorReason: 'Serveur indisponible (404)',
      timeToFirstByte: 40,
    );

StreamProbeResult _dead(String url) => StreamProbeResult(
      originalUrl: url,
      finalUrl: url,
      success: false,
      errorReason: 'Le serveur ne répond pas — réessaie',
    );

const XtreamAccountInfo _activeAccount = XtreamAccountInfo(
  status: 'Active',
  maxConnections: 1,
  activeCons: 0,
);

final List<String> _samples = <String>[
  'http://host.tv:8080/U/P/1.ts',
  'http://host.tv:8080/U/P/2.ts',
  'http://host.tv:8080/U/P/3.ts',
];

/// Fabrique un calibrateur entièrement « fake ». [probeByUrl] décide du
/// résultat de chaque sonde unitaire ; [uaResult] celui de la sonde
/// multi-signatures.
SourceCalibrator _calibrator({
  required Playlist playlist,
  Future<XtreamAccountInfo> Function()? account,
  List<String>? samples,
  required StreamProbeResult Function(String url, String? ua) probeByUrl,
  UserAgentProbeResult? uaResult,
  List<String>? persistedFormats,
  List<String>? persistedUas,
  List<String>? probedUrls,
}) {
  return SourceCalibrator(
    playlist: playlist,
    accountFetcher: account ?? () async => _activeAccount,
    sampleUrls: () async => samples ?? _samples,
    probeOnce: (
      String url, {
      Duration timeout = SourceCalibrator.kProbeTimeout,
      String? userAgent,
    }) async {
      probedUrls?.add(url);
      return probeByUrl(url, userAgent);
    },
    probeUserAgents: (
      String url, {
      required List<String> candidates,
      Duration timeout = SourceCalibrator.kProbeTimeout,
    }) async {
      return uaResult ??
          UserAgentProbeResult(
            workingUserAgent: candidates.first,
            attempts: <String, StreamProbeResult>{
              candidates.first: _ok(url),
            },
          );
    },
    persistFormat: (int pid, XtreamContentType type, String code) async {
      persistedFormats?.add('$pid/${type.name}/$code');
    },
    persistUserAgent: (int pid, String ua) async {
      persistedUas?.add('$pid/$ua');
    },
  );
}

void main() {
  test('compte expiré → arrêt immédiat, AUCUNE sonde, verdict clair',
      () async {
    final List<String> probed = <String>[];
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      account: () async => XtreamAccountInfo(
        status: 'Expired',
        expDate: DateTime(2020),
      ),
      probeByUrl: (String url, _) => _ok(url),
      probedUrls: probed,
    );
    final CalibrationReport r = await c.run();
    expect(r.verdict, CalibrationVerdict.accountExpired);
    expect(r.accountChecked, isTrue);
    expect(r.accountOk, isFalse);
    expect(probed, isEmpty);
  });

  test('date passée = expiré même si status dit « Active »', () async {
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      account: () async => XtreamAccountInfo(
        status: 'Active',
        expDate: DateTime(2020),
      ),
      probeByUrl: (String url, _) => _ok(url),
    );
    expect((await c.run()).verdict, CalibrationVerdict.accountExpired);
  });

  test('API compte injoignable → serverUnreachable', () async {
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      account: () async => throw TimeoutException('timeout'),
      probeByUrl: (String url, _) => _ok(url),
    );
    expect((await c.run()).verdict, CalibrationVerdict.serverUnreachable);
  });

  test('aucune chaîne échantillon → noChannels', () async {
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      samples: const <String>[],
      probeByUrl: (String url, _) => _ok(url),
    );
    expect((await c.run()).verdict, CalibrationVerdict.noChannels);
  });

  test(
      'cas France 2 : .ts en 404, /live/….m3u8 OK partout → format '
      'gagnant persisté + démarrage moyen', () async {
    final List<String> formats = <String>[];
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      probeByUrl: (String url, _) =>
          url.contains('/live/') && url.endsWith('.m3u8')
              ? _ok(url, ttfb: 800)
              : _http404(url),
      persistedFormats: formats,
    );
    final CalibrationReport r = await c.run();
    expect(r.verdict, CalibrationVerdict.ok);
    expect(r.winningFormat, 'live:m3u8');
    expect(formats, <String>['1/live/live:m3u8']);
    // Moyenne sur TOUTES les sondes réussies : 3 × 800 ms (cascade +
    // validation) + 500 ms (sonde signature, ttfb du fake par défaut).
    expect(r.avgStartupMs, (800 * 3 + 500) ~/ 4);
    expect(r.signatureChecked, isTrue);
  });

  test('format d\'origine déjà bon → RIEN persisté, verdict ok', () async {
    final List<String> formats = <String>[];
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      probeByUrl: (String url, _) => _ok(url, ttfb: 300),
      persistedFormats: formats,
    );
    final CalibrationReport r = await c.run();
    expect(r.verdict, CalibrationVerdict.ok);
    expect(r.winningFormat, isNull);
    expect(formats, isEmpty);
    // 3 × 300 ms (cascade + validation) + 500 ms (sonde signature).
    expect(r.avgStartupMs, (300 * 3 + 500) ~/ 4);
  });

  test(
      'tous les formats refusés mais une AUTRE signature passe → UA '
      'persistée pour la source', () async {
    final List<String> uas = <String>[];
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      probeByUrl: (String url, _) => _http404(url),
      uaResult: UserAgentProbeResult(
        workingUserAgent: 'IPTVSmartersPlayer',
        attempts: <String, StreamProbeResult>{
          'VLC/3.0.18 LibVLC/3.0.18': _http404(_samples.first),
          'IPTVSmartersPlayer': _ok(_samples.first, ttfb: 1200),
        },
      ),
      persistedUas: uas,
    );
    final CalibrationReport r = await c.run();
    expect(r.verdict, CalibrationVerdict.ok);
    expect(r.winningUserAgent, 'IPTVSmartersPlayer');
    expect(uas, <String>['1/IPTVSmartersPlayer']);
  });

  test('serveur répond mais refuse TOUT → allFormatsRefused (VPN)',
      () async {
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      probeByUrl: (String url, _) => _http404(url),
      uaResult: const UserAgentProbeResult(
        workingUserAgent: null,
        attempts: <String, StreamProbeResult>{},
      ),
    );
    final CalibrationReport r = await c.run();
    expect(r.verdict, CalibrationVerdict.allFormatsRefused);
  });

  test('échecs de niveau RÉSEAU partout → serverUnreachable', () async {
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      probeByUrl: (String url, _) => _dead(url),
      uaResult: const UserAgentProbeResult(
        workingUserAgent: null,
        attempts: <String, StreamProbeResult>{},
      ),
    );
    final CalibrationReport r = await c.run();
    expect(r.verdict, CalibrationVerdict.serverUnreachable);
  });

  test('source M3U : pas d\'étape compte, pas de cascade de format, '
      'mais signature sondée', () async {
    final List<String> formats = <String>[];
    final List<String> probed = <String>[];
    final SourceCalibrator c = _calibrator(
      playlist: _m3u(),
      samples: const <String>['http://cdn.tv/stream1.m3u8'],
      probeByUrl: (String url, _) => _ok(url),
      persistedFormats: formats,
      probedUrls: probed,
    );
    final CalibrationReport r = await c.run();
    expect(r.verdict, CalibrationVerdict.ok);
    expect(r.accountChecked, isFalse);
    expect(r.formatChecked, isFalse);
    expect(probed, isEmpty, reason: 'aucune cascade pour une M3U');
    expect(r.signatureChecked, isTrue);
  });

  test('annulation → verdict cancelled, étapes suivantes non exécutées',
      () async {
    final List<String> probed = <String>[];
    final SourceCalibrator c = _calibrator(
      playlist: _xtream(),
      probeByUrl: (String url, _) => _ok(url),
      probedUrls: probed,
    );
    c.cancel();
    final CalibrationReport r = await c.run();
    expect(r.verdict, CalibrationVerdict.cancelled);
    expect(probed, isEmpty);
  });

  test('la progression annonce les 4 étapes dans l\'ordre', () async {
    final List<int> steps = <int>[];
    final SourceCalibrator c = SourceCalibrator(
      playlist: _xtream(),
      onProgress: (CalibrationProgress p) => steps.add(p.step),
      accountFetcher: () async => _activeAccount,
      sampleUrls: () async => _samples,
      probeOnce: (
        String url, {
        Duration timeout = SourceCalibrator.kProbeTimeout,
        String? userAgent,
      }) async =>
          _ok(url),
      probeUserAgents: (
        String url, {
        required List<String> candidates,
        Duration timeout = SourceCalibrator.kProbeTimeout,
      }) async =>
          UserAgentProbeResult(
        workingUserAgent: candidates.first,
        attempts: <String, StreamProbeResult>{candidates.first: _ok(url)},
      ),
      persistFormat: (_, __, ___) async {},
      persistUserAgent: (_, __) async {},
    );
    await c.run();
    expect(steps, <int>[1, 2, 3, 4]);
  });
}
