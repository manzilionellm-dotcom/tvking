// Régressions observées : repli français, ancien réglage régional et erreur
// figée dans l'ancienne langue. Aucun serveur ni lecteur natif n'est appelé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/i18n/locale_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_legal_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_localized_format.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = LocaleRepository.instance;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await repo.initialize();
  });

  test('toutes les langues déclarées ont un catalogue généré', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      LocaleRepository.supportedLocales.map((l) => l.languageCode).toSet(),
    );
  });

  test('régions, alias norvégiens, liste de préférences et repli anglais', () {
    for (final input in <Locale>[
      const Locale('sv', 'SE'),
      const Locale('sv', 'FI'),
    ]) {
      expect(
        LocaleRepository.resolve([input], AppLocalizations.supportedLocales),
        const Locale('sv'),
      );
    }
    for (final code in ['no', 'nn', 'nb']) {
      expect(
        LocaleRepository.resolve([
          Locale(code),
        ], AppLocalizations.supportedLocales),
        const Locale('nb'),
      );
    }
    expect(
      LocaleRepository.resolve([
        const Locale('ja'),
        const Locale('de', 'AT'),
      ], AppLocalizations.supportedLocales),
      const Locale('de'),
    );
    expect(
      LocaleRepository.resolve([
        const Locale('ja'),
      ], AppLocalizations.supportedLocales),
      const Locale('en'),
    );
    expect(
      LocaleRepository.resolve(null, AppLocalizations.supportedLocales),
      const Locale('en'),
    );
    expect(
      LocaleRepository.resolve(null, [const Locale('sv')]),
      const Locale('sv'),
    );
  });

  test(
    'préférence ancienne normalisée, inconnue remplacée par Automatique',
    () async {
      for (final entry in <String, Locale?>{
        'sv_SE': const Locale('sv'),
        'pt-BR': const Locale('pt'),
        'no_NO': const Locale('nb'),
        'SYSTEM': null,
        'xx': null,
        '': null,
      }.entries) {
        SharedPreferences.setMockInitialValues({'app.locale.v1': entry.key});
        await repo.initialize();
        expect(repo.locale, entry.value, reason: entry.key);
      }
      await repo.setLocale(const Locale('ar'));
      await repo.initialize();
      expect(repo.locale, const Locale('ar'));
      await repo.setLocale(null);
      await repo.initialize();
      expect(repo.locale, isNull);
    },
  );

  test(
    'les services sont prévenus du changement système en mode Automatique',
    () async {
      var changes = 0;
      void listener() => changes++;
      repo.addListener(listener);
      repo.didChangeLocales([const Locale('sv')]);
      expect(changes, 1);
      await repo.setLocale(const Locale('fr'));
      final manualChanges = changes;
      repo.didChangeLocales([const Locale('ar')]);
      expect(changes, manualChanges);
      repo.removeListener(listener);
    },
  );

  Widget app(Widget child, {Locale? locale}) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    localeListResolutionCallback: LocaleRepository.resolve,
    home: Scaffold(body: child),
  );

  testWidgets(
    'la TV suédoise ouvre en suédois ; une erreur ouverte passe en arabe',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.localesTestValue = [const Locale('sv', 'SE')];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(app(const TvAddSourceScreen()));
      await tester.pumpAndSettle();
      final sv = await AppLocalizations.delegate.load(const Locale('sv'));
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(find.text(sv.tvSourcePasteHelp), findsOneWidget);
      final screen = tester.state(find.byType(TvAddSourceScreen));
      tester.widget<TvCtaButton>(find.byType(TvCtaButton)).onSelect!();
      await tester.pump();
      expect(find.text(sv.tvSourceNeedXtream), findsOneWidget);
      tester.platformDispatcher.localesTestValue = [const Locale('ar')];
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TvAddSourceScreen)), same(screen));
      expect(find.text(ar.tvSourceNeedXtream), findsOneWidget);
      expect(find.text(sv.tvSourceNeedXtream), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(TvAddSourceScreen))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in LocaleRepository.supportedLocales) {
    testWidgets(
      'formulaire et conditions rendus en ${locale.languageCode} sans débordement',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final words = await AppLocalizations.delegate.load(locale);
        await tester.pumpWidget(app(const TvAddSourceScreen(), locale: locale));
        await tester.pumpAndSettle();
        expect(find.text(words.tvSourcePasteHelp), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(app(const TvLegalScreen(), locale: locale));
        await tester.pumpAndSettle();
        expect(find.text(words.tvLegalSection1Title), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'dates et unités ne restent pas françaises sur une TV allemande',
    (tester) async {
      String? size;
      String? date;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              size = tvBytes(context, 1572864);
              date = tvDateTime(context, DateTime(2026, 10, 12, 15, 30));
              return const SizedBox();
            },
          ),
          locale: const Locale('de'),
        ),
      );
      await tester.pumpAndSettle();
      expect(size, '1,5 MB');
      expect(date, contains('Okt.'));
      expect(date, isNot(contains(' à ')));
    },
  );
}
