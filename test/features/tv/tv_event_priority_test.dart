// =========================================================
//  tv_event_priority_test.dart — le match doit passer devant
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) :
//
//    « Il faut ajouter les notifications des grands événements, les
//      matchs, comme France 24 te signale le nouveau journal. »
//
//  Ces tests protègent DEUX choses, et la seconde compte autant que la
//  première :
//
//   1. QU'ON PRÉVIENNE. Un match reconnu, annoncé 30 minutes avant.
//
//   2. QU'ON NE CRIE PAS POUR RIEN. C'est le risque réel d'une
//      détection par mots-clés : un mot trop vague, et le client reçoit
//      « le match commence » devant un documentaire animalier. Deux
//      fausses alertes et il ignore la bannière pour toujours — la
//      fonctionnalité est alors pire qu'absente, parce qu'elle a brûlé
//      l'attention qu'on lui demandait.
//
//  D'où une liste de cas NÉGATIFS aussi longue que celle des positifs.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_event_priority.dart';

void main() {
  group('on reconnaît un MATCH', () {
    // Écrits comme les vrais guides IPTV les écrivent — trois
    // fournisseurs, trois graphies pour la même rencontre.
    for (final String titre in <String>[
      'FOOT : PSG - OM',
      'Ligue 1 · PSG/OM',
      'LIVE PSG vs OM',
      'Finale Coupe du Monde',
      'Demi-finale Roland-Garros',
      'UEFA Champions League',
      'CAN 2026 : Sénégal - Maroc',
      'NBA : Lakers @ Celtics',
      'Grand Prix de Monaco',
      'Tour de France — 14e étape',
      'Derby de Milan',
    ]) {
      test('« $titre »', () {
        expect(classerEvenement(titre), TypeEvenement.match, reason: titre);
      });
    }
  });

  group('on reconnaît un JOURNAL', () {
    for (final String titre in <String>[
      'Journal de 20h',
      'Le 20h',
      'JT de la mi-journée',
      'Édition spéciale',
      'Flash info',
      'Les titres de l\'actualité',
    ]) {
      test('« $titre »', () {
        expect(classerEvenement(titre), TypeEvenement.journal, reason: titre);
      });
    }
  });

  group('ON NE CRIE PAS POUR RIEN — le risque réel', () {
    // Chacun de ces titres contient un mot PROCHE d'un mot-clé. S'il
    // déclenchait, le client verrait « le match commence » devant un
    // documentaire — et n'écouterait plus jamais la bannière.
    for (final String titre in <String>[
      'Documentaire animalier',
      'Le journal d\'Anne Frank', // « journal » — mais dans un titre d'œuvre…
      'Téléfilm : Les canaux de Venise', // « can » est dans « canaux »
      'Footloose', // « foot » sans espace — ne doit PAS passer
      'Footing du matin', // idem
      'Cuisine : la liaison des sauces', // témoin ordinaire
      'Météo',
      'Les infos pratiques du jardinage',
      'News de la mode',
      'Sport en salle : yoga',
      'Concert live au Zénith',
      '',
      '   ',
    ]) {
      test('« $titre » n\'est PAS un match', () {
        expect(classerEvenement(titre), isNot(TypeEvenement.match),
            reason: titre);
      });
    }

    test('« can » ne se déclenche pas sur « canal », « canapé », « canard »',
        () {
      // Le piège exact que l'espace après « can » évite. Sans lui,
      // « Canal Football Club » ET « Canal+ Cinéma » seraient des matchs.
      for (final String t in <String>[
        'Canal+ Cinéma',
        'Le canapé rouge',
        'Le canard enchaîné',
        'Vacances au Canada',
      ]) {
        expect(classerEvenement(t), TypeEvenement.ordinaire, reason: t);
      }
    });

    test('un titre vide ne fait pas tomber l\'écran', () {
      // Un guide IPTV mal rempli ne doit jamais casser l'accueil.
      expect(classerEvenement(''), TypeEvenement.ordinaire);
      expect(classerEvenement('   '), TypeEvenement.ordinaire);
    });
  });

  group('accents et casse ne changent rien', () {
    test('« ÉDITION SPÉCIALE » = « edition speciale »', () {
      expect(classerEvenement('ÉDITION SPÉCIALE'), TypeEvenement.journal);
      expect(classerEvenement('edition speciale'), TypeEvenement.journal);
      expect(classerEvenement('Édition Spéciale'), TypeEvenement.journal);
    });

    test('« DEMI-FINALE » = « demi finale »', () {
      expect(classerEvenement('DEMI-FINALE'), TypeEvenement.match);
      expect(classerEvenement('Demi finale'), TypeEvenement.match);
    });
  });

  test('le MATCH l\'emporte sur le journal', () {
    // « Journal des sports : finale » est d'abord une finale. Si le
    // journal gagnait, le client serait prévenu 10 min avant au lieu
    // de 30 — soit exactement ce qu'on cherchait à corriger.
    expect(classerEvenement('Journal des sports · Finale'),
        TypeEvenement.match);
  });

  group('la fenêtre d\'annonce', () {
    test('MATCH = 30 minutes — le chiffre demandé au mot près', () {
      expect(fenetreAnnonce(TypeEvenement.match),
          const Duration(minutes: 30));
    });

    test('journal et ordinaire = 10 minutes, comme AVANT', () {
      // Ce correctif AJOUTE, il n'enlève rien : le comportement
      // historique doit rester identique pour tout le reste.
      expect(fenetreAnnonce(TypeEvenement.journal),
          const Duration(minutes: 10));
      expect(fenetreAnnonce(TypeEvenement.ordinaire),
          const Duration(minutes: 10));
    });
  });

  test('l\'ordre de passage : match > journal > ordinaire', () {
    // Sert quand plusieurs émissions commencent en même temps : une
    // rediffusion sur le favori n°1 ne doit pas passer devant la finale
    // du favori n°4.
    expect(prioriteEvenement(TypeEvenement.match),
        greaterThan(prioriteEvenement(TypeEvenement.journal)));
    expect(prioriteEvenement(TypeEvenement.journal),
        greaterThan(prioriteEvenement(TypeEvenement.ordinaire)));
  });
}
