import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/security/data/pin_attempt_policy.dart';

void main() {
  const PinAttemptPolicy policy = PinAttemptPolicy();

  test('0000 est refusé comme code', () {
    expect(policy.isForbidden('0000'), isTrue);
    expect(policy.isForbidden('1234'), isFalse);
  });

  test('cinq erreurs bloquent cinq minutes', () {
    int failures = 0;
    int locked = 0;
    const int now = 1000000;
    for (int i = 0; i < 4; i++) {
      final r = policy.onFailure(failures: failures, nowMs: now);
      failures = r.failures;
      locked = r.lockedUntilMs;
    }
    expect(locked, 0);
    final r = policy.onFailure(failures: failures, nowMs: now);
    expect(policy.isLocked(lockedUntilMs: r.lockedUntilMs, nowMs: now), isTrue);
    expect(
      policy.isLocked(
        lockedUntilMs: r.lockedUntilMs,
        nowMs: now + PinAttemptPolicy.lockMs,
      ),
      isFalse,
    );
  });
}
