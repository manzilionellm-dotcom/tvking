import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:native_video_player/video_quality.dart';
import 'package:tv_king/features/tv/presentation/tv_playback_quality.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> show(WidgetTester tester, Object? status) async {
    final quality = const NativeVideoQuality(
      sourceWidth: 640, sourceHeight: 360,
      outputWidth: 1280, outputHeight: 720,
    ).withAiPicture(NativeAiPictureStatus.read(status));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: TvPlaybackQuality(quality: quality)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('état absent, actif et refusé ont trois libellés honnêtes', (tester) async {
    await show(tester, null);
    expect(find.text('IA : état inconnu'), findsOneWidget);
    expect(find.text('IA ×2'), findsNothing);
    expect(find.text('Rendu natif'), findsNothing);

    await show(tester, <String, Object?>{
      'active': true, 'reason': null, 'scale': 2,
      'sourceWidth': 640, 'sourceHeight': 360,
      'outputWidth': 1280, 'outputHeight': 720,
      'score': 400, 'p95Ms': 5.3,
    });
    expect(find.text('IA ×2'), findsOneWidget);
    expect(find.text('Sortie lecteur : 1280 × 720 px'), findsOneWidget);
    expect(find.textContaining('Format source : 640 × 360 px'), findsOneWidget);
    expect(find.textContaining('400'), findsNothing);
    expect(find.textContaining('5.3'), findsNothing);

    await show(tester, <String, Object>{'active': false, 'reason': 'TOO_SLOW'});
    expect(find.text('Rendu natif'), findsOneWidget);
    expect(find.byTooltip('Priorité à la fluidité.'), findsOneWidget);
    expect(find.text('IA ×2'), findsNothing);
  });

  testWidgets('modèle présent ou événement incomplet ne deviennent pas IA active', (tester) async {
    await show(tester, <String, Object>{
      'active': true, 'model': 'ArtCNN_C4F16', 'score': 999,
    });
    expect(find.text('IA : état inconnu'), findsOneWidget);
    expect(find.text('IA ×2'), findsNothing);
    await show(tester, <String, Object>{'active': false, 'reason': 'HDR_OR_DRM'});
    expect(find.text('Rendu natif'), findsOneWidget);
    expect(find.byTooltip('Ce format conserve le rendu d’origine.'), findsOneWidget);
  });
}
