// =========================================================
//  black_box_ua_count_test.dart — la Boîte noire ne doit pas mentir
// =========================================================
//  17/09/2026. Le propriétaire envoie la Boîte noire d'une box en
//  clientèle. On y lit, sur CHAQUE échec de lecture :
//
//    player.playback_failure {channel: France 2, uaTried: 0,
//      verdict: Le flux s'est coupé malgré les reconnexions
//               automatiques (serveur du fournisseur instable)}
//
//  `uaTried: 0` veut dire « aucune signature essayée ». On en a conclu
//  que la cascade de repli ne se déclenchait pas — et le verdict
//  affiché accusait le fournisseur.
//
//  LES DEUX ÉTAIENT FAUX. La cascade tournait très bien. Simplement,
//  les trois appels à `_recordPlaybackFailure` laissaient le paramètre
//  `uaTried` à sa valeur par défaut. Le journal écrivait donc zéro,
//  toujours, quoi qu'il arrive.
//
//  UN JOURNAL QUI AFFICHE TOUJOURS ZÉRO EST PIRE QU'UN JOURNAL MUET :
//  il donne une réponse fausse à une question qu'on ne repose plus. Ça
//  a failli nous faire corriger le mauvais bout — et accuser le
//  fournisseur du client par écrit.
//
//  Ce test lit le fichier source : il refuse qu'on revienne à un appel
//  qui n'alimente pas le compteur.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File ecran =
      File('lib/features/tv/presentation/tv_player_screen.dart');
  final File cascade =
      File('lib/features/player/data/stream_blocked_fallback.dart');

  test('les fichiers sont là où on les croit', () {
    // Un test qui lit un fichier absent passerait tout vert sans rien
    // vérifier. On échoue franchement plutôt que de rassurer à tort.
    expect(ecran.existsSync(), isTrue, reason: ecran.path);
    expect(cascade.existsSync(), isTrue, reason: cascade.path);
  });

  test('la cascade COMPTE les signatures qu\'elle essaie', () {
    final String c = cascade.readAsStringSync();
    expect(c.contains('int signaturesTestees'), isTrue,
        reason: 'sans ce compteur, personne ne peut renseigner uaTried');
    expect(c.contains('signaturesTestees = uaCandidates.length'), isTrue,
        reason: 'il doit être posé AU MOMENT où la liste est décidée : '
            'à l\'échec, cette liste n\'existe plus');
  });

  test('AUCUN échec n\'est gravé sans son compteur', () {
    final String code = ecran
        .readAsStringSync()
        .split('\n')
        .where((String l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    // L'appel nu — celui qui laisse le zéro par défaut — ne doit plus
    // exister. On cherche la forme exacte `_recordPlaybackFailure()`.
    expect(
      code.contains('_recordPlaybackFailure()'),
      isFalse,
      reason: 'un appel sans `uaTried` grave un zéro qui ne veut rien dire '
          'et fait accuser le fournisseur à tort',
    );

    // Et les appels réels doivent lire le compteur de la cascade.
    final int avecCompteur =
        '_recordPlaybackFailure(uaTried:'.allMatches(code).length;
    expect(avecCompteur, greaterThanOrEqualTo(3),
        reason: 'les trois chemins d\'échec doivent renseigner le compteur');
  });

  test('zéro reste possible — et devient une INFORMATION', () {
    // On ne veut pas interdire le zéro : sur un excès de rebuffer, la
    // cascade n'a réellement pas tourné, et `0` est alors la vérité.
    // Ce qu'on interdit, c'est un zéro POSÉ D'OFFICE.
    final String c = cascade.readAsStringSync();
    expect(c.contains('int signaturesTestees = 0;'), isTrue,
        reason: 'valeur initiale 0 = « la cascade n\'a pas encore tourné »');
  });
}
