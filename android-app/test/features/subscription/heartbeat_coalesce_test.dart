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

  test('une lecture de statut refusée ne déclenche pas de heartbeat', () {
    final HeartbeatCoalesce gate = HeartbeatCoalesce();
    // POST lent en vol ; la veille (1 à 2 s) relit plusieurs fois.
    expect(gate.start(), isTrue);
    expect(gate.start(resend: false), isFalse);
    expect(gate.start(resend: false), isFalse);
    // Pas de renvoi : sinon chaque lecture relancerait un POST.
    expect(gate.finish(), isFalse);
  });

  test('un zap pendant une lecture de statut garde son heartbeat', () {
    final HeartbeatCoalesce gate = HeartbeatCoalesce();
    expect(gate.start(resend: false), isTrue);
    expect(gate.start(), isFalse);
    expect(gate.finish(), isTrue);
    expect(gate.finish(), isFalse);
  });
}
