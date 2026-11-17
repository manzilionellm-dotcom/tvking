import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/device/data/novatube_identity.dart';
import 'package:tv_king/features/playlists/data/box_reset.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/subscription/data/novatube_atlas.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = Platform.environment['NOVATUBE_ATLAS_LOCAL'];
  test('le panel reçoit la confirmation seulement après un enregistrement réussi', () async {
    HttpOverrides.global = null;
    final config = jsonDecode(await File(fixture!).readAsString()) as Map<String, dynamic>;
    final base = Uri.parse(config['url'] as String);
    expect(base.host, '127.0.0.1');
    NovatubeAtlas.baseUrl = base.toString();
    SharedPreferences.setMockInitialValues({});
    final seed = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    NovatubeIdentity.seedProvider = () async => seed;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('listes-du-panel-');
    PlaylistDatabase.debugFilePath = '${tmp.path}/source.db';
    addTearDown(() async {
      await PlaylistDatabase.instance.closeForTesting();
      await tmp.delete(recursive: true);
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    PlaylistRepository.mergeAllPlaylists = true;
    final repo = PlaylistRepository.instance;
    await repo.initialize();
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => source.close(force: true));
    final origin = 'http://127.0.0.1:${source.port}';
    final suite = Completer<void>();
    addTearDown(() { if (!suite.isCompleted) suite.complete(); });
    int fileRequests = 0;
    source.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/player_api.php') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'user_info': {'auth': 0}}));
      } else if (req.uri.path == '/manuel.m3u') {
        res.write('#EXTM3U\n#EXTINF:-1,Perso\n$origin/manuel.ts\n');
      } else if (req.uri.path == '/get.php') {
        fileRequests++;
        expect(req.uri.queryParameters['password'], 'p+q');
        res.write('#EXTM3U\n#EXTINF:-1,Mire fournie\n$origin/fournie.ts\n');
      } else if (req.uri.path == '/refuse.m3u') {
        res.statusCode = HttpStatus.forbidden;
      } else {
        res.write('#EXTM3U\n');
        for (var i = 0; i < 300; i++) {
          res.write('#EXTINF:-1 group-title="Test",Mire $i\n$origin/direct/$i.ts\n');
        }
        await res.flush();
        await suite.future;
        res.write('#EXTINF:-1 group-title="Test",Fin\n$origin/direct/fin.ts\n');
      }
      await res.close();
    });
    final licence = SubscriptionState.instance;
    await licence.initialize();
    expect(await licence.syncWithBackend(), RemoteSyncOutcome.applied);
    final login = await http.post(base.resolve('/api/v1/auth/login'),
        headers: {'Content-Type':'application/json'},
        body: jsonEncode({'email':'admin','password':config['adminSecret']}));
    expect(login.statusCode, 200);
    final token = (jsonDecode(login.body) as Map<String, dynamic>)['token'];
    final mac = await NovatubeIdentity.instance.mac;
    final endpoint = base.resolve('/api/v1/sources/${Uri.encodeComponent(mac)}');
    final auth = {'Content-Type':'application/json','Authorization':'Bearer $token'};
    Future<String> envoyer(String chemin) async {
      final reponse = await http.put(endpoint, headers:auth, body:jsonEncode({
        'sources':[{'type':'m3u','label':'Mire locale','m3u_url':'$origin/$chemin'}],
      }));
      expect(reponse.statusCode, 200);
      return (jsonDecode(reponse.body) as Map)['order_id'] as String;
    }
    Future<String?> ordre(String id) async {
      final uri = base.resolve('/api/v1/orders').replace(queryParameters: {'mac': mac});
      final response = await http.get(uri, headers: auth);
      expect(response.statusCode, 200);
      final items = (jsonDecode(response.body) as Map)['items'] as List;
      for (final item in items.whereType<Map>()) {
        if (item['order_id'] == id) return item['state'] as String?;
      }
      return null;
    }
    Future<void> attendre(Future<bool> Function() condition, String attendu) async {
      final clock = Stopwatch()..start();
      while (clock.elapsed < const Duration(seconds: 15)) {
        if (await condition()) return;
        await Future<void>.delayed(const Duration(milliseconds: 75));
      }
      fail(attendu);
    }
    Future<bool> confirme(int revision) async {
      final r = await http.get(Uri.parse('$endpoint/revisions'), headers:auth);
      expect(r.statusCode, 200);
      final liste = (jsonDecode(r.body) as Map<String, dynamic>)['revisions'] as List<dynamic>;
      return liste.any((e) => e['rev'] == revision && e['state'] == 'acknowledged');
    }
    final reveil = Completer<void>();
    SubscriptionBackend.onStatusBody = (_) { if (!reveil.isCompleted) reveil.complete(); };
    addTearDown(() { SubscriptionBackend.onStatusBody = null; });
    final veille = RemoteActivationWatch.instance;
    veille.start();
    addTearDown(veille.stop);
    await reveil.future.timeout(const Duration(seconds:15));
    final debut = repo.channelsStream.firstWhere((c) => c.isNotEmpty);
    await envoyer('essai.m3u');
    try {
      expect((await debut.timeout(const Duration(seconds:5))).length, inInclusiveRange(1,48));
      expect(await confirme(1), isFalse);
    } finally {
      suite.complete();
    }
    for (var i=0; i<100 && !await confirme(1); i++) {
      await Future<void>.delayed(const Duration(milliseconds:40));
    }
    expect(await confirme(1), isTrue);
    expect(repo.currentChannels.length, 301);
    final refus = Completer<void>();
    void observe() {
      if (RemoteSourceRepository.lastResult.value == RemoteSyncResult.sourceFailed && !refus.isCompleted) {
        refus.complete();
      }
    }
    RemoteSourceRepository.lastResult.addListener(observe);
    addTearDown(() => RemoteSourceRepository.lastResult.removeListener(observe));
    final refuse = await envoyer('refuse.m3u');
    await refus.future.timeout(const Duration(seconds:5));
    await Future<void>.delayed(const Duration(milliseconds:200));
    expect(await confirme(2), isFalse);
    expect(repo.currentChannels.length, 301);
    await attendre(() async => await ordre(refuse) == 'failed', 'refus fournisseur remonté');
    await repo.addM3uPlaylist(name: 'Perso', url: '$origin/manuel.m3u');
    final ajout = await envoyer('get.php?username=u&password=p%2Bq&type=m3u_plus');
    await attendre(() async => await ordre(ajout) == 'applied', 'lien M3U utilisable enregistré');
    expect(await confirme(3), isTrue);
    expect(fileRequests, 1);
    expect((await repo.getAllPlaylists()).map((p) => p.name), containsAll(['Perso','Mire locale']));

    final retrait = await http.delete(endpoint, headers: auth);
    expect(retrait.statusCode, 200);
    final idRetrait = (jsonDecode(retrait.body) as Map)['order_id'] as String;
    await attendre(() async => await ordre(idRetrait) == 'applied', 'retrait confirmé après effacement');
    expect((await repo.getAllPlaylists()).map((p) => p.name), ['Perso']);

    final reset = await http.post(Uri.parse('$endpoint/reset'), headers: auth);
    expect(reset.statusCode, 200);
    final stamp = (jsonDecode(reset.body) as Map)['reset_at'] as int;
    await attendre(() async => (await repo.getAllPlaylists()).isEmpty, 'remise à neuf locale');
    final prefs = await SharedPreferences.getInstance();
    await attendre(() async => prefs.getInt(BoxReset.appliedKey) == stamp, 'effacement terminé');
    expect(await NovatubeIdentity.instance.mac, mac);
    expect(licence.status, SubscriptionStatus.trialActive);
    await repo.addM3uPlaylist(name: 'Après le reset', url: '$origin/manuel.m3u');
    expect(await BoxReset.maybeApply(stamp), isFalse);
    expect((await repo.getAllPlaylists()).single.name, 'Après le reset');
  }, timeout: const Timeout(Duration(minutes: 2)), skip: fixture == null || !kNovatubeTv ? 'Nécessite la TV NovaTube et le serveur local.' : null);
}
