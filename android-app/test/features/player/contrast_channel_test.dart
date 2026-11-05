import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Ce test vérifie la vraie liaison Flutter → Android, notamment l'ordre
  // avant setUrl. Les pixels sont vérifiés séparément par l'instrumentation
  // NativeContrastPixelTest ; ce transport simulé ne prouve pas le rendu.
  for (final enabled in <bool>[true, false]) {
    testWidgets('la préférence $enabled arrive avant la première URL',
        (tester) async {
      NativeVideoController.backendFactory = null;
      NativeVideoController.defaultLightContrast = true;
      NativeVideoController.audiblePlayers.debugReset();
      final calls = <MethodCall>[];
      final channels = <MethodChannel>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform_views,
          (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['id'] as int;
          final channel = MethodChannel('native_video_player/$id');
          channels.add(channel);
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
        }
        return null;
      });
      final controller = NativeVideoController(
        initialUrl: 'https://example.invalid/test-only.mp4',
      );
      // Le cas true reste au défaut, sans setter qui masquerait une régression.
      if (!enabled) controller.setLightContrast(false);
      try {
        await tester.pumpWidget(MaterialApp(
          home: SizedBox(
            width: 320,
            height: 180,
            child: NativeVideoView(controller: controller),
          ),
        ));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        final contrast =
            calls.indexWhere((call) => call.method == 'setContrast');
        final url = calls.indexWhere((call) => call.method == 'setUrl');
        expect(contrast, greaterThanOrEqualTo(0));
        expect(calls[contrast].arguments, enabled);
        expect(url, greaterThan(contrast));
        controller.setLightContrast(!enabled);
        await tester.pump();
        expect(
            calls.lastWhere((call) => call.method == 'setContrast').arguments,
            !enabled);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.pump();
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        for (final channel in channels) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        NativeVideoController.defaultLightContrast = false;
      }
    });
  }

  test('préférence, capacité et effet appliqué restent distincts', () {
    final controller = NativeVideoController();
    controller.applyBackendEvent('imageCaps', <String, Object>{
      'contrastHardware': true,
    });
    controller.applyBackendEvent('contrast', true);
    expect(controller.contrastHardware, isTrue);
    expect(controller.contrastApplied, isTrue);
    controller.applyBackendEvent('contrast', false);
    controller.applyBackendEvent('contrastReason', 'hdr');
    expect(controller.contrastApplied, isFalse);
    expect(controller.contrastReason, 'hdr');
    controller.applyBackendEvent('contrast', true);
    expect(controller.contrastReason, isNull);
    controller.dispose();
  });
}
