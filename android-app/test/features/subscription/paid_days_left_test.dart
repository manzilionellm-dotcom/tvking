// =========================================================
//  paid_days_left_test.dart — « X jours restants » sur l'accueil
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/domain/paid_days_left.dart';

const int _day = 24 * 60 * 60 * 1000;

void main() {
  const int now = 1800000000000;

  test('pas de date connue (à vie, serveur muet) : rien à afficher', () {
    expect(paidDaysLeft(paidUntilMs: 0, nowMs: now), isNull);
    expect(paidDaysLeft(paidUntilMs: now - 1, nowMs: now), isNull);
  });

  test('le jour entamé compte pour un jour', () {
    expect(paidDaysLeft(paidUntilMs: now + 2 * 3600000, nowMs: now), 1);
    expect(paidDaysLeft(paidUntilMs: now + 3 * _day, nowMs: now), 3);
    expect(paidDaysLeft(paidUntilMs: now + 3 * _day + 1, nowMs: now), 4);
  });

  test('alerte seulement la dernière semaine', () {
    expect(paidEndsSoon(null), isFalse);
    expect(paidEndsSoon(30), isFalse);
    expect(paidEndsSoon(8), isFalse);
    expect(paidEndsSoon(7), isTrue);
    expect(paidEndsSoon(1), isTrue);
  });
}
