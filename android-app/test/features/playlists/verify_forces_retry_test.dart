// =========================================================
//  verify_forces_retry_test.dart — « Vérifier mon abonnement » retente tout de suite
// =========================================================
//  Téléphone du propriétaire (06/10/2026) : abonnement actif, 1 liste du
//  panel servie par le serveur, et pourtant « Pas encore de chaînes ».
//  Mécanisme prouvé ici avec le vrai code de synchronisation et un vrai
//  SQLite : une liste refusée une fois (fournisseur en panne) est mise de
//  côté plusieurs minutes ; une relecture NON forcée la saute. Le bouton
//  « Vérifier » appelle désormais sync(force: true) : elle est retentée et
//  chargée aussitôt. Serveur simulé (MockClient), hôtes *.invalid.
// =========================================================
import 'dart:convert';
import 'dart:io';

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
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

const String kMac = 'MK:30:70:0E:D7:5B';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  bool providerDown = true;

  http.Client client() => MockClient((http.Request r) async {
        if (r.url.path.startsWith('/api/device-source/')) {
          return http.Response(jsonEncode(<String, Object?>{
            'mac': kMac,
            'sources': <Map<String, Object?>>[
              <String, Object?>{'type': 'm3u', 'm3u_url': 'http://fournisseur.invalid/l.m3u', 'origin': 'panel'},
            ],
          }), 200);
        }
        if (r.url.path.startsWith('/api/')) return http.Response('{}', 404);
        if (r.url.host == 'fournisseur.invalid') {
          if (providerDown) return http.Response('panne', 503);
          return http.Response('#EXTM3U\n#EXTINF:-1 group-title="G",Une\nhttp://127.0.0.1/s/1.ts\n', 200);
        }
        return http.Response('inconnu', 404);
      });

  Future<RemoteSyncResult> sync({bool force = false}) =>
      http.runWithClient(() => RemoteSourceRepository.sync(force: force), client);

  Future<bool> hasList() async => (await PlaylistRepository.instance.getAllPlaylists())
      .any((Playlist p) => (p.m3uUrl ?? '').contains('fournisseur.invalid') && p.channelCount > 0);

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('zuno-verify-');
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = true;
    SharedPreferences.setMockInitialValues(<String, Object>{'device.virtual_mac.v1': kMac});
    RepairFlags.debugReset();
    RemoteSourceRepository.importing.value = false;
    RemoteSourceRepository.lastResult.value = null;
    ImportProgressBus.clear();
    providerDown = true;
  });

  tearDown(() async {
    RepairFlags.debugReset();
    RemoteSourceRepository.importing.value = false;
    RemoteSourceRepository.lastResult.value = null;
    ImportProgressBus.clear();
    await PlaylistDatabase.instance.closeForTesting();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('liste refusée une fois : relecture normale la saute, Vérifier (forcé) la charge', () async {
    // Masquer la pastille globale ne doit pas masquer les faits de l'import
    // dont dépend l'écran Direct, déjà ouvert lors de l'ordre du panel.
    RepairFlags.syncPillOff = true;
    final List<bool> imports = <bool>[];
    final List<RemoteSyncResult?> results = <RemoteSyncResult?>[];
    void onImport() => imports.add(RemoteSourceRepository.importing.value);
    void onResult() => results.add(RemoteSourceRepository.lastResult.value);
    RemoteSourceRepository.importing.addListener(onImport);
    RemoteSourceRepository.lastResult.addListener(onResult);
    addTearDown(() {
      RemoteSourceRepository.importing.removeListener(onImport);
      RemoteSourceRepository.lastResult.removeListener(onResult);
    });

    // Fournisseur en panne : un vrai import commence puis termine en refus.
    expect(await sync(), RemoteSyncResult.sourceFailed);
    expect(imports, <bool>[true, false]);
    expect(RemoteSourceRepository.importing.value, isFalse);
    expect(RemoteSourceRepository.lastResult.value, RemoteSyncResult.sourceFailed);
    expect(results, <RemoteSyncResult>[RemoteSyncResult.sourceFailed]);
    expect(await hasList(), isFalse);

    providerDown = false; // le fournisseur répond de nouveau
    expect(await sync(), RemoteSyncResult.sourceFailed);
    expect(imports, <bool>[true, false],
        reason: 'une liste mise de côté ne simule pas un téléchargement');
    expect(RemoteSourceRepository.lastResult.value, RemoteSyncResult.sourceFailed);
    expect(await hasList(), isFalse,
        reason: 'contre-preuve : la liste reste mise de côté → « Pas encore de chaînes »');

    expect(await sync(force: true), RemoteSyncResult.loaded);
    expect(imports, <bool>[true, false, true, false]);
    expect(RemoteSourceRepository.importing.value, isFalse);
    expect(RemoteSourceRepository.lastResult.value, RemoteSyncResult.loaded);
    expect(results, <RemoteSyncResult>[
      RemoteSyncResult.sourceFailed,
      RemoteSyncResult.loaded,
    ]);
    expect(await hasList(), isTrue, reason: 'retentée tout de suite et chargée');
  });
}
