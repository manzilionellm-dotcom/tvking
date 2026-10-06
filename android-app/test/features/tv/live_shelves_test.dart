// =========================================================
//  live_shelves_test.dart — Rayons Direct sans calcul sur le fil UI
// =========================================================
//  ANR du 06/10/2026 (SHIELD, 09:07:21) : 50 000 chaînes arrivent alors que
//  l'écran croit le pré-calcul fini ; Tendances / « Pour vous » appelaient
//  cleanName / genre / country, qui CALCULENT quand la valeur manque.
//  Preuves ici :
//    1. les nouvelles fonctions ne déclenchent AUCUN calcul (cache intact) ;
//    2. contre-preuve : l'ancien accès (getter) remplit le cache = calcule,
//       et son temps est mesuré sur la même liste ;
//    3. résultats justes une fois le pré-calcul fait.
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/domain/live_shelves.dart';

List<Channel> _make(String prefix, int n) => <Channel>[
      for (int i = 0; i < n; i++)
        Channel(
          id: '$prefix-$i',
          name: i % 3 == 0
              ? 'US| FOX SPORTS $i ᴴᴰ/ᴿᴬᵂ ⁶⁰ᶠᵖˢ'
              : i % 3 == 1
                  ? 'FR| TF1 $i FHD'
                  : 'BR| NBA PASS PPV $i',
          category: i % 3 == 0 ? 'US| SPORT ᴴᴰ/ᴿᴬᵂ ⁶⁰ᶠᵖˢ' : 'FR| GENERAL',
          streamUrl: 'http://127.0.0.1/s/$prefix/$i.ts',
          isLive: true,
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('50 000 chaînes pas encore pré-calculées : aucun calcul, rayons vides, cache intact', () {
    final List<Channel> all = _make('nocalc', 50000);
    final Map<String, Channel> byId = <String, Channel>{for (final Channel c in all) c.id: c};
    final Stopwatch sw = Stopwatch()..start();
    final List<Channel> trend = trendingFromCache(all, <String>['TF1 1', 'FOX SPORTS 0']);
    final List<Channel> forYou = forYouFromCache(
      all: all, byId: byId, recent: <String>['nocalc-0', 'nocalc-1'], favorites: <String>{},
    );
    sw.stop();
    expect(trend, isEmpty);
    expect(forYou, isEmpty);
    for (final Channel c in all) {
      expect(ChannelPrecompute.cachedCleanName(c), isNull);
      expect(ChannelPrecompute.cachedGenre(c), isNull);
      expect(ChannelPrecompute.cachedCountry(c).known, isFalse);
    }
    debugPrint('[mesure] rayons depuis le cache, 50 000 chaînes : ${sw.elapsedMilliseconds} ms');
  });

  test('contre-preuve : l’ancien accès (getters) CALCULE sur le fil appelant', () {
    final List<Channel> all = _make('legacy', 50000);
    final Stopwatch sw = Stopwatch()..start();
    // Ce que faisait l'ancien code de Tendances + « Pour vous ».
    for (final Channel c in all) {
      c.cleanName;
      c.genre;
      c.country;
    }
    sw.stop();
    expect(all.every((Channel c) => ChannelPrecompute.cachedCleanName(c) != null), isTrue,
        reason: 'le getter a calculé et rempli le cache : c’est ce travail qui figeait le fil UI');
    debugPrint('[mesure] ancien calcul sur le fil appelant, 50 000 chaînes (machine de test) : '
        '${sw.elapsedMilliseconds} ms');
  });

  test('après le pré-calcul (isolate) : Tendances et « Pour vous » justes', () async {
    final List<Channel> all = _make('ok', 300);
    await ChannelPrecompute.run(all);
    expect(all.every(ChannelPrecompute.isDone), isTrue);
    final Map<String, Channel> byId = <String, Channel>{for (final Channel c in all) c.id: c};

    final String wanted = ChannelPrecompute.cachedCleanName(all[4])!;
    final List<Channel> trend = trendingFromCache(all, <String>[wanted.toUpperCase(), 'inconnue']);
    expect(trend.map((Channel c) => c.id), <String>['ok-4']);

    final List<Channel> forYou = forYouFromCache(
      all: all, byId: byId, recent: <String>['ok-0', 'ok-3'], favorites: <String>{'ok-6'},
    );
    expect(forYou, isNotEmpty);
    expect(forYou.length, lessThanOrEqualTo(40));
    expect(forYou.any((Channel c) => <String>{'ok-0', 'ok-3', 'ok-6'}.contains(c.id)), isFalse,
        reason: 'déjà vues et favorites exclues');
    final ChannelGenre g0 = ChannelPrecompute.cachedGenre(all[0])!;
    if (g0 != ChannelGenre.other) {
      expect(ChannelPrecompute.cachedGenre(forYou.first), g0, reason: 'le genre regardé passe en tête');
    }
  });
}
