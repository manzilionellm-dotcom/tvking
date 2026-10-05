// =========================================================
//  box_reset_test.dart — « Réinitialiser la box » depuis le panel
// =========================================================
//  Demande du propriétaire (06/10/2026) : un bouton du panel, et
//  l'application redevient comme neuve ; il renvoie ensuite une liste à
//  distance. Ici : la règle pure (une demande ne se rejoue jamais), la
//  lecture de `reset_at` dans le statut, et l'effacement réel sur le vrai
//  dépôt (deux listes importées, puis plus rien). Adresses en 127.0.0.1.
// =========================================================
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/box_reset.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';
import 'package:tv_king/features/subscription/domain/box_signal.dart';

Uint8List _m3u(int n) {
  final StringBuffer sb = StringBuffer('#EXTM3U\n');
  for (int i = 0; i < n; i++) {
    sb.write('#EXTINF:-1 tvg-id="c$i" group-title="G",Chaîne $i\nhttp://127.0.0.1/t/$i.ts\n');
  }
  return Uint8List.fromList(sb.toString().codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('règle pure : seule une demande plus récente que la dernière appliquée compte', () {
    expect(BoxReset.shouldApply(resetAt: 0, appliedAt: 0), isFalse);
    expect(BoxReset.shouldApply(resetAt: 1000, appliedAt: 0), isTrue);
    expect(BoxReset.shouldApply(resetAt: 1000, appliedAt: 1000), isFalse);
    expect(BoxReset.shouldApply(resetAt: 999, appliedAt: 1000), isFalse);
    expect(BoxReset.shouldApply(resetAt: 1001, appliedAt: 1000), isTrue);
  });

  test('statut : reset_at lu, absent = 0 (Worker pas encore mis à jour)', () {
    final RemoteSubscriptionStatus a = RemoteSubscriptionStatus.fromJson(<String, dynamic>{
      'exists': true, 'status': 'active', 'reset_at': 1791300000000,
    });
    expect(a.resetAt, 1791300000000);
    final RemoteSubscriptionStatus b = RemoteSubscriptionStatus.fromJson(<String, dynamic>{
      'exists': true, 'status': 'active',
    });
    expect(b.resetAt, 0);
    expect(RemoteSubscriptionStatus.unknown.resetAt, 0);
  });

  test('ordre « reset » : relecture du statut puis des listes', () {
    expect(refreshesFor('reset'), <SignalRefresh>{SignalRefresh.status, SignalRefresh.source});
    expect(kindNeedsStatus('reset'), isTrue);
  });

  group('effacement réel', () {
    late Directory dir;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
      dir = await Directory.systemTemp.createTemp('zuno-reset-');
      PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
      PlaylistRepository.mergeAllPlaylists = true;
    });

    tearDownAll(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    tearDown(() {
      RepairFlags.remoteResetOff = false;
    });

    Future<void> seedTwoLists() async {
      final http.Client client = MockClient((http.Request r) async => http.Response.bytes(_m3u(5), 200));
      await PlaylistRepository.instance.addM3uPlaylist(name: 'A', url: 'http://127.0.0.1/a.m3u', httpClient: client);
      await PlaylistRepository.instance.addM3uPlaylist(name: 'B', url: 'http://127.0.0.1/b.m3u', httpClient: client);
    }

    test('demande neuve : listes effacées, mémoire des listes servies vidée, heure mémorisée', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RemoteSourceRepository.rememberedKey: <String>['m3u|http://127.0.0.1/a.m3u'],
        RemoteSourceRepository.failuresKey: '{}',
      });
      await seedTwoLists();
      expect((await PlaylistRepository.instance.getAllPlaylists()).length, 2);

      final bool applied = await BoxReset.maybeApply(1791300000000);
      expect(applied, isTrue);
      expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
      expect(PlaylistRepository.instance.currentChannels, isEmpty);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(BoxReset.appliedKey), 1791300000000);
      expect(prefs.getStringList(RemoteSourceRepository.rememberedKey), isNull);
      expect(prefs.getString(RemoteSourceRepository.failuresKey), isNull);

      // Même demande au tour suivant : rien ne se rejoue.
      await seedTwoLists();
      expect(await BoxReset.maybeApply(1791300000000), isFalse);
      expect((await PlaylistRepository.instance.getAllPlaylists()).length, 2);
      // Demande plus récente : rejouée.
      expect(await BoxReset.maybeApply(1791300001000), isTrue);
      expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
    });

    test('aucune demande (0) ou repli zuno.reset.off : rien n\'est touché', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await seedTwoLists();
      expect(await BoxReset.maybeApply(0), isFalse);
      RepairFlags.remoteResetOff = true;
      expect(await BoxReset.maybeApply(1791300002000), isFalse);
      final List<Playlist> all = await PlaylistRepository.instance.getAllPlaylists();
      expect(all.length, 2);
      for (final Playlist p in all) {
        await PlaylistRepository.instance.deletePlaylist(p.id!, reason: 'test');
      }
    });
  });
}
