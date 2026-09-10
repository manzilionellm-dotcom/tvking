// Test — la barre de progression du lecteur PC.
//
// Ces trois regles se trompent EN SILENCE : rien ne plante, ca s'affiche
// simplement faux. D'ou ces assertions.
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/player/player_progress.dart';

void main() {
  group('estDirect', () {
    test('une chaine en direct n\'a pas de duree', () {
      expect(estDirect(Duration.zero), isTrue);
    });

    test('les premieres millisecondes d\'un flux comptent aussi comme direct',
        () {
      // libmpv annonce parfois une duree minuscule le temps que le tampon
      // se remplisse. Sans ce seuil, la barre clignoterait au demarrage de
      // chaque chaine.
      expect(estDirect(const Duration(milliseconds: 400)), isTrue);
    });

    test('un film a une duree, ce n\'est pas du direct', () {
      expect(estDirect(const Duration(minutes: 92)), isFalse);
    });
  });

  group('progression', () {
    test('la moitie d\'un film donne 0,5', () {
      expect(
        progression(const Duration(minutes: 45), const Duration(minutes: 90)),
        closeTo(0.5, 0.001),
      );
    });

    test('en direct, aucune progression a afficher', () {
      expect(progression(const Duration(hours: 3), Duration.zero), 0);
    });

    // LE CAS QUI COMPTE. Sur un flux live, la position depasse
    // regulierement la duree annoncee (le tampon a de l'avance). Sans
    // bornage, la barre sortirait de son cadre a l'ecran.
    test('une position qui depasse la duree ne fait pas deborder la barre',
        () {
      expect(
        progression(const Duration(minutes: 200), const Duration(minutes: 90)),
        1,
      );
    });

    test('une position negative ne recule pas la barre', () {
      expect(
        progression(const Duration(seconds: -5), const Duration(minutes: 90)),
        0,
      );
    });
  });

  group('formatDuree', () {
    test('sous une heure, on n\'ecrit pas l\'heure', () {
      // « 0:04:07 » se lit moins bien que « 4:07 », et de loin sur une
      // tele, chaque caractere inutile est un caractere de trop.
      expect(formatDuree(const Duration(minutes: 4, seconds: 7)), '4:07');
    });

    test('au-dela d\'une heure, on l\'ecrit', () {
      expect(
        formatDuree(const Duration(hours: 1, minutes: 2, seconds: 7)),
        '1:02:07',
      );
    });

    test('les secondes gardent toujours deux chiffres', () {
      expect(formatDuree(const Duration(minutes: 3, seconds: 5)), '3:05');
    });

    test('zero s\'ecrit 0:00, pas une chaine vide', () {
      expect(formatDuree(Duration.zero), '0:00');
    });

    test('une duree negative devient 0:00 et pas « -1:59 »', () {
      // Au tout debut d'un flux, la position peut revenir negative.
      expect(formatDuree(const Duration(seconds: -1)), '0:00');
    });
  });
}
