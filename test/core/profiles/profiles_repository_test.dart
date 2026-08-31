// =========================================================
//  profiles_repository_test.dart — Les règles qui protègent la famille
// =========================================================
//  On teste ici les décisions qui, si elles se retournaient, feraient
//  soit une PANNE CLIENT (plus de profils du tout), soit un TROU DE
//  CONTRÔLE PARENTAL (un enfant qui reprend la main). Ce sont les deux
//  seules façons dont cette fonctionnalité peut vraiment mal tourner.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/profiles/profiles_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ProfilesRepository.instance.debugReset();
  });

  TvProfile p(String id,
          {bool enabled = true, bool kids = false, ProfilePin? pin}) =>
      TvProfile(
          id: id, name: id, emoji: '🙂', enabled: enabled, kids: kids, pin: pin);

  group('applyRemote', () {
    test('les profils du panel arrivent marques « managed »', () async {
      final bool changed = await ProfilesRepository.instance
          .applyRemote(<TvProfile>[p('papa'), p('enfant1', kids: true)]);
      expect(changed, isTrue);
      // « Famille » + les deux du panel.
      expect(ProfilesRepository.instance.profiles.length, 3);
      expect(ProfilesRepository.instance.byId('papa')!.managed, isTrue);
    });

    test('rejouer la MEME liste ne signale aucun changement', () async {
      final List<TvProfile> list = <TvProfile>[p('papa'), p('maman')];
      expect(await ProfilesRepository.instance.applyRemote(list), isTrue);
      // Sans ce « false », chaque synchro (toutes les 5 min) ferait
      // recharger tous les dépôts par profil pour rien.
      expect(await ProfilesRepository.instance.applyRemote(list), isFalse);
    });

    test('un profil cree A LA MAIN survit a une poussee du panel', () async {
      await ProfilesRepository.instance.create('Mamie', '👵');
      await ProfilesRepository.instance.applyRemote(<TvProfile>[p('papa')]);
      // Le panel pousse SES profils ; il n'efface pas ceux du client.
      expect(ProfilesRepository.instance.byName('Mamie'), isNotNull);
    });

    test('couper le profil ACTIF a distance rend la main a « Famille »',
        () async {
      await ProfilesRepository.instance.applyRemote(<TvProfile>[p('enfant1')]);
      await ProfilesRepository.instance.setActive('enfant1');
      expect(ProfilesRepository.instance.active.id, 'enfant1');

      // C'est TOUT l'intérêt de pouvoir désactiver depuis le panel : la
      // bascule doit être immédiate, pas au prochain redémarrage.
      await ProfilesRepository.instance
          .applyRemote(<TvProfile>[p('enfant1', enabled: false)]);
      expect(ProfilesRepository.instance.active.id,
          ProfilesRepository.familyProfile.id);
    });

    test('un profil desactive reste VISIBLE mais pas selectionnable',
        () async {
      await ProfilesRepository.instance
          .applyRemote(<TvProfile>[p('enfant2', enabled: false)]);
      // Visible (grisé) : un enfant dont le profil disparaît croit à une
      // panne ; grisé, le message « c'est fermé » se lit tout seul.
      expect(ProfilesRepository.instance.byId('enfant2'), isNotNull);
      expect(
        ProfilesRepository.instance.selectable
            .any((TvProfile x) => x.id == 'enfant2'),
        isFalse,
      );
      // Et setActive refuse, même appelé directement.
      await ProfilesRepository.instance.setActive('enfant2');
      expect(ProfilesRepository.instance.active.id,
          ProfilesRepository.familyProfile.id);
    });
  });

  group('contournement du controle parental', () {
    test('un profil du PANEL ne se supprime pas depuis l appareil', () async {
      await ProfilesRepository.instance
          .applyRemote(<TvProfile>[p('enfant1', kids: true)]);
      await ProfilesRepository.instance.delete('enfant1');
      // Sinon il suffirait de supprimer le profil pour effacer la règle
      // qu'il porte, puis de regarder ce qu'on veut sous « Famille ».
      expect(ProfilesRepository.instance.byId('enfant1'), isNotNull);
    });

    test('« Famille » est indestructible', () async {
      await ProfilesRepository.instance
          .delete(ProfilesRepository.familyProfile.id);
      expect(ProfilesRepository.instance.byId('default'), isNotNull);
    });
  });

  group('mode enfant et categories, par profil', () {
    test('activeIsKids suit le profil actif', () async {
      await ProfilesRepository.instance.applyRemote(<TvProfile>[
        p('papa'),
        p('enfant1', kids: true),
      ]);
      expect(ProfilesRepository.instance.activeIsKids, isFalse); // Famille
      await ProfilesRepository.instance.setActive('enfant1');
      expect(ProfilesRepository.instance.activeIsKids, isTrue);
      await ProfilesRepository.instance.setActive('papa');
      expect(ProfilesRepository.instance.activeIsKids, isFalse);
    });

    test('les categories bloquees suivent le profil actif', () async {
      await ProfilesRepository.instance.applyRemote(<TvProfile>[
        const TvProfile(
          id: 'enfant1',
          name: 'Enfant 1',
          emoji: '🧒',
          blockedCategories: <String>['Adulte', 'Cinéma'],
        ),
      ]);
      expect(ProfilesRepository.instance.activeBlockedCategories, isEmpty);
      await ProfilesRepository.instance.setActive('enfant1');
      expect(ProfilesRepository.instance.activeBlockedCategories,
          <String>['Adulte', 'Cinéma']);
    });
  });

  group('lecture tolerante du JSON', () {
    test('un champ « enabled » ABSENT vaut « active »', () {
      // Règle qui évite une panne de masse : un serveur qui oublierait le
      // champ rendrait sinon TOUS les profils inaccessibles d'un coup.
      final TvProfile? x = TvProfile.fromJson(
          <String, Object?>{'id': 'a', 'name': 'A'});
      expect(x, isNotNull);
      expect(x!.enabled, isTrue);
      expect(x.kids, isFalse);
    });

    test('une ligne sans id ou sans nom est ignoree, pas fatale', () {
      expect(TvProfile.fromJson(<String, Object?>{'name': 'A'}), isNull);
      expect(TvProfile.fromJson(<String, Object?>{'id': 'a'}), isNull);
      expect(TvProfile.fromJson('pas un objet'), isNull);
    });

    test('un aller-retour JSON conserve tout, PIN compris', () {
      final TvProfile before = TvProfile(
        id: 'enfant1',
        name: 'Enfant 1',
        emoji: '🧒',
        enabled: false,
        kids: true,
        blockedCategories: const <String>['Adulte'],
        managed: true,
        pin: ProfilePin(salt: 's', hash: ProfilePin.derive('1234', 's')),
      );
      final TvProfile after = TvProfile.fromJson(before.toJson())!;
      expect(after.enabled, isFalse);
      expect(after.kids, isTrue);
      expect(after.managed, isTrue);
      expect(after.blockedCategories, <String>['Adulte']);
      expect(after.pin!.matches('1234'), isTrue);
    });
  });

  group('verifyPin', () {
    test('refuse un profil inconnu — jamais « true » par defaut', () {
      expect(ProfilesRepository.instance.verifyPin('inexistant', '1234'),
          isFalse);
    });

    test('un profil SANS code ne demande rien', () async {
      await ProfilesRepository.instance.applyRemote(<TvProfile>[p('papa')]);
      expect(ProfilesRepository.instance.requiresPin('papa'), isFalse);
      // …mais verifyPin reste faux : il n'y a pas de code à valider.
      expect(ProfilesRepository.instance.verifyPin('papa', '0000'), isFalse);
    });

    test('un profil AVEC code accepte le bon et refuse les autres', () async {
      await ProfilesRepository.instance.applyRemote(<TvProfile>[
        p('papa', pin: ProfilePin(salt: 'sel', hash: ProfilePin.derive('4242', 'sel'))),
      ]);
      expect(ProfilesRepository.instance.requiresPin('papa'), isTrue);
      expect(ProfilesRepository.instance.verifyPin('papa', '4242'), isTrue);
      expect(ProfilesRepository.instance.verifyPin('papa', '4243'), isFalse);
    });
  });

  group('capacite', () {
    test('les cinq profils du panel tiennent a cote de « Famille »',
        () async {
      // Le plafond était à 6 : « Famille » + 5, soit ZÉRO marge. Un seul
      // profil créé à la main faisait échouer en silence la génération du
      // panel — panne invisible et impossible à comprendre côté client.
      for (int i = 0; i < 3; i++) {
        await ProfilesRepository.instance.create('Local $i', '🙂');
      }
      await ProfilesRepository.instance.applyRemote(<TvProfile>[
        p('papa'), p('maman'), p('enfant1'), p('enfant2'), p('enfant3'),
      ]);
      expect(ProfilesRepository.instance.profiles.length, 9); // 1 + 5 + 3
      expect(ProfilesRepository.maxProfiles, greaterThanOrEqualTo(9));
    });
  });
}
