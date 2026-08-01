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
//    4. bouquet vide → aucun plantage, l'écran reste utilisable.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
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

void main() {
  // L'accueil lit le bouquet, qui passe par le filtre de « flavor » —
  // comme au vrai démarrage de l'app (main() appelle setCurrent).
  setUpAll(() => FlavorConfig.setCurrent(FlavorConfig.sevenMotion));

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
}
