import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_channel_loading_status.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> show(
    WidgetTester tester,
    TvChannelLoadingStatus status, {
    String language = 'fr',
    double width = 560,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(child: status),
      ),
    ));
    // Le bandeau indéterminé reste animé jusqu'à réception de faits réseau :
    // pumpAndSettle attendrait à tort une fin que ce test ne déclenche pas.
    await tester.pump();
  }

  testWidgets('vérification : aucun ancien compteur ni pourcentage inventé',
      (tester) async {
    await show(
      tester,
      const TvChannelLoadingStatus(
        checking: true,
        importing: false,
        progress: ImportProgress(ImportStage.done, count: 99999),
      ),
    );
    expect(find.text('Vérification de votre liste…'), findsOneWidget);
    expect(find.textContaining('99 999'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    ).value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('téléchargement : les octets reçus deviennent visibles',
      (tester) async {
    await show(
      tester,
      const TvChannelLoadingStatus(
        checking: true,
        importing: true,
        progress: ImportProgress(ImportStage.downloading, bytes: 5242880),
      ),
    );
    expect(find.text('Téléchargement… 5.0 Mo'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    ).value, isNull);
  });

  testWidgets('les chaînes réellement trouvées sont comptées', (tester) async {
    await show(
      tester,
      const TvChannelLoadingStatus(
        checking: false,
        importing: true,
        progress: ImportProgress(ImportStage.found, count: 12345),
      ),
    );
    expect(find.text('12 345 chaînes trouvées'), findsOneWidget);
    expect(find.text('Vos chaînes se préparent'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    ).value, isNull);
    expect(
      tester.getSize(find.byKey(
        const ValueKey<String>('tv-channel-loading-status'),
      )).height,
      lessThanOrEqualTo(220),
    );
  });

  testWidgets('enregistrement : fraction réelle, puis arrêt sur échec',
      (tester) async {
    const progress = ImportProgress(ImportStage.saving, index: 3000, total: 12000);
    await show(
      tester,
      const TvChannelLoadingStatus(
        checking: true,
        importing: true,
        progress: progress,
      ),
    );
    expect(find.text('12 000 chaînes trouvées'), findsOneWidget);
    expect(find.text('Enregistrement 3 000 / 12 000 chaînes'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    ).value, 0.25);

    await show(
      tester,
      const TvChannelLoadingStatus(
        checking: false,
        importing: false,
        progress: progress,
        result: RemoteSyncResult.sourceFailed,
      ),
    );
    expect(find.text('Impossible de charger cette liste'), findsOneWidget);
    expect(find.textContaining('12 000'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Code pas activé'), findsNothing);
  });

  for (final result in <RemoteSyncResult?>[null, RemoteSyncResult.noSource]) {
    testWidgets('sans liste ($result) : attente claire, aucun import simulé',
        (tester) async {
      await show(
        tester,
        TvChannelLoadingStatus(
          checking: false,
          importing: false,
          progress: const ImportProgress(ImportStage.found, count: 12345),
          result: result,
        ),
      );
      expect(find.text('En attente de votre liste'), findsOneWidget);
      expect(find.textContaining('12 345'), findsNothing);
      expect(find.text('Code pas activé'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  }

  testWidgets('réseau, puis aucun résultat affiché : messages distincts en anglais',
      (tester) async {
    await show(
      tester,
      const TvChannelLoadingStatus(
        checking: false,
        importing: false,
        result: RemoteSyncResult.networkError,
      ),
      language: 'en',
    );
    expect(find.text('No network'), findsOneWidget);
    expect(find.text('Unable to reach the server. Check your connection and try again.'),
        findsOneWidget);
    await show(
      tester,
      const TvChannelLoadingStatus(
        checking: false,
        importing: false,
        result: RemoteSyncResult.loaded,
      ),
      language: 'en',
    );
    expect(find.text('No channels displayed'), findsOneWidget);
    expect(find.text('Code not activated'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  for (final language in <String>['fr', 'en']) {
    testWidgets('320 px, texte à 200 %, $language : aucun débordement',
        (tester) async {
      await show(
        tester,
        const TvChannelLoadingStatus(
          checking: false,
          importing: true,
          progress: ImportProgress(ImportStage.saving, index: 12000, total: 18230),
        ),
        language: language,
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // Le message reste lisible et le bas de la carte accessible par scroll.
      await tester.ensureVisible(find.byType(LinearProgressIndicator));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
