// =========================================================
//  smart_search_test.dart — Tests du moteur de recherche
// =========================================================
//  Couvre les six promesses du moteur (voir smart_search.dart) :
//  multi-mots ordre libre, tolérance aux fautes, accents,
//  classement par pertinence, personnalisation, anti-doublons.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/data/smart_search.dart';
import 'package:tv_king/features/channels/domain/channel.dart';

/// Fabrique une chaîne de test minimale. L'id doit être unique
/// dans TOUT le fichier (les caches statiques de Channel et de
/// SmartSearch sont mémoïsés par id pour toute la session de test).
Channel ch(
  String id,
  String name, {
  String category = 'GENERAL',
  String? logoUrl,
}) =>
    Channel(
      id: id,
      name: name,
      category: category,
      streamUrl: 'http://example.com/$id.ts',
      isLive: true,
      logoUrl: logoUrl,
    );

void main() {
  group('SmartSearch.normalize', () {
    test('minuscules, accents retirés, décorations → espaces', () {
      expect(SmartSearch.normalize('Ciné+ Premier'), 'cine premier');
      expect(SmartSearch.normalize('★ FR| TF1 ᴴᴰ'), 'fr tf1');
      expect(SmartSearch.normalize('  beIN--SPORTS_1  '), 'bein sports 1');
    });
  });

  group('multi-mots, ordre libre (logique ET)', () {
    final List<Channel> pool = <Channel>[
      ch('mw1', 'beIN SPORTS 1 FR'),
      ch('mw2', 'TF1'),
      ch('mw3', 'France Sport TV'),
    ];

    test('« bein 1 » trouve « beIN SPORTS 1 FR », pas TF1', () {
      final List<Channel> r =
          SmartSearch.rank(query: 'bein 1', pool: pool);
      expect(r.map((Channel c) => c.id), contains('mw1'));
      expect(r.map((Channel c) => c.id), isNot(contains('mw2')));
    });

    test('« sport france » trouve « France Sport TV » (ordre inversé)',
        () {
      final List<Channel> r =
          SmartSearch.rank(query: 'sport france', pool: pool);
      expect(r.map((Channel c) => c.id), contains('mw3'));
    });

    test('un mot sans correspondance rejette la chaîne', () {
      final List<Channel> r =
          SmartSearch.rank(query: 'bein cinema', pool: pool);
      expect(r, isEmpty);
    });

    test('requête vide → aucun résultat', () {
      expect(SmartSearch.rank(query: '   ', pool: pool), isEmpty);
      expect(SmartSearch.rank(query: '', pool: pool), isEmpty);
    });
  });

  group('tolérance aux fautes de frappe', () {
    final List<Channel> pool = <Channel>[
      ch('tp1', 'Netflix Action'),
      ch('tp2', 'Sport TV'),
      ch('tp3', 'TF1'),
    ];

    test('lettre manquante : « netflx » → Netflix', () {
      final List<Channel> r =
          SmartSearch.rank(query: 'netflx', pool: pool);
      expect(r.map((Channel c) => c.id), contains('tp1'));
    });

    test('transposition : « sprot » → Sport TV (1 seule faute en OSA)',
        () {
      final List<Channel> r =
          SmartSearch.rank(query: 'sprot', pool: pool);
      expect(r.map((Channel c) => c.id), contains('tp2'));
    });

    test('pas de correction sur les mots courts : « tf2 » ≠ TF1', () {
      final List<Channel> r = SmartSearch.rank(query: 'tf2', pool: pool);
      expect(r.map((Channel c) => c.id), isNot(contains('tp3')));
    });
  });

  group('accents et décorations IPTV', () {
    final List<Channel> pool = <Channel>[
      ch('ac1', 'Ciné+ Premier'),
      ch('ac2', '★ FR| M6 ★', category: 'FR| GENERALISTE'),
    ];

    test('« cine » trouve « Ciné+ Premier »', () {
      final List<Channel> r = SmartSearch.rank(query: 'cine', pool: pool);
      expect(r.map((Channel c) => c.id), contains('ac1'));
    });

    test('« m6 » trouve la chaîne malgré les décorations', () {
      final List<Channel> r = SmartSearch.rank(query: 'm6', pool: pool);
      expect(r.map((Channel c) => c.id), contains('ac2'));
    });
  });

  group('classement par pertinence', () {
    test('mot entier > préfixe de mot > substring', () {
      final List<Channel> pool = <Channel>[
        ch('rk1', 'Eurosport'), // « sport » en substring
        ch('rk2', 'Sport TV'), // mot entier + commence par la requête
        ch('rk3', 'beIN Sports'), // préfixe de mot (« sports »)
      ];
      final List<Channel> r = SmartSearch.rank(query: 'sport', pool: pool);
      expect(r.map((Channel c) => c.id).toList(),
          <String>['rk2', 'rk3', 'rk1']);
    });

    test('le nom pèse plus que la catégorie', () {
      final List<Channel> pool = <Channel>[
        ch('rc1', 'Chasse & Pêche', category: 'SPORT'),
        ch('rc2', 'Sportitalia'),
      ];
      final List<Channel> r = SmartSearch.rank(query: 'sport', pool: pool);
      expect(r.first.id, 'rc2');
      // La correspondance par catégorie reste trouvée, juste plus bas.
      expect(r.map((Channel c) => c.id), contains('rc1'));
    });
  });

  group('personnalisation (favoris / historique)', () {
    test('un favori remonte au-dessus d\'un score textuel égal', () {
      final List<Channel> pool = <Channel>[
        ch('pf1', 'RMC Sport 1'),
        ch('pf2', 'RMC Sport 2'),
      ];
      final List<Channel> r = SmartSearch.rank(
        query: 'rmc',
        pool: pool,
        signals: const SearchSignals(favoriteIds: <String>{'pf2'}),
      );
      expect(r.first.id, 'pf2');
    });

    test('une chaîne réellement regardée remonte', () {
      final List<Channel> pool = <Channel>[
        ch('pw1', 'DAZN 1'),
        ch('pw2', 'DAZN 2'),
      ];
      final List<Channel> r = SmartSearch.rank(
        query: 'dazn',
        pool: pool,
        signals: const SearchSignals(
          recentIds: <String>['pw2'],
          watchMsById: <String, int>{'pw2': 3600000},
        ),
      );
      expect(r.first.id, 'pw2');
    });

    test('la personnalisation ne fait pas remonter un mauvais match '
        'au-dessus d\'un excellent match', () {
      final List<Channel> pool = <Channel>[
        ch('pb1', 'Arte'), // match exact
        ch('pb2', 'Arte Concert HD'), // favori mais moins précis
      ];
      final List<Channel> r = SmartSearch.rank(
        query: 'arte',
        pool: pool,
        signals: const SearchSignals(favoriteIds: <String>{'pb2'}),
      );
      // « Arte » == la requête : le bonus plein-exact (+80) dépasse
      // tout cumul de personnalisation → l'intention textuelle gagne.
      expect(r.first.id, 'pb1');
    });
  });

  group('anti-doublons IPTV', () {
    test('les variantes du même nom sont rétrogradées, pas supprimées',
        () {
      final List<Channel> pool = <Channel>[
        ch('dd1', 'beIN Sports 1'),
        ch('dd2', 'beIN Sports 1'),
        ch('dd3', 'beIN Sports 1'),
        ch('dd4', 'beIN Sports Max 1'),
      ];
      final List<Channel> r =
          SmartSearch.rank(query: 'bein 1', pool: pool);
      // Tout le monde est là (rien n'est caché à l'utilisateur)…
      expect(r.length, 4);
      // …mais la 2e place revient à Max 1, pas au clone n°2.
      expect(r[1].id, 'dd4');
    });
  });

  group('bornes', () {
    test('le paramètre limit est respecté', () {
      final List<Channel> pool = <Channel>[
        for (int i = 0; i < 50; i++) ch('lim$i', 'News Channel $i'),
      ];
      final List<Channel> r =
          SmartSearch.rank(query: 'news', pool: pool, limit: 10);
      expect(r.length, 10);
    });
  });
}
