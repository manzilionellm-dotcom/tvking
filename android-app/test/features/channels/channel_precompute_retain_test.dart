// Le cache du pré-calcul (noms, genres, pays, qualités) ne doit pas garder
// les chaînes d'un catalogue qui a quitté l'écran, et ne doit rien faire tant
// que le catalogue ne change pas. Données synthétiques uniquement.
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';

List<Channel> _catalog(String prefix, int count) => <Channel>[
      for (int i = 0; i < count; i++)
        Channel(
          id: '$prefix-$i',
          name: 'FR| Chaîne $prefix $i HD',
          category: 'Catégorie ${i % 7}',
          streamUrl: 'http://example.invalid/$prefix/$i.ts',
          isLive: true,
        ),
    ];

void main() {
  test('catalogue inchangé : le cache est conservé tel quel', () async {
    final List<Channel> a = _catalog('stable', 1500);
    await ChannelPrecompute.run(a);
    expect(a.every(ChannelPrecompute.isDone), isTrue);
    final int before = ChannelPrecompute.debugCacheSize;
    ChannelPrecompute.retainOnly(a);
    expect(ChannelPrecompute.debugCacheSize, before);
    expect(a.every(ChannelPrecompute.isDone), isTrue);
  });

  test('source remplacée : les chaînes disparues quittent le cache', () async {
    final List<Channel> old = _catalog('ancienne', 1500);
    await ChannelPrecompute.run(old);
    final List<Channel> fresh = _catalog('nouvelle', 20);
    await ChannelPrecompute.run(fresh);

    ChannelPrecompute.retainOnly(fresh);

    expect(old.any(ChannelPrecompute.isDone), isFalse);
    expect(fresh.every(ChannelPrecompute.isDone), isTrue,
        reason: 'le catalogue affiché garde ses valeurs (pas de recalcul)');
    expect(ChannelPrecompute.debugCacheSize, lessThanOrEqualTo(fresh.length));
  });

  test('petite marge : quelques chaînes en trop ne déclenchent aucun travail', () async {
    final List<Channel> shown = _catalog('affiche', 100);
    await ChannelPrecompute.run(shown);
    final List<Channel> extra = _catalog('recente', 50);
    await ChannelPrecompute.run(extra);
    final int before = ChannelPrecompute.debugCacheSize;
    // 50 orphelines < marge (+20 % et +1 000) : pas d'élagage.
    ChannelPrecompute.retainOnly(shown);
    expect(ChannelPrecompute.debugCacheSize, before);
  });
}
