import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';
import 'package:tv_king/features/missed_show/presentation/missed_guide_details.dart';
import 'package:tv_king/features/missed_show/domain/missed_summary.dart';
import 'package:tv_king/features/missed_show/presentation/missed_notice.dart';

const MissedSummary _summary = MissedSummary(
  title: 'Programme de test',
  missedMinutes: 19,
  description: 'Résumé détaillé du programme.',
  rewindUrl: 'https://replay.invalid/programme',
);

Widget _app({
  int generation = 1,
  bool suppressed = false,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Align(
    alignment: Alignment.topCenter,
    child: MissedNotice(
      key: ValueKey<int>(generation),
      summary: _summary,
      suppressed: suppressed,
    ),
  ),
);

void main() {
  setUp(RepairFlags.debugReset);
  tearDown(RepairFlags.debugReset);
  testWidgets('le bandeau libère l’image après deux secondes', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Align(
        alignment: Alignment.topCenter,
        child: MissedNotice(
          summary: MissedSummary(
            title: 'Programme de test',
            missedMinutes: 19,
            description: 'Résumé détaillé du programme.',
          ),
        ),
      ),
    ));
    final Finder noticeText = find.descendant(
      of: find.byType(MissedNotice),
      matching: find.byType(Text),
    );
    expect(noticeText, findsWidgets);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(noticeText, findsWidgets);
    await tester.pump(const Duration(milliseconds: 1));
    expect(noticeText, findsNothing,
        reason: 'le bandeau ne doit plus recouvrir le direct après 2 s');
  });

  testWidgets('une seule ligne neutre, en anglais puis en français',
      (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('Program started 19 min ago'), findsOneWidget);
    expect(find.text(_summary.title), findsNothing);
    expect(find.text(_summary.description!), findsNothing);
    final Text label = tester.widget<Text>(
        find.text('Program started 19 min ago'));
    expect(label.maxLines, 1);
    await tester.pumpWidget(_app(locale: const Locale('fr')));
    expect(find.text('Programme commencé il y a 19 min'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('un rebuild ne prolonge pas les deux secondes', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 499));
    expect(find.text('Program started 19 min ago'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Program started 19 min ago'), findsNothing);
    await tester.pumpWidget(_app());
    expect(find.text('Program started 19 min ago'), findsNothing);
  });

  testWidgets('un ancien zap ne ferme pas la notification de la chaîne suivante',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(_app(generation: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Program started 19 min ago'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 999));
    expect(find.text('Program started 19 min ago'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Program started 19 min ago'), findsNothing);
  });

  testWidgets('le retour du replay ne réaffiche pas un bandeau expiré',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(_app(suppressed: true));
    expect(find.text('Program started 19 min ago'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpWidget(_app());
    expect(find.text('Program started 19 min ago'), findsNothing);
  });

  testWidgets('fermer le lecteur annule la minuterie', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('le repli chargé par sa clé garde la carte historique permanente',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.missedNoticeLegacyKey: true,
    });
    await RepairFlags.load();
    await tester.pumpWidget(_app());
    expect(find.text('You missed 19 min'), findsOneWidget);
    expect(find.text(_summary.title), findsOneWidget);
    expect(find.text(_summary.description!), findsOneWidget);
    expect(find.text('Right, then OK: from the start.'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('You missed 19 min'), findsOneWidget);
    await tester.pumpWidget(_app(suppressed: true));
    expect(find.text('You missed 19 min'), findsNothing);
    await tester.pumpWidget(_app());
    expect(find.text('You missed 19 min'), findsOneWidget);
  });

  testWidgets('le résumé reste consultable dans le Guide après le délai',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Column(children: const <Widget>[
        MissedNotice(summary: _summary),
        MissedGuideDetails(summary: _summary),
      ]),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.descendant(of: find.byType(MissedNotice),
        matching: find.byType(Text)), findsNothing);
    expect(find.text(_summary.title), findsOneWidget);
    expect(find.text(_summary.description!), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text(_summary.description!), findsOneWidget);
  });

  testWidgets('le Guide ne crée pas de détail sans texte ni avec le repli',
      (tester) async {
    for (final MissedSummary? summary in <MissedSummary?>[
      null,
      const MissedSummary(title: 'Programme', missedMinutes: 19),
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: MissedGuideDetails(summary: summary),
      ));
      expect(find.byType(Text), findsNothing);
    }
    RepairFlags.missedNoticeLegacy = true;
    await tester.pumpWidget(const MaterialApp(
      home: MissedGuideDetails(summary: _summary),
    ));
    expect(find.byType(Text), findsNothing);
  });
}
