// Un profil vide ne doit jamais masquer au panel les sources de l'appareil.
// Le test utilise le vrai dépôt SQLite et le vrai corps du heartbeat.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const device = MethodChannel('com.manzilionellm.tvking/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('profil vide : inventaire appareil complet et sources toujours connues',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    final repo = PlaylistRepository.instance;
    final profiles = ProfileRepository.instance;
    profiles.resetForTesting(ProfileCatalog.fresh());
    PlaylistRepository.mergeAllPlaylists = true;
    PackageInfo.setMockInitialValues(
      appName: 'Zuno',
      packageName: 'com.sevenmotion.tv.seven_tv',
      version: 'test',
      buildNumber: '1',
      buildSignature: '',
    );
    messenger.setMockMethodCallHandler(
        device,
        (call) async => call.method == 'getAndroidId'
            ? 'fixture-device'
            : <String, String>{});
    final sourceClient = MockClient((request) async {
      final name = request.url.pathSegments.last;
      return http.Response(
        '#EXTM3U\n#EXTINF:-1 tvg-id="$name",$name\n'
        'http://fixture.invalid/$name.ts\n',
        200,
      );
    });
    try {
      await repo.initialize();
      for (final name in <String>['Source A', 'Source B']) {
        await repo.addM3uPlaylist(
          name: name,
          url: 'http://fixture.invalid/${Uri.encodeComponent(name)}.m3u',
          httpClient: sourceClient,
        );
      }
      final created = await profiles.addProfile(name: 'Invité', isKids: false);
      expect(created, isNotNull);
      await profiles.activate(created!.id, leaveAllowed: true);
      expect(await repo.getAllChannels(), isEmpty);
      expect(await repo.getVisiblePlaylists(), isEmpty);
      expect(repo.hasDeviceChannels, isTrue);

      Map<String, dynamic>? sent;
      await http.runWithClient(
        () => SubscriptionBackend.heartbeat('MK:11:22:33:44:55'),
        () => MockClient((request) async {
          expect(request.url.path, '/api/heartbeat');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"exists":true,"status":"active"}', 200);
        }),
      );
      final inventory = sent!['sources'] as List<dynamic>;
      expect(inventory.map((dynamic row) => row['name']),
          unorderedEquals(<String>['Source A', 'Source B']));
      expect(inventory.every((dynamic row) => row['channels'] == 1), isTrue);
      expect(
          inventory.every((dynamic row) =>
              !(row as Map<String, dynamic>).containsKey('password')),
          isTrue);
    } finally {
      sourceClient.close();
      profiles.resetForTesting(ProfileCatalog.fresh());
      await repo.initialize();
      messenger.setMockMethodCallHandler(device, null);
      await PlaylistDatabase.instance.closeForTesting();
      PlaylistDatabase.debugFilePath = null;
    }
  });
}
