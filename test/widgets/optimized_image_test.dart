// =========================================================
//  optimized_image_test.dart — Le widget d'image partagé
// =========================================================
//  Contrat (demande client 2026-08-01) : un seul endroit décide de la
//  façon d'afficher une image, pour qu'on ne puisse plus OUBLIER une
//  borne quelque part.
//    1. les bornes mémoire ET disque sont TOUJOURS posées, même quand
//       l'appelant n'en donne aucune (déduites de la taille affichée) ;
//    2. une largeur explicite est respectée telle quelle ;
//    3. un plafond dur protège les cas « largeur infinie » (bannières) ;
//    4. le repli fourni s'affiche AVANT l'image (jamais de trou gris) ;
//    5. le rayon d'arrondi n'est appliqué que s'il est demandé.
// =========================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/widgets/optimized_image.dart';

CachedNetworkImage _img(WidgetTester t) =>
    t.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('bornes déduites de la taille affichée (mémoire ET disque)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(const OptimizedImage(
      imageUrl: 'https://exemple.test/a.jpg',
      width: 240,
      height: 360,
    )));
    final CachedNetworkImage img = _img(tester);
    // 2× la taille affichée : net sur une dalle 4K, sans excès.
    expect(img.memCacheWidth, 480);
    expect(img.maxWidthDiskCache, 480,
        reason: 'le disque doit être borné comme la mémoire');
  });

  testWidgets('largeur explicite respectée', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const OptimizedImage(
      imageUrl: 'https://exemple.test/a.jpg',
      width: 240,
      memCacheWidth: 100,
    )));
    expect(_img(tester).memCacheWidth, 100);
    expect(_img(tester).maxWidthDiskCache, 100);
  });

  testWidgets('largeur infinie (bannière) → plafond dur, jamais l\'original',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(const SizedBox(
      width: 600,
      height: 200,
      child: OptimizedImage(
        imageUrl: 'https://exemple.test/a.jpg',
        width: double.infinity,
        height: 200,
      ),
    )));
    final CachedNetworkImage img = _img(tester);
    expect(img.memCacheWidth, 1400);
    expect(img.maxWidthDiskCache, 1400);
  });

  testWidgets('le repli s\'affiche avant l\'image (jamais de trou)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(OptimizedImage(
      imageUrl: 'https://exemple.test/a.jpg',
      width: 200,
      height: 200,
      fallback: const Text('REPLI'),
    )));
    await tester.pump();
    expect(find.text('REPLI'), findsOneWidget);
  });

  testWidgets('arrondi appliqué seulement s\'il est demandé',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(const OptimizedImage(
      imageUrl: 'https://exemple.test/a.jpg',
      width: 100,
      height: 100,
    )));
    expect(find.byType(ClipRRect), findsNothing);

    await tester.pumpWidget(_host(OptimizedImage(
      imageUrl: 'https://exemple.test/a.jpg',
      width: 100,
      height: 100,
      borderRadius: BorderRadius.circular(12),
    )));
    expect(find.byType(ClipRRect), findsOneWidget);
  });
}
