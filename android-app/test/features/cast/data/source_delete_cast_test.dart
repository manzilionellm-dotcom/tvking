import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

class _Receiver implements CastTransport {
  int stops = 0;
  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'Test',
      String? imageUrl}) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {
    stops++;
  }
}

// Le binding Flutter sert aux plugins/SharedPreferences ; les requêtes de
// ce test doivent atteindre notre vrai HttpServer loopback, pas son mock400.
class _LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database db;
  final server = LocalCastServer.instance;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    directory = await Directory.systemTemp.createTemp('zuno-delete-cast-');
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${directory.path}/fixture.db';
    db = await PlaylistDatabase.instance.database;
    PlaylistRepository.mergeAllPlaylists = true;
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    await ParentalControls.instance.load();
    server.debugLanIpResolver = (_) async => '127.0.0.1';
  });

  tearDown(() async {
    await server.stop();
    server.debugLanIpResolver = null;
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    PlaylistRepository.mergeAllPlaylists = false;
    await directory.delete(recursive: true);
  });

  for (final bool adult in <bool>[false, true]) {
    test(
        'DELETE SQLite réel ferme Cast et QR ${adult ? "protégés" : "ordinaires"}',
        () async {
      await HttpOverrides.runWithHttpOverrides<Future<void>>(() async {
        final int source = await db.insert('playlists', <String, Object?>{
          'name': 'Source test',
          'type': 'm3u',
          'created_at': 1,
          'is_active': 1,
          'channel_count': 1,
          'm3u_url': 'https://fixture.invalid/list.m3u',
        });
        await db.insert('channels', <String, Object?>{
          'playlist_id': source,
          'external_id': 'fixture',
          'name': adult ? 'XXX Fixture' : 'Journal',
          'category': adult ? 'Adultes' : 'Actualités',
          'stream_url': 'https://fixture.invalid/live.ts',
          'is_live': 1,
        });
        await PlaylistRepository.instance.initialize();
        final channel = PlaylistRepository.instance.currentChannels.single;
        final AdultAccessGrant? grant = adult
            ? await authenticateAdultAccess(
                reason: 'Test suppression de source protégée',
                confirmPin: () async => true,
              )
            : null;
        if (adult) expect(grant?.isValid, isTrue);
        final receiver = _Receiver();
        final manager = CastManager.forTesting(
          transportFactory: (_) => receiver,
          probe: (url) async =>
              StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
        );
        final client = HttpClient();
        try {
          await manager.castTo(
              const CastDevice(
                  id: 'fixture',
                  name: 'TV test',
                  kind: CastDeviceKind.roku,
                  host: '192.0.2.1',
                  port: 8060,
                  controlUrl: 'http://192.0.2.1'),
              streamUrl: channel.streamUrl,
              title: channel.name,
              adultAccess: grant);
          manager
              .setCastPlaylist(<Channel>[channel], channel, adultAccess: grant);
          expect(
              await server.serveBrowser(
                  upstreamUrl: channel.streamUrl,
                  title: channel.name,
                  owner: Object(),
                  isCancelled: () => grant?.isValid == false),
              isNotNull);

          Future<Map<String, dynamic>> current() async {
            final request = await client
                .getUrl(Uri.parse('http://127.0.0.1:${server.port}/current'));
            final response = await request.close();
            return jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, dynamic>;
          }

          final String previousPath = (await current())['url'] as String;
          expect(manager.isCasting, isTrue);
          expect(server.hasBrowserSession, isTrue);

          // La suppression passe réellement par DeletedSources et la
          // transaction SQLite ; aucun changement de profil manuel ici.
          await PlaylistRepository.instance
              .deletePlaylist(source, reason: 'test');
          expect(
              await db.query('playlists',
                  where: 'id = ?', whereArgs: <Object>[source]),
              isEmpty);
          expect(
              await db.query('channels',
                  where: 'playlist_id = ?', whereArgs: <Object>[source]),
              isEmpty);
          if (adult) expect(grant!.isValid, isFalse);
          expect(receiver.stops, 1);
          expect(manager.hasActiveSession, isFalse);
          expect(manager.hasTarget, isFalse);
          expect(manager.currentCastChannel, isNull);
          expect((await current())['url'], isNull);
          final request = await client.getUrl(
              Uri.parse('http://127.0.0.1:${server.port}$previousPath'));
          final response = await request.close();
          expect(response.statusCode, HttpStatus.notFound);
          await response.drain<void>();
        } finally {
          client.close(force: true);
          await manager.disconnect();
          manager.dispose();
          grant?.dispose();
        }
      }, _LoopbackHttpOverrides());
    });
  }
}
