import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_light_intro.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(TvLightIntro.debugReset);

  Future<void> pumpIntro(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: const TvLightIntro(child: Text('accueil')),
        ),
      ),
    );
  }

  testWidgets('le logo apparaît puis laisse l\'accueil', (WidgetTester tester) async {
    await pumpIntro(tester);
    await tester.pump();
    expect(find.byType(TvLogo), findsOneWidget);
    expect(find.text('accueil'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(TvLogo), findsOneWidget);
    final Image logo = tester.widget<Image>(find.byType(Image));
    await tester.runAsync(() async {
      await precacheImage(logo.image, tester.element(find.byType(Image)));
    });
    await tester.pump();
    await expectLater(
      find.byType(TvLightIntro),
      matchesGoldenFile('goldens/tv_light_intro.png'),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(TvLogo), findsNothing);
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('une touche saute l\'intro', (WidgetTester tester) async {
    await pumpIntro(tester);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.byType(TvLogo), findsNothing);
  });

  testWidgets('animations système coupées : pas de voile', (WidgetTester tester) async {
    await pumpIntro(tester, disableAnimations: true);
    await tester.pump();
    expect(find.byType(TvLogo), findsNothing);
    expect(find.text('accueil'), findsOneWidget);
  });
}
