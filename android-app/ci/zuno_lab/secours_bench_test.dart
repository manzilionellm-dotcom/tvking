import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/player/domain/live_fallback.dart';

void main() {
  test('mesure les quatre secours parmi vingt mille homonymes', () {
    final output = File(Platform.environment['ZUNO_FALLBACK_OUTPUT']!);
    final measurements = <Map<String, Object>>[];
    for (final external in [false, true]) {
      final catalog = List<Channel>.generate(20000, (index) {
        final host = external && index >= 19996 ? 'secours$index' : 'local';
        return Channel(id: 'canal$index', name: 'Mire HD', category: 'LAB',
            streamUrl: 'http://$host.invalid/$index.ts', isLive: true);
      });
      final expected = external ? catalog.skip(19996) : catalog.skip(1).take(4);
      for (var i = 0; i <= 11; i++) {
        final clock = Stopwatch()..start();
        final list = LiveFallback.backups(catalog.first, catalog);
        clock.stop();
        expect(list, expected.map((e) => e.streamUrl).toList());
        if (i > 0) {
          measurements.add({'external_at_end': external, 'iteration': i,
            'microseconds': clock.elapsedMicroseconds, 'matched': list.length});
        }
      }
    }
    output.writeAsStringSync(jsonEncode(measurements));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
