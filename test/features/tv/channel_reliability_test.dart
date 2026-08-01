// Tests du score de fiabilité par chaîne (n°38) : pas de verdict avant
// 3 tentatives, seuil 40 %, vieillissement, plafond d'entrées, persistance.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/tv/data/channel_reliability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ChannelReliability r = ChannelReliability.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('pas de verdict avant 3 tentatives (un raté isolé ≠ un état)', () {
    r.recordFailure('a');
    expect(r.scoreOf('a'), isNull);
    expect(r.isFlaky('a'), isFalse);
    r.recordFailure('a');
    expect(r.isFlaky('a'), isFalse);
    r.recordFailure('a');
    expect(r.scoreOf('a'), 0.0);
    expect(r.isFlaky('a'), isTrue);
  });

  test('sous 40 % de réussite → douteuse ; au-dessus → saine', () {
    // 1 réussite / 4 tentatives = 25 % → douteuse.
    r
      ..recordSuccess('b')
      ..recordFailure('b')
      ..recordFailure('b')
      ..recordFailure('b');
    expect(r.isFlaky('b'), isTrue);
    // 3 réussites / 4 = 75 % → saine.
    r
      ..recordSuccess('c')
      ..recordSuccess('c')
      ..recordSuccess('c')
      ..recordFailure('c');
    expect(r.isFlaky('c'), isFalse);
  });

  test('une chaîne réparée se rachète (vieillissement par moitié)', () {
    for (int i = 0; i < 12; i++) {
      r.recordFailure('d');
    }
    expect(r.isFlaky('d'), isTrue);
    // Le panel répare la chaîne : les réussites s'accumulent et le
    // vieillissement fait fondre les vieux échecs.
    for (int i = 0; i < 30; i++) {
      r.recordSuccess('d');
    }
    expect(r.isFlaky('d'), isFalse);
  });

  test('les votes sont persistés en SharedPreferences', () async {
    r
      ..recordFailure('e')
      ..recordFailure('e')
      ..recordFailure('e');
    // La persistance est asynchrone best-effort → laisser la micro-tâche
    // s'exécuter avant de lire.
    await Future<void>.delayed(Duration.zero);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tv.reliability.v1'), contains('"e"'));
  });
}
