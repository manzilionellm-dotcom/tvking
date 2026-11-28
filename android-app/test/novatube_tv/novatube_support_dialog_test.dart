import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/device/data/novatube_identity.dart';
import 'package:tv_king/features/subscription/data/novatube_atlas.dart';
import 'package:tv_king/features/tv/presentation/tv_novatube_access_code_dialog.dart';
import 'package:tv_king/features/tv/presentation/tv_settings_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import 'ahem_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(installAhemFonts);
  tearDownAll(removeAhemFonts);
  late http.Response response;
  late List<String> requests;
  const first = 'REC-TEST-A';
  const second = 'REC-TEST-B';
  final support = find.byKey(const ValueKey('novatube-open-support'));

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    SharedPreferences.setMockInitialValues(<String, Object>{
      NovatubeIdentity.kRawKey: '0123456789AB',
      NovatubeIdentity.kDeviceKeyKey: 'a' * 64,
    });
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'org.example.test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    NovatubeIdentity.instance.resetForTesting();
    NovatubeAtlas.instance.resetForTesting();
    NovatubeAtlas.baseUrl = 'https://atlas.test';
    requests = <String>[];
    NovatubeAtlas.clientFactory = () => MockClient((req) async {
          requests.add(req.url.pathSegments.last);
          return response;
        });
  });
  tearDown(() {
    NovatubeAtlas.clientFactory = http.Client.new;
    NovatubeAtlas.instance.resetForTesting();
    FlavorConfig.resetForTesting();
  });

  Future<void> provision(int status, [String? code]) async {
    response = http.Response(
        jsonEncode(status == 200
            ? {'ok': true, 'status': 'active', 'active': true}
            : {
                'recovery': {if (code != null) 'code': code}
              }),
        status);
    await NovatubeAtlas.instance.readStatus();
  }

  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: home),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Réglages, droite puis OK révèle le code uniquement dans Assistance',
      (tester) async {
    await provision(409, first);
    await show(tester, const TvSettingsScreen());
    expect(find.textContaining(first), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Consulter le code d’assistance de cet appareil.'),
        findsOneWidget);
    expect(find.textContaining(first), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.textContaining(first)),
        findsOneWidget);
    final count = requests.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining(first), findsNothing);
    expect(requests.length, count);
  }, skip: !kNovatubeTv);

  testWidgets(
      'avant activation, Assistance apparaît sur conflit, suit le code puis son retrait',
      (tester) async {
    await show(tester, const TvNovatubeAccessCodeDialog());
    expect(support, findsNothing);
    await provision(409);
    await tester.pumpAndSettle();
    expect(support, findsNothing);
    await provision(409, '  ');
    await tester.pumpAndSettle();
    expect(support, findsNothing);
    await provision(409, first);
    await tester.pumpAndSettle();
    expect(support, findsOneWidget);
    expect(find.textContaining(first), findsNothing);
    final beforeRead = List.of(requests);
    await tester.tap(support);
    await tester.pumpAndSettle();
    expect(find.textContaining(first), findsOneWidget);
    expect(requests, beforeRead);
    await provision(409, second);
    await tester.pumpAndSettle();
    expect(find.textContaining(first), findsNothing);
    expect(find.textContaining(second), findsOneWidget);
    await provision(200);
    await tester.pumpAndSettle();
    expect(find.textContaining(second), findsNothing);
    expect(find.text('Aucun code d’assistance actif pour cet appareil.'),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(support, findsNothing);
    expect(requests, everyElement('register'));
  }, skip: !kNovatubeTv);

  testWidgets('Réglages peut afficher explicitement l’absence de code',
      (tester) async {
    await show(tester, const TvSettingsScreen());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Aucun code d’assistance actif pour cet appareil.'),
        findsOneWidget);
    expect(requests, isEmpty);
  }, skip: !kNovatubeTv);

  testWidgets('ZUNO ne propose aucune des deux entrées NovaTube',
      (tester) async {
    await provision(409, first);
    await show(tester, const TvSettingsScreen());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Consulter le code d’assistance de cet appareil.'),
        findsNothing);
    expect(find.textContaining(first), findsNothing);
    await show(tester, const TvNovatubeAccessCodeDialog());
    expect(support, findsNothing);
    expect(find.textContaining(first), findsNothing);
  }, skip: kNovatubeTv);
}
