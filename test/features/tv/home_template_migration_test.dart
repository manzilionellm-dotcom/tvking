// =========================================================
//  home_template_migration_test.dart — Bascule A↔B (15/08/2026)
// =========================================================
//  Décision du propriétaire : le modèle « grandes tuiles » devient le
//  Modèle A (vitrine) et l'accueil par défaut des installations NEUVES ;
//  l'accueil historique devient le Modèle B.
//
//  LE RISQUE que ces tests verrouillent : chaque univers a SES favoris
//  (`favoritesScopeForTemplate` — `default` pour le classique, `seven`
//  pour les autres). Si une box DÉJÀ EN SERVICE basculait d'office sur le
//  nouveau défaut, le client verrait son accueil changer ET ses favoris
//  « disparaître » du jour au lendemain. La règle est donc :
//
//    • préférences VIERGES (vraie 1re ouverture) → Modèle A (launcher) ;
//    • préférences DÉJÀ PEUPLÉES (box en service) → on reste sur
//      l'historique (classic), et on le GRAVE pour stabiliser ;
//    • choix explicite déjà mémorisé → intouchable, quel qu'il soit.
//
//  Si un patch futur retire ce garde-fou, on saute ici.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/tv/core/tv_home_template.dart';

const String _kKey = 'tv.home.template.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ordre et libellés des modèles', () {
    test('le lanceur est le Modèle A, le classique le Modèle B', () {
      expect(kTemplateOrder.first, TvHomeTemplate.launcher);
      expect(TvHomeTemplate.launcher.letter, 'A');
      expect(TvHomeTemplate.classic.letter, 'B');
      expect(TvHomeTemplate.rails.letter, 'C');
      expect(TvHomeTemplate.tivimate.letter, 'D');
    });

    test('chaque modèle apparaît une fois et une seule dans l\'ordre', () {
      expect(kTemplateOrder.toSet().length, TvHomeTemplate.values.length);
      for (final TvHomeTemplate t in TvHomeTemplate.values) {
        expect(kTemplateOrder.contains(t), isTrue, reason: '${t.id} absent');
      }
    });

    test('les identifiants persistés restent stables (pas de casse des box)',
        () {
      expect(TvHomeTemplate.classic.id, 'classic');
      expect(TvHomeTemplate.launcher.id, 'launcher');
      expect(TvHomeTemplate.rails.id, 'rails');
      expect(TvHomeTemplate.tivimate.id, 'tivimate');
    });
  });

  group('Migration au démarrage', () {
    test('installation NEUVE (prefs vierges) → Modèle A (lanceur)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await TvHomeTemplateRepository.instance.initialize();
      expect(TvHomeTemplateRepository.instance.template, kDefaultTemplate);
      expect(TvHomeTemplateRepository.instance.template,
          TvHomeTemplate.launcher);
      // La décision est GRAVÉE : le prochain boot ne rejoue pas l'arbitrage.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kKey), 'launcher');
    });

    test(
        'box DÉJÀ EN SERVICE (prefs peuplées, aucun template choisi) → reste '
        'sur l\'accueil historique — favoris préservés', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tv_overscan_pct': 3,
        'some.other.legacy.key': true,
      });
      await TvHomeTemplateRepository.instance.initialize();
      expect(TvHomeTemplateRepository.instance.template,
          kLegacyDefaultTemplate);
      expect(TvHomeTemplateRepository.instance.template,
          TvHomeTemplate.classic);
      expect(favoritesScopeForTemplate(TvHomeTemplateRepository.instance.template),
          'default');
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kKey), 'classic');
    });

    test('choix explicite du client → respecté à l\'identique', () async {
      for (final TvHomeTemplate t in TvHomeTemplate.values) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          _kKey: t.id,
          'tv_overscan_pct': 0,
        });
        await TvHomeTemplateRepository.instance.initialize();
        expect(TvHomeTemplateRepository.instance.template, t,
            reason: 'le choix ${t.id} a été écrasé');
      }
    });

    test('identifiant inconnu (retour arrière de version) → repli historique',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kKey: 'modele-du-futur',
      });
      await TvHomeTemplateRepository.instance.initialize();
      expect(TvHomeTemplateRepository.instance.template,
          kLegacyDefaultTemplate);
    });
  });
}
