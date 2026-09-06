// =========================================================
//  exit_guards_wave2_test.dart — Vague 2 : les gardes de sortie d'écran
// =========================================================
//  Audit externe (05/09/2026), points 2.1 / 2.3 / 2.6 : des relances de
//  flux pendant que l'écran n'est plus regardé. Trois gardes ont été
//  posées dans les deux lecteurs (TV et téléphone) :
//
//   2.1 TV — en arrière-plan (Home), la cascade de secours ne doit plus
//       relancer la chaîne : `isAlive` tient compte de `_suspended`, et
//       le chien de garde de démarrage est annulé.
//   2.3 TV + mobile — la fermeture d'un écran note le rang de session
//       relais AVANT ses `await`, et ne ferme rien de plus récent.
//   2.6 mobile — le verrou des téléchargements ne se lève qu'à la FIN
//       de la fermeture réseau, et un recyclage de lecteur après
//       `dispose` ne crée pas d'instance orpheline.
//
//  CES TESTS LISENT LE CODE SOURCE (même patron que
//  no_idle_interruption_test.dart). Les deux écrans s'appuient sur un
//  lecteur natif (Media3 / mpv) qu'aucun test unitaire ne peut monter ;
//  ce qu'on veut empêcher, c'est le RETRAIT d'une garde — et ça, ça se
//  voit dans le source. Les tests de comportement du relais et du
//  créneau, eux, sont dans local_stream_relay_wave2_test.dart et
//  stream_slot_test.dart.
// =========================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source sans les lignes de commentaire (elles citent les noms qu'on
/// cherche pour expliquer, et fausseraient la recherche).
String _code(File f) => f
    .readAsStringSync()
    .split('\n')
    .where((String l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final File tv = File('lib/features/tv/presentation/tv_player_screen.dart');
  final File mobile =
      File('lib/features/player/presentation/video_player_screen.dart');

  test('les deux lecteurs sont bien là', () {
    expect(tv.existsSync(), isTrue, reason: 'chemin du lecteur TV changé');
    expect(mobile.existsSync(), isTrue,
        reason: 'chemin du lecteur mobile changé');
  });

  group('2.1 — TV en arrière-plan : aucune relance de la chaîne', () {
    late String code;
    setUp(() => code = _code(tv));

    test('`isAlive` tient compte de la suspension', () {
      expect(code, contains('isAlive: () => mounted && !_suspended'),
          reason: '`mounted` seul reste vrai derrière le lanceur : la '
              'cascade relançait la chaîne pendant que le client regardait '
              'autre chose (« connexion déjà utilisée »).');
    });

    test('le passage en arrière-plan suspend ET annule le chien de garde',
        () {
      final int paused = code.indexOf('case AppLifecycleState.paused:');
      final int resumed = code.indexOf('case AppLifecycleState.resumed:');
      expect(paused, greaterThan(-1));
      expect(resumed, greaterThan(paused));
      final String bloc = code.substring(paused, resumed);
      expect(bloc, contains('_suspended = true;'));
      expect(bloc, contains('_startupWatchdog?.cancel();'),
          reason: 'un chien de garde armé juste avant Home tirait 20 s '
              'plus tard et rouvrait le flux en arrière-plan');
    });

    test('le retour au premier plan lève la suspension', () {
      final int resumed = code.indexOf('case AppLifecycleState.resumed:');
      final String bloc = code.substring(resumed, resumed + 400);
      expect(bloc, contains('_suspended = false;'));
    });
  });

  group('2.3 — la fermeture d\'un écran est bornée à son rang relais', () {
    /// Dans `dispose()`, entre son début et la fermeture bornée : le rang
    /// doit être lu là, et AUCUNE fermeture non bornée ne doit s'y
    /// trouver. (Les autres `closeOtherPlaybacks('')` du fichier — zap,
    /// bascule de variante — sont volontaires et restent légitimes.)
    void verifie(File f) {
      final String code = _code(f);
      final int dispose = code.indexOf('void dispose() {');
      final int close =
          code.indexOf("closeOtherPlaybacks('', upToGeneration: relayGen)");
      expect(dispose, greaterThan(-1));
      expect(close, greaterThan(dispose),
          reason: 'la fermeture de dispose() doit être bornée au rang');
      final String bloc = code.substring(dispose, close);
      expect(
        bloc,
        contains('final int relayGen = LocalStreamRelay.instance.sessionGeneration;'),
        reason: 'le rang doit être lu DANS dispose(), avant les await',
      );
      expect(bloc, isNot(contains("closeOtherPlaybacks('')")),
          reason: 'une fermeture non bornée dans dispose() fermerait la '
              'session de l\'écran suivant');
    }

    test('TV : le rang est lu AVANT les await, puis passé à la fermeture',
        () => verifie(tv));

    test('mobile : même garde', () => verifie(mobile));
  });

  group('2.6 — mobile : sortie propre', () {
    late String code;
    setUp(() => code = _code(mobile));

    test('le verrou des téléchargements se lève à la FIN de la fermeture',
        () {
      // Dans `dispose`, la seule levée autorisée est celle qui attend le
      // shutdown. On localise `dispose()` et on vérifie qu'entre son
      // début et le `handOff`, aucune levée immédiate ne subsiste.
      final int dispose = code.indexOf('void dispose() {');
      final int handOff =
          code.indexOf("handOff(this, shutdown, label: 'fermeture lecteur quitté')");
      expect(dispose, greaterThan(-1));
      expect(handOff, greaterThan(dispose));
      final String avant = code.substring(dispose, handOff);
      expect(avant, isNot(contains('setPlaybackHold(false)')),
          reason: 'levé AVANT le stop mpv, le verrou laissait la file '
              'Cinéma reprendre la ligne pendant le démontage → « déjà '
              'ouverte ailleurs » au film suivant');
      expect(
        code,
        contains('shutdown.whenComplete(\n'
            '        () => VodDownloadService.instance.setPlaybackHold(false))'),
        reason: 'la levée doit attendre la fin réelle de la fermeture',
      );
    });

    test('un recyclage de lecteur après la sortie ne crée pas d\'orphelin',
        () {
      final int recycle = code.indexOf('_recyclePlayer(');
      expect(recycle, greaterThan(-1));
      final int create = code.indexOf('_createPlayer();', recycle);
      expect(create, greaterThan(recycle));
      final String bloc = code.substring(recycle, create);
      expect(bloc, contains('if (!mounted) return;'),
          reason: 'deux await (jusqu\'à 10 s) précèdent la création : '
              'écran quitté entre-temps = instance mpv que personne ne '
              'ferme, et une connexion fournisseur que rien ne rend');
    });
  });
}
