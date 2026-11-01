import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/i18n/locale_repository.dart';
import 'package:tv_king/features/player/data/pip_service.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.manzilionellm.tvking/pip');
  final messenger = binding.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app.locale.v1': 'fr',
    });
    await LocaleRepository.instance.initialize();
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final code in <String>['fr', 'en']) {
    test('START : accord natif et payload 7 MOTION localisé ($code)', () async {
      await LocaleRepository.instance.setLocale(Locale(code));
      final words = lookupAppLocalizations(Locale(code));
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });

      expect(await PipService.instance.startBackgroundAudio('Chaîne de test'), isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'startBackgroundAudio');
      expect(calls.single.arguments, <String, Object>{
        'title': 'Chaîne de test',
        'body': words.playbackNotifDefaultBody,
        'stopLabel': words.castStop,
        'channelName': words.playbackNotifChannelName,
        'channelDesc': words.playbackNotifChannelDesc,
      });

      // Le Cast emploie le même service avec son corps de notification.
      // Le titre et les libellés restent ceux de la langue active.
      expect(await PipService.instance.startBackgroundAudio(
        'Chaîne de test', body: words.castNotifRelayBody,
      ), isTrue);
      expect(calls, hasLength(2));
      expect(calls.last.arguments, <String, Object>{
        'title': 'Chaîne de test',
        'body': words.castNotifRelayBody,
        'stopLabel': words.castStop,
        'channelName': words.playbackNotifChannelName,
        'channelDesc': words.playbackNotifChannelDesc,
      });
    });
  }

  for (final response in <bool?>[false, null]) {
    test('START : réponse $response ne devient jamais un faux succès', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return response;
      });
      expect(await PipService.instance.startBackgroundAudio('Chaîne de test'), isFalse);
      expect(calls.single.method, 'startBackgroundAudio');
    });
  }

  test('START : bridge absent renvoie false sans exception à l’appelant', () async {
    // Aucun handler natif : reproduit le service manquant dans Zuno.
    messenger.setMockMethodCallHandler(channel, null);
    expect(await PipService.instance.startBackgroundAudio('Chaîne de test'), isFalse);
  });

  test('START : refus Android renvoie false et permet un nouvel essai', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (calls.length == 1) {
        throw PlatformException(code: 'FOREGROUND_SERVICE_START_NOT_ALLOWED');
      }
      return true;
    });
    expect(await PipService.instance.startBackgroundAudio('Chaîne de test'), isFalse);
    expect(await PipService.instance.startBackgroundAudio('Chaîne de test'), isTrue);
    expect(calls, hasLength(2));
  });

  test('STOP : répétable, sans lancement ni argument fournisseur', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await PipService.instance.stopBackgroundAudio();
    await PipService.instance.stopBackgroundAudio();
    expect(calls.map((call) => call.method),
        <String>['stopBackgroundAudio', 'stopBackgroundAudio']);
    expect(calls.every((call) => call.arguments == null), isTrue);
  });

  test('STOP : bridge disparu ou erreur Android ne bloque pas le nettoyage', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(PipService.instance.stopBackgroundAudio(), completes);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'SERVICE_ALREADY_STOPPED');
    });
    await expectLater(PipService.instance.stopBackgroundAudio(), completes);
  });
}
