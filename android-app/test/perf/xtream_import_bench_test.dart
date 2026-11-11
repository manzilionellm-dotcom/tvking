// =========================================================
//  xtream_import_bench_test.dart — Banc de mesure de l'import Xtream
// =========================================================
//  Rejoue le VRAI parcours d'ajout d'un compte Xtream (XtreamClient +
//  PlaylistRepository + SQLite FFI) contre un serveur simulé : 919
//  catégories (comme le journal de la Fire TV AFTSS du 03/11/2026) et
//  10 000 / 50 000 / 100 000 chaînes.
//
//  Mesures (affichées en JSON, une ligne par scénario) :
//    - durée totale de l'import jusqu'à l'état publié à l'interface ;
//    - plus long blocage du fil principal (timer de 2 ms qui arrive en
//      retard = fil occupé), et nombre de blocages > 100 ms / > 700 ms
//      (700 ms = seuil du chien de garde de la boîte noire) ;
//    - pic de mémoire résidente du processus (RSS), échantillonné toutes
//      les 5 ms par un isolate séparé (il continue de mesurer même quand
//      le fil principal est bloqué).
//
//  IMPORTANT : ces chiffres viennent de la machine qui exécute le test, pas
//  d'une Fire TV. Ils servent à COMPARER avant/après sur la même machine,
//  pas à prédire les millisecondes d'un appareil réel.
//
//  Désactivé par défaut (lourd) : ZUNO_BENCH=1 flutter test test/perf/
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';

const int _kCategories = 919;

/// Catalogue Xtream synthétique : quelques grosses catégories (comme les
/// bouquets « ALL » des fournisseurs) puis une longue traîne, 2 % de chaînes
/// rangées dans deux catégories (vrai cas de dédoublonnage).
class _SyntheticXtream {
  _SyntheticXtream(this.total) {
    final math.Random rnd = math.Random(42);
    for (int i = 0; i < total; i++) {
      // 30 % des chaînes dans les 20 premières catégories, le reste réparti.
      final int cat = i % 10 < 3 ? 1 + rnd.nextInt(20) : 21 + rnd.nextInt(_kCategories - 20);
      (_byCat[cat] ??= <int>[]).add(i);
      if (rnd.nextInt(50) == 0) {
        (_byCat[1 + rnd.nextInt(_kCategories)] ??= <int>[]).add(i);
      }
    }
  }

  final int total;
  final Map<int, List<int>> _byCat = <int, List<int>>{};

  String _stream(int id, int cat) => jsonEncode(<String, Object?>{
        'num': id + 1,
        'name': 'FR| Chaîne d’essai n°$id HD',
        'stream_type': 'live',
        'stream_id': id,
        'stream_icon': 'http://logo.bench.invalid/$id.png',
        'epg_channel_id': 'chaine$id.fr',
        'added': '1700000000',
        'is_adult': '0',
        'category_id': '$cat',
        'category_ids': <int>[cat],
        'custom_sid': '',
        'tv_archive': id % 5 == 0 ? 1 : 0,
        'direct_source': '',
        'tv_archive_duration': id % 5 == 0 ? 3 : 0,
      });

  String categories() => jsonEncode(<Map<String, String>>[
        for (int c = 1; c <= _kCategories; c++)
          <String, String>{'category_id': '$c', 'category_name': 'Catégorie $c', 'parent_id': '0'},
      ]);

  String streams(int? cat) {
    final StringBuffer b = StringBuffer('[');
    bool first = true;
    void add(int id, int c) {
      if (!first) b.write(',');
      first = false;
      b.write(_stream(id, c));
    }

    if (cat == null) {
      for (final MapEntry<int, List<int>> e in _byCat.entries) {
        for (final int id in e.value) {
          add(id, e.key);
        }
      }
    } else {
      for (final int id in _byCat[cat] ?? const <int>[]) {
        add(id, cat);
      }
    }
    b.write(']');
    return b.toString();
  }

