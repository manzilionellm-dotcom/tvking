// =========================================================
//  playback_health_test.dart — Qualité de lecture en %
// =========================================================
//  Règle : part du temps où l'image a joué. Une attente de moins de
//  3 s (zap) ne compte pas. Moins de 10 s observées : pas de chiffre.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/data/playback_health.dart';

void main() {
  late int now;
  late PlaybackHealth health;

  setUp(() {
    now = 1000000;
    health = PlaybackHealth(clock: () => now);
  });

  test('rien à l\'écran : pas de pourcentage', () {
    now += 60000;
    expect(health.takePercent(), isNull);
  });

  test('lecture sans attente : 100 %', () {
    health.mark(stalled: false);
    now += 60000;
    expect(health.takePercent(), 100);
  });

  test('un cinquième du temps à charger : 80 %', () {
    health.mark(stalled: false);
    now += 48000;
    health.mark(stalled: true);
    now += 12000;
    health.mark(stalled: false);
    expect(health.takePercent(), 80);
  });

  test('l\'ouverture d\'une chaîne (moins de 3 s) ne compte pas', () {
    health.mark(stalled: true);
    now += 2000;
    health.mark(stalled: false);
    now += 28000;
    expect(health.takePercent(), 100);
  });

  test('trop court pour juger : pas de chiffre, jamais 0 % inventé', () {
    health.mark(stalled: true);
    now += 5000;
    expect(health.takePercent(), isNull);
  });

  test('bloqué tout le temps : 0 %', () {
    health.mark(stalled: true);
    now += 30000;
    expect(health.takePercent(), 0);
  });

  test('chaque signal repart de zéro ; lecteur fermé = on ne compte plus', () {
    health.mark(stalled: false);
    now += 20000;
    expect(health.takePercent(), 100);
    health.mark(stalled: true);
    now += 20000;
    expect(health.takePercent(), 0);
    health.stop();
    now += 60000;
    expect(health.takePercent(), isNull);
  });
}
