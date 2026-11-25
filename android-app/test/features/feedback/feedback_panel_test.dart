import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/feedback/data/feedback_repository.dart';
import 'package:tv_king/features/feedback/presentation/tv_feedback_card.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Les polices de production restent inchangées. Comme les autres tests TV,
  // on fournit Ahem du SDK sous les noms attendus, sans accès au réseau.
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) throw StateError('FLUTTER_ROOT nécessaire pour Ahem');
    final font = ByteData.sublistView(
        File('$root/packages/flutter_tools/static/Ahem.ttf').readAsBytesSync());
    final assets = <String, List<Map<String, String>>>{
      for (final weight in ['Regular', 'SemiBold'])
        'fonts/Inter-$weight.ttf': [
          {'asset': 'fonts/Inter-$weight.ttf'},
        ],
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      if (key == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(assets);
      }
      if (key == 'AssetManifest.json') {
        return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
          for (final key in assets.keys) key: [key],
        }))));
      }
      if (assets.containsKey(key)) return font;
      return messenger.delegate.send('flutter/assets', message);
    });
  });
  tearDownAll(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', null));

  final repo = FeedbackRepository.instance;
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(
        {'device.virtual_mac.v1': 'MK:11:22:33:44:55'});
  });
  test('commande panel : notifier, OFF et refus de faux succès à l’envoi',
      () async {
    var enabled = true;
    var response = http.Response('{"ok":false}', 200);
    int changes = 0;
    void listener() => changes++;
    repo.addListener(listener);
    addTearDown(() => repo.removeListener(listener));
    await http.runWithClient(() async {
      await repo.reload(strict: true);
      expect(await repo.shouldPrompt(), isTrue);
      expect(changes, 1);
      expect(await repo.submit(text: 'Mon avis', rating: 4), isFalse);
      expect(await repo.shouldPrompt(), isTrue);
      response = http.Response('panne', 503);
      expect(await repo.submit(text: 'Mon avis'), isFalse);
      expect(await repo.shouldPrompt(), isTrue);
      response = http.Response('{"ok":true}', 200);
      expect(await repo.submit(text: 'Mon avis'), isTrue);
      expect(await repo.shouldPrompt(), isFalse);
      enabled = false;
      await repo.reload(strict: true);
      expect(await repo.shouldPrompt(), isFalse);
    },
        () => MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response(
                    jsonEncode({'enabled': enabled, 'message': 'Votre avis ?'}),
                    200);
              }
              expect(request.url.path, '/api/feedback');
              expect((jsonDecode(request.body) as Map)['message'], 'Mon avis');
              return response;
            }));
  });
  test('une nouvelle invitation ne disparaît pas après l’envoi de l’ancienne',
      () async {
    var prompt = 'Premier';
    final finish = Completer<http.Response>();
    await http.runWithClient(() async {
      await repo.reload(strict: true);
      final send = repo.submit(text: 'Bonjour');
      await Future<void>.delayed(Duration.zero);
      prompt = 'Deuxième';
      await repo.reload(strict: true);
      finish.complete(http.Response('{"ok":true}', 200));
      expect(await send, isTrue);
      expect(await repo.shouldPrompt(), isTrue);
    },
        () => MockClient((request) async => request.method == 'GET'
            ? http.Response(
                jsonEncode({'enabled': true, 'message': prompt}), 200)
            : finish.future));
  });
  testWidgets(
      'carte TV : pas d’envoi automatique, erreur réessayable, clavier sans overflow',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    int posts = 0;
    bool fail = true;
    await http.runWithClient(() async {
      await repo.reload(strict: true);
      await tester.pumpWidget(MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: TvFeedbackCard(message: 'Votre avis ?'))));
      await tester.pumpAndSettle();
      expect(posts, 0);
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey<String>('tv-feedback-text'));
      await tester.enterText(input, 'Un avis de test');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(FilledButton, 'Envoyer')));
      await tester.tap(find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(FilledButton, 'Envoyer')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(input, findsOneWidget);
      expect(await repo.shouldPrompt(), isTrue);
      fail = false;
      await tester.ensureVisible(find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(FilledButton, 'Réessayer')));
      await tester.tap(find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(FilledButton, 'Réessayer')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(posts, 2);
      expect(await repo.shouldPrompt(), isFalse);
    },
        () => MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response(
                    '{"enabled":true,"message":"Votre avis ?"}', 200);
              }
              posts++;
              return http.Response(
                  fail ? '{"ok":false}' : '{"ok":true}', fail ? 503 : 200);
            }));
  });
}
