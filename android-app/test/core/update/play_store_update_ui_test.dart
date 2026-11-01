import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/core/update/build_flags.dart';
import 'package:tv_king/features/about/presentation/about_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_settings_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  const device = MethodChannel('com.manzilionellm.tvking/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final opened = <String>[];
  setUp(() {
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
        appName: 'ZUNO',
        packageName: 'com.sevenmotion.tv.seven_tv',
        version: '113',
        buildNumber: '1793555495',
        buildSignature: '');
    opened.clear();
    messenger.setMockMethodCallHandler(device, (_) async => null);
    messenger.setMockMethodCallHandler(launcher, (call) async {
      opened.add((call.arguments as Map)['url'] as String);
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(device, null);
    messenger.setMockMethodCallHandler(launcher, null);
  });
  Future<void> show(WidgetTester tester, Widget body) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: body),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opened, isEmpty); // Le Store ne s'ouvre jamais tout seul.
  }

  testWidgets(
      'Play / À propos : le bouton ouvre la fiche, sans fausse erreur réseau',
      (tester) async {
    await show(tester, const AboutScreen());
    final button = find.widgetWithText(OutlinedButton, 'Ouvrir Google Play');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 500));
    expect(opened, [
      'https://play.google.com/store/apps/details?id=com.sevenmotion.tv.seven_tv'
    ]);
    expect(tester.takeException(), isNull);
  }, skip: !kIsPlayBuild);

  testWidgets(
      'Play / TV : navigation télécommande vers le Store sans faux état à jour',
      (tester) async {
    await show(tester, const TvSettingsScreen());
    await tester.pumpAndSettle();
    // Les rubriques restent dans leur anneau habituel ; le test utilise les
    // mêmes flèches et le même OK que la télécommande de la box.
    final storeHelp =
        find.text('Vérifie et installe les mises à jour depuis Google Play.');
    for (int i = 0; i < 20 && storeHelp.evaluate().isEmpty; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(storeHelp, findsOneWidget);
    final words = await AppLocalizations.delegate.load(const Locale('fr'));
    expect(find.text(words.tvUpdateUpToDate('113')), findsNothing);
    expect(find.text('v113  ✓'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, [
      'https://play.google.com/store/apps/details?id=com.sevenmotion.tv.seven_tv'
    ]);
    expect(tester.takeException(), isNull);
  }, skip: !kIsPlayBuild);
}
