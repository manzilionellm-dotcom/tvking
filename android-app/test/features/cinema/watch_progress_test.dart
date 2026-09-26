// =========================================================
//  watch_progress_test.dart — Reprise + « Continuer à regarder »
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';

WatchEntry _e(String id,
        {int pos = 60000,
        int dur = 6000000,
        int at = 1,
        String? series,
        int? ep}) =>
    WatchEntry(
      id: id,
      isEpisode: series != null,
      title: series ?? id,
      streamUrl: 'http://x/$id.mp4',
      posMs: pos,
      durMs: dur,
      updatedAt: at,
      seriesId: series,
      season: series == null ? null : 1,
      episode: ep,
    );

void main() {
  test('terminé : ≥ 93 % ou < 2 min restantes', () {
    expect(WatchEntry.isFinishedAt(5580000, 6000000), isTrue); // 93 %
    expect(WatchEntry.isFinishedAt(5000000, 6000000), isFalse);
    expect(WatchEntry.isFinishedAt(2900000, 3000000), isTrue); // 100 s restantes
    expect(WatchEntry.isFinishedAt(1000, 0), isFalse); // durée inconnue
  });

  test('reprise 5 s plus tôt, jamais négative', () {
    final WatchProgressStore s = WatchProgressStore();
    expect(s.record(_e('a', pos: 125000)).resumeAt, const Duration(seconds: 120));
    expect(s.record(_e('b', pos: 10000)).isResumable, isFalse, reason: '< 30 s');
  });

  test('film fini → sort de Continuer', () {
    final WatchProgressStore s = WatchProgressStore();
    s.record(_e('a', pos: 5900000));
    expect(s.continueWatching(), isEmpty);
    expect(s.get('a')!.finished, isTrue);
  });

  test('une seule entrée par série, la plus récente, et « suivant » proposé', () {
    final WatchProgressStore s = WatchProgressStore();
    s.record(_e('e1', series: 'S', ep: 1, pos: 2950000, dur: 3000000, at: 10));
    s.proposeNext(_e('e2', series: 'S', ep: 2, at: 11));
    s.record(_e('film', at: 5));
    final List<WatchEntry> c = s.continueWatching();
    expect(c.map((WatchEntry e) => e.id), <String>['e2', 'film']);
    expect(c.first.upNext, isTrue);
    expect(c.first.resumeAt, Duration.zero);

    // On commence e2 → il remplace la proposition, reste unique pour la série.
    s.record(_e('e2', series: 'S', ep: 2, pos: 400000, dur: 3000000, at: 20));
    expect(s.continueWatching(episodes: true).single.id, 'e2');
    expect(s.latestForSeries('S')!.id, 'e2');
  });

  test('proposeNext n\'écrase pas un épisode déjà entamé', () {
    final WatchProgressStore s = WatchProgressStore();
    s.record(_e('e2', series: 'S', pos: 400000, at: 3));
    s.proposeNext(_e('e2', series: 'S', at: 4));
    expect(s.get('e2')!.posMs, 400000);
  });

  test('dismiss + sérialisation aller-retour + stockage corrompu', () {
    final WatchProgressStore s = WatchProgressStore();
    s.record(_e('a', at: 1));
    s.record(_e('b', at: 2));
    s.dismiss('a');
    final WatchProgressStore r = WatchProgressStore.decode(s.encode());
    expect(r.continueWatching().map((WatchEntry e) => e.id), <String>['b']);
    expect(r.get('a')!.finished, isTrue);
    expect(WatchProgressStore.decode('{pas du json').all, isEmpty);
  });

  test('plafond de 400 entrées (les plus récentes gardées)', () {
    final WatchProgressStore s = WatchProgressStore();
    for (int i = 0; i < 450; i++) {
      s.record(_e('m$i', at: i));
    }
    expect(s.all.length, WatchProgressStore.maxEntries);
    expect(s.get('m0'), isNull);
    expect(s.get('m449'), isNotNull);
  });
}
