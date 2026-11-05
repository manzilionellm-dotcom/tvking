import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:tv_king/core/i18n/locale_repository.dart';
import 'package:tv_king/core/i18n/somali_formats.dart';
import 'package:tv_king/core/i18n/somali_localizations.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(initializeSomaliFormats);

  test('le somali partage le même ordre de date entre affichage et saisie', () {
    const material = SomaliMaterialLocalizations();
    const cupertino = SomaliCupertinoLocalizations();
    final date = DateTime(2026, 12, 31);
    expect(material.formatCompactDate(date), '31/12/2026');
    expect(material.parseCompactDate('31/12/2026'), date);
    expect(material.parseCompactDate('02/03/2026'), DateTime(2026, 3, 2));
    expect(material.parseCompactDate('31/02/2026'), isNull);
    expect(material.parseCompactDate('29/02/2025'), isNull);
    expect(material.parseCompactDate('29/02/2024'), DateTime(2024, 2, 29));
    expect(material.parseCompactDate('12/31/2026'), isNull);
    expect(material.parseCompactDate('bad'), isNull);
    expect(cupertino.datePickerDateOrder, DatePickerDateOrder.dmy);
    expect(DateFormat.yMd('so').format(date), '31/12/2026');
    expect(DateFormat.yMMMMd('so').format(date), contains('Diseembar'));
    expect(NumberFormat.decimalPattern('so').format(1234), '1,234');
  });

  for (final locale in LocaleRepository.supportedLocales) {
    testWidgets('les contrôles et dates chargent en ${locale.languageCode}',
        (tester) async {
      MaterialLocalizations? material;
      CupertinoLocalizations? cupertino;
      WidgetsLocalizations? widgets;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          ...somaliLocalizationsDelegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        home: Builder(builder: (context) {
          material = MaterialLocalizations.of(context);
          cupertino = CupertinoLocalizations.of(context);
          widgets = WidgetsLocalizations.of(context);
          return const Scaffold(body: TextField());
        }),
      ));
      await tester.pumpAndSettle();
      expect(material!.formatFullDate(DateTime(2026, 11, 1)), isNotEmpty);
      expect(material!.copyButtonLabel, isNotEmpty);
      expect(cupertino!.pasteButtonLabel, isNotEmpty);
      expect(widgets!.textDirection,
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr);
      if (locale.languageCode == 'so') {
        expect(material!.copyButtonLabel, 'Nuqul ka samee');
        expect(material!.pasteButtonLabel, 'Ku dheji');
        expect(cupertino!.cancelButtonLabel, 'Jooji');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('calendrier somali : texte et saisie jour/mois gardent la date',
      (tester) async {
    DateTime? chosen;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('so'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        ...somaliLocalizationsDelegates,
        ...AppLocalizations.localizationsDelegates,
      ],
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      chosen = await showDatePicker(
                          context: context,
                          initialDate: DateTime(2026, 11, 1),
                          firstDate: DateTime(2026),
                          lastDate: DateTime(2030));
                    },
                    child: const Text('calendar')),
              )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Dooro taariikhda'), findsOneWidget);
    expect(find.text('Jooji'), findsOneWidget);
    await tester.tap(find.byTooltip('U beddel gelinta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '31/12/2026');
    await tester.tap(find.text('Hagaag'));
    await tester.pumpAndSettle();
    expect(chosen, DateTime(2026, 12, 31));
    expect(tester.takeException(), isNull);
  });
}
