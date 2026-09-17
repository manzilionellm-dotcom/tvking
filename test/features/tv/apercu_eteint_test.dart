// =========================================================
//  apercu_eteint_test.dart — un seul décodeur à la fois
// =========================================================
//  LE PROPRIÉTAIRE, DEVANT SA BOX, LE 17/09/2026 PASSÉ MINUIT :
//
//    « Je pense que la cause, c'est ces petits écrans. Il faut les
//      enlever. […] Je pense que c'est ça qui ramène le problème de
//      retourner en arrière. »
//
//  IL AVAIT RAISON, et ce n'était pas une intuition d'écran : la tuile
//  d'aperçu n'affiche pas une image, elle ouvre un VRAI lecteur
//  ExoPlayer/Media3 — le MÊME moteur que le plein écran. Une chaîne qui
//  joue + une liste qui montre l'aperçu = DEUX flux vidéo décodés en
//  même temps.
//
//  Sur une box de 1 Go, le deuxième décodeur est ce qui reste à
//  sacrifier. La boîte noire d'une box en clientèle, ce soir-là :
//
//    21:17:35 WARN memoire.pressure.purge {count: 2}
//    21:20:43 WARN memoire.pressure.purge {count: 3}
//    21:23:17 WARN memoire.pressure.purge {count: 4}
//    21:23:30 INFO lifecycle.boot        ← Android a tué l'app
//
//  Le garde-mémoire existant allégeait bien l'app, mais son profil
//  « petite box » ne s'active qu'en dessous de 800 Mo. Il protégeait les
//  Fire TV Stick et laissait passer exactement les box du client.
//
//  ---------------------------------------------------------
//  CE QUE CE TEST PROTÈGE
//  ---------------------------------------------------------
//  Une seule chose, mais elle décide de tout : **aucun lecteur ne doit
//  s'ouvrir**. On le vérifie par le résolveur d'URL injecté — c'est
//  l'étape qui précède immédiatement l'ouverture du flux. S'il n'est
//  jamais appelé, aucune connexion n'est ouverte et aucun décodeur n'est
//  alloué.
//
//  On vérifie AUSSI que la tuile reste dessinée. Éteindre l'aperçu ne
//  doit pas laisser un trou noir dans l'accueil : le logo de la chaîne
//  prend la place, exactement comme pendant le chargement.
// =========================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/core/tv_preview_feature.dart';
import 'package:tv_king/features/tv/presentation/tv_live_preview.dart';

Channel _channel(String id, String name) => Channel(
      id: id,
      name: name,
      category: 'Généralistes',
      streamUrl: 'http://panel.example/live/u/p/$id.ts',
      isLive: true,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 400, height: 225, child: child),
        ),
      ),
    );

void main() {
  // Ce fichier teste l'app TELLE QU'ELLE PART. On ne rallume donc PAS
  // l'interrupteur — on le remet seulement dans sa position de
  // compilation, au cas où un autre fichier du même processus l'aurait
  // laissé allumé (tv_live_preview_test.dart le fait, volontairement).
  setUp(reinitialiserApercuPourTest);

  test('l\'interrupteur est ÉTEINT par défaut', () {
    expect(kApercuDirectActif, isFalse,
        reason: 'c\'est CE booléen que lit _start() ; s\'il est allumé, '
            'le reste de ce fichier ne prouve rien');
    expect(kApercuDirectCompile, isFalse,
        reason: 'un build sans --dart-define doit partir aperçu éteint');
  });

  testWidgets('AUCUN lecteur ne s\'ouvre — c\'est tout l\'enjeu',
      (WidgetTester tester) async {
    // Le résolveur est la dernière étape avant l'ouverture du flux. S'il
    // n'est jamais appelé, il n'y a ni connexion, ni décodeur, ni
    // mémoire consommée. C'est la mesure la plus proche du symptôme
    // qu'on puisse faire sans une vraie box.
    int appels = 0;
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c1', 'France 3'),
      // `startImmediately` court-circuite l'anti-rebond : c'est le chemin
      // le PLUS agressif vers l'ouverture d'un lecteur. S'il ne passe pas
      // non plus, aucun autre ne passera.
      startImmediately: true,
      resolver: (Channel c) async {
        appels++;
        return const TvPreviewSource(url: 'http://exemple/flux.ts');
      },
    )));

    // On laisse passer largement plus que l'anti-rebond (~600 ms).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));

    expect(appels, 0,
        reason: 'un seul appel ici = un deuxième décodeur sur la box = '
            'la purge mémoire puis le redémarrage');
  });

  testWidgets('la tuile reste dessinée : le logo prend la place',
      (WidgetTester tester) async {
    // Éteindre l'aperçu ne doit pas laisser un trou noir dans l'accueil.
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c2', 'France 2'),
      startImmediately: true,
      resolver: (Channel c) async =>
          const TvPreviewSource(url: 'http://exemple/flux.ts'),
    )));
    await tester.pump(const Duration(seconds: 3));

    // Le widget est monté et n'a pas explosé : pas d'exception en attente.
    expect(tester.takeException(), isNull);
    expect(find.byType(TvLivePreview), findsOneWidget);
  });

  testWidgets('rallumé, l\'aperçu REMARCHE — éteindre n\'est pas casser',
      (WidgetTester tester) async {
    // Un interrupteur à sens unique serait un piège : le jour où le
    // parc n'aura plus que des box qui encaissent deux décodeurs, il
    // faut pouvoir revenir.
    apercuDirectPourTest = true;
    addTearDown(reinitialiserApercuPourTest);

    int appels = 0;
    await tester.pumpWidget(_host(TvLivePreview(
      channel: _channel('c3', 'TF1'),
      startImmediately: true,
      resolver: (Channel c) async {
        appels++;
        return const TvPreviewSource(url: 'http://exemple/flux.ts');
      },
    )));
    await tester.pump(const Duration(seconds: 3));

    expect(appels, greaterThan(0),
        reason: 'rallumé, le chemin d\'ouverture doit être intact');
  });

  test('le garde est posé À LA SOURCE, pas sur les quatre écrans', () {
    // Quatre écrans posent un aperçu. Quatre gardes, ce serait trois
    // occasions d'en oublier un — et celui qu'on oublie est celui qui
    // tue la box, un soir, chez un client. Même leçon que
    // `android_overlay/**` absent des `paths` des workflows.
    final File source =
        File('lib/features/tv/presentation/tv_live_preview.dart');
    expect(source.existsSync(), isTrue, reason: source.path);

    final String code = source.readAsStringSync();
    expect(code.contains('if (!kApercuDirectActif) return;'), isTrue,
        reason: 'le garde doit être dans _start(), la seule méthode qui '
            'ouvre un lecteur');

    // Et les écrans, eux, ne doivent PAS porter de copie de la décision.
    for (final String chemin in <String>[
      'lib/features/tv/presentation/tv_launcher_home_screen.dart',
      'lib/features/tv/presentation/tv_rails_home_screen.dart',
      'lib/features/tv/presentation/tv_tivimate_home_screen.dart',
      'lib/features/tv/presentation/tv_channels_screen.dart',
    ]) {
      final File f = File(chemin);
      expect(f.existsSync(), isTrue, reason: chemin);
      expect(f.readAsStringSync().contains('kApercuDirectActif'), isFalse,
          reason: '$chemin recopie la décision : le jour où une copie dit '
              'oui pendant que la source dit non, on rouvre un décodeur '
              'sans que personne le voie');
    }
  });
}
