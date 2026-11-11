// Preuve portable : sur le 116, les lectures restent bornées, mais aucune
// trace CATALOGUE ne relie les 100 000 lignes stockées aux 50 000 lignes lues.
// Ce test n'importe aucun nouveau symbole de production L1-04.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';

import 'channel_limit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ChannelLimitFixture.setUpAll);
  tearDownAll(ChannelLimitFixture.tearDownAll);

  test(
    '100 000 lignes conservées, 50 000 lues : la trace explique la limite',
    () async {
      final before = await ChannelLimitFixture.fingerprint();
      expect(
        before.fold<int>(0, (n, row) => n + (row['rows_count'] as int)),
        100000,
      );
      await ChannelLimitFixture.preventChannelWrites();
      final trace = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) trace.add(message);
      };
      try {
        await PlaylistRepository.instance.initialize();
      } finally {
        debugPrint = previous;
      }
      expect(PlaylistRepository.instance.currentChannels, hasLength(50000));
      expect(await ChannelLimitFixture.fingerprint(), before);
      expect(
        trace.any(
          (line) =>
              line.contains('CATALOGUE') &&
              line.contains('100000') &&
              line.contains('50000'),
        ),
        isTrue,
        reason:
            'La trace doit donner les lignes enregistrées et lues, '
            'sans prétendre que les lignes restantes ont disparu.',
      );
    },
  );
}
