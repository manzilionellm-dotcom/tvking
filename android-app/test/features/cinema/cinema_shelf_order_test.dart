// =========================================================
//  cinema_shelf_order_test.dart — Rangement du cinéma
// =========================================================
//  Règle : rien n'est caché. Les rayons que le client fréquente passent
//  devant (3 au plus), puis sa langue, puis les catégories sans langue,
//  puis les autres langues. L'ordre du fournisseur est gardé dans
//  chaque groupe.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/cinema/data/cinema_taste.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/cinema/domain/cinema_shelf_order.dart';

CinemaCategory _cat(String key, {String? lang}) => CinemaCategory(
      key: key,
      name: key,
      parts: const <CategoryRef>[],
      languageKey: lang,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<CinemaCategory> cats = <CinemaCategory>[
    _cat('en action', lang: 'en'),
    _cat('netflix'),
    _cat('fr action', lang: 'fr'),
    _cat('ar drama', lang: 'ar'),
    _cat('fr comedie', lang: 'fr'),
    _cat('4k'),
  ];

  List<String> keys(List<CinemaCategory> l) =>
      l.map((CinemaCategory c) => c.key).toList();

  test('la langue du client passe devant, rien ne disparaît', () {
    final List<CinemaCategory> out =
        orderCinemaShelves(cats, viewerLanguage: 'fr');
    expect(keys(out), <String>[
      'fr action',
      'fr comedie',
      'netflix',
      '4k',
      'en action',
      'ar drama',
    ]);
    expect(out.length, cats.length);
  });

  test('code régional ou ISO 3 lettres : même langue', () {
    expect(
      keys(orderCinemaShelves(cats, viewerLanguage: 'fr-CA')).first,
      'fr action',
    );
    expect(
      keys(orderCinemaShelves(cats, viewerLanguage: 'ara')).first,
      'ar drama',
    );
  });

  test('langue inconnue ou absente : ordre du fournisseur, sans langue devant',
      () {
    expect(keys(orderCinemaShelves(cats, viewerLanguage: null)), <String>[
      'netflix',
      '4k',
      'en action',
      'fr action',
      'ar drama',
      'fr comedie',
    ]);
  });

  test('ses rayons montent en tête, trois au plus', () {
    final List<CinemaCategory> out = orderCinemaShelves(
      cats,
      viewerLanguage: 'fr',
      taste: const <String, int>{
        'ar drama': 5,
        '4k': 2,
        'en action': 2,
        'netflix': 1,
        'disparue': 9,
      },
    );
    expect(keys(out), <String>[
      'ar drama',
      'en action',
      '4k',
      'fr action',
      'fr comedie',
      'netflix',
    ]);
  });

  test('le carnet compte, et oublie les rayons les moins ouverts', () {
    Map<String, int> t = const <String, int>{};
    t = noteCinemaShelf(t, 'a');
    t = noteCinemaShelf(t, 'a');
    t = noteCinemaShelf(t, 'b');
    expect(t, <String, int>{'a': 2, 'b': 1});
    expect(noteCinemaShelf(t, ''), t);
    final Map<String, int> capped = noteCinemaShelf(t, 'c', maxEntries: 2);
    expect(capped.length, 2);
    expect(capped['a'], 2);
  });

  test('un carnet par profil et par type, effacé avec le profil', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await CinemaTaste.note('movie', 'p2', 'fr action');
    await CinemaTaste.note('movie', 'p2', 'fr action');
    await CinemaTaste.note('series', 'p2', 'netflix');
    await CinemaTaste.note('movie', 'p3', '4k');
    expect(await CinemaTaste.read('movie', 'p2'), <String, int>{'fr action': 2});
    expect(await CinemaTaste.read('series', 'p2'), <String, int>{'netflix': 1});
    await CinemaTaste.drop('p2');
    expect(await CinemaTaste.read('movie', 'p2'), isEmpty);
    expect(await CinemaTaste.read('series', 'p2'), isEmpty);
    expect(await CinemaTaste.read('movie', 'p3'), <String, int>{'4k': 1});
    expect(CinemaTaste.decode('pas du json'), isEmpty);
  });
}
