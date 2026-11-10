// Régression du vrai écran Direct 117 : un ordre extérieur met à jour les
// compteurs déjà visibles, puis les chaînes remplacent l'attente sans changer
// les trois colonnes historiques. Aucun serveur ni flux réel n'est contacté.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:native_video_player/playback_lease.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_type.dart';
import 'package:tv_king/features/tv/presentation/tv_channel_loading_status.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_live_preview.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_scaled_viewport.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/features/tv/presentation/tv_source_entry_form.dart';
import 'package:tv_king/features/tv/presentation/tv_source_setup.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const _captureKey = Key('direct-117-capture');

/// Export facultatif des vrais widgets : la CI normale n'écrit aucune image.
/// Exemple : ZUNO_CAPTURE_DIR=/tmp/zuno-captures flutter test ce_fichier.dart.
Future<void> _captureDirect(WidgetTester tester) async {
  final String? directory = Platform.environment['ZUNO_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  // Les fontes embarquées et le guide SQLite doivent avoir terminé avant
  // l'image. Le verrou d'aperçu interdit tout lecteur durant cette capture.
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final ui.Image? image = await tester.runAsync(
    () => boundary.toImage(pixelRatio: 1),
  );
  if (image == null) throw StateError('Capture Direct indisponible');
  try {
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    if (bytes == null) throw StateError('Encodage de la capture impossible');
    await tester.runAsync(() async {
      await Directory(directory).create(recursive: true);
      await File('$directory/zuno-117-direct-noir-fantome-fixture.png')
          .writeAsBytes(bytes.buffer.asUint8List());
    });
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (Platform.environment['ZUNO_CAPTURE_DIR']?.isNotEmpty == true) {
      // Les widget tests n'installent pas la fonte des icônes par défaut.
      // On prend la vraie fonte du SDK employé pour le test, sans substitut.
      final String? sdk = Platform.environment['FLUTTER_ROOT'];
      if (sdk == null || sdk.isEmpty) {
        throw StateError('FLUTTER_ROOT requis pour la capture des icônes');
      }
      final bytes = await File(
        '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    await PlaylistDatabase.instance.database;
  });

  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
  });

  setUp(() {
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:12:34:AB:CD:56',
    });
    RepairFlags.debugReset();
    RemoteSourceRepository.importing.value = false;
    RemoteSourceRepository.syncing.value = false;
    RemoteSourceRepository.manualImporting.value = false;
    RemoteSourceRepository.lastResult.value = null;
    RemoteSourceRepository.resetImportQueueForTesting();
    ImportProgressBus.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.manzilionellm.tvking/device'),
      (MethodCall call) async => call.method == 'getAndroidId'
          ? 'fixture-device-only'
          : <String, String>{},
    );
  });

  tearDown(() {
    RemoteSourceRepository.importing.value = false;
    RemoteSourceRepository.syncing.value = false;
    RemoteSourceRepository.manualImporting.value = false;
    RemoteSourceRepository.lastResult.value = null;
    ImportProgressBus.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.manzilionellm.tvking/device'), null);
  });

  testWidgets(
    'Direct 117 : progression externe, erreur puis chaînes dans les trois colonnes',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ForegroundPlayback.lock();
      addTearDown(ForegroundPlayback.unlock);
      await http.runWithClient(() async {
        const palette = TvAppTokens(ghost: true);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: palette.bg,
            textTheme: TvType.material(palette.text),
            colorScheme: ColorScheme.dark(
              surface: palette.card,
              primary: palette.accent,
            ),
            extensions: const <ThemeExtension<dynamic>>[palette],
          ),
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const RepaintBoundary(
            key: _captureKey,
            child: TvScaledViewport(
              child: Scaffold(body: TvShell(child: TvLiveScreen())),
            ),
          ),
        ));
        await tester.runAsync(GoogleFonts.pendingFonts);
        // La première lecture est une vraie sync HTTP/SQLite simulée. On
        // attend son issue avant d'émettre un nouvel ordre depuis l'extérieur.
        await tester.pump(const Duration(seconds: 9));
        await tester.pumpAndSettle();
        final BuildContext context = tester.element(find.byType(TvLiveScreen));
        final AppLocalizations words = AppLocalizations.of(context)!;
        expect(MediaQuery.sizeOf(context), const Size(1280, 720));
        expect(
            RemoteSourceRepository.lastResult.value, RemoteSyncResult.noSource);
        expect(find.text(words.tvChannelWaitingTitle), findsOneWidget);
        expect(find.text(words.tvCodeInactive), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);

        final Finder form = find.byType(TvSourceEntryForm);
        final State<StatefulWidget> formState = tester.state(form);
        final Finder server = find.descendant(
          of: find.byKey(const ValueKey<String>('tv-source-server')),
          matching: find.byType(TextField),
        );
        await tester.enterText(server, 'https://fixture.invalid:8080');

        // Aucun bouton local n'est actionné : ces notifiers sont exactement
        // ceux publiés par l'import lancé depuis le canal panel/WebSocket.
        RemoteSourceRepository.syncing.value = true;
        RemoteSourceRepository.importing.value = true;
        ImportProgressBus.connecting();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(TvChannelLoadingStatus), findsOneWidget);
        expect(find.text(words.tvImpConnecting), findsOneWidget);
        expect(find.text(words.tvChannelWaitingTitle), findsNothing);
        expect(tester.state(form), same(formState));
        expect(tester.widget<TextField>(server).controller!.text,
            'https://fixture.invalid:8080');
        final Finder submit =
            find.byKey(const ValueKey<String>('tv-source-submit'));
        expect(tester.widget<TvCtaButton>(submit).onSelect, isNull);

        ImportProgressBus.set(
          const ImportProgress(ImportStage.downloading, bytes: 5 * 1024 * 1024),
          force: true,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(words.tvImpDownloading('5.0')), findsOneWidget);
        expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value,
            isNull);

        ImportProgressBus.set(
          const ImportProgress(ImportStage.category,
              index: 2, total: 8, count: 1200),
          force: true,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
            find.text(words.tvImpCategory('2', '8', '1 200')), findsOneWidget);

        ImportProgressBus.set(
          const ImportProgress(ImportStage.saving, index: 1200, total: 2400),
          force: true,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(words.tvImpSaving('1 200', '2 400')), findsOneWidget);
        expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value,
            0.5);
        expect(tester.takeException(), isNull);

        // L'erreur termine l'import, même si son ancien dernier compteur
        // reste dans le bus. Le formulaire et les saisies restent en place.
        RemoteSourceRepository.importing.value = false;
        RemoteSourceRepository.lastResult.value = RemoteSyncResult.sourceFailed;
        RemoteSourceRepository.syncing.value = false;
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(words.tvChannelSourceFailedTitle), findsOneWidget);
        expect(find.text(words.tvImpSaving('1 200', '2 400')), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.state(form), same(formState));
        expect(tester.widget<TvCtaButton>(submit).onSelect, isNotNull);

        // La nouvelle vérification remplace immédiatement l'ancienne erreur.
        RemoteSourceRepository.syncing.value = true;
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(words.tvChannelCheckingTitle), findsOneWidget);
        expect(find.text(words.tvChannelSourceFailedTitle), findsNothing);
        expect(find.text(words.tvImpSaving('1 200', '2 400')), findsNothing);

        // Le vrai dépôt importe une minuscule liste factice et émet son flux.
        // L'écran ouvert doit basculer tout seul vers son layout 117 existant.
        RemoteSourceRepository.importing.value = true;
        await tester.runAsync(() async {
          final saved = await PlaylistRepository.instance.addM3uPlaylist(
            name: 'Fixture Direct',
            url: 'https://fixture.invalid/list.m3u',
            httpClient: MockClient((_) async => http.Response(
                  '#EXTM3U\n#EXTINF:-1 tvg-id="fixture-live" group-title="Fixture Groupe",Fixture Direct\n'
                  'https://fixture.invalid/stream.ts\n',
                  200,
                )),
          );
          expect(saved.channelCount, 1);
        });
        RemoteSourceRepository.lastResult.value = RemoteSyncResult.loaded;
        RemoteSourceRepository.importing.value = false;
        RemoteSourceRepository.syncing.value = false;
        // Reste sous le délai de 1,5 s de l'aperçu natif : aucun lecteur ni
        // accès à l'URL factice n'est lancé pour ce contrôle de disposition.
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byType(TvSourceSetup), findsNothing);
        expect(find.byType(TvChannelLoadingStatus), findsNothing);
        expect(find.byType(TvLivePreview), findsOneWidget);
        expect(find.text('Fixture Direct'), findsWidgets);
        final Row columns = tester.widget<Row>(find
            .descendant(
              of: find.byType(TvLiveScreen),
              matching: find.byType(Row),
            )
            .first);
        expect(columns.children, hasLength(5));
        expect((columns.children.first as SizedBox).width, 300);
        expect((columns.children.last as SizedBox).width, 470);
        expect(tester.takeException(), isNull);
        await _captureDirect(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        ImportProgressBus.done(1);
        RemoteSourceRepository.lastResult.value = RemoteSyncResult.networkError;
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
          () => MockClient((http.Request request) async {
                if (request.url.path.startsWith('/api/device-source/')) {
                  return http.Response('{"sources":[]}', 200);
                }
                return http.Response('{}', 503);
              }));
    },
  );
}
