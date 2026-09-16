// Play Store reçoit le M3U du panel. Plus de porte `storeBuild`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';

void main() {
  test('Play Store : pas de porte storeBuild qui ignore le panel', () {
    final String code = File(
      'lib/features/playlists/data/remote_source_repository.dart',
    ).readAsStringSync();
    expect(code.contains('if (storeBuild)'), isFalse,
        reason: 'le M3U collé au panel doit arriver sur l\'app Play Store');
  });

  test('liste vide → noSource (rien d\'assigné, pas une porte store)',
      () async {
    expect(await RemoteSourceRepository.applySources(<Map<String, dynamic>>[]),
        RemoteSyncResult.noSource);
  });
}
