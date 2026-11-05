import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/domain/heartbeat_coalesce.dart';

void main() {
  test('un heartbeat déjà en vol ne perd pas le suivant', () {
    final HeartbeatCoalesce gate = HeartbeatCoalesce();
    expect(gate.start(), isTrue);
    // Zap pendant l'écriture : on ne lance pas un second POST.
    expect(gate.start(), isFalse);
    expect(gate.start(), isFalse);
    // À la fin, un seul renvoi. Il lira la chaîne la plus récente.
    expect(gate.finish(), isTrue);
    expect(gate.finish(), isFalse);
  });

  test('rien en attente : on ne renvoie pas', () {
    final HeartbeatCoalesce gate = HeartbeatCoalesce();
    expect(gate.start(), isTrue);
    expect(gate.finish(), isFalse);
    expect(gate.start(), isTrue);
  });
}
