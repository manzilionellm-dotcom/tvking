import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/update/update_check.dart';

Map<String, Object?> manifest(int code) => <String, Object?>{
      'versionCode': code,
      'versionName': 'Zuno $code',
      'url': 'https://example.invalid/$code.apk',
      'sha256': 'a' * 64,
      'size': 1000,
    };

void main() {
  test('les deux canaux démarrent ensemble et les doublons sont réunis',
      () async {
    final Map<String, Completer<Object?>> replies =
        <String, Completer<Object?>>{};
    final Future<UpdateCheckResult> pending = checkUpdateManifests(
      urls: <String>['client', 'test', 'client'],
      currentBuild: 10,
      read: (String url) {
        final Completer<Object?> reply = Completer<Object?>();
        replies[url] = reply;
        return reply.future;
      },
    );
    expect(replies.keys, <String>['client', 'test']);
    replies['test']!.complete(manifest(12));
    replies['client']!.complete(manifest(11));
    final UpdateCheckResult result = await pending;
    expect(result.status, UpdateCheckStatus.available);
    expect(result.manifest!.versionCode, 12);
  });

  test('une réponse mal typée ne masque pas une mise à jour valide', () async {
    final UpdateCheckResult result = await checkUpdateManifests(
      urls: <String>['broken', 'client'],
      currentBuild: 10,
      read: (String url) async => url == 'broken'
          ? <String, Object?>{...manifest(20), 'versionCode': '20'}
          : manifest(11),
    );
    expect(result.status, UpdateCheckStatus.available);
    expect(result.manifest!.versionCode, 11);
  });

  test('une panne réseau ne devient jamais un succès à jour', () async {
    for (final List<String> urls in <List<String>>[
      <String>[],
      <String>['broken'],
      <String>['client', 'broken'],
    ]) {
      final UpdateCheckResult result = await checkUpdateManifests(
        urls: urls,
        currentBuild: 10,
        read: (String url) async {
          if (url == 'broken') throw const FormatException('network');
          return manifest(10);
        },
      );
      expect(result.status, UpdateCheckStatus.unavailable);
      expect(result.manifest, isNull);
    }
  });

  test('à jour seulement quand tous les canaux complets le prouvent', () async {
    final UpdateCheckResult result = await checkUpdateManifests(
      urls: <String>['client', 'test'],
      currentBuild: 12,
      read: (String url) async => manifest(url == 'client' ? 12 : 11),
    );
    expect(result.status, UpdateCheckStatus.upToDate);
    expect(result.manifest, isNull);
  });
}
