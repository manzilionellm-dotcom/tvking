import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:native_video_player/video_quality.dart';
import 'package:tv_king/features/tv/presentation/tv_playback_quality.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> show(WidgetTester tester, NativeVideoQuality quality) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Column(children: <Widget>[
        // Une promesse commerciale voisine ne doit jamais devenir une mesure.
        const Text('Chaîne 4K HEVC HDR 60FPS AI'),
        TvPlaybackQuality(quality: quality),
      ])),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('nom 4K/60/IA, vraie source et sortie 720, cadence 24 comptée', (tester) async {
    final quality = const NativeVideoQuality()
        .withSourceFormat(<String, Object>{
          'width': 1280, 'height': 720, 'mimeType': 'video/avc', 'frameRate': 60,
        })
        .withVideoSize(<String, int>{'width': 1280, 'height': 720})
        .withCadence(<String, int>{
          'renderedFrames': 48, 'droppedFrames': 2, 'windowMs': 2000,
        });
    await show(tester, quality);
    expect(find.text('Sortie lecteur : 1280 × 720 px'), findsOneWidget);
    expect(find.text('Format source : 1280 × 720 px · H.264 · HDR/SDR non renseigné'), findsOneWidget);
    expect(find.text('Sortie décodeur : 24,0 images/s · 2 perdues / 2,0 s'), findsOneWidget);
    final labels = tester.widgetList<Text>(find.descendant(
      of: find.byType(TvPlaybackQuality), matching: find.byType(Text),
    )).map((text) => text.data).join(' ');
    expect(labels, isNot(contains('4K')));
    expect(labels, isNot(contains('HEVC')));
    expect(labels, isNot(contains('60')));
    expect(labels, isNot(contains('AI')));
  });

  testWidgets('inconnu reste inconnu et une sortie agrandie reste distincte de la source', (tester) async {
    await show(tester, const NativeVideoQuality());
    expect(find.text('Sortie lecteur : mesure indisponible'), findsOneWidget);
    expect(find.text('Format source : codec inconnu · HDR/SDR non renseigné'), findsOneWidget);
    expect(find.textContaining('Sortie décodeur'), findsNothing);
    await show(tester, const NativeVideoQuality()
        .withSourceFormat(<String, Object>{
          'width': 1280, 'height': 720, 'mimeType': 'video/avc', 'dynamicRange': 'sdr',
        })
        .withVideoSize(<String, int>{'width': 2560, 'height': 1440}));
    expect(find.text('Sortie lecteur : 2560 × 1440 px'), findsOneWidget);
    expect(find.text('Format source : 1280 × 720 px · H.264 · SDR'), findsOneWidget);
    expect(find.textContaining('Sortie décodeur'), findsNothing);
  });
}
