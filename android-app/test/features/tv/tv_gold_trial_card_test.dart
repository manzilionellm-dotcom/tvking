import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/theme/app_theme.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/subscription/data/gold_trial_backend.dart';
import 'package:tv_king/features/subscription/data/gold_trial_controller.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';
import 'package:tv_king/features/tv/presentation/tv_activation_frame.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_gold_trial_card.dart';

const _capture = bool.fromEnvironment('ZUNO_CAPTURE_REVIEW');
const _previewKey = ValueKey<String>('tv-trial-preview');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (!_capture) return;
    // Les tests Flutter dessinent normalement des blocs Ahem. Pour les
    // captures de revue uniquement, charger une police locale lisible sans
    // téléchargement réseau ni modification des polices de l'application.
    final font = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (await font.exists()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      final families = <String?>{
        TvTokens.ui(18).fontFamily,
        TvTokens.ui(18, weight: FontWeight.w600).fontFamily,
        TvTokens.ui(18, weight: FontWeight.w700).fontFamily,
        TvTokens.display(40).fontFamily,
        TvTokens.mono(30).fontFamily,
      };
      for (final family in families.whereType<String>()) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (await icons.exists()) {
        await (FontLoader('MaterialIcons')..addFont(Future.value(
            ByteData.sublistView(await icons.readAsBytes())))).load();
      }
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  GoldTrialController create(Future<http.Response> Function(http.Request) handler,
      {bool customer = false}) => GoldTrialController(
    backend: GoldTrialBackend(clientFactory: () => MockClient(handler)),
    sourceHeaders: () async => <String, String>{'X-Device-Secret': 'fixture'},
    loadIdentity: () async => const GoldTrialIdentity(mac: 'MK:11:22:33:44:55',
        androidId: 'fixture', appVersion: '109-review'),
    hasSubscription: () => customer,
    hasLoadedTrial: () => true,
    loadPlaylists: () async => const <Playlist>[],
    playlistChanges: const Stream<List<Playlist>>.empty(),
  );

  Future<void> show(WidgetTester tester, GoldTrialController controller,
      {Size size = const Size(1280, 720)}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.initialize();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.cinema,
      home: Scaffold(backgroundColor: TvTokens.bg, body: RepaintBoundary(
        key: _previewKey,
        child: Padding(padding: const EdgeInsets.all(24), child: TvActivationFrame(
          activation: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const TvLogo(width: 180),
            TvGoldTrialCard(controller: controller, autofocus: true),
            const SizedBox(height: 24),
            Text('Votre code d’activation', style: TvTokens.ui(18)),
            Text('11:22:33:44:55', style: TvTokens.mono(30)),
            const SizedBox(height: 24),
            TvCtaButton(label: 'J’ai payé — Vérifier', onSelect: () {}),
          ]),
          help: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.live_tv_rounded, size: 80, color: TvTokens.accentBright),
            const SizedBox(height: 24),
            Text('Zuno TV', style: TvTokens.display(40)),
            const SizedBox(height: 12),
            Text('Votre télévision, simplement.', style: TvTokens.ui(22, color: TvTokens.muted)),
          ]),
        )),
      )),
    ));
    await tester.pumpAndSettle();
    if (_capture) {
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/branding/zuno_logo.png'),
          tester.element(find.byType(TvLogo))));
      await tester.pumpAndSettle();
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_previewKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/zuno-trial-review/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  testWidgets('télécommande : focus, OK maintenu, double clic et message public', (tester) async {
    int posts = 0;
    final pending = Completer<http.Response>();
    final controller = create((_) { posts++; return pending.future; });
    addTearDown(controller.dispose);
    await show(tester, controller);
    expect(find.text('Je teste'), findsOneWidget);
    expect(find.text('24 H'), findsOneWidget);
    await capture(tester, '01-ready-720p');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(posts, 1);
    expect(find.text('Activation de votre essai…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(posts, 1, reason: 'pas de deuxième demande pendant le POST');
    await capture(tester, '02-loading-720p');
    pending.complete(http.Response('{"ok":true,"expire":"2030-10-29T12:00:00Z","message":"Votre essai est prêt."}', 201));
    await tester.pumpAndSettle();
    expect(find.text('Votre essai est prêt.'), findsOneWidget);
    expect(find.textContaining('29/10/2030'), findsOneWidget);
    expect(find.text('Je teste'), findsNothing);
    expect(tester.takeException(), isNull);
    await capture(tester, '03-success-720p');
  });

  testWidgets('essai utilisé : QR WhatsApp et retour à la télécommande', (tester) async {
    final controller = create((_) async => http.Response('{"error":"trial_already_used"}', 409));
    addTearDown(controller.dispose);
    await show(tester, controller);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Vous avez déjà utilisé votre essai gratuit'), findsOneWidget);
    expect(find.text('Je teste'), findsNothing);
    await tester.tap(find.text('S’abonner sur WhatsApp'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tv-trial-whatsapp-qr')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tv-trial-whatsapp-qr')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OFF : message sûr et abonnement ; client existant : carte masquée', (tester) async {
    final controller = create((_) async => http.Response('{"error":"trial_disabled","message":"cms-8k.net private-provider-secret"}', 403));
    addTearDown(controller.dispose);
    await show(tester, controller);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Les essais sont fermés pour le moment.'), findsOneWidget);
    expect(find.textContaining('cms-8k'), findsNothing);
    final customer = create((_) async => http.Response('{}', 500), customer: true);
    addTearDown(customer.dispose);
    await show(tester, customer);
    expect(find.text('Je teste'), findsNothing);
    expect(find.text('Votre essai gratuit'), findsNothing);
  });

  for (final size in <Size>[const Size(960, 540), const Size(1920, 1080), const Size(720, 1280)]) {
    testWidgets('mise en page $size : message long sans débordement', (tester) async {
      final controller = create((_) async => http.Response('{"error":"trial_disabled","message":"Les essais sont temporairement fermés. Vous pouvez contacter notre service pour découvrir les abonnements disponibles et recevoir de l’aide pour votre activation."}', 403, headers: <String, String>{'content-type': 'application/json; charset=utf-8'}));
      addTearDown(controller.dispose);
      await show(tester, controller, size: size);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('S’abonner sur WhatsApp'), findsOneWidget);
    });
  }

  testWidgets('activation longue : les dernières commandes restent accessibles au D-pad', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 540);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int selected = -1;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TvActivationFrame(
      activation: Column(children: <Widget>[
        for (int i = 0; i < 12; i++) Padding(
          padding: const EdgeInsets.all(12),
          child: TvCtaButton(label: 'Commande $i', autofocus: i == 0,
              onSelect: () { selected = i; }),
        ),
      ]),
      help: const SizedBox.shrink(),
    ))));
    await tester.pumpAndSettle();
    for (int i = 0; i < 11; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, 11);
    expect(tester.getCenter(find.text('Commande 11')).dy, inInclusiveRange(0, 540));
    expect(tester.takeException(), isNull);
  });
}
