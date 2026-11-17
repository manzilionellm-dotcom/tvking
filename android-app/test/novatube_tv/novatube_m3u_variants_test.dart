import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('le favori désigne la même variante pendant et après un import M3U',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('novatube-variantes');
    PlaylistDatabase.debugFilePath = '${temp.path}/essai.db';
    addTearDown(() async {
      await PlaylistDatabase.instance.closeForTesting();
      PlaylistDatabase.debugFilePath = null;
      PlaylistRepository.mergeAllPlaylists = false;
      await temp.delete(recursive: true);
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    PlaylistRepository.mergeAllPlaylists = true;
    final repo = PlaylistRepository.instance;
    final favorites = FavoritesRepository.instance;
    await repo.initialize();
    await favorites.initialize();
    var order = ['SD', 'HD', 'UHD', 'SD'];
    final client = MockClient((_) async {
      final text = StringBuffer('#EXTM3U\n');
      for (final label in order) {
        text.writeln(
            '#EXTINF:-1 tvg-id="Guide.Exact" group-title="TV",Démo $label');
        text.writeln(
            'https://exemple.invalid/variantes/$label.m3u8?original=1');
      }
      // Un vrai préfixe de téléchargement est publié à partir de 8 Kio.
      for (var i = 0; i < 200; i++) {
        text.writeln('#EXTINF:-1 tvg-id="u$i" group-title="Essais",Autre $i');
        text.writeln('https://exemple.invalid/autre/$i.ts');
      }
      return http.Response.bytes(utf8.encode(text.toString()), 200);
    });
    addTearDown(client.close);
    List<Channel> variants() =>
        repo.currentChannels.where((c) => c.category == 'TV').toList();
    Map<String, String> ids() => {for (final c in variants()) c.name: c.id};
    const url = 'https://exemple.invalid/catalogue.m3u';
    Map<String, String>? early;
    final ready = Completer<void>();
    final adding = repo.addM3uPlaylist(
        name: 'Mire',
        url: url,
        httpClient: client,
        onFirstChannels: () {
          early = ids();
          if (kNovatubeTv) ready.complete(favorites.toggle(early!['Démo HD']!));
        });
    final source = await adding;
    if (!kNovatubeTv) {
      expect(early, isNull);
      expect(variants().map((c) => c.name), ['Démo SD', 'Démo HD']);
      return;
    }
    await ready.future;
    expect(early!.values.toSet(), hasLength(3));
    expect(variants(), hasLength(3));
    final assigned = ids();
    expect(assigned, early);
    expect(assigned['Démo SD'], 'Guide.Exact');
    expect(assigned['Démo HD'], 'Guide.Exact~p${source.id}');
    expect(
        variants().where((c) => favorites.current.contains(c.id)).single.name,
        'Démo HD');
    for (final c in variants()) {
      final quality = c.name.split(' ').last;
      expect(c.streamUrl,
          'https://exemple.invalid/variantes/$quality.m3u8?original=1');
    }
    order = ['UHD', 'HD', 'SD', 'UHD'];
    await repo.editSource(source,
        name: 'Mire', address: url, httpClient: client);
    await repo.initialize();
    expect(ids(), assigned);
    expect(variants().map((c) => c.name), ['Démo UHD', 'Démo HD', 'Démo SD']);
    expect(
        variants().where((c) => favorites.current.contains(c.id)).single.name,
        'Démo HD');
    final guide = EpgRepository.instance;
    await guide.initialize();
    final db = await PlaylistDatabase.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final start in [now - 100000, now + 100000]) {
      await db.insert('epg_programs', {
        'channel_id': 'Guide.Exact',
        'start_time': start,
        'stop_time': start + 200000,
        'title': start < now ? 'En cours' : 'Suivant'
      });
    }
    for (final id in assigned.values) {
      expect((await guide.currentProgram(id))?.channelId, id);
      expect((await guide.nextProgram(id))?.title, 'Suivant');
      expect(
          (await guide.programsBetween(id, now - 300000, now + 300000)).length,
          2);
    }
    expect(
        (await guide.programsOverlapping(now, now + 1000))
            .map((p) => p.channelId)
            .toSet(),
        assigned.values.toSet());
  });
}
