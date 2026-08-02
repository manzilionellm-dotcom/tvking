// =========================================================
//  tv_terms_notice_test.dart — Les conditions SANS bloquer la télé
// =========================================================
//  Demande du client, mot pour mot : « les conditions qui ne bloquent
//  pas la télé. Juste un petit message comme un chat […] que ça ne
//  dérange pas, mais il doit dire oui ou non. »
//
//  Ce que ces tests garantissent — et qui ne doit jamais régresser :
//    1. la télé DERRIÈRE reste visible et utilisable : la bulle ne
//       remplace rien, elle se pose par-dessus ;
//    2. elle ne surgit pas à l'instant du démarrage, elle attend ;
//    3. « Oui » l'éteint et l'enregistre — elle ne revient plus ;
//    4. « Non » ne coupe RIEN : la bulle s'efface, les conditions
//       s'ouvrent, et la télé continue ;
//    5. quelqu'un qui a déjà accepté ne la revoit jamais.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/onboarding/data/consent_state.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';
import 'package:tv_king/features/tv/presentation/tv_legal_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_terms_notice.dart';

const String _kTele = 'LA TÉLÉ EST LÀ';

/// Monte la bulle EXACTEMENT comme dans l'app : par-dessus l'accueil,
/// dans une pile — jamais à sa place.
Future<void> _pump(WidgetTester tester, {Duration? delay}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const Center(child: Text(_kTele)),
        TvTermsNotice(delay: delay ?? const Duration(milliseconds: 50)),
      ],
    ),
  ));
  await tester.pump(); // lecture de la préférence
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('elle attend avant de se montrer — jamais pendant le démarrage',
      (WidgetTester tester) async {
    await _pump(tester, delay: const Duration(seconds: 3));
    expect(find.textContaining('Un mot'), findsNothing,
        reason: 'une bulle qui surgit au chargement passe pour une erreur');

    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('Un mot'), findsOneWidget);
  });

  testWidgets('la télé reste visible derrière : rien n\'est bloqué',
      (WidgetTester tester) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(_kTele), findsOneWidget,
        reason: 'la bulle se pose PAR-DESSUS, elle ne remplace pas l\'accueil');
    expect(find.text('Oui, j\'ai compris'), findsOneWidget);
    expect(find.text('Non, lire les conditions'), findsOneWidget);
  });

  testWidgets('« Oui » l\'éteint et l\'enregistre pour de bon',
      (WidgetTester tester) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Oui, j\'ai compris'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Un mot'), findsNothing);
    expect(find.text(_kTele), findsOneWidget);
    expect(await ConsentState.instance.hasAccepted(), isTrue);
  });

  testWidgets('« Non » ne coupe rien : les conditions s\'ouvrent, la télé vit',
      (WidgetTester tester) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Non, lire les conditions'));
    await tester.pumpAndSettle();

    expect(find.byType(TvLegalScreen), findsOneWidget);
    // Rien n'a été enregistré : la question se reposera, sans jamais
    // barrer l'accès entre-temps.
    expect(await ConsentState.instance.hasAccepted(), isFalse);
  });

  testWidgets('déjà accepté : on ne le rembête plus jamais',
      (WidgetTester tester) async {
    await ConsentState.instance.markAccepted();
    await _pump(tester);
    await tester.pump(const Duration(seconds: 5));

    expect(find.textContaining('Un mot'), findsNothing);
    expect(find.text(_kTele), findsOneWidget);
  });
}
