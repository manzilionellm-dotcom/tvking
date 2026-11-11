// Capture explicite du nouvel avertissement avec une vraie fixture SQLite
// 4 × 25 000 lignes. Ce fichier n'est pas lancé par la suite ordinaire.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/core/theme/app_colors.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/core/tv_type.dart';
import 'package:tv_king/features/tv/presentation/tv_catalog_limit_notice.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import '../playlists/channel_limit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('ZUNO_L1_CAPTURE_DIR');
  setUpAll(() async {
    if (output.isEmpty) throw StateError('ZUNO_L1_CAPTURE_DIR requis');
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final entry in {
      'Inter_regular': 'Inter-Regular.ttf',
      'Inter_500': 'Inter-Medium.ttf',
      'Inter_600': 'Inter-SemiBold.ttf',
      'Inter_700': 'Inter-Bold.ttf',
    }.entries) {
      final font = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
      await font.load();
    }
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk == null) throw StateError('FLUTTER_ROOT requis');
    final bytes = await File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await icons.load();
    await ChannelLimitFixture.setUpAll();
    await PlaylistRepository.instance.initialize();
    await ParentalControls.instance.load();
  });
  tearDownAll(ChannelLimitFixture.tearDownAll);

  testWidgets('L1-04 : captures bandeau et détail des quatre sources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: child!,
          ),
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: AppColors.stealthBlack,
            textTheme: TvType.material(AppColors.textPrimary),
          ),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: TvCatalogLimitNotice(),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(GoogleFonts.pendingFonts);
    await tester.pumpAndSettle();
    final snapshot = PlaylistRepository.instance.channelLimitSnapshot.value!;
    expect(snapshot.storedRows, 100000);
    expect(snapshot.loadedRows, 50000);
    expect(snapshot.affectedSources.map((source) => source.name), [
      'Source 3',
      'Source 4',
    ]);
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          final file = File('$output/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    await capture('limite-bandeau');
    await tester.tap(find.text('Détails'));
    await tester.pumpAndSettle();
    await capture('limite-details');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
