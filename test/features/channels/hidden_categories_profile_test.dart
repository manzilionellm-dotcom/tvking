// =========================================================
//  hidden_categories_profile_test.dart — Le verrou du panel tient
// =========================================================
//  Deux listes de masquage cohabitent : le CHOIX DU CLIENT (modifiable)
//  et le VERROU DU PANEL (lecture seule). Ce test vérifie qu'elles ne se
//  mélangent pas — parce que si elles se mélangeaient, `unhide()`
//  laisserait un enfant ré-afficher une catégorie que son parent a
//  interdite à distance. C'est LE trou possible de cette fonctionnalité.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/profiles/profiles_repository.dart';
import 'package:tv_king/features/channels/data/hidden_categories_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiddenCategoriesStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ProfilesRepository.instance.debugReset();
    store = HiddenCategoriesStore.instance;
    store.debugReset();
    await store.ensureLoaded();
  });

  Future<void> connecter(String id, List<String> bloquees) async {
    await ProfilesRepository.instance.applyRemote(<TvProfile>[
      TvProfile(
          id: id, name: id, emoji: '🧒', blockedCategories: bloquees),
    ]);
    await ProfilesRepository.instance.setActive(id);
    await store.reload();
  }

  test('le verrou du panel masque, meme sans choix du client', () async {
    await connecter('enfant1', <String>['Adulte']);
    expect(store.isHidden('Adulte'), isTrue);
    expect(store.blockedByPanelCount, 1);
  });

  test('unhide NE PEUT PAS rouvrir ce que le panel a bloque', () async {
    await connecter('enfant1', <String>['Adulte']);
    // Le geste que ferait un enfant curieux depuis « Catégories masquées ».
    await store.unhide('Adulte');
    expect(store.isHidden('Adulte'), isTrue,
        reason: 'le controle parental se contournerait en un clic');
    // clear() non plus : c'est le bouton « tout ré-afficher ».
    await store.clear();
    expect(store.isHidden('Adulte'), isTrue);
  });

  test('le client garde la main sur SES propres masquages', () async {
    await connecter('papa', <String>[]);
    await store.hide('Belgique');
    expect(store.isHidden('Belgique'), isTrue);
    await store.unhide('Belgique');
    expect(store.isHidden('Belgique'), isFalse);
  });

  test('la comparaison du panel ignore casse, accents et ponctuation',
      () async {
    // Le panel saisit « cinema » ; la source écrit « Cinéma & Séries ».
    // Sans normalisation, le parent croirait avoir bloqué une catégorie
    // qui, elle, resterait visible — le pire des cas : une protection
    // qu'on croit posée.
    await connecter('enfant2', <String>['cinema & series']);
    expect(store.isHidden('Cinéma & Séries'), isTrue);
    expect(store.isHidden('CINEMA-SERIES'), isTrue);
    // Mais on ne bloque pas au-delà : « Cinema Adulte » est autre chose.
    expect(store.isHidden('Cinema Adulte'), isFalse);
  });

  test('changer de profil change la liste bloquee', () async {
    await connecter('enfant1', <String>['Adulte']);
    expect(store.isHidden('Adulte'), isTrue);

    await ProfilesRepository.instance.applyRemote(<TvProfile>[
      const TvProfile(id: 'papa', name: 'Papa', emoji: '👨'),
      const TvProfile(
          id: 'enfant1',
          name: 'Enfant 1',
          emoji: '🧒',
          blockedCategories: <String>['Adulte']),
    ]);
    await ProfilesRepository.instance.setActive('papa');
    await store.reload();
    expect(store.isHidden('Adulte'), isFalse);
  });

  test('le masquage du client est PAR PROFIL', () async {
    await connecter('papa', <String>[]);
    await store.hide('Sport');
    expect(store.isHidden('Sport'), isTrue);

    // Maman ne doit pas hériter du choix de papa.
    await ProfilesRepository.instance.applyRemote(<TvProfile>[
      const TvProfile(id: 'papa', name: 'Papa', emoji: '👨'),
      const TvProfile(id: 'maman', name: 'Maman', emoji: '👩'),
    ]);
    await ProfilesRepository.instance.setActive('maman');
    await store.reload();
    expect(store.isHidden('Sport'), isFalse);

    // …et le choix de papa n'est pas perdu pour autant.
    await ProfilesRepository.instance.setActive('papa');
    await store.reload();
    expect(store.isHidden('Sport'), isTrue);
  });

  test('applyFilter retire les deux sortes de masquage', () async {
    await connecter('enfant1', <String>['Adulte']);
    await store.hide('Belgique');
    final List<String> visibles = store.applyFilter<String>(
      <String>['Adulte', 'Belgique', 'Sport', 'Actualites'],
      (String s) => s,
    );
    expect(visibles, <String>['Sport', 'Actualites']);
  });
}
