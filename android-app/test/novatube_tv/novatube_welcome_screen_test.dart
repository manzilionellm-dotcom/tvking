// =========================================================
//  « Bienvenue sur NovaTube » : premier écran simple et ouvert.
// =========================================================
//  Vérifie ce que le propriétaire a demandé, sans réseau :
//    • le titre et les DEUX grands boutons (M3U, Xtream Codes) ;
//    • chaque bouton ouvre le BON formulaire existant ;
//    • le code appareil complet MK:XX:XX:XX:XX:XX est visible ;
//    • l'état de la licence est dit clairement (ici : jamais activée) ;
//    • aucun nom du panel d'administration à l'écran.
//  Données entièrement factices.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/features/device/data/novatube_identity.dart';
import 'package:tv_king/features/playlists/domain/open_source_input.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_novatube_welcome_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import 'ahem_fonts.dart';

// Code affiché : identité Zuno (MAC virtuelle) ou, dans l'édition NovaTube,
// code Atlas calculé comme le serveur à partir de la MAC brute.
const String _zunoMac = 'MK:12:34:AB:CD:56';
const String _novatubeRaw = '0123456789AB';
const String _novatubeMac = 'MK:F8:CA:83:78:18';
const String _mac = kNovatubeTv ? _novatubeMac : _zunoMac;

Widget _app(Widget child, Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    );

Future<void> _pumpWelcome(WidgetTester tester, {Locale locale = const Locale('fr')}) async {
  // Taille d'une TV 720p : les deux boutons sont côte à côte.
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(const TvNovatubeWelcomeScreen(), locale));
  // Laisse DeviceIdentity lire la MAC factice des préférences.
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(installAhemFonts);
  tearDownAll(removeAhemFonts);
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': _zunoMac,
      NovatubeIdentity.kRawKey: _novatubeRaw,
      NovatubeIdentity.kDeviceKeyKey: 'a' * 64,
    });
    NovatubeIdentity.instance.resetForTesting();
  });

  testWidgets('titre, deux grands boutons, code MK complet, licence en attente',
      (WidgetTester tester) async {
    await _pumpWelcome(tester);
    expect(find.text('Bienvenue sur NovaTube'), findsOneWidget);
    expect(find.text('Ajouter une liste M3U'), findsOneWidget);
    expect(find.text('Se connecter avec Xtream Codes'), findsOneWidget);
    expect(find.text(_mac), findsOneWidget);
    expect(find.text("Licence en attente d'activation"), findsOneWidget);
    expect(find.text('Vérifier mon accès'), findsOneWidget);
    // Le client ne voit jamais le nom du panel ni une adresse de serveur.
    expect(find.textContaining('Atlas'), findsNothing);
    expect(find.textContaining('http'), findsNothing);
    expect(find.textContaining('zuno8k'), findsNothing);
  });

  testWidgets('le bouton M3U ouvre le formulaire M3U', (WidgetTester tester) async {
    await _pumpWelcome(tester);
    await tester.tap(find.text('Ajouter une liste M3U'));
    await tester.pumpAndSettle();
    final TvAddSourceScreen screen =
        tester.widget<TvAddSourceScreen>(find.byType(TvAddSourceScreen));
    expect(screen.initialMode, OpenEntryMode.m3u);
  });

  testWidgets('le bouton Xtream ouvre le formulaire Xtream Codes',
      (WidgetTester tester) async {
    await _pumpWelcome(tester);
    await tester.tap(find.text('Se connecter avec Xtream Codes'));
    await tester.pumpAndSettle();
    final TvAddSourceScreen screen =
        tester.widget<TvAddSourceScreen>(find.byType(TvAddSourceScreen));
    expect(screen.initialMode, OpenEntryMode.xtream);
  });

  testWidgets('la télécommande arrive directement sur « Ajouter une liste M3U »',
      (WidgetTester tester) async {
    await _pumpWelcome(tester);
    final FocusNode? focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    // Le nœud focalisé appartient au bouton M3U (clé stable du bouton).
    final Finder m3u = find.byKey(const ValueKey<String>('novatube-welcome-m3u'));
    expect(m3u, findsOneWidget);
    expect(
      find.descendant(of: m3u, matching: find.byWidgetPredicate(
        (Widget w) => w is Focus && w.focusNode == focused,
      )).evaluate().isNotEmpty ||
          Focus.of(tester.element(find.descendant(
            of: m3u,
            matching: find.text('Ajouter une liste M3U'),
          ))).hasFocus,
      isTrue,
    );
  });

  testWidgets('anglais : textes traduits, même code', (WidgetTester tester) async {
    await _pumpWelcome(tester, locale: const Locale('en'));
    expect(find.text('Welcome to NovaTube'), findsOneWidget);
    expect(find.text('Add an M3U playlist'), findsOneWidget);
    expect(find.text('Sign in with Xtream Codes'), findsOneWidget);
    expect(find.text(_mac), findsOneWidget);
  });
}
