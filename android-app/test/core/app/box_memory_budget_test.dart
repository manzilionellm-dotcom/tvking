// =========================================================
//  box_memory_budget_test.dart — Paliers RAM de la box
// =========================================================
//  Les chiffres du cache d'images sont ceux qui étaient écrits
//  dans guarded_main. Ce test les fige : un palier qui dérive
//  changerait l'empreinte de toutes les box déjà en service.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/box_memory_budget.dart';

void main() {
  tearDown(BoxMemoryBudget.resetForTest);

  test('seuils historiques : low RAM, 1 Go, 2 Go, au-delà', () {
    expect(
      BoxMemoryBudget.classify(totalMb: 4096, lowRam: true),
      BoxRamTier.tight,
    );
    expect(
      BoxMemoryBudget.classify(totalMb: 1024, lowRam: false),
      BoxRamTier.tight,
    );
    expect(
      BoxMemoryBudget.classify(totalMb: 1025, lowRam: false),
      BoxRamTier.balanced,
    );
    expect(
      BoxMemoryBudget.classify(totalMb: 2048, lowRam: false),
      BoxRamTier.balanced,
    );
    // Total à 0 : l'ancienne branche « ≤ 2048 » s'appliquait.
    expect(
      BoxMemoryBudget.classify(totalMb: 0, lowRam: false),
      BoxRamTier.balanced,
    );
    expect(
      BoxMemoryBudget.classify(totalMb: 2049, lowRam: false),
      BoxRamTier.roomy,
    );
  });

  test('cache d\'images : 60/24 Mo, 120/48 Mo, 220/96 Mo', () {
    expect(
      BoxMemoryBudget.imageCacheFor(BoxRamTier.tight),
      (count: 60, bytes: 24 << 20),
    );
    expect(
      BoxMemoryBudget.imageCacheFor(BoxRamTier.balanced),
      (count: 120, bytes: 48 << 20),
    );
    expect(
      BoxMemoryBudget.imageCacheFor(BoxRamTier.roomy),
      (count: 220, bytes: 96 << 20),
    );
  });

  test('≤ 2 Go : pas de lueur, logos nets, fond plus petit, liste courte', () {
    BoxMemoryBudget.debugTier = BoxRamTier.tight;
    expect(BoxMemoryBudget.paintFocusGlow, isFalse);
    expect(BoxMemoryBudget.logoFade(const Duration(milliseconds: 180)),
        Duration.zero);
    expect(BoxMemoryBudget.hubBackgroundCacheWidth, 960);
    expect(BoxMemoryBudget.liveListCacheExtent, 96);

    BoxMemoryBudget.debugTier = BoxRamTier.balanced;
    expect(BoxMemoryBudget.paintFocusGlow, isFalse);
    expect(BoxMemoryBudget.hubBackgroundCacheWidth, 1280);
    expect(BoxMemoryBudget.liveListCacheExtent, 160);
  });

  test('> 2 Go : lueur, fondu demandé, fond fichier, marge Flutter 250', () {
    BoxMemoryBudget.debugTier = BoxRamTier.roomy;
    expect(BoxMemoryBudget.paintFocusGlow, isTrue);
    expect(
      BoxMemoryBudget.logoFade(const Duration(milliseconds: 180)),
      const Duration(milliseconds: 180),
    );
    expect(BoxMemoryBudget.hubBackgroundCacheWidth, isNull);
    expect(BoxMemoryBudget.liveListCacheExtent, 250);
  });

  test('le PC reprend le palier large, un test figé n\'est pas écrasé', () {
    BoxMemoryBudget.useDesktop();
    expect(BoxMemoryBudget.tier, BoxRamTier.roomy);

    BoxMemoryBudget.debugTier = BoxRamTier.tight;
    BoxMemoryBudget.useDesktop();
    BoxMemoryBudget.note(totalMb: 8192, lowRam: false);
    expect(BoxMemoryBudget.current, BoxRamTier.tight);
    expect(BoxMemoryBudget.tier, BoxRamTier.roomy);
  });
}
