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
//
//  MISE À JOUR 21/08/2026 (décision propriétaire) : l'app ne PRÉSENTE
//  plus qu'un seul modèle — le D (panneau façon TiviMate) — hors mode
//  Développeur (caché, appui long sur « À propos »). La migration
//  ci-dessus continue de piloter le CHOIX MÉMORISÉ (`chosenTemplate`),
//  restitué tel quel dès que le mode Développeur est activé ; le
//  template EFFECTIF (`template`), lui, est forcé à D quand il est
//  inactif. Les assertions distinguent donc les deux.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/tv/core/tv_developer_mode.dart';
import 'package:tv_king/features/tv/core/tv_home_template.dart';

const String _kKey = 'tv.home.template.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Chaque test repart mode Développeur INACTIF (le défaut produit).
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await TvDeveloperMode.instance.setEnabled(false);
  });

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
    test('installation NEUVE (prefs vierges) → Modèle D (unique présenté)',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await TvHomeTemplateRepository.instance.initialize();
      expect(TvHomeTemplateRepository.instance.chosenTemplate,
          kDefaultTemplate);
      expect(TvHomeTemplateRepository.instance.template,
          TvHomeTemplate.tivimate);
      // La décision est GRAVÉE : le prochain boot ne rejoue pas l'arbitrage.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kKey), 'tivimate');
    });

    test(
        'box DÉJÀ EN SERVICE (prefs peuplées, aucun template choisi) : le '
        'choix mémorisé reste l\'historique, l\'accueil PRÉSENTÉ est le D',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tv_overscan_pct': 3,
        'some.other.legacy.key': true,
      });
      await TvHomeTemplateRepository.instance.initialize();
      expect(TvHomeTemplateRepository.instance.chosenTemplate,
          kLegacyDefaultTemplate);
      // Hors mode Développeur : Modèle D forcé (décision du 21/08).
      expect(TvHomeTemplateRepository.instance.template,
          TvHomeTemplate.tivimate);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kKey), 'classic',
          reason: 'le choix mémorisé n\'est jamais écrasé par le forçage');
    });

    test(
        'choix explicite du client → mémorisé à l\'identique, restitué en '
        'mode Développeur, D forcé sinon', () async {
      for (final TvHomeTemplate t in TvHomeTemplate.values) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          _kKey: t.id,
          'tv_overscan_pct': 0,
        });
        await TvHomeTemplateRepository.instance.initialize();
        expect(TvHomeTemplateRepository.instance.chosenTemplate, t,
            reason: 'le choix ${t.id} a été écrasé');
        expect(TvHomeTemplateRepository.instance.template,
            TvHomeTemplate.tivimate,
            reason: 'hors mode Développeur, l\'accueil présenté est TOUJOURS '
                'le Modèle D');
        await TvDeveloperMode.instance.setEnabled(true);
        expect(TvHomeTemplateRepository.instance.template, t,
            reason: 'le mode Développeur restitue le choix ${t.id}');
        await TvDeveloperMode.instance.setEnabled(false);
      }
    });

    test('identifiant inconnu (retour arrière de version) → repli historique',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kKey: 'modele-du-futur',
      });
      await TvHomeTemplateRepository.instance.initialize();
      expect(TvHomeTemplateRepository.instance.chosenTemplate,
          kLegacyDefaultTemplate);
      expect(TvHomeTemplateRepository.instance.template,
          TvHomeTemplate.tivimate);
    });
  });
}
