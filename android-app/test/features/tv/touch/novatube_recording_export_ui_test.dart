// Parcours réel de la liste NOVATUBE : export natif attendu jusqu'à sa fin,
// absence de double export et protection du fichier encore utilisé.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/recordings/data/recording_repository.dart';
import 'package:tv_king/features/recordings/domain/recording.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/presentation/tv_recordings_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

final _android = TargetPlatformVariant.only(TargetPlatform.android);
const _gallery = MethodChannel('com.manzilionellm.tvking/gallery');
const _exportKey = ValueKey<String>('novatube-recording-export-1');
const _deleteKey = ValueKey<String>('novatube-recording-delete-1');
const _recording = Recording(
  id: 1,
  channelId: 'fixture-channel',
  channelName: 'Chaîne personnelle',
  filePath: '/fixture/Recordings/chaine-20261111-120000.ts',
  startedAt: 1794398400000,
  endedAt: 1794398460000,
  fileSizeBytes: 2000000,
);

class _Repository implements RecordingRepository {
  _Repository(List<Recording> records) : _records = records;
  List<Recording> _records;
  final _events = StreamController<List<Recording>>.broadcast();
  final List<Recording> deleted = <Recording>[];

  @override
  List<Recording> get current => _records;
  @override
  Stream<List<Recording>> get stream => _events.stream;

  void emit(List<Recording> records) {
    _records = records;
    _events.add(records);
  }

  @override
  Future<void> delete(Recording recording) async {
    deleted.add(recording);
    emit(_records.where((item) => item.id != recording.id).toList());
  }

  Future<void> close() => _events.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _installTestFonts() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) throw StateError('FLUTTER_ROOT nécessaire pour Ahem');
  final ByteData bytes = ByteData.sublistView(
    File('$root/packages/flutter_tools/static/Ahem.ttf').readAsBytesSync(),
  );
  final Map<String, ByteData> fonts = <String, ByteData>{};
  for (final String family in <String>['Inter', 'Oswald', 'JetBrainsMono']) {
    for (final String weight in <String>[
      'Thin',
      'ExtraLight',
      'Light',
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ]) {
      fonts['fonts/$family-$weight.ttf'] = bytes;
    }
  }
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final String key = utf8.decode(message!.buffer.asUint8List(
      message.offsetInBytes,
      message.lengthInBytes,
    ));
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{
        for (final String asset in fonts.keys)
          asset: <Map<String, String>>[
            <String, String>{'asset': asset}
          ],
      });
    }
    if (key == 'AssetManifest.json') {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(
        <String, List<String>>{
          for (final String asset in fonts.keys) asset: <String>[asset],
        },
      ))));
    }
    if (fonts.containsKey(key)) return fonts[key];
    return messenger.delegate.send('flutter/assets', message);
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<void> _mount(WidgetTester tester, _Repository repository,
    {double scale = 1, bool pendingExport = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
        body: TvShell(
      child: TvRecordingsScreen(repository: repository),
    )),
  ));
  if (pendingExport) {
    await tester.pump();
  } else {
    await _settle(tester);
  }
  await tester.runAsync(GoogleFonts.pendingFonts);
  if (pendingExport) {
    await tester.pump();
  } else {
    await _settle(tester);
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
}

