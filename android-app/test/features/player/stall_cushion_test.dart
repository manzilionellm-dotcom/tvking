// =========================================================
//  stall_cushion_test.dart — « Coussin anti-coupure » et lignes « LECTURE »
// =========================================================
//  Côté Flutter seulement : le réglage, son envoi AVANT la première adresse,
//  et la ligne des pauses qui arrive à la boîte noire. Ce que le lecteur
//  mesure et décide est testé sans box dans logic-test (PlaybackStallsTest).
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/player/data/image_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void reset() {
    ImagePrefs.resetForTesting();
    NativeVideoController.onPlaybackDiagnostic = null;
  }

  setUp(reset);
  tearDown(reset);

  test('coupé par défaut : le lecteur garde sa reprise d\'origine', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    expect(ImagePrefs.stallCushion, isFalse);
    expect(NativeVideoController.stallCushion, isFalse);
  });

  test('allumé, il survit au redémarrage ; coupé, il revient au réglage d\'origine', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    await ImagePrefs.setStallCushion(true);
    expect(NativeVideoController.stallCushion, isTrue);
    ImagePrefs.resetForTesting();
    expect(NativeVideoController.stallCushion, isFalse);
    await ImagePrefs.load();
    expect(ImagePrefs.stallCushion, isTrue);
    expect(NativeVideoController.stallCushion, isTrue);
    await ImagePrefs.setStallCushion(false);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ImagePrefs.stallCushionKey), isFalse);
    expect(NativeVideoController.stallCushion, isFalse);
  });

  test('le coussin ne touche ni le HDR, ni le contraste, ni le moteur d\'image', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    await ImagePrefs.setStallCushion(true);
    expect(ImagePrefs.hdrCompat, isFalse);
    expect(ImagePrefs.lightContrast, isFalse);
    expect(ImagePrefs.frameRateMatch, isFalse);
  });

  for (final bool enabled in <bool>[true, false]) {
    testWidgets('le coussin ($enabled) arrive avant la première URL, et suit les changements',
        (WidgetTester tester) async {
      NativeVideoController.backendFactory = null;
      NativeVideoController.audiblePlayers.debugReset();
      NativeVideoController.stallCushion = enabled;
      final List<MethodCall> calls = <MethodCall>[];
      final List<MethodChannel> channels = <MethodChannel>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform_views,
          (MethodCall call) async {
        if (call.method == 'create') {
          final int id = (call.arguments as Map<Object?, Object?>)['id']! as int;
          final MethodChannel channel = MethodChannel('native_video_player/$id');
          channels.add(channel);
          messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            return null;
          });
        }
        return null;
      });
      final NativeVideoController controller = NativeVideoController(
        initialUrl: 'https://example.invalid/test-only.ts',
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
        final int cushion = calls.indexWhere((MethodCall c) => c.method == 'setStallCushion');
        final int url = calls.indexWhere((MethodCall c) => c.method == 'setUrl');
        expect(cushion, greaterThanOrEqualTo(0));
        expect(calls[cushion].arguments, enabled);
        expect(url, greaterThan(cushion), reason: 'le réglage part AVANT la première adresse');

        // Changé dans Réglages pendant qu'un lecteur est ouvert : la vue le
        // reçoit tout de suite (le lecteur le relit à chaque reprise).
        NativeVideoController.stallCushion = !enabled;
        NativeVideoController.pushAudioDiagFlags();
        await tester.pump();
        expect(
          calls.lastWhere((MethodCall c) => c.method == 'setStallCushion').arguments,
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
        NativeVideoController.stallCushion = false;
      }
    });
  }

  test('la ligne d\'une pause arrive à la boîte noire sans rien changer au lecteur', () {
    final List<String> lines = <String>[];
    NativeVideoController.onPlaybackDiagnostic = lines.add;
    final NativeVideoController controller = NativeVideoController();
    int notified = 0;
    controller.addListener(() => notified++);
    controller.applyBackendEvent(
      'playDiag',
      'Pause n°1 : 3,1 s. Silence du serveur pendant la pause : 2,9 s.',
    );
    // Vide ou d'un autre type : ignoré, sans erreur.
    controller.applyBackendEvent('playDiag', '');
    controller.applyBackendEvent('playDiag', null);
    controller.applyBackendEvent('playDiag', 42);
    expect(lines, <String>[
      'Pause n°1 : 3,1 s. Silence du serveur pendant la pause : 2,9 s.',
    ]);
    expect(notified, 0);
    expect(controller.hasError, isFalse);
    controller.dispose();
  });
}
