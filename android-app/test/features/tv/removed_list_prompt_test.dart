import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/playlists/data/removed_list_notice.dart';
import 'package:tv_king/features/tv/presentation/removed_list_prompt.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    RemovedListNotice.instance.resetForTesting();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RemovedListPrompt(
          child: Builder(
            builder: (BuildContext context) {
              return Scaffold(
                body: Column(
                  children: <Widget>[
                    const Text('accueil'),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const Scaffold(body: Text('lecteur')),
                          ),
                        );
                      },
                      child: const Text('ouvrir lecteur'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir lecteur'));
    await tester.pumpAndSettle();
  }

  testWidgets('liste retirée, plus rien : message puis Ajouter ma source',
      (WidgetTester tester) async {
    await pump(tester);
    expect(find.text('lecteur'), findsOneWidget);

    RemovedListNotice.instance.signal(removed: 1, noneLeft: true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Liste retirée'), findsOneWidget);
    expect(find.textContaining('Ton revendeur a retiré cette liste'),
        findsOneWidget);
    // Le lecteur est encore là derrière la boîte.
    expect(find.text('lecteur'), findsOneWidget);

    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Ajouter ma source'), findsOneWidget);
    expect(find.text('lecteur'), findsNothing);
  });

  testWidgets('il reste une autre liste : retour à l\'accueil, pas d\'ajout',
      (WidgetTester tester) async {
    await pump(tester);
    RemovedListNotice.instance.signal(removed: 1, noneLeft: false);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('accueil'), findsOneWidget);
    expect(find.text('Ajouter ma source'), findsNothing);
    expect(find.text('lecteur'), findsNothing);
  });
}
