import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/playlists/data/channel_limit_snapshot.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/presentation/tv_catalog_limit_notice.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import '../playlists/channel_limit_fixture.dart';

ChannelLimitSnapshot _snapshot({bool importOnly = false}) =>
    ChannelLimitSnapshot(
      profileId: ActiveProfile.instance.id,
      scope: ActiveProfile.instance.scopeListenable.value,
      limit: 50000,
      sources: importOnly
          ? [
              const ChannelLimitSource(
                playlistId: 1,
                name: 'Import test',
                storedRows: 50000,
                loadedRows: 50000,
                loadedChannels: 50000,
                importCounts: M3uImportCounts(
                  validEntries: 50003,
                  retainedEntries: 50000,
                ),
              ),
            ]
          : [
              for (var id = 1; id <= 4; id++)
                ChannelLimitSource(
                  playlistId: id,
                  name: 'Source $id',
                  storedRows: 25000,
                  loadedRows: id < 3 ? 25000 : 0,
                  loadedChannels: id < 3 ? 25000 : 0,
                ),
            ],
    );

Widget _app() => MaterialApp(
  locale: const Locale('fr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData.dark(),
  home: const Scaffold(body: TvCatalogLimitNotice()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = PlaylistRepository.instance;
  final controls = ParentalControls.instance;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final font in {
      'Inter_regular': 'Inter-Regular.ttf',
      'Inter_500': 'Inter-Medium.ttf',
      'Inter_600': 'Inter-SemiBold.ttf',
      'Inter_700': 'Inter-Bold.ttf',
    }.entries) {
      await (FontLoader(
        font.key,
      )..addFont(rootBundle.load('assets/fonts/${font.value}'))).load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppPlatform.isZuno = true;
    RepairFlags.debugReset();
    controls.resetProtectionForTesting();
    ProfileRepository.instance.resetForTesting(
      ChannelLimitFixture.catalog(ids: [1, 2, 3, 4]),
    );
    controls.protectZunoBeforeProfile();
    await controls.load();
    repo.channelLimitSnapshot.value = _snapshot();
  });
  tearDown(() {
    repo.channelLimitSnapshot.value = null;
    controls.resetProtectionForTesting();
    RepairFlags.debugReset();
    AppPlatform.isZuno = false;
  });

  testWidgets(
    'adulte : compteurs réels et sources affectées dans les détails',
    (tester) async {
      await tester.pumpWidget(_app());
      expect(find.textContaining('100000 lignes enregistrées'), findsOneWidget);
      expect(find.textContaining('Source 3 · Source 4'), findsOneWidget);
      expect(find.textContaining('Source 1'), findsNothing);
      await tester.tap(find.text('Détails'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Source 3 : 25000 lignes enregistrées, 0 lues, 0 chaînes chargées.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Source 4 : 25000 lignes enregistrées, 0 lues, 0 chaînes chargées.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('n’efface aucune donnée'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Enfants : aucun nom de source, nombre ni bouton de détails', (
    tester,
  ) async {
    ProfileRepository.instance.resetForTesting(
      ChannelLimitFixture.catalog(ids: [1, 2, 3, 4], kids: true),
    );
    await controls.load();
    repo.channelLimitSnapshot.value = _snapshot();
    await tester.pumpWidget(_app());
    expect(find.textContaining('Un adulte peut consulter'), findsOneWidget);
    expect(find.textContaining('Source'), findsNothing);
    expect(find.textContaining('100000'), findsNothing);
    expect(find.text('Détails'), findsNothing);
  });

  testWidgets(
    'import : les trois entrées ignorées ne sont pas des lignes stockées',
    (tester) async {
      repo.channelLimitSnapshot.value = _snapshot(importOnly: true);
      await tester.pumpWidget(_app());
      expect(find.textContaining('50000 lignes enregistrées'), findsOneWidget);
      await tester.tap(find.text('Détails'));
      await tester.pumpAndSettle();
      expect(find.textContaining('50003 entrées valides'), findsOneWidget);
      expect(find.textContaining('3 non importées'), findsOneWidget);
      expect(find.textContaining('n’efface aucune donnée'), findsNothing);
    },
  );

  testWidgets(
    'dialogue adulte ouvert : la bascule Enfants retire ses détails',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.tap(find.text('Détails'));
      await tester.pumpAndSettle();
      ProfileRepository.instance.resetForTesting(
        ChannelLimitFixture.catalog(ids: [1, 2, 3, 4], kids: true),
      );
      await tester.pump();
      expect(find.textContaining('Source 3'), findsNothing);
      expect(find.textContaining('100000'), findsNothing);
      expect(find.textContaining('Un adulte peut consulter'), findsWidgets);
    },
  );

  testWidgets('lecture en attente ou en erreur : état générique uniquement', (
    tester,
  ) async {
    for (final state in [ParentalReadiness.loading, ParentalReadiness.failed]) {
      controls.readiness.value = state;
      await tester.pumpWidget(_app());
      await tester.pump();
      expect(find.textContaining('Un adulte peut consulter'), findsOneWidget);
      expect(find.textContaining('Source'), findsNothing);
      expect(find.textContaining('100000'), findsNothing);
    }
  });

  testWidgets(
    'ancienne portée : dialogue fermé, abonnement libéré à la sortie',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.tap(find.text('Détails'));
      await tester.pumpAndSettle();
      ActiveProfile.instance.set('autre', playlistIds: [4]);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Catalogue limité'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      // Une notification après fermeture ne doit plus appeler le State du
      // bandeau ou du dialogue détruit : une fuite provoquerait une erreur
      // Flutter (« setState après dispose »). Aucun membre protégé n'est lu.
      repo.channelLimitSnapshot.value = _snapshot();
      repo.channelLimitSnapshot.value = null;
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ancien bouton : permission relue avant ouverture indirecte',
      (tester) async {
    await tester.pumpWidget(_app());
    final callback = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Détails')).onPressed!;
    // Le callback appartient encore au bouton adulte, sans reconstruction.
    controls.readiness.value = ParentalReadiness.failed;
    callback();
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Source'), findsNothing);
    expect(find.textContaining('100000'), findsNothing);
  });

  testWidgets(
    'repli du bandeau et 7 MOTION : aucun affichage, snapshot intact',
    (tester) async {
      final snapshot = repo.channelLimitSnapshot.value;
      RepairFlags.catalogLimitNoticeOff = true;
      await tester.pumpWidget(_app());
      expect(find.text('Catalogue limité'), findsNothing);
      expect(repo.channelLimitSnapshot.value, same(snapshot));
      await tester.pumpWidget(const SizedBox.shrink());
      RepairFlags.catalogLimitNoticeOff = false;
      AppPlatform.isZuno = false;
      await tester.pumpWidget(_app());
      expect(find.text('Catalogue limité'), findsNothing);
      expect(repo.channelLimitSnapshot.value, same(snapshot));
    },
  );

  testWidgets('7 MOTION : le cadre conserve les contraintes du contenu',
      (tester) async {
    AppPlatform.isZuno = false;
    const contentKey = ValueKey('contenu-historique');
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TvCatalogLimitFrame(
            child: SizedBox(key: contentKey, height: 40),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(contentKey)).height, 40);
    expect(find.text('Catalogue limité'), findsNothing);
  });
}
