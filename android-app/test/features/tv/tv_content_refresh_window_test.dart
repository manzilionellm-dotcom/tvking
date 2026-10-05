// =========================================================
//  tv_content_refresh_window_test.dart — La passe automatique ne
//  retélécharge pas une liste à jour depuis moins de 6 h.
// =========================================================
//  Mesuré le 05/10/2026 : avec la fenêtre de 2 minutes, chaque
//  ouverture retéléchargeait les 3 listes de la box, « Mise à jour… »
//  restait 10 minutes à l'écran. Le bouton Redémarrer garde 2 minutes.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_content_refresh.dart';

void main() {
  test('passe automatique : 6 h ; Redémarrer : 2 min', () {
    expect(
      TvContentRefresh.skipWindow(automatic: true, fullLegacy: false),
      const Duration(hours: 6),
    );
    expect(
      TvContentRefresh.skipWindow(automatic: false, fullLegacy: false),
      const Duration(minutes: 2),
    );
  });

  test('repli zuno.refresh.auto_full : la passe automatique redevient complète',
      () {
    expect(
      TvContentRefresh.skipWindow(automatic: true, fullLegacy: true),
      const Duration(minutes: 2),
    );
    expect(
      TvContentRefresh.skipWindow(automatic: false, fullLegacy: true),
      const Duration(minutes: 2),
    );
  });

  test('la fenêtre automatique est celle de la passe périodique', () {
    // Sinon une liste pourrait vieillir plus que l'intervalle des passes.
    expect(TvContentRefresh.autoSkipWindow, const Duration(hours: 6));
    expect(TvContentRefresh.manualSkipWindow, const Duration(minutes: 2));
  });
}
