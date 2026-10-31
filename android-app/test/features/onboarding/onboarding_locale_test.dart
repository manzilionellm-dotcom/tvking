import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  setUp(() {
    FlavorConfig.resetForTesting();
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
  });

  Widget app(String language) => MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: OnboardingScreen(onDone: () {}),
      );

  testWidgets('accueil guidé en suédois selon la langue de l’appareil',
      (tester) async {
    await tester.pumpWidget(app('sv'));
    expect(find.text('Välkommen till The Few'), findsOneWidget);
    expect(find.text('Bienvenue sur The Few'), findsNothing);

    await tester.tap(find.text('Nästa'));
    await tester.pumpAndSettle();
    expect(find.text('Ladda din spellista'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accueil guidé en arabe avec les traductions RTL',
      (tester) async {
    await tester.pumpWidget(app('ar'));
    expect(find.text('مرحباً بك في The Few'), findsOneWidget);
    expect(find.text('Bienvenue sur The Few'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
