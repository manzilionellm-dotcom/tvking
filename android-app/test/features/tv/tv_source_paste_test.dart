import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/playlists/data/local_m3u_bytes.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/open_source_input.dart';
import 'package:tv_king/features/tv/data/local_m3u_picker.dart';
import 'package:tv_king/features/tv/presentation/tv_source_entry_form.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    Future<void> load(String family, String asset) async {
      final FontLoader loader = FontLoader(family)
        ..addFont(rootBundle.load(asset));
      await loader.load();
    }

    await load('Inter_regular', 'assets/fonts/Inter-Regular.ttf');
    await load('Inter_600', 'assets/fonts/Inter-SemiBold.ttf');
  });

  test('fichier vide ou trop gros : message, pas de lecture infinie', () async {
    final Directory dir = await Directory.systemTemp.createTemp('zuno-m3u');
    addTearDown(() => dir.delete(recursive: true));
    final File empty = File('${dir.path}/vide.m3u');
    await empty.writeAsString('');
    await expectLater(
      readLocalM3uBytes(empty.path),
      throwsA(
        isA<LocalM3uRead>().having(
          (LocalM3uRead e) => e.code,
          'code',
          'local_empty',
        ),
      ),
    );
  });

  testWidgets('Coller reconnaît un lien Xtream et le fichier absent se dit', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? imported;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TvSourceEntryForm(
            readClipboardForTesting: () async =>
                'http://panel.invalid:8080/get.php?username=demo&password=jeton',
            pickLocalFileForTesting: () async =>
                const LocalM3uPick(LocalM3uPickStatus.unavailable),
            importLocalFileForTesting: (String path) async {
              imported = path;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('tv-source-paste')));
    await tester.pump();
    expect(find.text('http://panel.invalid:8080'), findsOneWidget);
    expect(find.text('demo'), findsOneWidget);

    await expectLater(
      find.byType(TvSourceEntryForm),
      matchesGoldenFile('goldens/tv_source_paste.png'),
    );

    await tester.tap(find.byKey(const ValueKey<String>('tv-source-file')));
    await tester.pump();
    expect(find.textContaining('n\'ouvre pas les fichiers'), findsOneWidget);
    expect(imported, isNull);
  });

  Future<void> showForm(
    WidgetTester tester, {
    Future<String?> Function()? readClipboard,
    Future<LocalM3uPick> Function()? pickLocalFile,
    Future<void> Function(String path)? importLocalFile,
    Future<void> Function(OpenSourceDraft draft, String name)? submit,
  }) async {
    RemoteSourceRepository.resetImportQueueForTesting();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TvSourceEntryForm(
            autofocus: true,
            readClipboardForTesting: readClipboard,
            pickLocalFileForTesting: pickLocalFile,
            importLocalFileForTesting: importLocalFile,
            submitForTesting: submit,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String? focusedKey() {
    final BuildContext? context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? found;
    context.visitAncestorElements((Element element) {
      final Key? key = element.widget.key;
      if (key is ValueKey<String> && key.value.startsWith('tv-source-')) {
        found = key.value;
        return false;
      }
      return true;
    });
    return found;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  testWidgets('Coller et Fichier : au D-pad au-dessus des modes', (
    WidgetTester tester,
  ) async {
    await showForm(
      tester,
      readClipboard: () async =>
          'http://panel.invalid:8080/get.php?username=demo&password=jeton',
    );
    expect(focusedKey(), 'tv-source-server');

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedKey(), startsWith('tv-source-mode-'));

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(
      <String>['tv-source-paste', 'tv-source-file'],
      contains(focusedKey()),
      reason: 'Haut depuis les modes atteint Coller / Fichier',
    );
    if (focusedKey() == 'tv-source-file') {
      await press(tester, LogicalKeyboardKey.arrowLeft);
    }
    expect(focusedKey(), 'tv-source-paste');

    await press(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('http://panel.invalid:8080'), findsOneWidget);
    expect(find.text('demo'), findsOneWidget);
  });

  testWidgets('un second OK sur Fichier ne relance pas le sélecteur', (
    WidgetTester tester,
  ) async {
    int asked = 0;
    Completer<LocalM3uPick> picker = Completer<LocalM3uPick>();
    await showForm(
      tester,
      pickLocalFile: () {
        asked++;
        return picker.future;
      },
    );

    final Finder file = find.byKey(const ValueKey<String>('tv-source-file'));
    await tester.tap(file);
    await tester.pump();
    await tester.tap(file);
    await tester.pump();
    expect(asked, 1, reason: 'sélecteur ou copie encore en cours');

    picker.complete(const LocalM3uPick(LocalM3uPickStatus.cancelled));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('tv-source-error')), findsNothing);

    picker = Completer<LocalM3uPick>();
    await tester.tap(file);
    await tester.pump();
    expect(asked, 2, reason: 'une fois la réponse reçue, Fichier rouvre');
    picker.complete(const LocalM3uPick(LocalM3uPickStatus.cancelled));
    await tester.pump();
  });

  testWidgets('connexion refusée : le focus revient sur Connexion', (
    WidgetTester tester,
  ) async {
    await showForm(
      tester,
      readClipboard: () async =>
          'http://panel.invalid:8080/get.php?username=demo&password=jeton',
      submit: (OpenSourceDraft draft, String name) async =>
          throw StateError('refus du fournisseur'),
    );
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-paste')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-server')));
    await tester.pump();
    for (int i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focusedKey(), 'tv-source-submit');

    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tv-source-error')), findsOneWidget);
    expect(focusedKey(), 'tv-source-submit', reason: 'OK relance, Haut corrige');

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedKey(), 'tv-source-password');
  });

  testWidgets('fichier refusé à l\'import : le focus revient sur Fichier', (
    WidgetTester tester,
  ) async {
    final Completer<void> refused = Completer<void>();
    await showForm(
      tester,
      pickLocalFile: () async =>
          const LocalM3uPick(LocalM3uPickStatus.ok, path: '/cache/m3u/l.m3u'),
      importLocalFile: (String path) => refused.future,
    );
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp);
    if (focusedKey() == 'tv-source-paste') {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focusedKey(), 'tv-source-file');

    await press(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(focusedKey(), isNot('tv-source-file'), reason: 'exclu pendant l\'import');

    refused.completeError(StateError('liste illisible'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tv-source-error')), findsOneWidget);
    expect(focusedKey(), 'tv-source-file');
  });

  testWidgets('focus parti hors du formulaire pendant l\'import : respecté', (
    WidgetTester tester,
  ) async {
    RemoteSourceRepository.resetImportQueueForTesting();
    final Completer<void> refused = Completer<void>();
    final FocusNode outside = FocusNode();
    addTearDown(outside.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: <Widget>[
              Expanded(
                child: TvSourceEntryForm(
                  readClipboardForTesting: () async =>
                      'http://panel.invalid:8080/get.php?username=demo&password=jeton',
                  submitForTesting: (OpenSourceDraft draft, String name) =>
                      refused.future,
                ),
              ),
              Focus(
                focusNode: outside,
                child: const SizedBox(width: 40, height: 40),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-paste')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('tv-source-submit')));
    await tester.pump();
    outside.requestFocus();
    await tester.pump();

    refused.completeError(StateError('refus du fournisseur'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tv-source-error')), findsOneWidget);
    expect(outside.hasPrimaryFocus, isTrue);
  });
}
