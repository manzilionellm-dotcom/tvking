import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/tv/presentation/tv_epg_preview_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

Channel _ch(String id, String name) => Channel(
      id: id,
      name: name,
      category: 'FR',
      streamUrl: 'http://example.invalid/$id',
      isLive: true,
    );

EpgProgram _slot(String id, String title, int hour) => EpgProgram(
      channelId: id,
      startTime: DateTime(2026, 11, 4, hour).millisecondsSinceEpoch,
      stopTime: DateTime(2026, 11, 4, hour + 1).millisecondsSinceEpoch,
      title: title,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    // Les tests n'ont pas le réseau : on charge les polices déjà
    // embarquées, sous les noms que google_fonts demande.
    Future<void> load(String family, String asset) async {
      final FontLoader loader = FontLoader(family)
        ..addFont(rootBundle.load(asset));
      await loader.load();
    }

    await load('Inter_regular', 'assets/fonts/Inter-Regular.ttf');
    await load('Inter_600', 'assets/fonts/Inter-SemiBold.ttf');
  });

  testWidgets('le guide montre le programme et l\'aperçu de la chaîne', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: TvEpgPreviewScreen(
          channels: <Channel>[_ch('a', 'TF1'), _ch('b', 'France 2')],
          loadWindow: (String id) async => TvEpgWindow(
            now: _slot(id, id == 'a' ? 'Journal' : 'Météo', 20),
            next: _slot(id, 'Suite', 21),
          ),
          preview: (Channel c) => ColoredBox(
            color: const Color(0xFF141416),
            child: Center(
              child: Text(
                'aperçu ${c.name}',
                style: const TextStyle(
                  fontFamily: 'Inter_regular',
                  color: Color(0xFFF4F1E8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Guide'), findsOneWidget);
    expect(find.text('Journal'), findsOneWidget);
    expect(find.text('aperçu TF1'), findsOneWidget);
    expect(find.text('Suite'), findsOneWidget);

    await expectLater(
      find.byType(TvEpgPreviewScreen),
      matchesGoldenFile('goldens/tv_epg_preview.png'),
    );
  });
}
