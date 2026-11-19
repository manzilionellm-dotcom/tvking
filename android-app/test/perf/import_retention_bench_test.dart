// =========================================================
//  import_retention_bench_test.dart — Catalogues encore vivants
// =========================================================
//  Question mesurée : combien d'objets [Channel] restent EN MÉMOIRE après un
//  ajout puis une actualisation Xtream de 50 000 chaînes, PENDANT que le
//  guide (xmltv.php) se télécharge encore — cas réel d'une box : le XMLTV
//  d'un fournisseur prend plusieurs minutes.
//
//  Méthode exacte (pas de RSS) : le service de la VM Dart force une
//  collecte complète puis compte les instances vivantes de la classe
//  Channel. L'écran garde un catalogue (50 000) : tout le reste est retenu
//  inutilement.
//
//  Le faux fournisseur est un VRAI serveur HTTP local (127.0.0.1) : le
//  guide, téléchargé dans un isolate avec son propre client, reste ainsi
//  réellement « en cours » (le serveur ne répond jamais à xmltv.php).
//
//  Désactivé par défaut : ZUNO_BENCH=1 flutter test test/perf/
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service.dart' as vm;
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';

const int _kCategories = 919;
const int _kChannels = 50000;

/// Fournisseur Xtream local : réponses précalculées, guide jamais servi.
class _LocalXtream {
  late final HttpServer _server;
  final List<HttpRequest> _heldGuides = <HttpRequest>[];
  late final List<int> _auth, _cats, _whole;
  late final Map<int, List<int>> _perCat;

  String get url => 'http://127.0.0.1:${_server.port}';
  int get pendingGuides => _heldGuides.length;

  static String _stream(int id, int cat) => jsonEncode(<String, Object?>{
        'num': id + 1,
        'name': 'FR| Chaîne d’essai n°$id HD',
        'stream_type': 'live',
        'stream_id': id,
        'stream_icon': 'http://logo.bench.invalid/$id.png',
        'epg_channel_id': 'chaine$id.fr',
        'category_id': '$cat',
        'tv_archive': 0,
        'tv_archive_duration': 0,
      });

  Future<void> start() async {
    final Map<int, List<int>> byCat = <int, List<int>>{};
    for (int i = 0; i < _kChannels; i++) {
      (byCat[1 + i % _kCategories] ??= <int>[]).add(i);
    }
    String streams(Iterable<MapEntry<int, List<int>>> cats) {
      final StringBuffer b = StringBuffer('[');
      bool first = true;
      for (final MapEntry<int, List<int>> e in cats) {
        for (final int id in e.value) {
          if (!first) b.write(',');
          first = false;
          b.write(_stream(id, e.key));
        }
      }
      b.write(']');
      return b.toString();
    }

    _auth = utf8.encode(jsonEncode(<String, Object?>{
      'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
    }));
    _cats = utf8.encode(jsonEncode(<Map<String, String>>[
      for (int c = 1; c <= _kCategories; c++)
        <String, String>{'category_id': '$c', 'category_name': 'Catégorie $c'},
    ]));
    _whole = utf8.encode(streams(byCat.entries));
    _perCat = <int, List<int>>{
      for (final MapEntry<int, List<int>> e in byCat.entries)
        e.key: utf8.encode(streams(<MapEntry<int, List<int>>>[e])),
    };

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((HttpRequest r) async {
      if (r.uri.path.endsWith('xmltv.php')) {
        _heldGuides.add(r); // guide « en cours » : jamais de réponse
        return;
      }
      final String? action = r.uri.queryParameters['action'];
      final String? cat = r.uri.queryParameters['category_id'];
      final List<int> body = switch (action) {
        null => _auth,
        'get_live_categories' => _cats,
        'get_live_streams' => cat == null ? _whole : _perCat[int.parse(cat)] ?? utf8.encode('[]'),
        _ => utf8.encode('[]'),
      };
      r.response.headers.contentType = ContentType.json;
      r.response.add(body);
      await r.response.close();
    });
  }

