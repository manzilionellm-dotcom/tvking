// =========================================================
//  famille_eteinte_test.dart — « une application normale »
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (17/09/2026) :
//
//    « Désactive carrément les trucs de famille, que ce soit une
//      application normale qui n'a pas de trucs de famille, des users. »
//
//  ---------------------------------------------------------
//  CE QUI L'A DÉCLENCHÉE : LA BOÎTE NOIRE D'UNE VRAIE BOX
//  ---------------------------------------------------------
//    21:14:51 WARN profiles.remote.sync_fail
//             {Failed host lookup: 'seven-motion-backend…workers.dev',
//              errno = 7}
//    21:09:57 WARN profiles.remote.sync_fail   {la même, 5 min plus tôt}
//
//  La synchronisation des profils réveillait le réseau toutes les deux à
//  trois minutes pour aller chercher des profils que ce client n'a jamais
//  créés. Elle échouait, elle recommençait, et elle noyait les lignes qui
//  comptaient vraiment dans le journal.
//
//  ---------------------------------------------------------
//  CE QUE CE TEST PROTÈGE
//  ---------------------------------------------------------
//  Trois choses, et il faut les trois :
//
//   1. L'INTERRUPTEUR EST BIEN ÉTEINT PAR DÉFAUT. Un interrupteur qu'on
//      croit sur « off » et qui est sur « on » est pire que pas
//      d'interrupteur du tout.
//
//   2. PLUS AUCUN TRAVAIL DE FOND NE PART. C'est la moitié qui se voit
//      chez le client : pas de requête, pas de journal, pas de réveil.
//
//   3. LES DONNÉES DU CLIENT NE BOUGENT PAS D'UN POUCE. C'est la moitié
//      qui se voit le lendemain matin, quand quelqu'un rouvre l'app et
//      ne retrouve ni ses favoris ni son historique. `keySuffix` est la
//      pièce qui décide de ça, et elle doit rester VIDE.
//
//  Un quatrième test lit les FICHIERS SOURCES pour vérifier qu'aucune
//  porte d'interface n'a été laissée ouverte. On ne peut pas « cliquer »
//  ces écrans dans un test unitaire ; on peut, en revanche, refuser
//  qu'un bouton y mène sans passer par l'interrupteur.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/family_feature.dart';
import 'package:tv_king/core/profiles/profiles_repository.dart';
import 'package:tv_king/core/profiles/remote_profiles_repository.dart';
import 'package:tv_king/features/subscription/data/family_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Ce fichier teste l'app TELLE QU'ELLE PART. On ne touche donc PAS à
  // `familleActiveePourTest` ici — on remet seulement l'interrupteur dans
  // sa position de compilation, au cas où un autre fichier du même
  // processus l'aurait laissé allumé.
  setUp(reinitialiserFamillePourTest);

  group('l\'interrupteur', () {
    test('est ÉTEINT par défaut', () {
      expect(kFamilleActivee, isFalse,
          reason: 'c\'est CE booléen que lisent les quinze autres endroits ; '
              's\'il est allumé, tout le reste de ce fichier ne prouve rien');
      expect(kFamilleCompilee, isFalse,
          reason: 'un build sans --dart-define doit partir famille éteinte');
    });

    test('se rallume, et se remet en place', () {
      // Une extinction irréversible serait un piège : le jour où le
      // propriétaire revend du multi-profil, il faut pouvoir revenir.
      familleActiveePourTest = true;
      expect(kFamilleActivee, isTrue);
      reinitialiserFamillePourTest();
      expect(kFamilleActivee, isFalse);
    });
  });

  group('plus aucun travail de fond', () {
    test('la synchro des profils ne part PAS — c\'est la ligne du journal',
        () async {
      // Si le garde sautait, cet appel tenterait un vrai GET (donc une
      // résolution DNS) et mettrait des secondes à échouer. Ici il doit
      // rendre la main immédiatement, sans toucher au réseau.
      final Stopwatch sw = Stopwatch()..start();
      final bool change = await RemoteProfilesRepository.instance.sync('MK:AA');
      sw.stop();

      expect(change, isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)),
          reason: 'un retour instantané prouve qu\'aucun hôte n\'a été '
              'contacté : le timeout réseau du module est de 6 s');
    });

    test('les appels famille du backend rendent tous la main à vide',
        () async {
      // Les quatre portes réseau de FamilyBackend. Les fermer TOUTES est
      // la ceinture par-dessus les bretelles : l'interface qui y menait
      // est déjà inatteignable, mais une porte non fermée finit toujours
      // par être repoussée par quelqu'un.
      expect(await FamilyBackend.info('MK:AA'), isNull);
      expect(await FamilyBackend.invite('MK:AA'), isNull);
      expect(await FamilyBackend.join('MK:AA', '123456'), isNull);
      expect(await FamilyBackend.positions('MK:AA', 'default'), isNull);
      expect(
        await FamilyBackend.pushPositions('MK:AA', 'default',
            <Map<String, Object?>>[]),
        isFalse,
      );
    });
  });

  group('les données du client ne bougent pas', () {
    test('un seul profil, et c\'est « Famille »', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await ProfilesRepository.instance.debugReset();

      expect(ProfilesRepository.instance.profiles.length, 1);
      expect(ProfilesRepository.instance.active.id,
          ProfilesRepository.familyProfile.id);
      expect(ProfilesRepository.instance.selectable.length, 1);
    });

    test('LE POINT CRITIQUE : une box qui tournait sur le profil d\'un '
        'enfant retrouve ses favoris', () async {
      // Le scénario qui aurait coûté cher. `keySuffix` est collé à la fin
      // de CHAQUE clé de rangement : favoris, derniers vus, recherches,
      // watchlist, positions de lecture. Une box restée sur « .p_leo »
      // aurait cherché ses données sous un nom que plus personne n'écrit
      // — écrans vides, et un client persuadé d'avoir tout perdu.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tv_profile_active': 'p_leo',
        'tv_profiles': '[{"id":"p_leo","name":"Leo","emoji":"🦊"}]',
      });
      await ProfilesRepository.instance.debugReset();
      await ProfilesRepository.instance.load();

      expect(ProfilesRepository.instance.active.id, 'default');
      expect(ProfilesRepository.instance.keySuffix, '',
          reason: 'suffixe VIDE = les clés d\'origine = les données du '
              'client sont toujours là où elle les a rangées');
    });

    test('on n\'écrit pas ce qu\'on n\'affichera pas', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await ProfilesRepository.instance.debugReset();

      await ProfilesRepository.instance.create('Papa', '🧔');
      expect(ProfilesRepository.instance.profiles.length, 1,
          reason: 'un profil écrit sur le disque mais jamais affiché est '
              'un bug en attente du jour où on rallume');

      expect(
        await ProfilesRepository.instance.applyRemote(
          <TvProfile>[const TvProfile(id: 'p_x', name: 'X', emoji: '🙂')],
        ),
        isFalse,
      );
      expect(ProfilesRepository.instance.profiles.length, 1);
    });

    test('éteindre n\'est pas EFFACER', () async {
      // Les profils déjà créés par le client restent sur le disque. On
      // les cache, on ne les brûle pas : le rallumage doit les retrouver.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tv_profiles': '[{"id":"p_leo","name":"Leo","emoji":"🦊"}]',
      });
      await ProfilesRepository.instance.debugReset();
      await ProfilesRepository.instance.load();
      expect(ProfilesRepository.instance.profiles.length, 1);

      familleActiveePourTest = true;
      expect(ProfilesRepository.instance.profiles.length, 2,
          reason: 'Leo était toujours là, simplement caché');
      reinitialiserFamillePourTest();
    });
  });

  group('aucune porte d\'interface laissée ouverte', () {
    // On ne peut pas cliquer ces écrans dans un test unitaire. On peut
    // refuser qu'un chemin y mène sans passer par l'interrupteur.
    //
    // La règle : dans ces fichiers, chaque MENTION d'un écran famille doit
    // cohabiter avec `kFamilleActivee`. C'est grossier, et c'est voulu :
    // un test grossier qui se déclenche vaut mieux qu'un test fin que
    // personne n'écrit.
    const Map<String, List<String>> portes = <String, List<String>>{
      'lib/features/settings/presentation/settings_screen.dart': <String>[
        'FamilyScreen(',
        'ProfilePickerScreen(',
      ],
      'lib/features/tv/presentation/tv_settings_screen.dart': <String>[
        'TvFamilyScreen(',
        'TvProfilesScreen(',
      ],
      'lib/features/tv/presentation/tv_activation_screen.dart': <String>[
        'TvFamilyJoinScreen(',
      ],
      'lib/features/tv/presentation/tv_launcher_home_screen.dart': <String>[
        'TvProfilesScreen(',
      ],
      'lib/features/tv/presentation/tv_rails_home_screen.dart': <String>[
        'TvProfilesScreen(',
      ],
      'lib/features/tv/presentation/tv_app.dart': <String>[
        '_ProfileChip(',
      ],
    };

    portes.forEach((String chemin, List<String> ecrans) {
      test('${chemin.split('/').last} garde ses portes', () {
        final File f = File(chemin);
        // Un test qui lit un fichier absent passerait tout vert sans rien
        // vérifier. On échoue franchement plutôt que de rassurer à tort.
        expect(f.existsSync(), isTrue, reason: chemin);

        final String code = f.readAsStringSync();
        expect(code.contains('kFamilleActivee'), isTrue,
            reason: '$chemin mène à un écran famille sans lire '
                'l\'interrupteur : le bouton serait de nouveau visible');

        for (final String ecran in ecrans) {
          expect(code.contains(ecran), isTrue,
              reason: 'l\'écran $ecran a été renommé ou retiré de $chemin — '
                  'ce test ne surveille plus rien, mets-le à jour');
        }
      });
    });

    test('le garde est posé À LA SOURCE, pas seulement sur les boutons', () {
      // C'est la leçon de `android_overlay/**` absent des `paths` des
      // workflows : un appelant s'oublie, une source non. Les quatre
      // fichiers ci-dessous sont les points de passage obligés.
      for (final String chemin in <String>[
        'lib/core/profiles/remote_profiles_repository.dart', // la synchro
        'lib/core/profiles/profiles_repository.dart', // la liste
        'lib/features/subscription/data/family_backend.dart', // le réseau
        'lib/features/vod/data/family_position_sync.dart', // les positions
      ]) {
        final File f = File(chemin);
        expect(f.existsSync(), isTrue, reason: chemin);
        expect(f.readAsStringSync().contains('kFamilleActivee'), isTrue,
            reason: '$chemin travaille encore quand la famille est éteinte');
      }
    });

    test('LE SERVEUR N\'EST PAS TOUCHÉ — c\'est la grille de licence', () {
      // `familyStatusForMac` porte le mot « family » mais n'est PAS du
      // confort : c'est elle qui décide si une MAC a le droit de recevoir
      // sa playlist, et `familyOwnerOf` fait hériter une box de la source
      // de son propriétaire. Les couper, c'est couper la source de TOUT
      // le parc — des clients qui paient et qui n'ont plus rien.
      //
      // Ce test existe pour que la prochaine personne qui lit « famille »
      // dans `worker.js` et pense « ah, c'est désactivé » tombe ici.
      final File w = File('cloudflare/worker.js');
      expect(w.existsSync(), isTrue);
      final String js = w.readAsStringSync();
      expect(js.contains('familyStatusForMac'), isTrue,
          reason: 'la grille de licence a disparu du worker');
      expect(js.contains('familyOwnerOf'), isTrue,
          reason: 'l\'héritage de source a disparu du worker');
    });
  });
}
