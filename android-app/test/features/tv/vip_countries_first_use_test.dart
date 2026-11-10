import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/data/vip_countries_first_use.dart';
import 'package:tv_king/features/tv/data/vip_countries_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_vip_countries_first_use.dart';
import 'package:tv_king/features/tv/presentation/tv_vip_countries_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const hint = 'Choisis tes pays ici. Tu pourras les modifier à tout moment.';
const buttonKey = Key('existing-country-button');
const categoriesKey = Key('existing-categories');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VipCountriesFirstUse store;
  final navigator = GlobalKey<NavigatorState>();
  final available = ValueNotifier<bool>(false);
  final playing = ValueNotifier<bool>(false);

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    ActiveProfile.instance.set('hint-a');
    store = VipCountriesFirstUse();
    available.value = false;
    playing.value = false;
    RemoteSourceRepository.importing.value = false;
    RemoteSourceRepository.manualImporting.value = false;
    RemoteSourceRepository.syncing.value = false;
    ImportProgressBus.clear();
  });

  tearDown(() {
    ActiveProfile.instance.set(ProfileIds.origin);
    RemoteSourceRepository.importing.value = false;
    RemoteSourceRepository.manualImporting.value = false;
    RemoteSourceRepository.syncing.value = false;
    ImportProgressBus.clear();
  });

  Future<void> show(WidgetTester tester, {bool wrapped = true}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark()
          .copyWith(extensions: const [TvAppTokens(ghost: true)]),
      home: Scaffold(body: Builder(builder: (context) {
        Widget button(VoidCallback? open) => TvCtaButton(
              key: buttonKey,
              label: 'Mes pays · VIP',
              onSelect: open,
            );
        void open() => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
                body: TvVipCountriesScreen(available: {'fr': 3, 'rs': 2}))));
        return ListenableBuilder(
          listenable: Listenable.merge([available, playing]),
          builder: (context, _) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 300,
                child: Column(children: [
                  if (wrapped)
                    TvVipCountriesFirstUse(
                      available: available.value,
                      playing: playing.value,
                      store: store,
                      onOpen: open,
                      builder: button,
                    )
                  else
                    button(open),
                  const SizedBox(height: 12),
                  const SizedBox(
                      key: categoriesKey,
                      height: 150,
                      child: Text('Catégories existantes')),
                ])),
          ),
        );
      })),
    ));
    await tester.runAsync(GoogleFonts.pendingFonts);
    await settle(tester);
  }

  testWidgets(
      'pas de pays ni téléchargement terminé : aucun repère ni marqueur',
      (tester) async {
    await show(tester, wrapped: false);
    final buttonRect = tester.getRect(find.byKey(buttonKey));
    final categoriesRect = tester.getRect(find.byKey(categoriesKey));
    await show(tester);
    expect(find.text(hint), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(VipCountriesFirstUse.keyFor('hint-a')), isNull);
    RemoteSourceRepository.importing.value = true;
    RemoteSourceRepository.syncing.value = true;
    available.value = true;
    ImportProgressBus.current.value =
        const ImportProgress(ImportStage.saving, index: 1000, total: 3000);
    await settle(tester);
    expect(find.text(hint), findsNothing);
    RemoteSourceRepository.importing.value = false;
    await settle(tester);
    expect(find.text(hint), findsNothing,
        reason: 'la synchronisation des autres sources continue');
    RemoteSourceRepository.syncing.value = false;
    RemoteSourceRepository.manualImporting.value = true;
    ImportProgressBus.done(3000);
    await settle(tester);
    expect(find.text(hint), findsNothing,
        reason: 'un ajout manuel reste en cours');
    RemoteSourceRepository.manualImporting.value = false;
    await settle(tester);
    expect(find.text(hint), findsOneWidget);
    expect(prefs.getBool(VipCountriesFirstUse.keyFor('hint-a')), isTrue);
    expect(tester.getRect(find.byKey(buttonKey)), buttonRect);
    expect(tester.getRect(find.byKey(categoriesKey)), categoriesRect);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('repère une seule fois, après recréation et séparé par profil',
      (tester) async {
    available.value = true;
    await show(tester);
    expect(find.text(hint), findsOneWidget);
    await tester.pump(const Duration(seconds: 13));
    expect(find.text(hint), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store = VipCountriesFirstUse(); // relit le disque, pas le cache du widget
    await show(tester);
    expect(find.text(hint), findsNothing);
    ActiveProfile.instance.set('hint-b');
    await settle(tester);
    expect(find.text(hint), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(VipCountriesFirstUse.keyFor('hint-b')), isTrue);
    ActiveProfile.instance.set('hint-a');
    await settle(tester);
    expect(find.text(hint), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'un progrès périmé après échec ne masque pas les pays disponibles',
      (tester) async {
    available.value = true;
    RemoteSourceRepository.syncing.value = true;
    ImportProgressBus.current.value =
        const ImportProgress(ImportStage.saving, index: 1000, total: 3000);
    await show(tester);
    expect(find.text(hint), findsNothing);
    // Un import partiel a fourni des pays, puis une autre source a échoué.
    RemoteSourceRepository.syncing.value = false;
    await settle(tester);
    expect(find.text(hint), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'lecteur ou route couverte : premier usage conservé pour le retour',
      (tester) async {
    available.value = true;
    playing.value = true;
    await show(tester);
    expect(find.text(hint), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    playing.value = false;
    await settle(tester);
    expect(find.text(hint), findsNothing, reason: 'app en arrière-plan');
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Autre écran'))));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(VipCountriesFirstUse.keyFor('hint-a')), isNull);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text(hint), findsOneWidget);
    expect(prefs.getBool(VipCountriesFirstUse.keyFor('hint-a')), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'clic sur le bouton existant ouvre le vrai sélecteur et mémorise la découverte',
      (tester) async {
    await VipCountriesRepository.instance.load();
    // Ouverture volontaire avant même le repère : elle suffit à le consommer.
    await show(tester);
    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    expect(find.byType(TvVipCountriesScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('vip-add-fr')), findsOneWidget);
    expect(find.byKey(const ValueKey('vip-add-rs')), findsOneWidget);
    expect(find.text(hint), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(VipCountriesFirstUse.keyFor('hint-a')), isTrue);
    navigator.currentState!.pop();
    available.value = true;
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text(hint), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