  Future<void> stop() async {
    for (final HttpRequest r in _heldGuides) {
      try {
        r.response.statusCode = 503;
        await r.response.close();
      } catch (_) {}
    }
    await _server.close(force: true);
  }
}

/// Compte les [Channel] vivants après une collecte complète (VM service).
class _HeapProbe {
  late final vm.VmService _service;
  late final String _isolateId;

  Future<void> connect() async {
    dev.ServiceProtocolInfo info = await dev.Service.getInfo();
    if (info.serverWebSocketUri == null) {
      info = await dev.Service.controlWebServer(enable: true);
    }
    final Uri? ws = info.serverWebSocketUri;
    if (ws == null) throw StateError('Service VM indisponible');
    _service = await vmServiceConnectUri(ws.toString());
    _isolateId = dev.Service.getIsolateId(Isolate.current)!;
  }

  Future<int> liveChannels() async {
    final vm.AllocationProfile p =
        await _service.getAllocationProfile(_isolateId, gc: true);
    int n = 0;
    for (final vm.ClassHeapStats s in p.members ?? const <vm.ClassHeapStats>[]) {
      final vm.ClassRef? c = s.classRef;
      if (c?.name == 'Channel' &&
          (c?.library?.uri ?? '').endsWith('features/channels/domain/channel.dart')) {
        n += s.instancesCurrent ?? 0;
      }
    }
    return n;
  }

  Future<int> heapMb() async {
    final vm.MemoryUsage u = await _service.getMemoryUsage(_isolateId);
    return (u.heapUsage ?? 0) ~/ (1024 * 1024);
  }

  Future<void> close() => _service.dispose();
}

/// flutter_test remplace HttpClient par un faux qui répond 400 : ce banc
/// a besoin du vrai client, uniquement vers son serveur local 127.0.0.1.
class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bool enabled = Platform.environment['ZUNO_BENCH'] == '1';
  HttpOverrides.global = _RealHttp();

  test('catalogues Channel vivants pendant le guide (ajout puis actualisation)',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    final Directory dir = await Directory.systemTemp.createTemp('zuno-retention-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    RepairFlags.debugReset();
    ImportProgressBus.clear();
    final PlaylistRepository repo = PlaylistRepository.instance;
    await repo.initialize();
    final _LocalXtream server = _LocalXtream();
    await server.start();
    final _HeapProbe probe = _HeapProbe();
    await probe.connect();
    try {
      final saved = await repo.addXtreamPlaylist(
        name: 'Rétention',
        serverUrl: server.url,
        username: 'u',
        password: 'p',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      final int afterAdd = await probe.liveChannels();
      final int heapAfterAdd = await probe.heapMb();
      final int guidesAfterAdd = server.pendingGuides;

      final bool ok = await repo.refreshPlaylist(saved);
      await Future<void>.delayed(const Duration(seconds: 1));
      final int afterRefresh = await probe.liveChannels();
      final int heapAfterRefresh = await probe.heapMb();
      // ignore: avoid_print
      print('ZUNO_BENCH ${jsonEncode(<String, Object>{
            'scenario': 'retention_pendant_guide',
            'catalogue_ecran': repo.currentChannels.length,
            'guides_en_cours_apres_ajout': guidesAfterAdd,
            'channel_vivants_apres_ajout': afterAdd,
            'tas_dart_mo_apres_ajout': heapAfterAdd,
            'guides_en_cours_apres_actualisation': server.pendingGuides,
            'channel_vivants_apres_actualisation': afterRefresh,
            'tas_dart_mo_apres_actualisation': heapAfterRefresh,
            'actualisation_reussie': ok,
          })}');
      expect(ok, isTrue);
    } finally {
      await probe.close();
      await server.stop();
      await PlaylistDatabase.instance.closeForTesting();
      PlaylistDatabase.debugFilePath = null;
      await dir.delete(recursive: true);
    }
  }, skip: enabled ? false : 'banc lourd : ZUNO_BENCH=1 pour l’exécuter',
      timeout: const Timeout(Duration(minutes: 10)));
}
