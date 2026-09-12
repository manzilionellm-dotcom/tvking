// =========================================================
//  external_keyboard_test.dart — la frontière texte / navigation
// =========================================================
//  Le propriétaire (12/09/2026) : « j'ai une télécommande sur mon
//  téléphone, mais je ne parviens pas à écrire avec le clavier ». On a
//  donc ouvert l'écran de recherche aux claviers extérieurs.
//
//  CE QUI SE JOUE DANS CES TESTS. Ouvrir l'écran aux touches physiques,
//  c'est mettre un filtre entre la télécommande et la requête. Les deux
//  erreurs possibles ne coûtent PAS la même chose :
//
//    • prendre une lettre pour de la navigation → la lettre ne s'écrit
//      pas. Ennuyeux, visible, le client réessaie ;
//    • prendre une FLÈCHE pour une lettre → la flèche est avalée, la
//      grille ne bouge plus, et la télécommande a l'air cassée. Panne
//      muette, depuis le canapé, sans explication.
//
//  La seconde est la vraie. C'est pour elle que ce fichier existe.
// =========================================================
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/external_keyboard.dart';

void main() {
  group('les touches de NAVIGATION ne deviennent jamais du texte', () {
    test('les quatre flèches, OK et Retour sont refusés', () {
      // Le cas qui casserait tout : sur certaines plateformes, une touche
      // de direction arrive AVEC un caractère non vide. Si on regardait
      // seulement `character`, on écrirait un symbole invisible ET on
      // volerait la flèche à la navigation.
      for (final LogicalKeyboardKey k in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.goBack,
      ]) {
        expect(caractereTapable(k, 'X'), isNull,
            reason: k.debugName ?? k.toString());
      }
    });

    test('les touches média d\'une télécommande traversent sans être bues',
        () {
      // Le client doit pouvoir baisser le son pendant qu'il tape.
      for (final LogicalKeyboardKey k in <LogicalKeyboardKey>[
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.audioVolumeDown,
        LogicalKeyboardKey.audioVolumeMute,
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.channelUp,
        LogicalKeyboardKey.power,
      ]) {
        expect(caractereTapable(k, 'X'), isNull,
            reason: k.debugName ?? k.toString());
      }
    });
  });

  group('les vraies lettres s\'écrivent', () {
    test('une lettre passe telle que la plateforme l\'a produite', () {
      expect(caractereTapable(LogicalKeyboardKey.keyC, 'c'), 'c');
      expect(caractereTapable(LogicalKeyboardKey.keyC, 'C'), 'C');
    });

    test('L\'ESPACE est du texte — « canal plus » s\'écrit en deux mots', () {
      expect(caractereTapable(LogicalKeyboardKey.space, ' '), ' ');
    });

    test('chiffres et ponctuation passent', () {
      expect(caractereTapable(LogicalKeyboardKey.digit1, '1'), '1');
      expect(caractereTapable(LogicalKeyboardKey.minus, '-'), '-');
      expect(caractereTapable(LogicalKeyboardKey.period, '.'), '.');
    });

    test('accents et alphabets non latins passent intacts', () {
      // On ne reconstruit JAMAIS la lettre depuis le code de touche : un
      // AZERTY, un clavier arabe ou une touche morte donneraient alors
      // n'importe quoi. C'est `character` qui fait foi.
      expect(caractereTapable(LogicalKeyboardKey.keyE, 'é'), 'é');
      expect(caractereTapable(LogicalKeyboardKey.keyA, 'ا'), 'ا');
      expect(caractereTapable(LogicalKeyboardKey.keyO, 'ø'), 'ø');
    });
  });

  group('ce qui n\'est ni lettre ni navigation', () {
    test('un caractère absent ou vide ne s\'écrit pas', () {
      expect(caractereTapable(LogicalKeyboardKey.keyA, null), isNull);
      expect(caractereTapable(LogicalKeyboardKey.keyA, ''), isNull);
    });

    test('un caractère de CONTRÔLE ne s\'écrit pas', () {
      // Retour arrière, tabulation et entrée arrivent parfois avec un
      // « caractère » qui est en réalité un code de contrôle. L'écrire
      // remplirait la requête de signes invisibles — introuvables et
      // impossibles à comprendre pour le client.
      expect(caractereTapable(LogicalKeyboardKey.backspace, ''), isNull);
      expect(caractereTapable(LogicalKeyboardKey.tab, '\t'), isNull);
      expect(caractereTapable(LogicalKeyboardKey.keyA, '\n'), isNull);
      expect(caractereTapable(LogicalKeyboardKey.keyA, ''), isNull);
    });
  });

  group('effacer', () {
    test('retour arrière et suppression effacent', () {
      expect(estRetourArriere(LogicalKeyboardKey.backspace), isTrue);
      expect(estRetourArriere(LogicalKeyboardKey.delete), isTrue);
    });

    test('une lettre ou une flèche n\'efface pas', () {
      expect(estRetourArriere(LogicalKeyboardKey.keyA), isFalse);
      expect(estRetourArriere(LogicalKeyboardKey.arrowLeft), isFalse);
    });
  });
}
