import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'mise à jour de ZUNO TV : un favori garde sa qualité et son guide',
    () async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final temp = await Directory.systemTemp.createTemp('zuno-variantes-');
      PlaylistDatabase.debugFilePath = '${temp.path}/catalogue.db';
      addTearDown(() async {
        await PlaylistDatabase.instance.closeForTesting();
        PlaylistDatabase.debugFilePath = null;
        PlaylistRepository.mergeAllPlaylists = false;
        AppPlatform.isZuno = false;
        AppPlatform.isTv = false;
        await temp.delete(recursive: true);
      });
      FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
      PlaylistRepository.mergeAllPlaylists = true;
      final repo = PlaylistRepository.instance;
      final favorites = FavoritesRepository.instance;
      final file = File('${temp.path}/mire.m3u');
      Future<void> write(List<String> order) async {
        final text = StringBuffer('#EXTM3U\n');
        for (final label in order) {
          text.writeln(
            '#EXTINF:-1 tvg-id="Guide.Exact" group-title="TV",Démo $label',
          );
          text.writeln(
            'https://example.invalid/variantes/$label.m3u8?original=1',
          );
        }
        await file.writeAsString(text.toString());
      }

      List<Channel> variants() => repo.currentChannels;
      Map<String, String> ids() => {for (final c in variants()) c.name: c.id};

      // Le catalogue historique (encore utilisé sur téléphone) et ses favoris
      // existent déjà sur la box qui va recevoir la mise à jour.
      AppPlatform.configureZuno(isAndroidHandset: true);
      await repo.initialize();
      await favorites.initialize();
      await write(['SD', 'HD', 'UHD', 'SD']);
      final source = await repo.addM3uFromLocalFile(
        name: 'Mire',
        path: file.path,
      );
      expect(ids(), {
        'Démo SD': 'Guide.Exact',
        'Démo HD': 'Guide.Exact~p${source.id}',
      });
      await favorites.toggle(ids()['Démo HD']!);

      AppPlatform.configureZuno(isAndroidHandset: false);
      await repo.initialize();
      final assigned = ids();
      expect(assigned.values.toSet(), hasLength(3));
      expect(variants().map((c) => c.name), ['Démo SD', 'Démo HD', 'Démo UHD']);
      expect(assigned['Démo SD'], 'Guide.Exact');
      expect(assigned['Démo HD'], 'Guide.Exact~p${source.id}');
      for (final c in variants()) {
        final quality = c.name.split(' ').last;
        expect(
          c.streamUrl,
          'https://example.invalid/variantes/$quality.m3u8?original=1',
        );
      }
      await write(['UHD', 'HD', 'SD', 'UHD']);
      expect(await repo.refreshPlaylist(source), isTrue);
      await repo.initialize();
      expect(ids(), assigned);
      expect(variants().map((c) => c.name), ['Démo UHD', 'Démo HD', 'Démo SD']);
      expect(
        variants().singleWhere((c) => favorites.current.contains(c.id)).name,
        'Démo HD',
      );
      final guide = EpgRepository.instance;
      await guide.initialize();
      final db = await PlaylistDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final start in [now - 100000, now + 100000]) {
        await db.insert('epg_programs', {
          'channel_id': 'Guide.Exact',
          'start_time': start,
          'stop_time': start + 200000,
          'title': start < now ? 'En cours' : 'Suivant',
        });
      }
      for (final id in assigned.values) {
        expect((await guide.currentProgram(id))?.channelId, id);
        expect((await guide.nextProgram(id))?.title, 'Suivant');
        expect(
          (await guide.programsBetween(id, now - 300000, now + 300000)).length,
          2,
        );
      }
      expect(
        (await guide.programsOverlapping(
          now,
          now + 1000,
        )).map((p) => p.channelId).toSet(),
        assigned.values.toSet(),
      );
    },
  );
}
