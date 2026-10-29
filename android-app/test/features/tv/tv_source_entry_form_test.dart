import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/open_source_input.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_source_entry_form.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    ImportProgressBus.clear();
    // Chaque testWidgets a sa FakeAsyncZone. La file reste réelle dans le
    // scénario, mais ne doit pas conserver la zone d'un scénario terminé.
    RemoteSourceRepository.resetImportQueueForTesting();
  });

  Finder field(String name) => find.descendant(
    of: find.byKey(ValueKey<String>('tv-source-$name')),
    matching: find.byType(TextField),
  );
  TvCtaButton button(WidgetTester tester) => tester.widget<TvCtaButton>(
    find.byKey(const ValueKey<String>('tv-source-submit')),
  );
  Future<void> show(WidgetTester tester, TvSourceEntryForm form,
      {double width = 760, double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
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
      home: Scaffold(body: SingleChildScrollView(child: form)),
    ));
    await tester.pump();
  }
  Future<void> fillXtream(WidgetTester tester) async {
    await tester.enterText(field('server'), 'https://provider.invalid:8080');
    await tester.enterText(field('user'), 'fixture-user');
    await tester.enterText(field('password'), 'fixture-password');
  }

  testWidgets('validation obligatoire, puis brouillon Xtream sans réseau', (tester) async {
    OpenSourceDraft? draft;
    String? name;
    int added = 0;
    await show(tester, TvSourceEntryForm(
      submitForTesting: (value, label) async { draft = value; name = label; },
      onAdded: () => added++,
    ));
    expect(find.text('Xtream Codes'), findsOneWidget);
    expect(find.text('M3U / URL'), findsOneWidget);
    expect(find.text('Lien lecteur'), findsNothing);
    button(tester).onSelect!();
    await tester.pump();
    expect(find.text(OpenSourceInput.errNeedXtream), findsOneWidget);
    expect(draft, isNull);
    await fillXtream(tester);
    button(tester).onSelect!();
    await tester.pumpAndSettle();
    expect(draft!.kind, OpenSourceKind.xtream);
    expect(draft!.serverUrl, 'http://provider.invalid:8080');
    expect(draft!.username, 'fixture-user');
    expect(draft!.password, 'fixture-password');
    expect(name, isNotEmpty);
    expect(added, 1);
    expect(find.byType(TvSourceEntryForm), findsOneWidget,
        reason: 'un formulaire intégré ne ferme pas le Navigator');
    expect(RemoteSourceRepository.manualImporting.value, isFalse);
  });

  for (final entry in <String, OpenSourceKind>{
    'https://provider.invalid/list.m3u?token=fixture': OpenSourceKind.m3u,
    'https://provider.invalid/get.php?username=fixture&password=pass': OpenSourceKind.xtream,
  }.entries) {
    testWidgets('le raccourci lecteur ouvre M3U et accepte ${entry.value.name}', (tester) async {
      OpenSourceDraft? received;
      await show(tester, TvSourceEntryForm(
        initialMode: OpenEntryMode.player,
        submitForTesting: (draft, _) async { received = draft; },
      ));
      expect(find.byType(TextField), findsOneWidget);
      expect(field('m3u'), findsOneWidget);
      await tester.enterText(field('m3u'), entry.key);
      button(tester).onSelect!();
      await tester.pumpAndSettle();
      expect(received!.kind, entry.value);
      if (entry.value == OpenSourceKind.m3u) {
        expect(received!.m3uUrl, entry.key.replaceFirst('https://', 'http://'));
      } else {
        expect(received!.serverUrl, 'http://provider.invalid');
        expect(received!.username, 'fixture');
        expect(received!.password, 'pass');
      }
    });
  }

  testWidgets('les deux onglets gardent leurs champs et le mot de passe est masqué', (tester) async {
    await show(tester, const TvSourceEntryForm());
    await fillXtream(tester);
    expect(tester.widget<TextField>(field('password')).obscureText, isTrue);
    await tester.tap(find.byTooltip('Afficher le mot de passe'));
    await tester.pump();
    expect(tester.widget<TextField>(field('password')).obscureText, isFalse);
    await tester.tap(find.byTooltip('Masquer le mot de passe'));
    await tester.pump();
    expect(tester.widget<TextField>(field('password')).obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-mode-m3u')));
    await tester.pump();
    await tester.enterText(field('m3u'), 'https://provider.invalid/list.m3u');
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-mode-xtream')));
    await tester.pump();
    expect(tester.widget<TextField>(field('server')).controller!.text,
        'http://provider.invalid:8080');
    expect(tester.widget<TextField>(field('user')).controller!.text, 'fixture-user');
    expect(tester.widget<TextField>(field('password')).controller!.text, 'fixture-password');
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-mode-m3u')));
    await tester.pump();
    expect(tester.widget<TextField>(field('m3u')).controller!.text,
        'http://provider.invalid/list.m3u');
  });

  testWidgets('D-pad sur les onglets et action Suivant du clavier', (tester) async {
    await show(tester, const TvSourceEntryForm());
    await tester.enterText(field('server'), 'https://provider.invalid');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(tester.widget<TextField>(field('user')).focusNode!.hasFocus, isTrue);
    Focus.of(tester.element(find.text('M3U / URL'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(field('m3u'), findsOneWidget);
    expect(field('server'), findsNothing);
  });

  testWidgets('conversion HTTP immédiate limitée aux champs URL, identifiants et URL imbriquée intacts', (tester) async {
    final drafts = <OpenSourceDraft>[];
    await show(tester, TvSourceEntryForm(
      submitForTesting: (draft, _) async { drafts.add(draft); },
    ));
    await tester.enterText(field('server'), 'https://provider.invalid:8080');
    await tester.enterText(field('user'), 'https://username.invalid/account');
    await tester.enterText(field('password'), 'https://password.invalid/secret');
    expect(tester.widget<TextField>(field('server')).controller!.text,
        'http://provider.invalid:8080');
    expect(tester.widget<TextField>(field('user')).controller!.text,
        'https://username.invalid/account');
    expect(tester.widget<TextField>(field('password')).controller!.text,
        'https://password.invalid/secret');
    button(tester).onSelect!();
    await tester.pumpAndSettle();
    expect(drafts.single.serverUrl, 'http://provider.invalid:8080');
    expect(drafts.single.username, 'https://username.invalid/account');
    expect(drafts.single.password, 'https://password.invalid/secret');

    await tester.tap(find.byKey(const ValueKey<String>('tv-source-mode-m3u')));
    await tester.pump();
    const pasted = 'https://provider.invalid/list.m3u?next=https://nested.invalid/stream&token=a%2Bb';
    const corrected = 'http://provider.invalid/list.m3u?next=https://nested.invalid/stream&token=a%2Bb';
    await tester.enterText(field('m3u'), pasted);
    expect(tester.widget<TextField>(field('m3u')).controller!.text, corrected,
        reason: 'la correction est visible avant la validation');
    button(tester).onSelect!();
    await tester.pumpAndSettle();
    expect(drafts, hasLength(2));
    expect(drafts.last.kind, OpenSourceKind.m3u);
    expect(drafts.last.m3uUrl, corrected,
        reason: 'le lien HTTPS imbriqué et le token restent inchangés');
  });

  testWidgets('double-clic et IME : un import, progression réelle puis callback', (tester) async {
    final pending = Completer<void>();
    int calls = 0;
    int added = 0;
    await show(tester, TvSourceEntryForm(
      submitForTesting: (_, __) { calls++; return pending.future; },
      onAdded: () => added++,
    ));
    await fillXtream(tester);
    final submit = button(tester).onSelect!;
    final ime = tester.widget<TextField>(field('password')).onSubmitted!;
    submit();
    submit();
    ime('fixture-password');
    await tester.pump();
    expect(calls, 1);
    expect(button(tester).onSelect, isNull);
    expect(tester.widget<TextField>(field('server')).enabled, isFalse);
    expect(RemoteSourceRepository.manualImporting.value, isTrue);
    ImportProgressBus.saving(5, 20);
    await tester.pump();
    expect(find.text('Enregistrement 5 / 20 chaînes'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
        0.25);
    pending.complete();
    await tester.pumpAndSettle();
    expect(added, 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(ImportProgressBus.current.value, isNull);
    expect(find.byType(TvSourceEntryForm), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import du panel : saisie autorisée, validation bloquée', (tester) async {
    int calls = 0;
    await show(tester, TvSourceEntryForm(
      externalBusy: true,
      submitForTesting: (_, __) async { calls++; },
    ));
    await fillXtream(tester);
    expect(tester.widget<TextField>(field('server')).enabled, isTrue);
    expect(tester.widget<TextField>(field('password')).controller!.text, 'fixture-password');
    expect(button(tester).onSelect, isNull);
    tester.widget<TextField>(field('password')).onSubmitted!('fixture-password');
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('échec privé : message public, saisie conservée et nouvel essai', (tester) async {
    int calls = 0;
    int added = 0;
    await show(tester, TvSourceEntryForm(
      submitForTesting: (_, __) async {
        calls++;
        if (calls == 1) throw StateError('https://private.invalid/?password=never-display');
      },
      onAdded: () => added++,
    ));
    await fillXtream(tester);
    button(tester).onSelect!();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tv-source-error')), findsOneWidget);
    expect(find.textContaining('never-display'), findsNothing);
    expect(find.textContaining('private.invalid'), findsNothing);
    expect(tester.widget<TextField>(field('password')).controller!.text, 'fixture-password');
    expect(added, 0);
    expect(RemoteSourceRepository.manualImporting.value, isFalse);
    button(tester).onSelect!();
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(added, 1);
    expect(find.byKey(const ValueKey<String>('tv-source-error')), findsNothing);
  });

  testWidgets('le premier lot peut retirer le formulaire sans interrompre son import', (tester) async {
    final pending = Completer<void>();
    bool completed = false;
    int added = 0;
    await show(tester, TvSourceEntryForm(
      submitForTesting: (_, __) async { await pending.future; completed = true; },
      onAdded: () => added++,
    ));
    await fillXtream(tester);
    button(tester).onSelect!();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(added, 0);
    expect(RemoteSourceRepository.manualImporting.value, isFalse);
    expect(ImportProgressBus.current.value, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final mode in <OpenEntryMode>[OpenEntryMode.xtream, OpenEntryMode.m3u]) {
    testWidgets('320 px et texte à 200 % : mode ${mode.name} sans débordement', (tester) async {
      await show(tester, TvSourceEntryForm(initialMode: mode), width: 320, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey<String>('tv-source-submit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(button(tester).onSelect, isNotNull);
    });
  }
}
