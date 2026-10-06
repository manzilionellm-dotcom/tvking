// =========================================================
//  last_known_good_test.dart — Une mauvaise liste ne détruit jamais la
//  dernière bonne (vrai code de synchronisation, vrai SQLite)
// =========================================================
//  RemoteSourceRepository.sync() réel, PlaylistRepository réel (SQLite via
//  sqflite_common_ffi), serveur et fournisseurs simulés par MockClient
//  (http.runWithClient) — aucune adresse réelle.
//
//  Pannes injectées sur la NOUVELLE liste, l'ancienne étant retirée par le
//  panel : HTTP 500, délai dépassé, liste vide, fichier invalide ; puis le
//  tour suivant où la nouvelle liste est mise de côté (délai de réessai).
//  Attendu : l'ancienne liste reste chargée (mêmes chaînes) tant qu'aucune
//  nouvelle n'est chargée ; le rapport de lecture dit « refusée, ancienne
//  gardée » avec la révision servie.
//  Contre-preuve : avec le repli `zuno.source.drop_first_legacy` (ancien
//  ordre), le même scénario efface la bonne liste — le test détecte bien
//  le défaut.
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

const String kMac = 'MK:AA:BB:CC:DD:EE';

String _m3u(String tag, int n) {
  final StringBuffer sb = StringBuffer('#EXTM3U\n');
  for (int i = 0; i < n; i++) {
    sb.write('#EXTINF:-1 tvg-id="$tag$i" group-title="G",$tag $i\nhttp://127.0.0.1/s/$tag/$i.ts\n');
  }
  return sb.toString();
}

/// Serveur simulé : `served` = listes que le panel sert, `rev` = révision.
class _World {
  List<Map<String, Object?>> served = <Map<String, Object?>>[];
  int rev = 0;

  http.Client client() => MockClient((http.Request r) async {
        final String path = r.url.path;
        if (path.startsWith('/api/device-source/')) {
          return http.Response(jsonEncode(<String, Object?>{
            'mac': kMac,
            'sources': served,
            'source': served.isEmpty ? null : served.first,
            'updated_at': 1791300000000 + rev,
            'rev': rev,
          }), 200);
        }
        if (path.startsWith('/api/')) return http.Response('{}', 404);
        switch (r.url.host) {
          case 'good-a.invalid':
            return http.Response(_m3u('A', 5), 200);
          case 'good-b.invalid':
            return http.Response(_m3u('B', 7), 200);
          case 'http500.invalid':
            return http.Response('erreur', 500);
          case 'timeout.invalid':
            throw TimeoutException('fournisseur muet (injecté)');
          case 'empty.invalid':
            return http.Response('', 200);
          case 'html.invalid':
            return http.Response('<html><body>Forbidden</body></html>', 200);
        }
        return http.Response('inconnu', 404);
      });

  void serve(String host) {
    rev += 1;
    served = <Map<String, Object?>>[
      <String, Object?>{'type': 'm3u', 'm3u_url': 'http://$host/list.m3u', 'origin': 'panel'},
    ];
  }

  void clear() {
    rev += 1;
    served = <Map<String, Object?>>[];
  }
}

Future<RemoteSyncResult> _sync(_World w, {bool force = true}) =>
    http.runWithClient(() => RemoteSourceRepository.sync(force: force), w.client);

Future<List<Playlist>> _lists() => PlaylistRepository.instance.getAllPlaylists();

bool _has(List<Playlist> ps, String host) => ps.any((Playlist p) => (p.m3uUrl ?? '').contains(host));

int _channels(List<Playlist> ps, String host) =>
    ps.firstWhere((Playlist p) => (p.m3uUrl ?? '').contains(host)).channelCount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('zuno-lkg-');
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = true;
    SharedPreferences.setMockInitialValues(<String, Object>{'device.virtual_mac.v1': kMac});
    RepairFlags.sourceDropFirstLegacy = false;
    RepairFlags.sourceRetryAlways = false;
    RemoteSourceRepository.lastReport = null;
  });

  tearDown(() async {
    RepairFlags.sourceDropFirstLegacy = false;
    await PlaylistDatabase.instance.closeForTesting();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('HTTP 500, délai dépassé, liste vide, fichier invalide, puis tour en délai de réessai : la liste A reste',
      () async {
    final _World w = _World();
    w.serve('good-a.invalid');
    expect(await _sync(w), RemoteSyncResult.loaded);
    expect(_channels(await _lists(), 'good-a.invalid'), 5);

    for (final String bad in <String>['http500.invalid', 'timeout.invalid', 'empty.invalid', 'html.invalid']) {
      w.serve(bad);
      final RemoteSyncResult r = await _sync(w);
      final List<Playlist> ps = await _lists();
      expect(r, RemoteSyncResult.sourceFailed, reason: bad);
      expect(_has(ps, 'good-a.invalid'), isTrue, reason: '$bad : la dernière bonne liste doit rester');
      expect(_channels(ps, 'good-a.invalid'), 5, reason: '$bad : ses chaînes aussi');
      expect(_has(ps, bad), isFalse, reason: '$bad : la candidate refusée ne reste pas');
      expect(RemoteSourceRepository.lastReport!.result, 'sourceFailed');
      expect(RemoteSourceRepository.lastReport!.keptPrevious, isTrue, reason: bad);
      expect(RemoteSourceRepository.lastReport!.configRev, w.rev, reason: 'révision servie rapportée');
    }

    // Tour suivant SANS forçage : html.invalid vient d'échouer → mise de côté
    // (non essayée). Défaut corrigé le 06/10/2026 : A était alors effacée.
    final RemoteSyncResult skipped = await _sync(w, force: false);
    expect(skipped, RemoteSyncResult.sourceFailed);
    expect(_channels(await _lists(), 'good-a.invalid'), 5, reason: 'liste en délai de réessai : A reste');

    // Une bonne liste arrive : B chargée, ALORS seulement A part.
    w.serve('good-b.invalid');
    expect(await _sync(w), RemoteSyncResult.loaded);
    final List<Playlist> after = await _lists();
    expect(_channels(after, 'good-b.invalid'), 7);
    expect(_has(after, 'good-a.invalid'), isFalse);
    expect(RemoteSourceRepository.lastReport!.keptPrevious, isFalse);

    // Le panel vide tout : intention explicite, on efface.
    w.clear();
    await _sync(w);
    expect(await _lists(), isEmpty);
  });

  test('contre-preuve : ancien ordre (effacer puis importer) → la bonne liste est perdue', () async {
    final _World w = _World();
    w.serve('good-a.invalid');
    expect(await _sync(w), RemoteSyncResult.loaded);
    RepairFlags.sourceDropFirstLegacy = true;
    w.serve('http500.invalid');
    await _sync(w);
    expect(_has(await _lists(), 'good-a.invalid'), isFalse,
        reason: 'l’ancien ordre détruit la dernière bonne liste : le test ci-dessus le détecterait');
  });
}
