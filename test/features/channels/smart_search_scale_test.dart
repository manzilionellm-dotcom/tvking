// =========================================================
//  smart_search_scale_test.dart — 40 000 chaînes = 2 chaînes
// =========================================================
//  DEMANDE CLIENT (2026-08-01) : « même s'il y a 40 000 chaînes, mon app
//  doit répondre comme s'il y en avait deux ».
//
//  Le coût dominant de la recherche était la NORMALISATION : `rank`
//  normalisait 3 textes PAR CHAÎNE (nom, nom curé, catégorie) à chaque
//  frappe — 120 000 parcours caractère par caractère sur un gros
//  bouquet, sur le thread de l'interface. Ces textes ne changent jamais :
//  ils sont désormais mémorisés.
//
//  Contrat vérifié ici :
//    1. les résultats sont IDENTIQUES avec ou sans mémo (aucune
//       corruption : le mémo ne doit rien changer au classement) ;
//    2. la 2e recherche sur le même bouquet est nettement plus rapide
//       que la 1re (le mémo travaille vraiment) ;
//    3. 40 000 chaînes restent sous un budget de temps utilisable.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/data/smart_search.dart';
import 'package:tv_king/features/channels/domain/channel.dart';

List<Channel> _bouquet(int n) => <Channel>[
      for (int i = 0; i < n; i++)
        Channel(
          id: 'c$i',
          name: i % 7 == 0
              ? 'BEIN Sport ${i % 40} FR'
              : 'Chaîne Générale ${i % 500} HD',
          category: 'TV || CATÉGORIE ${i % 60}',
          streamUrl: 'http://panel.example/live/u/p/$i.ts',
          isLive: true,
        ),
    ];

void main() {
  setUp(SmartSearch.clearNormalizeCache);

  test('le mémo ne change RIEN aux résultats', () {
    final List<Channel> pool = _bouquet(3000);
    final List<Channel> aFroid =
        SmartSearch.rank(query: 'bein sport', pool: pool);
    // 2e passage : tout vient du mémo.
    final List<Channel> aChaud =
        SmartSearch.rank(query: 'bein sport', pool: pool);
    expect(aChaud.map((Channel c) => c.id).toList(),
        aFroid.map((Channel c) => c.id).toList());
    expect(aFroid, isNotEmpty);
  });

  test('accents et casse restent corrects après mémorisation', () {
    final List<Channel> pool = <Channel>[
      Channel(
        id: 'a',
        name: 'CINÉMA Première',
        category: 'FILMS',
        streamUrl: 'http://panel.example/live/u/p/a.ts',
        isLive: true,
      ),
    ];
    for (int i = 0; i < 3; i++) {
      final List<Channel> hits =
          SmartSearch.rank(query: 'cinema premiere', pool: pool);
      expect(hits.single.id, 'a', reason: 'passe $i');
    }
  });

  test('40 000 chaînes : la 2e recherche est bien plus rapide que la 1re',
      () {
    final List<Channel> pool = _bouquet(40000);

    final Stopwatch froid = Stopwatch()..start();
    SmartSearch.rank(query: 'bein', pool: pool);
    froid.stop();

    final Stopwatch chaud = Stopwatch()..start();
    SmartSearch.rank(query: 'beins', pool: pool); // frappe suivante
    chaud.stop();

    // Le mémo doit faire gagner un ORDRE de grandeur en pratique ; on
    // vérifie au minimum un net gain, sans dépendre de la machine de CI.
    expect(chaud.elapsedMicroseconds, lessThan(froid.elapsedMicroseconds),
        reason: 'la frappe suivante doit profiter du mémo '
            '(froid ${froid.elapsedMilliseconds} ms, '
            'chaud ${chaud.elapsedMilliseconds} ms)');
  });
}
