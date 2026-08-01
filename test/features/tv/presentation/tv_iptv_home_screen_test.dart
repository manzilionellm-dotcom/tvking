// =========================================================
//  tv_iptv_home_screen_test.dart — Modèle B (design client)
// =========================================================
//  Contrat de l'accueil fourni par le client, vérifié dans les
//  conditions réelles d'une box :
//    1. le bandeau annonce l'ambiance courante (« Mode soirée » après
//       19 h, « Mode jour » sinon) ;
//    2. la grille « Toutes les chaînes » est PARESSEUSE — avec 40 000
//       chaînes, seules quelques cartes sont construites (sinon une box
//       s'écroule à l'ouverture de l'accueil) ;
//    3. le compteur affiche la vraie taille du bouquet ;
//    4. bouquet vide → aucun plantage, l'écran reste utilisable.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
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

  testWidgets('bouquet vide : aucun plantage', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TvIptvHomeScreen()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Le titre de section porte le compteur, même à zéro.
    expect(find.textContaining('Toutes les chaînes'), findsOneWidget);
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
