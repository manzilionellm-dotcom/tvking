// =========================================================
//  hdr_compat_test.dart — film « Dolby Vision + HDR10+ »
// =========================================================
//  Côté Flutter seulement : le réglage, l'interrupteur de repli et la
//  ligne « IMAGE » de la boîte noire. Ce que le lecteur retire du flux
//  est testé sans box dans logic-test (HybridHdrTest), puis sur un vrai
//  décodeur Android par NativeHybridHdrTest.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/player/data/image_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void reset() {
    ImagePrefs.resetForTesting();
    RepairFlags.debugReset();
    NativeVideoController.onVideoDiagnostic = null;
  }

  setUp(reset);
  tearDown(reset);

  test('sans choix enregistré : rien n\'est retiré, le repli est désarmé',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    await RepairFlags.load();
    expect(ImagePrefs.hdrCompat, isFalse);
    expect(NativeVideoController.hdrCompat, isFalse);
    expect(RepairFlags.hybridHdrOff, isFalse);
    expect(NativeVideoController.hybridHdrOff, isFalse);
  });

  test('« Compatibilité HDR » allumé survit au redémarrage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    await ImagePrefs.setHdrCompat(true);
    expect(NativeVideoController.hdrCompat, isTrue);
    ImagePrefs.resetForTesting();
    expect(NativeVideoController.hdrCompat, isFalse);
    await ImagePrefs.load();
    expect(ImagePrefs.hdrCompat, isTrue);
    expect(NativeVideoController.hdrCompat, isTrue);
    await ImagePrefs.setHdrCompat(false);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ImagePrefs.hdrCompatKey), isFalse);
    expect(NativeVideoController.hdrCompat, isFalse);
  });

  test('le réglage ne touche ni le contraste ni le moteur d\'image', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    await ImagePrefs.setHdrCompat(true);
    expect(ImagePrefs.lightContrast, isFalse);
    expect(ImagePrefs.frameRateMatch, isFalse);
    expect(NativeVideoController.defaultLightContrast, isFalse);
  });

  test('l\'interrupteur de repli est lu au démarrage et remis par défaut',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.hybridHdrOffKey: true,
    });
    await RepairFlags.load();
    expect(RepairFlags.hybridHdrOff, isTrue);
    expect(NativeVideoController.hybridHdrOff, isTrue);
    // Le repli désarme l'automatique ; il n'allume pas le réglage manuel.
    expect(NativeVideoController.hdrCompat, isFalse);
    RepairFlags.debugReset();
    expect(RepairFlags.hybridHdrOff, isFalse);
    expect(NativeVideoController.hybridHdrOff, isFalse);
  });

  for (final bool enabled in <bool>[true, false]) {
    testWidgets('les deux réglages ($enabled) arrivent avant la première URL',
        (WidgetTester tester) async {
      NativeVideoController.backendFactory = null;
      NativeVideoController.audiblePlayers.debugReset();
      NativeVideoController.hdrCompat = enabled;
      NativeVideoController.hybridHdrOff = !enabled;
      final List<MethodCall> calls = <MethodCall>[];
      final List<MethodChannel> channels = <MethodChannel>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform_views,
          (MethodCall call) async {
        if (call.method == 'create') {
          final int id = (call.arguments as Map<Object?, Object?>)['id']! as int;
          final MethodChannel channel =
              MethodChannel('native_video_player/$id');
          channels.add(channel);
          messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            return null;
          });
        }
        return null;
      });
      final NativeVideoController controller = NativeVideoController(
        initialUrl: 'https://example.invalid/test-only.mkv',
      );
      try {
        await tester.pumpWidget(MaterialApp(
          home: SizedBox(
            width: 320,
            height: 180,
            child: NativeVideoView(controller: controller),
          ),
        ));
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        final int compat =
            calls.indexWhere((MethodCall c) => c.method == 'setHdrCompat');
        final int off =
            calls.indexWhere((MethodCall c) => c.method == 'setHybridHdrOff');
        final int url =
            calls.indexWhere((MethodCall c) => c.method == 'setUrl');
        expect(compat, greaterThanOrEqualTo(0));
        expect(off, greaterThanOrEqualTo(0));
        expect(calls[compat].arguments, enabled);
        expect(calls[off].arguments, !enabled);
        // Le décodeur du premier film doit déjà lire le bon réglage.
        expect(url, greaterThan(compat));
        expect(url, greaterThan(off));

        // Changé dans Réglages pendant qu'un lecteur est ouvert : la vue
        // le reçoit tout de suite, pour sa prochaine ouverture.
        NativeVideoController.hdrCompat = !enabled;
        NativeVideoController.pushAudioDiagFlags();
        await tester.pump();
        expect(
          calls
              .lastWhere((MethodCall c) => c.method == 'setHdrCompat')
              .arguments,
          !enabled,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.pump();
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        for (final MethodChannel channel in channels) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        NativeVideoController.hdrCompat = false;
        NativeVideoController.hybridHdrOff = false;
      }
    });
  }

  test('la ligne « IMAGE » du lecteur arrive à la boîte noire', () {
    final List<String> lines = <String>[];
    NativeVideoController.onVideoDiagnostic = lines.add;
    final NativeVideoController controller = NativeVideoController();
    controller.applyBackendEvent(
      'videoDiag',
      'HDR du flux : Dolby Vision oui, HDR10+ oui (film hybride).',
    );
    // Vide ou d'un autre type : ignoré, sans erreur.
    controller.applyBackendEvent('videoDiag', '');
    controller.applyBackendEvent('videoDiag', null);
    controller.applyBackendEvent('videoDiag', 42);
    expect(lines, <String>[
      'HDR du flux : Dolby Vision oui, HDR10+ oui (film hybride).',
    ]);
    controller.dispose();
  });

  test('une ligne « IMAGE » ne change pas l\'état du lecteur', () {
    NativeVideoController.onVideoDiagnostic = (_) {};
    final NativeVideoController controller = NativeVideoController();
    int notified = 0;
    controller.addListener(() => notified++);
    controller.applyBackendEvent('videoDiag', 'Vidéo : video/hevc.');
    expect(notified, 0);
    expect(controller.firstFrame, isFalse);
    expect(controller.hasError, isFalse);
    controller.dispose();
  });
}
