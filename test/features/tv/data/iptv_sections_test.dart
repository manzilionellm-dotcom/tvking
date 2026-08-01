// =========================================================
//  iptv_sections_test.dart — Le menu latéral du Modèle B
// =========================================================
//  La maquette du client écrivait cinq pays EN DUR (France, Royaume-Uni,
//  États-Unis, Allemagne, Espagne). Sa source du soir est BELGE : ces
//  cinq sections auraient été vides. On garde sa structure de menu mais
//  on déduit les pays du bouquet réel.
//
//  Contrat vérifié :
//    1. le pays est reconnu dans le nom de catégorie, quelle que soit la
//       casse et la façon d'écrire du panel (« BE| », « BELGIUM », …) ;
//    2. les pays sortent classés par nombre de chaînes, le plus fourni
//       d'abord, et on n'en garde que [max] ;
//    3. deux pays à égalité gardent un ordre STABLE d'un lancement à
//       l'autre (sinon le menu danse) ;
//    4. un bouquet sans pays reconnaissable ne produit aucune section —
//       l'écran retombe alors sur « International », jamais sur du vide.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/data/iptv_sections.dart';

Channel _c(String id, String name, String cat) => Channel(
      id: id,
      name: name,
      category: cat,
      streamUrl: 'http://panel.example/live/u/p/$id.ts',
      isLive: true,
    );

void main() {
  test('reconnaissance du pays dans le nom de catégorie', () {
    expect(countryOfCategory('TV || FRANCE HD'), 'fr');
    expect(countryOfCategory('BE| BELGIUM VIP RAW'), 'be');
    expect(countryOfCategory('uk | sports'), 'uk');
    expect(countryOfCategory('USA ENTERTAINMENT'), 'us');
    expect(countryOfCategory('TV || GERMAN HD'), 'de');
    expect(countryOfCategory('SPANISH MOVIES'), 'es');
    expect(countryOfCategory('TV || DIVERS'), isNull);
  });

  test('les 5 pays les mieux fournis, du plus gros au plus petit', () {
    final List<IptvSection> s = topCountrySections(<String, int>{
      'BE| BELGIUM VIP': 300,
      'BE| TELESAT': 200,
      'TV || FRANCE HD': 400,
      'UK | GENERAL': 50,
      'USA | NEWS': 10,
      'TV || GERMAN': 5,
      'SPANISH | TV': 1,
      'TV || DIVERS': 9999, // non reconnu : ignoré
    });
    expect(s.map((IptvSection e) => e.id).toList(),
        <String>['be', 'fr', 'uk', 'us', 'de']);
    // Belgique = 300 + 200 (deux catégories additionnées).
    expect(s.first.count, 500);
    expect(s.first.label, 'Belgique');
    expect(s.first.emoji, '🇧🇪');
    expect(s.length, 5, reason: 'l\'Espagne est 6e → hors du menu');
  });

  test('égalité : ordre STABLE (le menu ne doit pas danser)', () {
    Map<String, int> bouquet() => <String, int>{
          'TV || FRANCE': 100,
          'USA | TV': 100,
          'UK | TV': 100,
        };
    final List<String> a =
        topCountrySections(bouquet()).map((IptvSection e) => e.id).toList();
    final List<String> b =
        topCountrySections(bouquet()).map((IptvSection e) => e.id).toList();
    expect(a, b);
  });

  test(
      'aucun pays reconnu → aucune section (l\'écran bascule sur '
      'International)', () {
    expect(
      topCountrySections(<String, int>{'DIVERS': 10, 'AUTRES': 4}),
      isEmpty,
    );
  });

  test('sections fixes : l\'ordre demandé par le client', () {
    expect(kIptvFixedSections.map((IptvSection s) => s.id).toList(),
        <String>['sports', 'films', 'international', 'favoris']);
  });

  // ---------------------------------------------------------
  //  Tri d'une section (règle du client : Sport → Info → reste)
  // ---------------------------------------------------------
  group('tri d\'une section', () {
    test('le sport passe devant l\'info, l\'info devant le reste', () {
      final List<Channel> l = <Channel>[
        _c('a', 'Zed Comedy', 'TV || FRANCE DIVERTISSEMENT'),
        _c('b', 'BFM TV', 'TV || FRANCE NEWS'),
        _c('c', 'beIN Sports 1', 'TV || FRANCE SPORT'),
      ];
      sortIptvChannels(l);
      expect(l.map((Channel c) => c.id).toList(), <String>['c', 'b', 'a']);
    });

    test('à genre égal, la chaîne qui S\'OUVRE le mieux ici passe devant', () {
      final List<Channel> l = <Channel>[
        _c('casse', 'AAA Sport', 'TV || FRANCE SPORT'),
        _c('sûre', 'ZZZ Sport', 'TV || FRANCE SPORT'),
      ];
      // Malgré l'alphabet (AAA avant ZZZ), la chaîne fiable passe devant.
      sortIptvChannels(
        l,
        scoreOf: (String id) => id == 'sûre' ? 0.98 : 0.10,
      );
      expect(l.first.id, 'sûre');
    });

    test('chaîne jamais testée : devant la mauvaise, derrière la sûre', () {
      final List<Channel> l = <Channel>[
        _c('mauvaise', 'B Sport', 'TV || FRANCE SPORT'),
        _c('inconnue', 'C Sport', 'TV || FRANCE SPORT'),
        _c('sûre', 'A Sport', 'TV || FRANCE SPORT'),
      ];
      sortIptvChannels(l, scoreOf: (String id) {
        if (id == 'sûre') return 0.95;
        if (id == 'mauvaise') return 0.10;
        return null; // pas assez d'essais → aucun avis
      });
      expect(l.map((Channel c) => c.id).toList(),
          <String>['sûre', 'inconnue', 'mauvaise']);
    });

    test('sans aucun avis : ordre alphabétique STABLE (rien ne danse)', () {
      List<Channel> bouquet() => <Channel>[
            _c('3', 'Canal Sport', 'TV || FRANCE SPORT'),
            _c('1', 'Alpha Sport', 'TV || FRANCE SPORT'),
            _c('2', 'beIN Sport', 'TV || FRANCE SPORT'),
          ];
      final List<Channel> a = bouquet();
      final List<Channel> b = bouquet();
      sortIptvChannels(a);
      sortIptvChannels(b);
      expect(a.map((Channel c) => c.id).toList(), <String>['1', '2', '3']);
      expect(a.map((Channel c) => c.id).toList(),
          b.map((Channel c) => c.id).toList());
    });

    test('l\'adulte est toujours relégué en dernier', () {
      expect(iptvGenreRank(ChannelGenre.adult),
          greaterThan(iptvGenreRank(ChannelGenre.other)));
      expect(iptvGenreRank(ChannelGenre.sports), 0);
    });
  });
}
