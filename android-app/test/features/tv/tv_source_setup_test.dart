import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/core/support/vip_support.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_phone_source_qr.dart';
import 'package:tv_king/features/tv/presentation/tv_source_entry_form.dart';
import 'package:tv_king/features/tv/presentation/tv_source_setup.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    ImportProgressBus.clear();
    RemoteSourceRepository.importing.value = false;
    RemoteSourceRepository.manualImporting.value = false;
  });

  final support = find.byKey(const ValueKey<String>('source-whatsapp-support'));
  Finder field(String name) => find.descendant(
    of: find.byKey(ValueKey<String>('tv-source-$name')),
    matching: find.byType(TextField),
  );
  Future<void> show(WidgetTester tester, Widget body, {
    Size size = const Size(760, 900),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: body),
    ));
    await tester.pump();
  }

  testWidgets('support : aucun lancement au rendu et message sans données de la liste', (tester) async {
    final messages = <String>[];
    await show(tester, SingleChildScrollView(child: Column(children: <Widget>[
      const TvSourceEntryForm(),
      TvWhatsAppSupportButton(openForTesting: (message) async {
        messages.add(message);
        return true;
      }),
    ])));
    await tester.enterText(field('server'), 'https://private.invalid:8080');
    await tester.enterText(field('user'), 'fixture-account');
    await tester.enterText(field('password'), 'fixture-password');
    await tester.pump(const Duration(seconds: 2));
    expect(messages, isEmpty);
    await tester.ensureVisible(support);
    await tester.tap(support);
    await tester.pumpAndSettle();
    final words = await AppLocalizations.delegate.load(const Locale('fr'));
    expect(messages, <String>[words.tvSupportHello]);
    expect(messages.single, isNot(contains('private.invalid')));
    expect(messages.single, isNot(contains('fixture-account')));
    expect(messages.single, isNot(contains('fixture-password')));
    expect(messages.single, isNot(contains('MK:')));
  });

  testWidgets('support : deux clics dans la même frame ouvrent une seule fois', (tester) async {
    final pending = Completer<bool>();
    int calls = 0;
    await show(tester, TvWhatsAppSupportButton(openForTesting: (_) {
      calls++;
      return pending.future;
    }));
    final open = tester.widget<TextButton>(support).onPressed!;
    open();
    open();
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<TextButton>(support).onPressed, isNull);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(support).onPressed, isNotNull);
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final throws in <bool>[false, true]) {
    testWidgets('support indisponible (${throws ? 'exception' : 'false'}) : numéro existant et nouvel essai', (tester) async {
      int calls = 0;
      await show(tester, TvWhatsAppSupportButton(openForTesting: (_) async {
        calls++;
        if (calls > 1) return true;
        if (throws) throw StateError('https://private.invalid/?password=never-display');
        return false;
      }));
      await tester.tap(support);
      await tester.pumpAndSettle();
      final words = await AppLocalizations.delegate.load(const Locale('fr'));
      expect(find.text(words.tvSupportUnavailable), findsOneWidget);
      final number = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(number.data, VipSupport.displayNumber);
      expect(number.textDirection, TextDirection.ltr);
      expect(find.textContaining('never-display'), findsNothing);
      expect(find.textContaining('private.invalid'), findsNothing);
      expect(tester.widget<TextButton>(support).onPressed, isNotNull);
      await tester.tap(support);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text(words.tvSupportUnavailable), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
    });
  }

  testWidgets('support retiré pendant une ouverture : aucune mise à jour après dispose', (tester) async {
    final pending = Completer<bool>();
    int calls = 0;
    await show(tester, TvWhatsAppSupportButton(openForTesting: (_) {
      calls++;
      return pending.future;
    }));
    await tester.tap(support);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accueil sans QR, 320 px et texte à 200 % : saisie et support accessibles', (tester) async {
    await show(tester, const TvSourceSetup(details: Text('Informations de liste')),
        size: const Size(320, 720), scale: 2);
    expect(find.byType(TvSourceEntryForm), findsOneWidget);
    expect(find.byType(TvWhatsAppQr), findsNothing);
    expect(find.byType(TvPhoneSourceQr), findsNothing);
    expect(find.byType(TvOwnSourceQr), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(support);
    await tester.pumpAndSettle();
    expect(tester.getCenter(support).dy, inInclusiveRange(0, 720));
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait/paysage et retour : le même formulaire garde les deux saisies', (tester) async {
    await show(tester, const TvSourceSetup(details: Text('Informations de liste')),
        size: const Size(400, 900));
    final initialState = tester.state(find.byType(TvSourceEntryForm));
    await tester.enterText(field('server'), 'https://provider.invalid:8080');
    await tester.enterText(field('user'), 'fixture-user');
    await tester.enterText(field('password'), 'fixture-password');
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-mode-m3u')));
    await tester.pump();
    await tester.enterText(field('m3u'), 'https://provider.invalid/list.m3u');
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TvSourceEntryForm)), same(initialState));
    expect(tester.widget<TextField>(field('m3u')).controller!.text,
        'http://provider.invalid/list.m3u');
    tester.view.physicalSize = const Size(400, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-mode-xtream')));
    await tester.pump();
    expect(tester.state(find.byType(TvSourceEntryForm)), same(initialState));
    expect(tester.widget<TextField>(field('server')).controller!.text,
        'http://provider.invalid:8080');
    expect(tester.widget<TextField>(field('user')).controller!.text, 'fixture-user');
    expect(tester.widget<TextField>(field('password')).controller!.text, 'fixture-password');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sans Scaffold : clavier ouvert, mot de passe et validation restent accessibles', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    // Comme TvShell, Material n'adapte pas automatiquement sa hauteur au
    // clavier. Ce test dépend donc du Padding de production dans le setup.
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Material(child: TvSourceSetup(details: Text('Informations de liste'))),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsNothing);
    final initialState = tester.state(find.byType(TvSourceEntryForm));
    await tester.enterText(field('password'), 'fixture-password');

    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TvSourceEntryForm)), same(initialState));
    expect(tester.widget<TextField>(field('password')).controller!.text,
        'fixture-password');
    await tester.ensureVisible(field('password'));
    await tester.pumpAndSettle();
    final passwordRect = tester.getRect(field('password'));
    expect(passwordRect.top, greaterThanOrEqualTo(0));
    expect(passwordRect.bottom, lessThanOrEqualTo(400));

    final submit = find.byKey(const ValueKey<String>('tv-source-submit'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    final submitRect = tester.getRect(submit);
    expect(submitRect.top, greaterThanOrEqualTo(0));
    expect(submitRect.bottom, lessThanOrEqualTo(400));
    expect(tester.takeException(), isNull);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TvSourceEntryForm)), same(initialState));
    expect(tester.widget<TextField>(field('password')).controller!.text,
        'fixture-password');
    expect(tester.takeException(), isNull);
  });
}