  // Réponses PRÉCALCULÉES avant les mesures : sinon le faux serveur, qui
  // fabrique ~30 Mo de JSON sur le fil principal, serait compté comme un
  // blocage de l'application.
  late final List<int> _auth = utf8.encode(jsonEncode(<String, Object?>{
    'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
    'server_info': <String, Object?>{'url': 'bench.invalid'},
  }));
  late final List<int> _cats = utf8.encode(categories());
  late final List<int> _whole = utf8.encode(streams(null));
  late final Map<int, List<int>> _perCat = <int, List<int>>{
    for (int c = 1; c <= _kCategories; c++) c: utf8.encode(streams(c)),
  };

  void prepare() {
    _auth.length;
    _cats.length;
    _whole.length;
    _perCat.length;
  }

  http.Client client() => MockClient((http.Request r) async {
        // Petite latence réseau : laisse les requêtes parallèles s'entrelacer.
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final String? action = r.url.queryParameters['action'];
        final List<int> body;
        switch (action) {
          case null:
            body = _auth;
          case 'get_live_categories':
            body = _cats;
          case 'get_live_streams':
            final String? c = r.url.queryParameters['category_id'];
            body = c == null ? _whole : _perCat[int.parse(c)]!;
          default:
            return http.Response('', 404);
        }
        return http.Response.bytes(body, 200,
            headers: <String, String>{'content-type': 'application/json'});
      });
}

/// Échantillonne le RSS du processus depuis un isolate séparé.
class _RssSampler {
  late final Isolate _isolate;
  final ReceivePort _port = ReceivePort();
  late final SendPort _control;
  final Completer<int> _peak = Completer<int>();

  static void _main(SendPort out) {
    final ReceivePort inbox = ReceivePort();
    out.send(inbox.sendPort);
    int peak = ProcessInfo.currentRss;
    final Timer t = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final int now = ProcessInfo.currentRss;
      if (now > peak) peak = now;
    });
    inbox.listen((_) {
      t.cancel();
      out.send(peak);
      inbox.close();
    });
  }

  Future<void> start() async {
    _isolate = await Isolate.spawn(_main, _port.sendPort);
    final Completer<SendPort> ready = Completer<SendPort>();
    _port.listen((Object? m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is int) {
        _peak.complete(m);
      }
    });
    _control = await ready.future;
  }

  Future<int> stop() async {
    _control.send('stop');
    final int peak = await _peak.future;
    _port.close();
    _isolate.kill();
    return peak;
  }
}

/// Mesure les retards du fil principal (timer de 2 ms).
class _LagMeter {
  final Stopwatch _sw = Stopwatch();
  Timer? _t;
  int _last = 0;
  int maxLagMs = 0;
  int over100 = 0;
  int over700 = 0;

  void start() {
    _sw.start();
    _last = _sw.elapsedMilliseconds;
    _t = Timer.periodic(const Duration(milliseconds: 2), (_) {
      final int now = _sw.elapsedMilliseconds;
      final int lag = now - _last - 2;
      _last = now;
      if (lag > maxLagMs) maxLagMs = lag;
      if (lag > 100) over100++;
      if (lag > 700) over700++;
    });
  }

  void stop() => _t?.cancel();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bool enabled = Platform.environment['ZUNO_BENCH'] == '1';
  final PlaylistRepository repo = PlaylistRepository.instance;
  late Directory dir;

