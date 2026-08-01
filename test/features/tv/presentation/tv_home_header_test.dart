// =========================================================
//  tv_home_header_test.dart — Bug terrain : en-tête plié en colonne
// =========================================================
//  Photo box client (2026-08-01) : le bloc « Tierp (Comté d'Uppsala)
//  · 20° ☀️ · Samedi 11:04 » vivait dans un Expanded auquel les 8
//  puces de la barre ne laissaient que quelques pixels — le texte,
//  SANS maxLines, se repliait LETTRE PAR LETTRE en colonne, étirait
//  la barre en hauteur et « mélangeait » tout l'accueil.
//  Contrat testé ici, DANS les conditions de la photo :
//    1. largeur minuscule → UNE seule ligne (hauteur d'une ligne),
//       jamais de pliage vertical, aucune erreur de layout ;
//    2. la ville s'affiche COURTE (« Tierp », sans la parenthèse) ;
//    3. largeur normale → ville + température + heure présentes.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/tv/data/greeting_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_home_header.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const Greeting kTierp = Greeting(
  city: "Tierp (Comté d'Uppsala)",
  country: 'SE',
  tempC: 20,
  weatherCode: 0, // ☀️
);

Widget _host({required double width, Greeting? greeting}) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          // Reproduit le Row de la barre haute : le header est coincé
          // dans une largeur imposée (comme l'Expanded de la photo).
          child: SizedBox(
            width: width,
            child: TvHomeHeader(initialGreeting: greeting),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() {
    // Pas de réseau en test : la police retombe sur la police système.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
      'écrasé à 40 px (conditions de la photo) : une seule ligne, '
      'jamais de colonne de lettres', (WidgetTester tester) async {
    await tester.pumpWidget(_host(width: 40, greeting: kTierp));
    await tester.pump();

    // Aucune exception de layout (overflow, contraintes) n'a été levée.
    expect(tester.takeException(), isNull);

    // La hauteur du TEXTE rendu est celle d'UNE ligne (~18–30 px selon
    // la police de repli) — le bug la faisait exploser à plusieurs
    // centaines de pixels (une lettre par ligne). On mesure le RichText
    // lui-même : son Align parent, lui, remplit l'espace par design.
    final RenderBox text = tester.renderObject<RenderBox>(find.descendant(
      of: find.byType(TvHomeHeader),
      matching: find.byType(RichText),
    ));
    expect(text.size.height, lessThan(40),
        reason: 'le texte ne doit JAMAIS se replier en colonne');
  });

  testWidgets('la ville est affichée COURTE : « Tierp », sans la parenthèse',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(width: 900, greeting: kTierp));
    await tester.pump();

    final RichText rich = tester.widget<RichText>(find.descendant(
      of: find.byType(TvHomeHeader),
      matching: find.byType(RichText),
    ));
    final String plain = rich.text.toPlainText();
    expect(plain, contains('Tierp'));
    expect(plain, isNot(contains('Comté')),
        reason: 'la parenthèse administrative est réservée au sélecteur');
    expect(plain, contains('20°'));
    // L'heure « HH:MM » est présente (jour · heure en fin de bloc).
    expect(RegExp(r'\d{2}:\d{2}').hasMatch(plain), isTrue);
  });

  test('shortCityLabel : retire uniquement la parenthèse FINALE', () {
    expect(shortCityLabel("Tierp (Comté d'Uppsala)"), 'Tierp');
    expect(shortCityLabel('Paris'), 'Paris');
    expect(shortCityLabel('Aix-en-Provence (PACA) '), 'Aix-en-Provence');
    // Une parenthèse INTERNE (rare mais réelle) n'est pas touchée.
    expect(shortCityLabel('Ault (Somme) Plage'), 'Ault (Somme) Plage');
  });
}
