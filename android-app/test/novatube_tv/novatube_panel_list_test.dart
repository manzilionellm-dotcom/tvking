import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/device/data/novatube_identity.dart';
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
    source.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/refuse.m3u') {
        res.statusCode = HttpStatus.forbidden;
      } else {
        res.write('#EXTM3U\n');
        for (var i = 0; i < 4999; i++) {
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
    Future<int> envoyer(String chemin) async {
      final reponse = await http.put(endpoint, headers:auth, body:jsonEncode({
        'sources':[{'type':'m3u','label':'Mire locale','m3u_url':'$origin/$chemin'}],
      }));
      expect(reponse.statusCode, 200);
      return (jsonDecode(reponse.body) as Map<String, dynamic>)['rev'] as int;
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
    // Le premier accusé est interrompu avant Atlas. Toutes les autres requêtes
    // passent par le Worker local avec les mêmes en-têtes que sur la TV.
    final originalClient = NovatubeAtlas.clientFactory;
    final firstAck = Completer<int>();
    final retriedAck = Completer<int>();
    final allowRetry = Completer<void>();
    NovatubeAtlas.clientFactory = () => MockClient((request) async {
      if (request.url.path.endsWith('/ack')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final rev = body['source_rev'] as int;
        if (!firstAck.isCompleted) {
          firstAck.complete(rev);
          throw http.ClientException('Coupure locale avant accusé');
        }
        await allowRetry.future;
        if (!retriedAck.isCompleted) retriedAck.complete(rev);
      }
      return http.post(request.url, headers: request.headers, body: request.bodyBytes);
    });
    addTearDown(() {
      NovatubeAtlas.clientFactory = originalClient;
      if (!allowRetry.isCompleted) allowRetry.complete();
    });
    final revision = await envoyer('essai.m3u');
    try {
      expect((await debut.timeout(const Duration(seconds:5))).length, inInclusiveRange(1,48));
      expect(await confirme(revision), isFalse);
    } finally {
      suite.complete();
    }
    expect(await firstAck.future.timeout(const Duration(seconds:8)), revision);
    expect(await confirme(revision), isFalse);

    // Les adresses M3U sont chiffrées dans playlists. Le dépôt fournit
    // l'identifiant de la liste et une autre connexion relit le fichier SQLite.
    final playlistId = repo.currentPlaylists.singleWhere((p) => p.m3uUrl == '$origin/essai.m3u').id;
    Future<void> verifierSurDisque() async {
      final db = await databaseFactoryFfi.openDatabase(
        PlaylistDatabase.debugFilePath!,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        final saved = await db.rawQuery(
          'SELECT COUNT(*) AS n, COUNT(DISTINCT stream_url) AS distinctes '
          'FROM channels WHERE playlist_id = ?', [playlistId],
        );
        expect(saved.single, {'n': 5000, 'distinctes': 5000});
      } finally {
        await db.close();
      }
    }
    await verifierSurDisque();
    // Relance la veille avec la même base et le même ordre. Atlas doit
    // recevoir la révision écrite, même si son premier accusé a été perdu.
    veille.stop();
    await PlaylistDatabase.instance.closeForTesting();
    veille.start();
    allowRetry.complete();
    veille.nudge();
    expect(await retriedAck.future.timeout(const Duration(seconds:8)), revision);
    for (var i=0; i<100 && !await confirme(revision); i++) {
      await Future<void>.delayed(const Duration(milliseconds:40));
    }
    expect(await confirme(revision), isTrue);
    await verifierSurDisque();
    expect(repo.currentChannels.length, 5000);
    final refus = Completer<void>();
    void observe() {
      if (RemoteSourceRepository.lastResult.value == RemoteSyncResult.sourceFailed && !refus.isCompleted) {
        refus.complete();
      }
    }
    RemoteSourceRepository.lastResult.addListener(observe);
    addTearDown(() => RemoteSourceRepository.lastResult.removeListener(observe));
    final refusee = await envoyer('refuse.m3u');
    expect(refusee, greaterThan(revision));
    await refus.future.timeout(const Duration(seconds:5));
    await Future<void>.delayed(const Duration(milliseconds:200));
    expect(await confirme(refusee), isFalse);
    expect(repo.currentChannels.length, 5000);
  }, skip: fixture == null || !kNovatubeTv ? 'Nécessite la TV NovaTube et le serveur local.' : null);
}
