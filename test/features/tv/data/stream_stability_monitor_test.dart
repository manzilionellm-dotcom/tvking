// =========================================================
//  stream_stability_monitor_test.dart — Cerveau de l'ABR maison
// =========================================================
//  Scénarios terrain, à la seconde près (horodatages injectés) :
//    • connexion saine → aucune décision ;
//    • 3 gels en 90 s → descente ;
//    • débit qui s'effondre SANS gel → descente préventive ;
//    • calme 4 min après la descente → remontée ;
//    • rechute après remontée → patience doublée, puis plus de remontée
//      (anti yo-yo) ;
//    • zap manuel → session neuve, rien ne fuit d'une chaîne à l'autre.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/data/stream_stability_monitor.dart';

void main() {
  final DateTime t0 = DateTime(2026, 1, 1, 20, 0, 0);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  StreamStabilityMonitor fresh() {
    final StreamStabilityMonitor m = StreamStabilityMonitor();
    m.openChannel(t0);
    return m;
  }

  test('connexion saine : jamais de décision', () {
    final StreamStabilityMonitor m = fresh();
    for (int s = 4; s <= 300; s += 4) {
      expect(
        m.onSample(at(s), ingestBytesPerSecond: 800000),
        StabilityAction.none,
      );
    }
  });

  test('3 incidents en 90 s → downshift', () {
    final StreamStabilityMonitor m = fresh();
    m.onIncident(at(10));
    m.onIncident(at(40));
    expect(m.onSample(at(44)), StabilityAction.none);
    m.onIncident(at(70));
    expect(m.onSample(at(72)), StabilityAction.downshift);
  });

  test('3 incidents ÉTALÉS au-delà de la fenêtre → pas de downshift', () {
    final StreamStabilityMonitor m = fresh();
    m.onIncident(at(10));
    m.onIncident(at(120));
    m.onIncident(at(240));
    expect(m.onSample(at(244)), StabilityAction.none);
  });

  test('débit qui s\'effondre sans gel → descente préventive', () {
    final StreamStabilityMonitor m = fresh();
    // Débit nominal appris : ~800 Ko/s pendant 1 min.
    for (int s = 4; s <= 60; s += 4) {
      expect(m.onSample(at(s), ingestBytesPerSecond: 800000),
          StabilityAction.none);
    }
    // Le tuyau tombe à 200 Ko/s (le flux en demande 800000×0.65 minimum).
    StabilityAction last = StabilityAction.none;
    int decidedAt = -1;
    for (int s = 64; s <= 120; s += 4) {
      last = m.onSample(at(s), ingestBytesPerSecond: 200000);
      if (last == StabilityAction.downshift) {
        decidedAt = s;
        break;
      }
    }
    expect(last, StabilityAction.downshift,
        reason: 'le gel est imminent, il faut descendre AVANT l\'écran figé');
    // Préventif mais pas nerveux : il faut plusieurs échantillons.
    expect(decidedAt, greaterThanOrEqualTo(76));
  });

  test('un seul incident + déficit court → signal croisé, descente', () {
    final StreamStabilityMonitor m = fresh();
    for (int s = 4; s <= 40; s += 4) {
      m.onSample(at(s), ingestBytesPerSecond: 800000);
    }
    m.onIncident(at(44));
    StabilityAction last = StabilityAction.none;
    for (int s = 48; s <= 80 && last != StabilityAction.downshift; s += 4) {
      last = m.onSample(at(s), ingestBytesPerSecond: 100000);
    }
    expect(last, StabilityAction.downshift);
  });

  test('burst de démarrage puis régime stable → AUCUNE descente à tort', () {
    // Reproduit le faux positif d'audit : le relais remplit son tampon au
    // démarrage (ingestion 3× le temps réel pendant ~10 s), PUIS le débit
    // revient au régime réel. L'ancien code gravait le burst comme nominal →
    // le régime normal (bien suffisant) passait ensuite pour un déficit et
    // déclenchait une descente injustifiée. Ne doit PLUS arriver.
    final StreamStabilityMonitor m = fresh();
    // 0-8 s : burst de remplissage (3× le régime établi de 500 Ko/s).
    for (int s = 0; s <= 8; s += 4) {
      expect(m.onSample(at(s), ingestBytesPerSecond: 1500000),
          StabilityAction.none);
    }
    // 12-180 s : régime établi, PARFAITEMENT sain (500 Ko/s soutenus).
    StabilityAction worst = StabilityAction.none;
    for (int s = 12; s <= 180; s += 4) {
      final StabilityAction a =
          m.onSample(at(s), ingestBytesPerSecond: 500000);
      if (a == StabilityAction.downshift) worst = a;
    }
    expect(worst, StabilityAction.none,
        reason: 'un régime stable après un burst ne doit jamais dégrader');
  });

  test('après la descente : cooldown, puis remontée après 4 min de calme',
      () {
    final StreamStabilityMonitor m = fresh();
    m.onIncident(at(10));
    m.onIncident(at(20));
    m.onIncident(at(30));
    expect(m.onSample(at(32)), StabilityAction.downshift);
    m.noteShifted(at(32));
    expect(m.isShifted, isTrue);
    // Pendant le cooldown : silence, même si un incident traînait.
    expect(m.onSample(at(40)), StabilityAction.none);
    // Calme complet : la remontée n'arrive qu'après stableForRestore (4 min).
    expect(m.onSample(at(32 + 180), ingestBytesPerSecond: 500000),
        StabilityAction.none);
    expect(m.onSample(at(32 + 45 + 245), ingestBytesPerSecond: 500000),
        StabilityAction.restore);
    m.noteRestored(at(32 + 45 + 245));
    expect(m.isShifted, isFalse);
  });

  test('rechute après remontée → patience doublée puis plus de remontée',
      () {
    final StreamStabilityMonitor m = StreamStabilityMonitor(maxRestores: 1);
    m.openChannel(t0);
    // 1re descente + remontée.
    m.onIncident(at(10));
    m.onIncident(at(20));
    m.onIncident(at(30));
    expect(m.onSample(at(32)), StabilityAction.downshift);
    m.noteShifted(at(32));
    m.noteRestored(at(600));
    // Rechute 60 s après la remontée.
    m.onIncident(at(660));
    m.onIncident(at(670));
    m.onIncident(at(680));
    expect(m.onSample(at(682)), StabilityAction.downshift);
    m.noteShifted(at(682)); // rechute dans relapseWindow + maxRestores atteint
    // Même après 20 min de calme : plus JAMAIS de remontée cette session.
    expect(m.onSample(at(682 + 1200), ingestBytesPerSecond: 500000),
        StabilityAction.none);
    expect(m.isShifted, isTrue);
  });

  test('pas de déclinaison disponible → on ne redemande plus', () {
    final StreamStabilityMonitor m = fresh();
    m.onIncident(at(10));
    m.onIncident(at(20));
    m.onIncident(at(30));
    expect(m.onSample(at(32)), StabilityAction.downshift);
    m.noteDownshiftUnavailable();
    m.onIncident(at(40));
    expect(m.onSample(at(44)), StabilityAction.none);
  });

  test('zap manuel : rien ne fuit d\'une chaîne à l\'autre', () {
    final StreamStabilityMonitor m = fresh();
    m.onIncident(at(10));
    m.onIncident(at(20));
    m.openChannel(at(25)); // l'utilisateur zappe
    m.onIncident(at(30));
    expect(m.onSample(at(34)), StabilityAction.none);
    expect(m.isShifted, isFalse);
  });
}
