import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/core/support/vip_support.dart';
import 'package:tv_king/features/tv/presentation/tv_whatsapp_support_button.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final support = find.byKey(const ValueKey<String>('source-whatsapp-support'));

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

  Future<void> show(
    WidgetTester tester,
    Future<bool> Function(String) open, {
    String language = 'fr',
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TvWhatsAppSupportButton(openForTesting: open),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('aucune ouverture au rendu ; le clic utilise la langue courante',
      (tester) async {
    final messages = <String>[];
    await show(tester, (message) async {
      messages.add(message);
      return true;
    }, language: 'sv');
    expect(messages, isEmpty);
    await tester.tap(support);
    await tester.pumpAndSettle();
    final words = await AppLocalizations.delegate.load(const Locale('sv'));
    expect(messages, <String>[words.tvSupportHello]);
    expect(find.text(words.tvSupportWhatsApp), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double-clic : une seule ouverture jusqu’à la réponse',
      (tester) async {
    final pending = Completer<bool>();
    int calls = 0;
    await show(tester, (_) {
      calls++;
      return pending.future;
    });
    final onPressed = tester.widget<TextButton>(support).onPressed!;
    onPressed();
    onPressed();
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<TextButton>(support).onPressed, isNull);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(support).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la touche OK de la télécommande ouvre le contact',
      (tester) async {
    int calls = 0;
    await show(tester, (_) async {
      calls++;
      return true;
    });
    final words = await AppLocalizations.delegate.load(const Locale('fr'));
    Focus.of(tester.element(find.text(words.tvSupportWhatsApp))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  for (final throws in <bool>[false, true]) {
    testWidgets(
        'ouverture indisponible ($throws) : numéro lisible et nouvel essai',
        (tester) async {
      int calls = 0;
      await show(tester, (_) async {
        calls++;
        if (calls > 1) return true;
        if (throws) throw StateError('password=must-not-be-displayed');
        return false;
      }, language: 'ar', scale: 2);
      await tester.tap(support);
      await tester.pumpAndSettle();
      final words = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(find.text(words.tvSupportUnavailable), findsOneWidget);
      expect(find.textContaining('must-not-be-displayed'), findsNothing);
      final number = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(number.data, VipSupport.displayNumber);
      expect(number.textDirection, TextDirection.ltr);
      expect(tester.widget<TextButton>(support).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.tap(support);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'fermer l’écran pendant l’ouverture ne met pas à jour un état détruit',
      (tester) async {
    final pending = Completer<bool>();
    await show(tester, (_) => pending.future);
    await tester.tap(support);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
