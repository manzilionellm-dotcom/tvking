import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/presentation/tv_adult_section_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

Future<AdultAccessGrant?> _authorize() => authenticateAdultAccess(
      reason: 'Test entrée adulte',
      confirmPin: () async => true,
    );

Widget _app(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[TvAppTokens(ghost: true)],
      ),
      home: Scaffold(body: home),
    );

Widget _launcher({
  required Future<AdultAccessGrant?> Function() authenticate,
  Widget Function(AdultAccessGrant)? section,
}) =>
    Builder(
      builder: (context) => TextButton(
        onPressed: () => unawaited(openTvAdultSection(context,
            authenticateForTesting: authenticate,
            sectionBuilderForTesting: section)),
        child: const Text('Ouvrir'),
      ),
    );

void _back(WidgetTester tester, String text) =>
    Navigator.of(tester.element(find.text(text).first)).pop();

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRepository.instance.resetForTesting(ProfileCatalog(
      profiles: <FamilyProfile>[FamilyProfile.origin()],
      activeId: ProfileIds.origin,
      askOnStartup: null,
    ));
    ParentalControls.instance.kidsMode.value = false;
  });

  testWidgets('attente et annulation ne construisent aucune rubrique',
      (tester) async {
    final pending = Completer<AdultAccessGrant?>();
    int built = 0;
    await tester.pumpWidget(_app(_launcher(
      authenticate: () => pending.future,
      section: (_) {
        built++;
        return const Text('Ne doit pas apparaître');
      },
    )));
    await tester.tap(find.text('Ouvrir'));
    await tester.pump();
    expect(built, 0);
    expect(find.byType(TvAdultSectionScreen), findsNothing);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(built, 0);
    expect(find.text('Ouvrir'), findsOneWidget);
  });

  testWidgets('deux rubriques distinctes partagent le droit de la visite',
      (tester) async {
    AdultAccessGrant? current =
        await tester.runAsync<AdultAccessGrant?>(_authorize);
    int authCalls = 0;
    int liveBuilds = 0;
    int cinemaBuilds = 0;
    await tester.pumpWidget(_app(_launcher(
      authenticate: () async {
        authCalls++;
        return current;
      },
      section: (grant) => TvAdultSectionScreen(
        adultAccess: grant,
        liveBuilderForTesting: (received) {
          expect(identical(received, grant), isTrue);
          liveBuilds++;
          return const Text('Catalogue direct');
        },
        cinemaBuilderForTesting: (received) {
          expect(identical(received, grant), isTrue);
          cinemaBuilds++;
          return const Text('Catalogue cinéma');
        },
      ),
    )));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Direct adulte'), findsOneWidget);
    expect(find.text('Cinéma adulte'), findsOneWidget);
    expect(liveBuilds + cinemaBuilds, 0);
    // Le premier choix est également utilisable à la télécommande.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Catalogue direct'), findsOneWidget);
    expect(cinemaBuilds, 0);
    _back(tester, 'Catalogue direct');
    await tester.pumpAndSettle();
    expect(current!.isValid, isTrue);
    await tester.tap(find.text('Cinéma adulte'));
    await tester.pumpAndSettle();
    expect(find.text('Catalogue cinéma'), findsOneWidget);
    expect(authCalls, 1);
    _back(tester, 'Catalogue cinéma');
    await tester.pumpAndSettle();
    final previous = current!;
    _back(tester, 'Adultes');
    await tester.pumpAndSettle();
    expect(previous.isValid, isFalse);
    current = await tester.runAsync<AdultAccessGrant?>(_authorize);
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(authCalls, 2);
    expect(identical(current, previous), isFalse);
    _back(tester, 'Adultes');
    await tester.pumpAndSettle();
  });

  testWidgets('un changement de listes ferme aussi la rubrique ouverte',
      (tester) async {
    AdultAccessGrant? current =
        await tester.runAsync<AdultAccessGrant?>(_authorize);
    await tester.pumpWidget(_app(_launcher(
      authenticate: () async => current,
      section: (grant) => TvAdultSectionScreen(
        adultAccess: grant,
        liveBuilderForTesting: (_) => const Text('Catalogue direct'),
      ),
    )));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direct adulte'));
    await tester.pumpAndSettle();
    ActiveProfile.instance.set(ProfileIds.origin, playlistIds: const <int>[7]);
    await tester.pumpAndSettle();
    expect(current!.isValid, isFalse);
    expect(find.text('Catalogue direct'), findsNothing);
    expect(find.text('Direct adulte'), findsNothing);
    expect(find.text('Ouvrir'), findsOneWidget);
  });

  testWidgets('mode enfants refuse l’entrée avant même le dialogue',
      (tester) async {
    int attempts = 0;
    ParentalControls.instance.kidsMode.value = true;
    await tester.pumpWidget(_app(_launcher(authenticate: () async {
      attempts++;
      return null;
    })));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    expect(find.byType(TvAdultSectionScreen), findsNothing);
  });

  testWidgets('un grant révoqué pendant la demande reste fermé',
      (tester) async {
    final grant = await tester.runAsync<AdultAccessGrant?>(_authorize);
    expect(grant, isNotNull);
    final pending = Completer<AdultAccessGrant?>();
    await tester
        .pumpWidget(_app(_launcher(authenticate: () => pending.future)));
    await tester.tap(find.text('Ouvrir'));
    await tester.pump();
    grant!.revoke();
    pending.complete(grant);
    await tester.pumpAndSettle();
    expect(find.byType(TvAdultSectionScreen), findsNothing);
    expect(find.text('Ouvrir'), findsOneWidget);
  });

  testWidgets('deux choix lisibles sur téléphone en portrait', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final grant = await tester.runAsync<AdultAccessGrant?>(_authorize);
    await tester.pumpWidget(_app(_launcher(authenticate: () async => grant)));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Direct adulte'), findsOneWidget);
    expect(find.text('Cinéma adulte'), findsOneWidget);
    expect(tester.takeException(), isNull);
    _back(tester, 'Adultes');
    await tester.pumpAndSettle();
  });
}
