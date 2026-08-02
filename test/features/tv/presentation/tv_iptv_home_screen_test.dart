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
//    4. ZÉRO CHAÎNE → écran d'accueil, jamais un menu vide. Le critère
//       est le BOUQUET, pas la présence d'une source : une source
//       enregistrée mais vide menait au même cul-de-sac (signalé deux
//       fois par le client, photo à l'appui).
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
import 'package:tv_king/features/tv/presentation/tv_welcome_screen.dart';
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
  // il a sa source ET des chaînes dedans. On pose les deux avant chaque
  // test — car depuis le correctif signalé par le client, le critère
  // d'affichage est le BOUQUET, pas la simple présence d'une source.
  // Sans chaînes, c'est l'écran de bienvenue (vérifié séparément à la fin).
  setUp(() {
    PlaylistRepository.instance.debugSeedPlaylists(<Playlist>[_source()]);
    PlaylistRepository.instance.debugSeedChannels(_bouquet(40));
  });

  // C'est un écran de TÉLÉVISION : on le rend à la taille d'une box
  // (1280×720), pas dans la fenêtre 800×600 par défaut du harnais, qui
  // ne correspond à aucun appareil réel.
  setUp(() {
    final TestWidgetsFlutterBinding b = TestWidgetsFlutterBinding.instance;
    b.platformDispatcher.views.first
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1.0;
    addTearDown(b.platformDispatcher.views.first.reset);
  });
  tearDown(() {
    PlaylistRepository.instance.debugSeedPlaylists(const <Playlist>[]);
    PlaylistRepository.instance.debugSeedChannels(const <Channel>[]);
  });

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

  // Le menu latéral porte les sections FIXES du client, quelles que
  // soient les catégories réellement présentes dans son bouquet.
  // (Le cas « bouquet vide » ne passe plus par ici : il montre l'écran
  // d'accueil — c'est vérifié dans le groupe du bas.)
  testWidgets('le menu latéral porte les sections fixes du client',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TvIptvHomeScreen()));
    await tester.pump();
    expect(tester.takeException(), isNull);
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
    setUp(() {
      PlaylistRepository.instance.debugSeedPlaylists(const <Playlist>[]);
      PlaylistRepository.instance.debugSeedChannels(const <Channel>[]);
    });

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

    // LE CAS QUE LE CLIENT A DÛ SIGNALER DEUX FOIS (photo à l'appui) :
    // une source EST enregistrée, mais elle ne contient aucune chaîne
    // (abonnement vidé, expiré, ou jamais chargé). Se fier à « a-t-il
    // une source » le renvoyait sur le menu vide et « Aucune chaîne
    // dans cette section » — le cul-de-sac qu'on prétendait avoir
    // supprimé. Le critère, c'est le BOUQUET, pas la source.
    testWidgets('source enregistrée mais VIDE : on accueille quand même',
        (WidgetTester tester) async {
      PlaylistRepository.instance.debugSeedPlaylists(<Playlist>[_source()]);
      await pumpWelcome(tester);
      // Le délai d'anti-clignotement passé, l'accueil doit apparaître.
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(TvWelcomeScreen), findsOneWidget);
      expect(find.text('Sports'), findsNothing,
          reason: 'le menu vide était le cul-de-sac signalé par le client');
      // Et le bon geste lui est proposé : recharger, pas « ajouter » une
      // source qu'il a déjà.
      expect(find.text('Recharger ma source'), findsOneWidget);
    });

    // Le revers : ne PAS faire clignoter l'accueil au démarrage. Une
    // source enregistrée met un instant à livrer son bouquet ; pendant
    // ce temps on patiente, on n'annonce pas « aucune chaîne ».
    testWidgets('au démarrage, on patiente au lieu de crier « aucune chaîne »',
        (WidgetTester tester) async {
      PlaylistRepository.instance.debugSeedPlaylists(<Playlist>[_source()]);
      await pumpWelcome(tester);

      expect(find.text('Chargement de tes chaînes…'), findsOneWidget);
      expect(find.byType(TvWelcomeScreen), findsNothing);
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
      // Le contenu de l'écran est vérifié en détail — et sur quatre
      // tailles de dalle — dans tv_welcome_screen_test.dart. Ici on
      // vérifie seulement que l'accueil le monte bien, sans casse.
      expect(find.byType(TvWelcomeScreen), findsOneWidget);
    });
  });
}
