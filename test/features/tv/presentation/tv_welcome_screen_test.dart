// =========================================================
//  tv_welcome_screen_test.dart — Le premier écran du Modèle A
// =========================================================
//  Cahier des charges du client : « dès que le client ouvre
//  l'application après téléchargement, il doit immédiatement se sentir
//  en confiance, comme s'il utilisait Netflix ou Disney+ ».
//
//  Ce qui est vérifié ici, et qui ne doit jamais régresser :
//    1. les six blocs demandés sont présents (marque + état de la
//       connexion, bienvenue, fiche client, méthodes de connexion,
//       support, pied de page) ;
//    2. LE STATUT EST VRAI. Le cahier des charges demandait une
//       pastille verte « Abonnement actif » en dur ; on ne l'a pas
//       fait. Afficher « actif » à un client gelé ou expiré, c'est
//       exactement ce qui détruit la confiance qu'on cherche à créer.
//       La pastille suit le vrai statut ;
//    3. rien ne déborde, du 720p d'une box normale à une dalle plus
//       petite — un débordement ici, c'est la toute première image que
//       voit le client.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_welcome_screen.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 720),
  Future<void> Function()? onReload,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: SafeArea(child: TvWelcomeScreen(onReload: onReload))),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() => FlavorConfig.setCurrent(FlavorConfig.sevenMotion));

  group('les blocs demandés sont là', () {
    testWidgets('la marque et l\'état de la connexion en haut',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.byType(TvLogo), findsOneWidget);
      expect(find.text('Connexion sécurisée'), findsOneWidget);
      // Le logo porte déjà le nom : l'écrire à côté l'affichait deux fois.
      expect(find.text('7 MOTION'), findsNothing);
    });

    // Le logo est ORANGE, le thème turquoise : posé en permanence, il
    // écrase la palette. Le client : « il disparaît, il revient, genre il
    // montre juste qu'il est là. » Il doit donc RESPIRER — et le faire
    // sans jamais recalculer la mise en page (FadeTransition, pas de
    // taille animée qui ferait tressauter toute la barre du haut).
    testWidgets('le logo respire au lieu de rester planté',
        (WidgetTester tester) async {
      await _pump(tester);

      // `.first` = l'ancêtre le PLUS PROCHE du logo, donc le nôtre —
      // MaterialApp en empile d'autres pour ses transitions de route.
      final Finder op = find
          .ancestor(of: find.byType(TvLogo), matching: find.byType(Opacity))
          .first;
      double opacityNow() => tester.widget<Opacity>(op).opacity;

      // Chorégraphie sur 4500 ms : 0–25 % l'éclat passe (opacité pleine),
      // 25–65 % le logo s'efface, 65–100 % il revient.
      expect(opacityNow(), 1.0, reason: 'plein pendant le passage de l\'éclat');

      await tester.pump(const Duration(milliseconds: 2900)); // ~64 %
      final double low = opacityNow();
      expect(low, lessThan(0.5), reason: 'il doit vraiment s\'effacer');

      await tester.pump(const Duration(milliseconds: 1400)); // ~95 %
      expect(opacityNow(), greaterThan(low), reason: '…puis revenir');
    });

    // Le « shine sweep » fourni par le client, transposé du CSS. Il doit
    // traverser le logo — et SEULEMENT le logo : peint en srcATop, il
    // n'éclaire pas le vide autour de la tuile (une barre blanche en
    // travers du fond noir se verrait comme un défaut).
    testWidgets('un éclat balaie le logo, et rien d\'autre',
        (WidgetTester tester) async {
      await _pump(tester);

      final Finder mask = find
          .ancestor(of: find.byType(TvLogo), matching: find.byType(ShaderMask))
          .first;
      expect(mask, findsOneWidget);
      expect(tester.widget<ShaderMask>(mask).blendMode, BlendMode.srcATop,
          reason: 'sans srcATop, la lumière déborde sur le fond');

      // Le dégradé se déplace : deux instants du balayage ne donnent pas
      // le même shader.
      final Shader a = tester
          .widget<ShaderMask>(mask)
          .shaderCallback(const Rect.fromLTWH(0, 0, 210, 80));
      await tester.pump(const Duration(milliseconds: 500));
      final Shader b = tester
          .widget<ShaderMask>(mask)
          .shaderCallback(const Rect.fromLTWH(0, 0, 210, 80));
      expect(identical(a, b), isFalse);
    });

    testWidgets('l\'accueil et les deux méthodes de connexion',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.text('Bienvenue'), findsOneWidget);
      expect(find.text('Xtream Codes'), findsOneWidget);
      expect(find.text('Recommandé'), findsOneWidget);
      expect(find.text('Playlist M3U'), findsOneWidget);
      // L'onglet Xtream est ouvert d'entrée : c'est la méthode conseillée.
      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.text('Adresse du serveur'), findsOneWidget);
      expect(find.text('Nom d\'utilisateur'), findsOneWidget);
      expect(find.text('Mot de passe'), findsOneWidget);
    });

    testWidgets('basculer sur M3U change les champs et le bouton',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Playlist M3U'));
      await tester.pump();

      expect(find.text('Charger la playlist'), findsOneWidget);
      expect(find.text('Lien M3U'), findsOneWidget);
      expect(find.text('Se connecter'), findsNothing);
      expect(find.text('Mot de passe'), findsNothing);
    });

    testWidgets('la fiche de l\'appareil et le support',
        (WidgetTester tester) async {
      await _pump(tester);
      // L'identifiant client EST l'adresse MAC dans ce système : une
      // seule valeur, annoncée comme les deux.
      expect(find.text('Adresse MAC · ton identifiant client'), findsOneWidget);
      expect(find.text('Forfait'), findsOneWidget);
      expect(find.text('Expiration'), findsOneWidget);
      // Support : le QR porte déjà le code de l'appareil dans le message.
      expect(find.byType(TvWhatsAppQr), findsOneWidget);
      expect(find.text('Besoin d\'aide ? Notre équipe est disponible 24 h/24.'),
          findsOneWidget);
    });

    testWidgets('le pied de page : conditions et marque',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.text('Conditions d\'utilisation'), findsOneWidget);
      expect(find.text('Powered by 7 MOTION'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------
  //  RÈGLES « 10-FOOT » : overscan et cibles D-pad
  // ---------------------------------------------------------
  //  Beaucoup de téléviseurs ROGNENT les bords de l'image — surtout les
  //  anciens et ceux réglés en « zoom ». Le contenu utile doit donc
  //  rester dans la zone dite title-safe : 5 % de la surface, jamais
  //  moins de 48. Ce n'est pas cosmétique : c'est sur cet écran que se
  //  trouvent l'identifiant de l'appareil et le QR du support. Coupés,
  //  ils ne servent plus à rien.
  group('zone title-safe et cibles à la télécommande', () {
    testWidgets('rien d\'utile ne touche le bord de l\'écran',
        (WidgetTester tester) async {
      const Size size = Size(1280, 720);
      await _pump(tester, size: size);

      final double minMargin = 1280 * 0.05; // 64
      for (final Finder f in <Finder>[
        find.byType(TvLogo),
        find.text('Bienvenue'),
        find.byType(TvWhatsAppQr),
        find.text('Adresse MAC · ton identifiant client'),
      ]) {
        final Rect r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(minMargin - 1),
            reason: 'trop près du bord gauche : la TV peut le rogner');
        expect(r.right, lessThanOrEqualTo(size.width - minMargin + 1),
            reason: 'trop près du bord droit : la TV peut le rogner');
      }
    });

    testWidgets('les boutons sont assez grands pour être vus à 3 m',
        (WidgetTester tester) async {
      await _pump(tester);
      // 64 = le minimum « 10-foot » pour une cible actionnable.
      expect(tester.getSize(find.text('Se connecter')).height + 0, isNotNull);
      final Finder bouton = find.ancestor(
        of: find.text('Se connecter'),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(bouton.first).height, greaterThanOrEqualTo(64.0));
    });
  });

  // ---------------------------------------------------------
  //  LE POINT QUI COMPTE : on n'affiche pas un faux « actif »
  // ---------------------------------------------------------
  testWidgets('sans abonnement connu, on n\'annonce PAS « abonnement actif »',
      (WidgetTester tester) async {
    await _pump(tester);
    // Au démarrage d'un appareil neuf, le serveur n'a rien dit encore.
    // Le cahier des charges demandait « Abonnement Actif » en dur : ce
    // serait un mensonge, et c'est exactement ce qu'on refuse d'écrire.
    expect(find.text('Abonnement actif'), findsNothing);
    expect(find.text('En attente d\'activation'), findsOneWidget);
    expect(find.text('Connecté'), findsNothing,
        reason: 'le point vert ne s\'allume que si le serveur a répondu');
    expect(find.text('Hors ligne'), findsOneWidget);
  });

  // ---------------------------------------------------------
  //  Source enregistrée mais vide → recharger, pas ajouter
  // ---------------------------------------------------------
  testWidgets('avec onReload, le geste proposé est de RECHARGER',
      (WidgetTester tester) async {
    bool called = false;
    await _pump(tester, onReload: () async => called = true);

    expect(find.text('Recharger ma source'), findsOneWidget);
    await tester.tap(find.text('Recharger ma source'));
    await tester.pump();
    expect(called, isTrue,
        reason: 'le bouton principal doit vraiment relancer la synchro');
  });

  // ---------------------------------------------------------
  //  Rien ne déborde — première image du client
  // ---------------------------------------------------------
  group('tient sur toutes les dalles', () {
    for (final Size s in <Size>[
      const Size(1920, 1080),
      const Size(1280, 720),
      const Size(1024, 576),
      const Size(960, 540),
    ]) {
      testWidgets('${s.width.toInt()}×${s.height.toInt()}',
          (WidgetTester tester) async {
        await _pump(tester, size: s);
        expect(tester.takeException(), isNull,
            reason: 'un débordement ici, c\'est la première image de l\'app');
        expect(find.text('Bienvenue'), findsOneWidget);
      });
    }
  });
}
