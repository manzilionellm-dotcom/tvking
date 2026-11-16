import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/open_source_input.dart';

/// Le réseau rend la première tranche puis attend le signal du test.
class _Compte extends http.BaseClient {
  _Compte({this.invalide = false});
  final bool invalide;
  final connecte = Completer<void>();
  final continuer = Completer<void>();
  int catalogues = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final action = request.url.queryParameters['action'];
    Stream<List<int>> reponse() async* {
      if (action == 'get_live_streams') {
        catalogues++;
        final lignes = List.generate(180, (i) => jsonEncode({
          'stream_id': i + 1, 'name': 'Chaîne $i', 'category_id': '1',
        }));
        yield utf8.encode('[${lignes.join(',')},');
        connecte.complete();
        await continuer.future;
        yield utf8.encode(invalide ? 'erreur' : '{"stream_id":181,"name":"Fin","category_id":"1"}]');
      } else if (action == 'get_live_categories') {
        yield utf8.encode('[{"category_id":"1","category_name":"Groupe"}]');
      } else {
        yield utf8.encode('{"user_info":{"auth":1,"status":"Active"},"server_info":{}}');
      }
    }
    return http.StreamedResponse(reponse(), 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dossier;
  final repo = PlaylistRepository.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dossier = await Directory.systemTemp.createTemp('premier-catalogue');
    PlaylistDatabase.debugFilePath = '${dossier.path}/base.db';
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    PlaylistRepository.mergeAllPlaylists = true;
    await repo.initialize();
  });
  tearDown(() async {
    await PlaylistDatabase.instance.closeForTesting();
    await dossier.delete(recursive: true);
    PlaylistDatabase.debugFilePath = null;
    PlaylistRepository.mergeAllPlaylists = false;
  });

  for (final invalide in [false, true]) {
    test(invalide ? 'retrait du premier lot si la fin est invalide'
        : 'premières chaînes avant la fin du réseau, une seule requête',
        () async {
      final source = OpenSourceInput.playlistLink(
        'http://exemple.invalid/get.php?username=test&password=test&type=m3u_plus',
      ).draft!;
      expect(source.kind, OpenSourceKind.xtream);
      final compte = _Compte(invalide: invalide);
      final premierLot = Completer<void>();
      final ajout = repo.addXtreamPlaylist(
        name: 'Essai', serverUrl: source.serverUrl!, username: source.username!,
        password: source.password!, httpClient: compte,
        onFirstChannels: premierLot.complete,
      );
      final resultat = invalide ? expectLater(ajout, throwsException) : ajout;
      await compte.connecte.future.timeout(const Duration(seconds: 5));
      try {
        if (kNovatubeTv) {
          await premierLot.future.timeout(const Duration(seconds: 5));
          expect(repo.currentChannels.first.category, 'Groupe');
          expect(repo.currentChannels.length, inInclusiveRange(1, 48));
        } else {
          expect(premierLot.isCompleted, isFalse);
          expect(repo.currentChannels, isEmpty);
        }
      } finally {
        compte.continuer.complete();
      }
      await resultat;
      expect(compte.catalogues, 1);
      expect(repo.currentChannels, hasLength(invalide ? 0 : 181));
      expect(await repo.getAllPlaylists(), hasLength(invalide ? 0 : 1));
    });
  }
}
