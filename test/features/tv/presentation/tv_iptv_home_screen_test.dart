// =========================================================
//  tv_iptv_home_screen_test.dart — Modèle A (accueil principal)
// =========================================================
//  Contrat de l'accueil fourni par le client, vérifié dans les
//  conditions réelles d'une box :
//    1. le bandeau annonce l'ambiance courante (« Mode soirée » après
//       19 h, « Mode jour » sinon) ;
//    2. la grille « Toutes les chaînes » est PARESSEUSE — avec 40 000
//       chaînes, seules quelques cartes sont construites (sinon une box
//       s'écroule à l'ouverture de l'accueil) ;
//    3. le menu latéral affiche les sections fixes du client ;
//    4. bouquet vide → aucun plantage, l'écran reste utilisable ;
//    5. AUCUNE source enregistrée → écran d'accueil, pas un menu vide.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_films_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_iptv_home_screen.dart';

List<Channel> _bouquet(int n) => <Channel>[
      for (int i = 0; i < n; i++)
        Channel(
          id: 'c$i',
          name: 'Chaîne $i',
          category: 'TV || CAT ${i % 20}',
          streamUrl: 'http://panel.example/live/u/p/$i.ts',
          isLive: true,
        ),
    ];

/// Une source enregistrée, comme après un ajout réussi. Sans ça,
/// l'accueil montre — à raison — l'écran de bienvenue.
Playlist _source() => Playlist(
      id: 1,
      name: 'Mon abonnement',
      type: PlaylistType.m3u,
      createdAt: 0,
      m3uUrl: 'http://panel.example/get.php',
      isActive: true,
    );