  setUpAll(() async {
    if (!enabled) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('zuno-import-bench-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    await PlaylistDatabase.instance.database;
  });

  tearDownAll(() async {
    if (!enabled) return;
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await dir.delete(recursive: true);
  });

  for (final int total in <int>[10000, 50000, 100000]) {
    test('banc import Xtream $total chaînes / $_kCategories catégories', () async {
      RepairFlags.debugReset();
      ImportProgressBus.clear();
      final Database db = await PlaylistDatabase.instance.database;
      await db.delete('playlists');
      await repo.initialize();
      final _SyntheticXtream server = _SyntheticXtream(total)..prepare();

      final _RssSampler rss = _RssSampler();
      await rss.start();
      final int rssBefore = ProcessInfo.currentRss;
      final _LagMeter lag = _LagMeter()..start();
      final Stopwatch sw = Stopwatch()..start();

      final saved = await repo.addXtreamPlaylist(
        name: 'Banc $total',
        serverUrl: 'http://bench.invalid',
        username: 'u',
        password: 'p',
        httpClient: server.client(),
      );
      final int totalMs = sw.elapsedMilliseconds;
      lag.stop();
      final int peak = await rss.stop();

      final int rows = (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM channels WHERE playlist_id = ?',
              <Object>[saved.id!]))
          .first['n']! as int;
      // ignore: avoid_print
      print('ZUNO_BENCH ${jsonEncode(<String, Object>{
            'chaines_demandees': total,
            'chaines_en_base': rows,
            'chaines_en_memoire_ui': repo.currentChannels.length,
            'duree_ms': totalMs,
            'blocage_max_ms': lag.maxLagMs,
            'blocages_sup_100ms': lag.over100,
            'blocages_sup_700ms': lag.over700,
            'rss_avant_mo': rssBefore ~/ (1024 * 1024),
            'rss_pic_mo': peak ~/ (1024 * 1024),
            'rss_pic_delta_mo': (peak - rssBefore) ~/ (1024 * 1024),
          })}');
      expect(rows, greaterThan(0));
    }, skip: enabled ? false : 'banc lourd : ZUNO_BENCH=1 pour l’exécuter',
        timeout: const Timeout(Duration(minutes: 10)));
  }

  // Scénario du journal Fire TV : 50 000 chaînes DÉJÀ chargées à l'écran,
  // puis actualisation de la source Xtream (919 catégories). L'ancienne
  // liste reste affichée pendant l'import : c'est le pic mémoire réel.
  test('banc actualisation Xtream avec 50 000 chaînes déjà chargées', () async {
    RepairFlags.debugReset();
    ImportProgressBus.clear();
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('playlists');
    await repo.initialize();
    final _SyntheticXtream server = _SyntheticXtream(50000)..prepare();
    final saved = await repo.addXtreamPlaylist(
      name: 'Banc actualisation',
      serverUrl: 'http://bench.invalid',
      username: 'u',
      password: 'p',
      httpClient: server.client(),
    );
    expect(repo.currentChannels.length, 50000);
    // Laisse retomber l'import initial avant de mesurer l'actualisation.
    await Future<void>.delayed(const Duration(seconds: 2));

    final _RssSampler rss = _RssSampler();
    await rss.start();
    final int rssBefore = ProcessInfo.currentRss;
    final _LagMeter lag = _LagMeter()..start();
    final Stopwatch sw = Stopwatch()..start();
    final bool ok = await http.runWithClient(
      () => repo.refreshPlaylist(saved),
      server.client,
    );
    final int totalMs = sw.elapsedMilliseconds;
    lag.stop();
    final int peak = await rss.stop();
    // ignore: avoid_print
    print('ZUNO_BENCH ${jsonEncode(<String, Object>{
          'scenario': 'actualisation_50000_deja_chargees',
          'reussi': ok,
          'chaines_en_memoire_ui': repo.currentChannels.length,
          'duree_ms': totalMs,
          'blocage_max_ms': lag.maxLagMs,
          'blocages_sup_100ms': lag.over100,
          'rss_avant_mo': rssBefore ~/ (1024 * 1024),
          'rss_pic_mo': peak ~/ (1024 * 1024),
          'rss_pic_delta_mo': (peak - rssBefore) ~/ (1024 * 1024),
        })}');
    expect(ok, isTrue);
  }, skip: enabled ? false : 'banc lourd : ZUNO_BENCH=1 pour l’exécuter',
      timeout: const Timeout(Duration(minutes: 10)));
}
