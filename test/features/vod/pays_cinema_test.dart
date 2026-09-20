// =========================================================
//  pays_cinema_test.dart — le Cinéma rangé par pays, la France en tête
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026) : « les Turcs ne voient pas
//  leurs séries, c'est mélangé. Chaque pays… ça commence la France. Mais
//  ne casse pas le display Netflix. »
//
//  Les libellés ci-dessous sont ceux que les fournisseurs écrivent
//  vraiment. Si un patch futur reconnaît « Series NO Limit » comme la
//  Norvège, ou éparpille de nouveau les rangées turques, on saute ici.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/vod/domain/pays_cinema.dart';

void main() {
  group('paysDeCategorie — les vingt façons d\'écrire un préfixe', () {
    test('France, sous toutes ses formes', () {
      for (final String c in <String>[
        'FR| FILMS ACTION',
        '|FR| NETFLIX',
        '[FR] Comédie',
        'FR - Drame',
        'FR: Enfants',
        'FR ▶ Thriller',
        'FRANCE - DISNEY+',
        'FRENCH MOVIES',
        'Films Français',
        'VF | Action',
        'VOSTFR Séries',
        '(fr) documentaires',
      ]) {
        expect(paysDeCategorie(c), 'FR', reason: c);
      }
    });

    test('Turquie : code, mot, et le mot « dizi » tout seul', () {
      for (final String c in <String>[
        'TR| DIZILER',
        '|TR| Yerli Filmler',
        'Series Turkish',
        'Türk Dizileri',
        'Dizi 2026',
        'TURKEY - Movies',
      ]) {
        expect(paysDeCategorie(c), 'TR', reason: c);
      }
    });

    test('monde arabe : générique et par pays', () {
      expect(paysDeCategorie('AR: أفلام'), 'AR');
      expect(paysDeCategorie('ARABIC MOVIES'), 'AR');
      expect(paysDeCategorie('أفلام عربية'), 'AR');
      expect(paysDeCategorie('MA| Films Marocains'), 'MA');
      expect(paysDeCategorie('Séries Algérie'), 'DZ');
      expect(paysDeCategorie('EG - Egyptian Series'), 'EG');
    });

    test('anglophones, distingués', () {
      expect(paysDeCategorie('[EN] Netflix'), 'EN');
      expect(paysDeCategorie('UK| Movies'), 'UK');
      expect(paysDeCategorie('US - Hollywood'), 'US');
      expect(paysDeCategorie('English Series'), 'EN');
    });

    test('autres pays courants', () {
      expect(paysDeCategorie('DE | Kino'), 'DE');
      expect(paysDeCategorie('IT: Film'), 'IT');
      expect(paysDeCategorie('ES| Peliculas'), 'ES');
      expect(paysDeCategorie('Latino Series'), 'LAT');
      expect(paysDeCategorie('VOD - INDIA'), 'IN');
      expect(paysDeCategorie('Bollywood Movies'), 'IN');
      expect(paysDeCategorie('PL| Filmy'), 'PL');
      expect(paysDeCategorie('Anime'), 'JP');
      expect(paysDeCategorie('K-Drama Korea'), 'KR');
    });

    test('un code court AU MILIEU n\'est pas un pays', () {
      // « NO » n'est pas la Norvège, « IT » n'est pas l'Italie, « IN »
      // n'est pas l'Inde : trois faux positifs classiques.
      expect(paysDeCategorie('Series NO Limit'), isNull);
      expect(paysDeCategorie('Films IT'), isNull);
      expect(paysDeCategorie('Best IN Class'), isNull);
      expect(paysDeCategorie('Top US'), isNull);
    });

    test('sans pays : générique, vide', () {
      expect(paysDeCategorie('NETFLIX 4K'), isNull);
      expect(paysDeCategorie('Nouveautés'), isNull);
      expect(paysDeCategorie('Films - Action'), isNull);
      expect(paysDeCategorie(''), isNull);
      expect(paysDeCategorie('   '), isNull);
    });
  });

  group('ordonnerParPays — la France, le généraliste, puis chaque pays', () {
    const List<String> fournisseur = <String>[
      'TR| Dizi',
      'FR| Action',
      'NETFLIX',
      'AR| أفلام',
      'FR| Comédie',
      'TR| Yerli Film',
      'Nouveautés',
      'AR| مسلسلات',
      'DE | Kino',
      'FR| Enfants',
    ];

    test('le client turc trouve ses rangées ENSEMBLE', () {
      final List<String> r = ordonnerParPays(fournisseur);
      final int dizi = r.indexOf('TR| Dizi');
      final int film = r.indexOf('TR| Yerli Film');
      expect(film, dizi + 1, reason: 'plus rien entre les deux rangées turques');
    });

    test('la France d\'abord, dans l\'ordre du fournisseur', () {
      final List<String> r = ordonnerParPays(fournisseur);
      expect(r.sublist(0, 3), <String>['FR| Action', 'FR| Comédie', 'FR| Enfants']);
    });

    test('le généraliste juste après la France, avant les autres pays', () {
      final List<String> r = ordonnerParPays(fournisseur);
      expect(r.sublist(3, 5), <String>['NETFLIX', 'Nouveautés'],
          reason: 'un client français ne descend pas sous les rangées '
              'turques pour trouver Netflix');
    });

    test('les autres pays dans l\'ordre de première apparition', () {
      final List<String> r = ordonnerParPays(fournisseur);
      expect(r.sublist(5), <String>[
        'TR| Dizi', 'TR| Yerli Film', // la Turquie est apparue avant l'arabe
        'AR| أفلام', 'AR| مسلسلات',
        'DE | Kino',
      ]);
    });

    test('rien de perdu, rien en double, même avec des doublons en entrée',
        () {
      final List<String> r = ordonnerParPays(<String>[
        'FR| A', 'TR| B', 'FR| A', 'X',
      ]);
      expect(r, <String>['FR| A', 'FR| A', 'X', 'TR| B']);
      expect(r.length, 4);
    });

    test('un autre pays en tête, si un jour la règle change', () {
      final List<String> r = ordonnerParPays(fournisseur, premier: 'TR');
      expect(r.sublist(0, 2), <String>['TR| Dizi', 'TR| Yerli Film']);
    });

    test('liste vide → liste vide', () {
      expect(ordonnerParPays(const <String>[]), isEmpty);
    });
  });

  // DEMANDE DU 20/09/2026 : « que les langues soient différentes… l'arabe
  // comme ça, les Français… facile surtout pour les gens âgés. »
  group('entetesDeSection — un grand titre dans SA langue, au bon endroit',
      () {
    test('chaque pays écrit comme ses locuteurs l\'écrivent', () {
      expect(libelleDePays('FR'), 'Français');
      expect(libelleDePays('TR'), 'Türkçe');
      expect(libelleDePays('AR'), startsWith('العربية'));
      expect(libelleDePays('MA'), contains('Maroc'),
          reason: 'le français en secours si la police arabe manque');
      expect(libelleDePays('CN'), startsWith('Chine'),
          reason: 'CJK : le français d\'abord, la police manque souvent');
    });

    test('un code sans libellé s\'affiche tel quel, il ne disparaît pas', () {
      expect(libelleDePays('ZZ'), 'ZZ');
    });

    test('un en-tête sur la PREMIÈRE rangée de chaque pays, jamais ailleurs',
        () {
      final List<String> cats = ordonnerParPays(<String>[
        'TR| Dizi',
        'FR| Action',
        'NETFLIX',
        'AR| أفلام',
        'FR| Comédie',
        'TR| Yerli Film',
        'Nouveautés',
        'AR| مسلسلات',
      ]);
      // Ordre obtenu : FR Action, FR Comédie, NETFLIX, Nouveautés,
      //                TR Dizi, TR Yerli, AR أفلام, AR مسلسلات
      expect(entetesDeSection(cats), <String?>[
        'Français', null, // la deuxième rangée française : rien
        null, null, // le généraliste ne porte JAMAIS d'en-tête
        'Türkçe', null,
        'العربية · Arabe', null,
      ]);
    });

    test('même longueur que l\'entrée : l\'écran lit entetes[i] pour la '
        'rangée i', () {
      final List<String> cats = <String>['FR| A', 'X', 'TR| B', 'TR| C'];
      expect(entetesDeSection(cats).length, cats.length);
    });

    test('une seule langue → aucun en-tête (rien à distinguer)', () {
      expect(entetesDeSection(<String>['FR| A', 'FR| B', 'NETFLIX']),
          everyElement(isNull));
      expect(entetesDeSection(<String>['NETFLIX', '4K']),
          everyElement(isNull));
      expect(entetesDeSection(const <String>[]), isEmpty);
    });

    test('un pays qui réapparaît plus bas reprend un en-tête', () {
      // Sans passer par ordonnerParPays : la fonction reste juste.
      expect(entetesDeSection(<String>['FR| A', 'TR| B', 'FR| C']),
          <String?>['Français', 'Türkçe', 'Français']);
    });
  });
}
