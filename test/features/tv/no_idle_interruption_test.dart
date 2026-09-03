// =========================================================
//  no_idle_interruption_test.dart — Rien n'interrompt une lecture
// =========================================================
//  POURQUOI CE TEST EXISTE (31/08/2026).
//
//  Le propriétaire a demandé DEUX fois la même chose : « jamais le mode
//  veille », puis, photo à l'appui, « je ne veux pas ça » — l'écran
//  « Tu regardes encore ? » qui mettait la lecture en pause après 4 h
//  sans toucher la télécommande.
//
//  Le raisonnement qui a fait retirer cette fonction vaut aussi pour
//  celles qu'on pourrait rajouter demain : sur une télé de salon,
//  l'inactivité de la TÉLÉCOMMANDE ne veut pas dire absence de
//  SPECTATEUR. Un film de trois heures, un match, une soirée entre
//  amis : personne ne touche la télécommande, tout le monde regarde.
//
//  CE TEST LIT LE CODE SOURCE. C'est inhabituel, et c'est voulu : un
//  test d'interface ne prouverait rien ici, parce que le défaut qu'on
//  veut empêcher n'est pas « l'écran s'affiche mal » mais « quelqu'un a
//  RÉINTRODUIT un minuteur qui coupe la lecture ». Ça, ça se voit dans
//  le source, et nulle part ailleurs — surtout pour un déclenchement à
//  4 h qu'aucune suite de tests ne laissera jamais s'écouler.
// =========================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File lecteur =
      File('lib/features/tv/presentation/tv_player_screen.dart');

  test('le fichier du lecteur TV est bien là', () {
    // Si quelqu'un renomme le fichier, ce test devient sans objet en
    // silence — et la garantie disparaît sans que personne ne le voie.
    expect(lecteur.existsSync(), isTrue,
        reason: 'chemin du lecteur TV changé : mettre ce test à jour');
  });

  test('aucun « Tu regardes encore ? » ne remet la lecture en pause', () {
    final String src = lecteur.readAsStringSync();
    // On ignore les lignes de COMMENTAIRE : celles qui expliquent le
    // retrait citent forcément le nom de la fonction retirée.
    final String code = src
        .split('\n')
        .where((String l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    for (final String interdit in <String>[
      '_askStillWatching',
      '_kStillAfter',
      '_stillTimer',
      'tvPlayerStillWatching',
    ]) {
      expect(code.contains(interdit), isFalse,
          reason: 'le « Tu regardes encore ? » est de retour ($interdit). '
              'Le propriétaire l\'a fait retirer deux fois : ne pas le '
              'remettre sans lui demander.');
    }
  });

  test('aucun minuteur d inactivité ne met en pause ou n arrête le flux', () {
    final String src = lecteur.readAsStringSync();
    final List<String> lignes = src.split('\n');

    // On cherche un Timer.periodic dont le corps, dans les 12 lignes qui
    // suivent, appelle pause()/stop() sur le lecteur. C'est EXACTEMENT la
    // forme qu'avait le minuteur retiré ; c'est aussi celle que prendrait
    // sa réintroduction.
    final List<int> suspects = <int>[];
    for (int i = 0; i < lignes.length; i++) {
      if (!lignes[i].contains('Timer.periodic')) continue;
      final String bloc = lignes
          .sublist(i, i + 12 > lignes.length ? lignes.length : i + 12)
          .where((String l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (RegExp(r'_controller\.(pause|stop)\(').hasMatch(bloc)) {
        suspects.add(i + 1);
      }
    }
    expect(suspects, isEmpty,
        reason: 'un minuteur périodique met la lecture en pause ou l\'arrête '
            '(ligne(s) ${suspects.join(', ')}). Sur une télé de salon, '
            'télécommande immobile ne veut pas dire personne devant.');
  });

  test('l écran de veille ne s arme JAMAIS par-dessus le lecteur', () {
    // L'écran de veille anti-burn-in reste, lui : il protège les dalles
    // OLED des clients. Sa règle de sûreté est qu'il ne s'arme que sur
    // l'ACCUEIL. Ce test vérifie que la garde existe toujours — sans
    // elle, il redeviendrait une interruption de lecture.
    final File veille =
        File('lib/features/tv/presentation/tv_screensaver.dart');
    expect(veille.existsSync(), isTrue);
    final String src = veille.readAsStringSync();
    expect(
      RegExp(r'ModalRoute\.of|isCurrent|isActive').hasMatch(src),
      isTrue,
      reason: "l'écran de veille ne vérifie plus qu'il est sur l'écran "
          'visible : il pourrait recouvrir une lecture en cours.',
    );
  });
}
