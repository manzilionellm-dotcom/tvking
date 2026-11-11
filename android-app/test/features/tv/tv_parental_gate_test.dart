import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/presentation/tv_parental_gate.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

int _disposed = 0;

class _CachedProfile extends StatefulWidget {
  const _CachedProfile();
  @override
  State<_CachedProfile> createState() => _CachedProfileState();
}

class _CachedProfileState extends State<_CachedProfile> {
  late final String profile = ActiveProfile.instance.id;
  @override
  Widget build(BuildContext context) => Text('cache:$profile');
  @override
  void dispose() {
    _disposed++;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controls = ParentalControls.instance;
  final profiles = ProfileRepository.instance;
  late ProfileCatalog family;
  late SharedPreferences prefs;
  setUp(() async {
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    AppPlatform.isZuno = false;
    controls.resetProtectionForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    family =
        ProfileCatalog.fresh().add(name: 'Enfant', isKids: true, nowMs: 2)!;
    profiles.resetForTesting(family);
    AppPlatform.configureZuno(isAndroidHandset: false);
    _disposed = 0;
  });
  tearDown(() {
    AppPlatform.isZuno = false;
    controls.resetProtectionForTesting();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: GlobalKey<NavigatorState>(),
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => TvParentalGate(child: child!),
      home: const Scaffold(body: _CachedProfile()),
    ));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('première image Enfants pendant lecture : aucun ancien catalogue',
      (tester) async {
    profiles.resetForTesting(family.activate(family.profiles.last.id)!);
    final pending = Completer<SharedPreferences>();
    ParentalControls.preferencesForTesting = () => pending.future;
    final load = controls.load();
    await show(tester);
    expect(find.textContaining('cache:'), findsNothing);
    expect(controls.kidsMode.value, isTrue);
    pending.complete(prefs);
    await load;
    await tester.pump();
    expect(find.text('cache:${family.profiles.last.id}'), findsOneWidget);
    await close(tester);
  });

  testWidgets('budget 300 ms expiré : attente maintenue jusqu’à confirmation',
      (tester) async {
    final pending = Completer<SharedPreferences>();
    ParentalControls.preferencesForTesting = () => pending.future;
    var budgetEnded = false;
    unawaited(controls.loadBeforeFirstFrame().then((_) => budgetEnded = true));
    await show(tester);
    await tester.pump(const Duration(milliseconds: 301));
    expect(budgetEnded, isTrue);
    expect(controls.contentReady, isFalse);
    expect(find.textContaining('cache:'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('cache:'), findsNothing);
    pending.complete(prefs);
    await tester.runAsync(() async {});
    await tester.pump();
    await tester.pump();
    expect(controls.contentReady, isTrue,
        reason: '${controls.readiness.value}, ${ActiveProfile.instance.id}, '
            'profil confirmé : ${profiles.activeProfileConfirmed}');
    expect(find.text('cache:p1'), findsOneWidget);
    await close(tester);
  });

  testWidgets('erreur disque : aucune route ; réessayer conserve les données',
      (tester) async {
    await prefs.setString('fixture.sentinel', 'conservé');
    ParentalControls.preferencesForTesting =
        () async => throw StateError('lecture indisponible');
    await tester.runAsync(controls.loadBeforeFirstFrame);
    await show(tester);
    expect(find.textContaining('cache:'), findsNothing);
    expect(find.text('Réessayer'), findsOneWidget);
    ParentalControls.preferencesForTesting = () async => prefs;
    await tester.tap(find.text('Réessayer'));
    await tester.runAsync(() async {});
    await tester.pump();
    await tester.pump();
    expect(find.text('cache:p1'), findsOneWidget);
    expect(prefs.getString('fixture.sentinel'), 'conservé');
    await close(tester);
  });

  testWidgets(
      'adulte vers Enfants : Navigator précédent démonté, même GlobalKey',
      (tester) async {
    await tester.runAsync(controls.loadBeforeFirstFrame);
    await show(tester);
    expect(find.text('cache:p1'), findsOneWidget);
    final child = family.profiles.last.id;
    profiles.resetForTesting(family.activate(child)!);
    await tester.pump();
    expect(find.text('cache:p1'), findsNothing);
    await tester.runAsync(controls.load);
    await tester.pump();
    await tester.pump();
    expect(find.text('cache:$child'), findsOneWidget);
    expect(_disposed, 1);
    await close(tester);
  });

  testWidgets('réponse adulte tardive ne remplace pas les restrictions enfant',
      (tester) async {
    final old = Completer<SharedPreferences>();
    ParentalControls.preferencesForTesting = () => old.future;
    final oldLoad = controls.load();
    await show(tester);
    ParentalControls.preferencesForTesting = () async => prefs;
    profiles.resetForTesting(family.activate(family.profiles.last.id)!);
    await tester.runAsync(controls.load);
    await tester.pump();
    expect(controls.kidsMode.value, isTrue);
    old.complete(prefs);
    await oldLoad;
    await tester.pump();
    expect(controls.kidsMode.value, isTrue);
    expect(find.text('cache:p1'), findsNothing);
    await close(tester);
  });

  testWidgets('profil persistant illisible : aucune réparation écrite ni accès',
      (tester) async {
    await prefs.setString(ProfileKeys.catalog, '{cassé');
    profiles.resetForTesting(ProfileCatalog.fresh(), loaded: false);
    await tester.runAsync(controls.loadBeforeFirstFrame);
    await show(tester);
    expect(profiles.activeProfileConfirmed, isFalse);
    expect(controls.contentReady, isFalse);
    expect(find.textContaining('cache:'), findsNothing);
    expect(prefs.getString(ProfileKeys.catalog), '{cassé');
    await close(tester);
  });

  testWidgets('fermeture de la barrière libère ses abonnements',
      (tester) async {
    await tester.runAsync(controls.loadBeforeFirstFrame);
    await show(tester);
    await close(tester);
    profiles.resetForTesting(family.activate(family.profiles.last.id)!);
    await tester.runAsync(controls.load);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
