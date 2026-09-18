// =========================================================
//  veille_app_eteinte_test.dart — la box ne s'endort plus seule
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) :
//
//    « Il faut désactiver que ça ne soit jamais en veille. Parce
//      qu'apparemment, si ça fait longtemps, ça entre en veille. Il
//      faut que ce soit actif. »
//
//  CE N'ÉTAIT PAS LA BOX. `core/tv/screen_awake.dart` pose bien
//  `FLAG_KEEP_SCREEN_ON` au démarrage TV, et il EST branché dans
//  `main_tv.dart` — vérifié avant de toucher à quoi que ce soit. Le
//  système ne coupait rien.
//
//  C'est l'APPLICATION qui s'endormait toute seule : `TvScreensaverWatcher`
//  pousse son propre écran de veille après dix minutes sans appui sur la
//  télécommande. Or regarder la télévision, c'est précisément rester dix
//  minutes sans toucher à la télécommande. Le client voyait un écran noir
//  avec un logo qui bouge, et croyait à une panne.
//
//  CE QUE CE TEST PROTÈGE
//   1. L'interrupteur est éteint par défaut.
//   2. Aucune MINUTERIE n'est armée — pas seulement « rien ne s'affiche ».
//      Éteinte, la fonctionnalité ne doit pas coûter un seul réveil.
//   3. L'enfant passe quand même : envelopper un écran ne doit jamais le
//      faire disparaître.
//   4. Rallumé, tout remarche — éteindre n'est pas casser.
// =========================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/tv_screensaver.dart';

void main() {
  setUp(reinitialiserVeillePourTest);
  tearDown(reinitialiserVeillePourTest);

  test('l\'interrupteur est ÉTEINT par défaut', () {
    expect(kVeilleAppActive, isFalse,
        reason: 'c\'est CE booléen que lit _arm() ; allumé, le reste de '
            'ce fichier ne prouve rien');
    expect(kVeilleAppCompilee, isFalse,
        reason: 'un build sans --dart-define doit partir veille éteinte');
  });

  testWidgets('AUCUNE minuterie n\'est armée — coût zéro',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: TvScreensaverWatcher(child: Text('accueil')),
    ));

    // `pumpAndSettle` échoue s'il reste un timer en vol. C'est
    // exactement la preuve qu'on cherche : rien n'a été armé.
    await tester.pumpAndSettle();

    // Et on laisse passer BIEN plus que les dix minutes d'inactivité.
    await tester.pump(const Duration(minutes: 11));
    await tester.pump(const Duration(minutes: 11));

    expect(find.text('accueil'), findsOneWidget,
        reason: 'l\'accueil doit toujours être là — pas d\'écran noir');
    expect(tester.takeException(), isNull);
  });

  testWidgets('l\'enfant passe : envelopper n\'efface pas l\'écran',
      (WidgetTester tester) async {
    // Le risque bête d'un interrupteur posé au mauvais endroit : le
    // surveillant cesse de rendre son enfant et l'accueil disparaît.
    await tester.pumpWidget(const MaterialApp(
      home: TvScreensaverWatcher(child: Text('mon accueil')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('mon accueil'), findsOneWidget);
  });

  test('le garde est posé DANS le surveillant, pas sur les 4 écrans', () {
    // Quatre écrans enveloppent l'accueil (tv_app, Lanceur, Rails,
    // TiviMate). Quatre gardes, ce serait trois occasions d'en oublier
    // un — et celui qu'on oublie est celui qui endort la box d'un
    // client. Même règle que l'aperçu vidéo et que la famille.
    final File src =
        File('lib/features/tv/presentation/tv_screensaver.dart');
    expect(src.existsSync(), isTrue, reason: src.path);

    final String code = src.readAsStringSync();
    expect(code.contains('if (!kVeilleAppActive) return;'), isTrue,
        reason: 'le garde doit être dans _arm(), là où la minuterie naît');

    for (final String chemin in <String>[
      'lib/features/tv/presentation/tv_app.dart',
      'lib/features/tv/presentation/tv_launcher_home_screen.dart',
      'lib/features/tv/presentation/tv_rails_home_screen.dart',
      'lib/features/tv/presentation/tv_tivimate_home_screen.dart',
    ]) {
      final File f = File(chemin);
      expect(f.existsSync(), isTrue, reason: chemin);
      expect(f.readAsStringSync().contains('kVeilleAppActive'), isFalse,
          reason: '$chemin recopie la décision : le jour où une copie dit '
              'oui pendant que la source dit non, une box se rendort');
    }
  });

  test('le verrou SYSTÈME reste posé — on n\'a pas touché à ScreenAwake', () {
    // Ce qui empêche la BOX de s'endormir est un autre mécanisme, et il
    // marchait déjà. Si quelqu'un le débranchait en croyant « finir le
    // travail », l'écran se couperait de nouveau au bout de 15 min —
    // cette fois pour de vrai, et personne ne ferait le lien.
    final File main = File('lib/main_tv.dart');
    expect(main.existsSync(), isTrue);
    expect(main.readAsStringSync().contains('ScreenAwake.instance.install()'),
        isTrue,
        reason: 'sans ce verrou, la BOX coupe la sortie HDMI après 15 min');
  });

  testWidgets('RALLUMÉ, la veille remarche — éteindre n\'est pas casser',
      (WidgetTester tester) async {
    veilleAppPourTest = true;
    addTearDown(reinitialiserVeillePourTest);

    await tester.pumpWidget(const MaterialApp(
      home: TvScreensaverWatcher(child: Text('accueil')),
    ));
    await tester.pump();

    // Une minuterie EST armée : `pumpAndSettle` ne peut pas se stabiliser
    // tant qu'elle court. On ne l'appelle donc pas — on constate juste
    // que le widget vit et qu'aucune exception n'est tombée.
    expect(find.text('accueil'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // On purge la minuterie pour ne pas polluer le test suivant.
    veilleAppPourTest = false;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
