// =========================================================
//  reconnect_plan_test.dart — Reconnexion sans flux réel
// =========================================================
//  Aucune URL de chaîne. On vérifie l'attente croissante, le
//  refus d'un second essai (double son) et le choix « garder
//  l'image » plutôt qu'un panneau opaque.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/reconnect_plan.dart';

void main() {
  test('attente 1 s, 2 s, 4 s, puis 8 s', () {
    expect(ReconnectPlan.delayMs(0), 0);
    expect(ReconnectPlan.delayMs(1), 1000);
    expect(ReconnectPlan.delayMs(2), 2000);
    expect(ReconnectPlan.delayMs(3), 4000);
    expect(ReconnectPlan.delayMs(4), 8000);
    expect(ReconnectPlan.delayMs(8), 8000);
  });

  test('un essai déjà armé n\'en programme pas un second', () {
    final ReconnectGate gate = ReconnectGate();
    expect(gate.arm(maxAttempts: ReconnectPlan.maxSilent), 1000);
    expect(gate.pending, isTrue);
    expect(gate.arm(maxAttempts: ReconnectPlan.maxSilent), isNull);
    expect(gate.attempt, 1);
    expect(gate.fire(), isTrue);
    expect(gate.fire(), isFalse);
    expect(gate.arm(maxAttempts: ReconnectPlan.maxSilent), 2000);
  });

  test('au-delà du budget, on abandonne', () {
    final ReconnectGate gate = ReconnectGate();
    for (int i = 0; i < 5; i++) {
      expect(gate.arm(maxAttempts: 5), ReconnectPlan.delayMs(i + 1));
      expect(gate.fire(), isTrue);
    }
    expect(gate.arm(maxAttempts: 5), isNull);
  });

  test('le natif qui réessaie déjà empêche l\'écran de ré-ouvrir', () {
    expect(ReconnectPlan.letNativeOwnRetry(true), isTrue);
    expect(ReconnectPlan.letNativeOwnRetry(false), isFalse);
  });

  test('même adresse, image déjà vue : pas de panneau opaque', () {
    expect(
      ReconnectPlan.coverWithLoader(hadFrame: false, sameUrl: true),
      isTrue,
    );
    expect(
      ReconnectPlan.coverWithLoader(hadFrame: true, sameUrl: true),
      isFalse,
    );
    expect(
      ReconnectPlan.coverWithLoader(hadFrame: true, sameUrl: false),
      isTrue,
      reason: 'zap ou adresse de secours : on ne garde pas la mauvaise image',
    );
  });

  test('budget applicatif du zap sous 2 s, décision mesurée', () {
    expect(ReconnectPlan.bufferForPlaybackMs, 1000);
    expect(ReconnectPlan.zapSettleMs, 180);
    final int budget = ReconnectPlan.appSideBudgetMs;
    // ignore: avoid_print
    print(
      'MESURE budget_app_ms=$budget '
      'tampon_ms=${ReconnectPlan.bufferForPlaybackMs} '
      'zap_ms=${ReconnectPlan.zapSettleMs}',
    );
    expect(budget, lessThan(ReconnectPlan.startupTargetMs));

    final Stopwatch watch = Stopwatch()..start();
    int last = 0;
    for (int i = 0; i < 20; i++) {
      last = ReconnectPlan.delayMs(i + 1);
      ReconnectPlan.coverWithLoader(hadFrame: true, sameUrl: i.isEven);
    }
    watch.stop();
    // ignore: avoid_print
    print(
      'MESURE decision_reconnexion_20_microsecondes=${watch.elapsedMicroseconds} '
      'dernier_delai_ms=$last',
    );
    expect(watch.elapsedMicroseconds, lessThan(50000));
    expect(last, 8000);
  });
}