AppLocalizations _words(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TvRecordingsScreen)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) response;

  setUpAll(_installTestFonts);
  setUp(() {
    FlavorConfig.setCurrent(FlavorConfig.novatube);
    CastPlatform.configureZuno(ZunoEdition.touch);
    GoogleFonts.config.allowRuntimeFetching = false;
    calls = <MethodCall>[];
    response = (_) async => true;
    messenger.setMockMethodCallHandler(_gallery, (MethodCall call) async {
      calls.add(call);
      return response(call);
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_gallery, null);
    CastPlatform.resetForTesting();
  });
  tearDownAll(() => messenger.setMockMessageHandler('flutter/assets', null));

  testWidgets('export unique, progression réelle et succès à 320dp / texte1.5',
      (tester) async {
    final _Repository repository = _Repository(<Recording>[_recording]);
    addTearDown(repository.close);
    final Completer<bool> native = Completer<bool>();
    addTearDown(() {
      if (!native.isCompleted) native.complete(false);
    });
    response = (_) => native.future;
    await _mount(tester, repository, scale: 1.5);
    final AppLocalizations words = _words(tester);
    final Finder export = find.byKey(_exportKey);
    await tester.ensureVisible(export);
    expect(export.hitTestable(), findsOneWidget);
    await tester.tap(export);
    await tester.pump();
    expect(calls.length, 1);
    expect(calls.single.method, 'exportVideo');
    expect(calls.single.arguments, <String, Object>{
      'srcPath': _recording.filePath,
      'displayName': 'chaine-20261111-120000.mp4',
    });
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(words.tvRecordingExporting), findsOneWidget);
    expect(tester.widget<OutlinedButton>(export).onPressed, isNull);
    expect(tester.widget<TvFocusable>(find.byKey(_deleteKey)).enabled, isFalse);
    await tester.tap(export, warnIfMissed: false);
    await tester.tap(find.byKey(_deleteKey), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    expect(calls.length, 1);
    expect(repository.deleted, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    native.complete(true);
    await _settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(words.tvRecordingExportSuccess), findsOneWidget);
    expect(find.textContaining('7MOTION'), findsNothing);
    expect(tester.widget<OutlinedButton>(export).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  for (final String error in <String>[
    'CONVERSION_FAILED',
    'PERMISSION_DENIED'
  ]) {
    testWidgets('erreur $error lisible puis nouvel essai possible',
        (tester) async {
      final _Repository repository = _Repository(<Recording>[_recording]);
      addTearDown(repository.close);
      response = (_) async => throw PlatformException(
          code: error, message: 'detail_interne_a_ne_pas_afficher');
      await _mount(tester, repository);
      final AppLocalizations words = _words(tester);
      await tester.tap(find.byKey(_exportKey));
      await _settle(tester);
      expect(calls.length, 1);
      expect(
          find.text(error == 'CONVERSION_FAILED'
              ? words.tvRecordingExportFormat
              : words.tvRecordingExportPermission),
          findsOneWidget);
      expect(find.textContaining('detail_interne'), findsNothing);
      expect(find.text(words.tvRecordingExportSuccess), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(_exportKey)).onPressed,
          isNotNull);

      response = (_) async => true;
      await tester.tap(find.byKey(_exportKey));
      await _settle(tester);
      expect(calls.length, 2);
      expect(find.text(words.tvRecordingExportSuccess), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }, variant: _android);
  }

  testWidgets('fichier en cours protégé, actions activées après la fin',
      (tester) async {
    final Recording active = Recording(
      id: _recording.id,
      channelId: _recording.channelId,
      channelName: _recording.channelName,
      filePath: _recording.filePath,
      startedAt: _recording.startedAt,
    );
    final _Repository repository = _Repository(<Recording>[active]);
    addTearDown(repository.close);
    await _mount(tester, repository);
    expect(find.text(_words(tester).tvRecordingFinishBeforeExport),
        findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(_exportKey)).onPressed,
        isNull);
    expect(tester.widget<TvFocusable>(find.byKey(_deleteKey)).enabled, isFalse);
    await tester.tap(find.byKey(_exportKey), warnIfMissed: false);
    await tester.tap(find.byKey(_deleteKey), warnIfMissed: false);
    await _settle(tester);
    expect(calls, isEmpty);
    expect(repository.deleted, isEmpty);
    repository.emit(<Recording>[_recording]);
    await _settle(tester);
    expect(tester.widget<OutlinedButton>(find.byKey(_exportKey)).onPressed,
        isNotNull);
    expect(tester.widget<TvFocusable>(find.byKey(_deleteKey)).enabled, isTrue);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('rouvrir la liste attend le même export natif', (tester) async {
    final _Repository repository = _Repository(<Recording>[_recording]);
    addTearDown(repository.close);
    final Completer<bool> native = Completer<bool>();
    addTearDown(() {
      if (!native.isCompleted) native.complete(false);
    });
    response = (_) => native.future;
    await _mount(tester, repository);
    await tester.tap(find.byKey(_exportKey));
    await tester.pump();
    expect(calls.length, 1);
    await _unmount(tester);
    await _mount(tester, repository, pendingExport: true);
    expect(tester.widget<OutlinedButton>(find.byKey(_exportKey)).onPressed,
        isNull);
    expect(tester.widget<TvFocusable>(find.byKey(_deleteKey)).enabled, isFalse);
    await tester.tap(find.byKey(_exportKey), warnIfMissed: false);
    await tester.tap(find.byKey(_deleteKey), warnIfMissed: false);
    await tester.pump();
    expect(calls.length, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    native.complete(true);
    await _settle(tester);
    expect(find.text(_words(tester).tvRecordingExportSuccess), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('supprimer confirme avant de toucher au fichier', (tester) async {
    final _Repository repository = _Repository(<Recording>[_recording]);
    addTearDown(repository.close);
    await _mount(tester, repository);
    final AppLocalizations words = _words(tester);
    await tester.tap(find.byKey(_deleteKey));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(_exportKey)).onPressed,
        isNull);
    expect(repository.deleted, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, words.tvCancel));
    await _settle(tester);
    expect(repository.deleted, isEmpty);
    expect(tester.widget<OutlinedButton>(find.byKey(_exportKey)).onPressed,
        isNotNull);
    await tester.tap(find.byKey(_deleteKey));
    await _settle(tester);
    await tester.tap(find.widgetWithText(TextButton, words.tvDelete));
    await _settle(tester);
    expect(repository.deleted, <Recording>[_recording]);
    expect(find.byKey(_exportKey), findsNothing);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);
}
