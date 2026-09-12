// =========================================================
//  now_playing_test.dart — ne pas annoncer ce qui n'a pas commencé
// =========================================================
//  Le propriétaire (12/09/2026), photo de sa recherche : les chaînes
//  remontent bien, « mais les informations ne viennent pas ». On a donc
//  branché la recherche sur l'EPG courte du panel, qui répond « l'en-cours
//  et les suivants ».
//
//  LE PIÈGE, ET C'EST TOUT L'OBJET DE CE FICHIER : « l'en-cours et les
//  suivants » est une promesse du protocole, pas une garantie. Selon le
//  panel, la liste peut commencer au programme SUIVANT (l'en-cours ayant
//  déjà été filtré), arriver dans le désordre, ou contenir des créneaux
//  qui se chevauchent. Prendre le premier élément de la liste annoncerait
//  alors, sous le nom de la chaîne, une émission qui ne passe pas encore.
//
//  Un petit mensonge sous une vignette suffit à faire douter du reste de
//  l'écran. On exige donc que le créneau CONTIENNE l'instant.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/data/now_playing.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';

EpgProgram _p(String titre, DateTime debut, DateTime fin) => EpgProgram(
      channelId: 'xtream-1',
      startTime: debut.millisecondsSinceEpoch,
      stopTime: fin.millisecondsSinceEpoch,
      title: titre,
    );

void main() {
  // Heure FIXE : un test qui dépend de l'horloge réelle passe le matin et
  // échoue la nuit, puis finit désactivé.
  final DateTime maintenant = DateTime(2026, 9, 12, 20, 30);

  group('enCours — le créneau doit CONTENIR l\'instant', () {
    test('le programme à l\'antenne est retenu', () {
      final EpgProgram journal = _p('Journal', DateTime(2026, 9, 12, 20, 0),
          DateTime(2026, 9, 12, 21, 0));
      expect(
        NowPlaying.enCours(<EpgProgram>[journal], maintenant)?.title,
        'Journal',
      );
    });

    test('LE PIÈGE : une liste qui commence par le programme SUIVANT', () {
      // Le panel a filtré l'en-cours. Prendre le premier élément
      // annoncerait « Film » alors que le journal est encore à l'antenne.
      final EpgProgram film = _p('Film', DateTime(2026, 9, 12, 21, 0),
          DateTime(2026, 9, 12, 23, 0));
      expect(NowPlaying.enCours(<EpgProgram>[film], maintenant), isNull);
    });

    test('dans le désordre, c\'est bien l\'en-cours qui sort', () {
      final EpgProgram film = _p('Film', DateTime(2026, 9, 12, 21, 0),
          DateTime(2026, 9, 12, 23, 0));
      final EpgProgram journal = _p('Journal', DateTime(2026, 9, 12, 20, 0),
          DateTime(2026, 9, 12, 21, 0));
      final EpgProgram avant = _p('Météo', DateTime(2026, 9, 12, 19, 50),
          DateTime(2026, 9, 12, 20, 0));
      expect(
        NowPlaying.enCours(<EpgProgram>[film, avant, journal], maintenant)
            ?.title,
        'Journal',
      );
    });

    test('un programme TERMINÉ n\'est pas l\'en-cours', () {
      final EpgProgram fini = _p('Météo', DateTime(2026, 9, 12, 19, 50),
          DateTime(2026, 9, 12, 20, 0));
      expect(NowPlaying.enCours(<EpgProgram>[fini], maintenant), isNull);
    });
  });

  group('les bords de créneau', () {
    test('à la SECONDE du début, le programme est déjà à l\'antenne', () {
      final EpgProgram p = _p('Journal', maintenant,
          maintenant.add(const Duration(hours: 1)));
      expect(NowPlaying.enCours(<EpgProgram>[p], maintenant)?.title, 'Journal');
    });

    test('à la SECONDE de la fin, il ne l\'est plus', () {
      // Sinon deux programmes se disputeraient l'antenne à l'instant
      // pivot : celui qui finit et celui qui commence.
      final EpgProgram p = _p('Journal',
          maintenant.subtract(const Duration(hours: 1)), maintenant);
      expect(NowPlaying.enCours(<EpgProgram>[p], maintenant), isNull);
    });

    test('deux créneaux qui se touchent : le NOUVEAU gagne', () {
      final EpgProgram quiFinit = _p('Journal',
          maintenant.subtract(const Duration(hours: 1)), maintenant);
      final EpgProgram quiCommence = _p('Film', maintenant,
          maintenant.add(const Duration(hours: 2)));
      expect(
        NowPlaying.enCours(
            <EpgProgram>[quiFinit, quiCommence], maintenant)?.title,
        'Film',
      );
    });
  });

  test('liste vide → null, aucune exception', () {
    expect(NowPlaying.enCours(const <EpgProgram>[], maintenant), isNull);
  });

  group('suivant — le programme APRÈS l\'en-cours', () {
    test('prend le plus proche après la fin de l\'en-cours', () {
      final EpgProgram journal = _p('Journal', DateTime(2026, 9, 12, 20, 0),
          DateTime(2026, 9, 12, 21, 0));
      final EpgProgram film = _p('Film', DateTime(2026, 9, 12, 21, 0),
          DateTime(2026, 9, 12, 23, 0));
      final EpgProgram nuit = _p('Nuit', DateTime(2026, 9, 12, 23, 0),
          DateTime(2026, 9, 13, 1, 0));
      expect(
        NowPlaying.suivant(
          <EpgProgram>[nuit, film, journal],
          maintenant,
          enCours: journal,
        )?.title,
        'Film',
      );
    });

    test('sans en-cours, le premier qui n\'a pas encore commencé', () {
      final EpgProgram film = _p('Film', DateTime(2026, 9, 12, 21, 0),
          DateTime(2026, 9, 12, 23, 0));
      expect(
        NowPlaying.suivant(<EpgProgram>[film], maintenant)?.title,
        'Film',
      );
    });
  });
}
