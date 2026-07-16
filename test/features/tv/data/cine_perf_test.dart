// =========================================================
//  cine_perf_test.dart — Verrouille le contrat des chronos de fluidité
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/data/cine_perf.dart';

void main() {
  group('CinePerf', () {
    test('start puis end → durée mesurée (>= 0)', () {
      CinePerf.start(CinePerf.detailOpen);
      final int? ms = CinePerf.end(CinePerf.detailOpen);
      expect(ms, isNotNull);
      expect(ms, greaterThanOrEqualTo(0));
    });

    test('end sans start → null (no-op silencieux)', () {
      expect(CinePerf.end(CinePerf.homeFirstRender), isNull);
    });

    test('end consomme le chrono (pas de double mesure)', () {
      CinePerf.start(CinePerf.playToFirstFrame);
      expect(CinePerf.end(CinePerf.playToFirstFrame), isNotNull);
      expect(CinePerf.end(CinePerf.playToFirstFrame), isNull);
    });

    test('cancel abandonne sans mesurer', () {
      CinePerf.start(CinePerf.detailOpen);
      CinePerf.cancel(CinePerf.detailOpen);
      expect(CinePerf.end(CinePerf.detailOpen), isNull);
    });

    test('isRunning reflète la fenêtre de mesure', () {
      expect(CinePerf.isRunning(CinePerf.homeFirstRender), isFalse);
      CinePerf.start(CinePerf.homeFirstRender);
      expect(CinePerf.isRunning(CinePerf.homeFirstRender), isTrue);
      CinePerf.end(CinePerf.homeFirstRender);
      expect(CinePerf.isRunning(CinePerf.homeFirstRender), isFalse);
    });

    test('les budgets de la mission sont bien posés', () {
      expect(CinePerf.budgets[CinePerf.homeFirstRender], 400);
      expect(CinePerf.budgets[CinePerf.detailOpen], 300);
      expect(CinePerf.budgets[CinePerf.playToFirstFrame], 2500);
    });
  });
}
