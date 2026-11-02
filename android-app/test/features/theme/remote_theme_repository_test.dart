import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/branding/brand_config.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/core/theme/accent_controller.dart';
import 'package:tv_king/core/theme/remote_theme_settings.dart';
import 'package:tv_king/core/theme/theme_mode_repository.dart';
import 'package:tv_king/features/theme/data/remote_theme_repository.dart';

Future<void> reply(String body, {int status = 200, bool strict = false}) =>
    http.runWithClient(() => RemoteThemeRepository.fetchAndApply(strict: strict),
      () => MockClient((request) async {
        expect(request.url.path, '/api/theme');
        expect(request.url.queryParameters['platform'], 'tv');
        return http.Response(body, status);
      }));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    AppPlatform.configureZuno(isAndroidHandset: true);
    await reply('{"appName":"","accent":"","bg":""}');
  });

  test('nom, accent et fond arrivent ensemble ; reset restitue les choix locaux', () async {
    final local = kAccentThemes.firstWhere((theme) => theme.id == 'indigo');
    await AccentController.instance.select(local);
    await ThemeModeRepository.instance.setMode(ThemeMode.system);
    await reply('{"appName":"Mon salon","accent":"#1E8E4E","bg":"light"}', strict: true);
    expect(BrandConfig.instance.appName, 'Mon salon');
    expect(AccentController.instance.current.accent, const Color(0xFF1E8E4E));
    expect(ThemeModeRepository.instance.mode, ThemeMode.light);
    expect(RemoteThemeRepository.current.value.mode, ThemeMode.light);
    await reply('{"appName":"","accent":"","bg":""}', strict: true);
    expect(BrandConfig.instance.appName, FlavorConfig.current.appName);
    expect(AccentController.instance.current, same(local));
    expect(ThemeModeRepository.instance.mode, ThemeMode.system);
    expect(RemoteThemeRepository.current.value, const RemoteThemeSettings());
  });

  test('erreurs HTTP/JSON/champs invalides conservent le dernier thème', () async {
    await reply('{"appName":"Valide","accent":"#2E7DD6","bg":"dark"}');
    final previous = RemoteThemeRepository.current.value;
    for (final body in <String>['pas du JSON', '[]', '{}',
        '{"appName":{},"accent":"","bg":"light"}',
        '{"accent":"#XYZXYZ","bg":"light"}', '{"bg":"garbage"}']) {
      await expectLater(reply(body, strict: true), throwsA(isA<Exception>()));
      expect(RemoteThemeRepository.current.value, previous);
      await reply(body);
      expect(RemoteThemeRepository.current.value, previous);
    }
    await expectLater(reply('{}', status: 503, strict: true), throwsStateError);
    expect(RemoteThemeRepository.current.value, previous);
  });

  test('réponse ancienne et lente ne remplace pas une nouvelle couleur', () async {
    final slow = Completer<http.Response>();
    int reads = 0;
    await http.runWithClient(() async {
      final old = RemoteThemeRepository.fetchAndApply(strict: true);
      await Future<void>.delayed(Duration.zero);
      await RemoteThemeRepository.fetchAndApply(strict: true);
      final rejectsOld = expectLater(old, throwsStateError);
      slow.complete(http.Response(jsonEncode(<String, String>{
        'appName': 'Ancien', 'accent': '#FFFFFF', 'bg': 'light',
      }), 200));
      await rejectsOld;
    }, () => MockClient((_) async {
      if (++reads == 1) return slow.future;
      return http.Response('{"appName":"Récent","accent":"#000000","bg":"dark"}', 200);
    }));
    expect(RemoteThemeRepository.current.value.appName, 'Récent');
    expect(RemoteThemeRepository.current.value.accent, Colors.black);
  });

  test('nom borné et nettoyé, valeurs vides retirent explicitement la surcharge', () {
    final settings = RemoteThemeSettings.parse(<String, String>{
      'appName': ' Nom\n' + 'x' * 60, 'accent': '123456', 'bg': '',
    });
    expect(settings?.appName.length, 40);
    expect(settings?.appName.contains('\n'), isFalse);
    expect(settings?.accent, const Color(0xFF123456));
    expect(settings?.mode, isNull);
  });
}
