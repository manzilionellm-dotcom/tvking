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
import 'package:tv_king/features/tv/data/iptv_sections.dart';

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

  test('aucun pays reconnu → aucune section (l\'écran bascule sur '
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
}