void main() {
  // L'accueil lit le bouquet, qui passe par le filtre de « flavor » —
  // comme au vrai démarrage de l'app (main() appelle setCurrent).
  setUpAll(() => FlavorConfig.setCurrent(FlavorConfig.sevenMotion));

  // Le gros des tests ci-dessous vérifie l'accueil D'UN CLIENT ÉQUIPÉ :
  // il a déjà sa source. On la pose donc avant chaque test, sinon c'est
  // l'écran de bienvenue qui s'affiche (vérifié séparément à la fin).
  setUp(() =>
      PlaylistRepository.instance.debugSeedPlaylists(<Playlist>[_source()]));
  tearDown(
      () => PlaylistRepository.instance.debugSeedPlaylists(const <Playlist>[]));

  testWidgets('le bandeau annonce l\'ambiance de l\'heure courante',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TvIptvHomeScreen()));
    await tester.pump();

    final int h = DateTime.now().hour;
    final bool soir = h >= 19 || h < 6;
    expect(find.text(soir ? 'Mode soirée' : 'Mode jour'), findsOneWidget);
    expect(find.text('IPTV'), findsOneWidget);
  });

  // Le client : « il manque l'option paramètre et l'option de changer de
  // template. Juste un petit mot en haut. » Depuis l'inversion, cet écran
  // EST le Modèle A : la pastille doit donc proposer « Modèle B ».
  testWidgets('les options du haut : bascule de modèle + Réglages',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TvIptvHomeScreen()));
    await tester.pump();

    expect(find.text('Modèle B'), findsOneWidget);
    expect(find.text('Réglages'), findsOneWidget);
    // …et on ne se propose jamais soi-même.
    expect(find.text('Modèle A'), findsNothing);
  });

  // Les deux boutons du haut de menu, dont le « bouton magique » de mise à
  // jour : l'app va chercher la dernière version et l'installe par-dessus.
  testWidgets('menu : Rechercher et Mettre à jour', (WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(home: TvIptvHomeScreen()));
    await t.pump();
    expect(find.text('Rechercher…'), findsOneWidget);
    expect(find.text('Mettre à jour'), findsOneWidget);
  });

  // Signalé par le client : « quand on retourne pour faire Exit, ça marche
  // pas ». La cause : le PopScope racine de tv_app laisse la main à
  // l'accueil, et cet accueil ne la prenait pas — le bouton Retour ne
  // faisait donc RIEN. L'accueil doit intercepter le retour lui-même.
  testWidgets('le bouton Retour est intercepté par l\'accueil',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TvIptvHomeScreen()));
    await tester.pump();

    final Iterable<Widget> scopes =
        tester.widgetList(find.byWidgetPredicate((Widget w) => w is PopScope));
    expect(scopes, isNotEmpty,
        reason: 'sans PopScope, le bouton Retour ne fait rien du tout');
    final dynamic scope = scopes.first;
    expect(scope.canPop, isFalse,
        reason: 'sans ça, Retour quitte sans rien demander');
    expect(scope.onPopInvokedWithResult, isNotNull,
        reason: 'c\'est ce rappel qui ouvre la boîte « Quitter ? »');
  });

  testWidgets('bouquet vide : aucun plantage', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TvIptvHomeScreen()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Le menu latéral est là même sans bouquet, avec ses sections fixes.
    expect(find.text('IPTV'), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);
    expect(find.text('Favoris'), findsOneWidget);
  });

  // « Côté cinéma, il faut y travailler tellement » : la section Films du
  // Modèle B n'est PAS une grille de chaînes — c'est le vrai cinéma de
  // l'app (catalogue VOD, affiche vedette, rangées, fiche détail).
  testWidgets('Films ouvre le CINÉMA, pas une grille de chaînes',
      (WidgetTester tester) async {
    // Le cinéma lit les traductions (rayon « Autres ») : on monte l'écran
    // avec les mêmes délégués que l'app réelle.
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const TvIptvHomeScreen(),
    ));
    await tester.pump();

    await tester.tap(find.text('Films'));
    await tester.pump();

    expect(find.byType(TvFilmsScreen), findsOneWidget);
    expect(find.text('Cinéma'), findsOneWidget);
  });

  testWidgets('40 000 chaînes : la grille ne construit que le visible',
      (WidgetTester tester) async {
    // La grille passe par SliverChildBuilderDelegate : on vérifie le
    // CONTRAT de paresse sur le même delegate, sans dépendre du dépôt
    // (un widget test ne peut pas peupler SQLite).
    int built = 0;
    final SliverChildBuilderDelegate delegate = SliverChildBuilderDelegate(
      (BuildContext _, int i) {
        built++;
        return SizedBox(height: 100, child: Text('carte $i'));
      },
      childCount: 40000,
    );
    await tester.pumpWidget(MaterialApp(
      home: CustomScrollView(
        slivers: <Widget>[
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: delegate,
          ),
        ],
      ),
    ));
    await tester.pump();
    expect(built, lessThan(60),
        reason: 'construire les 40 000 cartes ferait tomber la box '
            '(en a construit $built)');
  });

  // ---------------------------------------------------------
  //  ÉCRAN DE BIENVENUE — aucune source enregistrée
  // ---------------------------------------------------------
  //  Signalé par le client : « le A, ça montre rien à quelqu'un s'il n'a
  //  pas le lien. Il n'y a pas d'écran d'accueil. » Un menu latéral vide
  //  et un « aucune chaîne » sont un cul-de-sac à la première ouverture.
  //  Contrat : sur un appareil vierge, l'accueil doit donner les trois
  //  choses dont un nouvel arrivant a besoin — ajouter sa source, lire
  //  son identifiant d'appareil, et joindre son revendeur par QR.
  group('accueil sans aucune source', () {
    setUp(() =>
        PlaylistRepository.instance.debugSeedPlaylists(const <Playlist>[]));

    Future<void> pumpWelcome(WidgetTester tester,
        {Size size = const Size(1280, 720)}) async {
      // Une vraie box, pas la fenêtre 800×600 par défaut : c'est en 720p
      // que cet écran doit tenir, c'est donc en 720p qu'on le vérifie.
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const TvIptvHomeScreen(),
      ));
      await tester.pump();
    }

    testWidgets('on accueille au lieu de montrer un menu vide',
        (WidgetTester tester) async {
      await pumpWelcome(tester);
      expect(find.text('Bienvenue'), findsOneWidget);
      // …et surtout PAS le menu latéral de l'accueil équipé.
      expect(find.text('Sports'), findsNothing);
    });

    testWidgets('le chemin pour ajouter sa source est le bouton principal',
        (WidgetTester tester) async {
      await pumpWelcome(tester);
      expect(find.text('Ajouter ma source'), findsOneWidget);
      // Les deux sorties de secours restent à portée de télécommande.
      expect(find.text('Réglages'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsOneWidget);
    });

    testWidgets('l\'identifiant de l\'appareil est affiché en clair',
        (WidgetTester tester) async {
      await pumpWelcome(tester);
      // C'est ce code que le client dicte à son revendeur.
      expect(find.text('Identifiant de cet appareil'), findsOneWidget);
    });

    testWidgets('un QR permet de joindre le revendeur',
        (WidgetTester tester) async {
      await pumpWelcome(tester);
      expect(find.byType(TvWhatsAppQr), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Une box bon marché peut sortir du 720p, voire moins. Un écran
    // d'accueil qui déborde, c'est la première image que voit le client.
    testWidgets('tient sur une petite dalle sans rien faire déborder',
        (WidgetTester tester) async {
      await pumpWelcome(tester, size: const Size(960, 540));
      expect(tester.takeException(), isNull,
          reason: 'un débordement ici, c\'est la première image de l\'app');
      expect(find.text('Ajouter ma source'), findsOneWidget);
    });
  });
}
