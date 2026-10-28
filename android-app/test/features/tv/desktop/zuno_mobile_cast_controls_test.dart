import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/tv/desktop/desktop_cast_controls.dart';

class LocalPlayer extends NativeVideoController {
  final List<String> events;
  LocalPlayer(this.events);
  @override
  Future<void> suspendForCast() async { events.add('local-stop'); }
  @override
  Future<void> resumeAfterCast() async { events.add('local-resume'); }
}
class Receiver implements CastTransport {
  final List<String> events;
  Receiver(this.events);
  @override
  Future<void> playStream({required String streamUrl, String title = '', String? imageUrl}) async { events.add('remote-play'); }
  @override
  Future<void> stop() async { events.add('remote-stop'); }
  @override
  Future<void> pause() async { events.add('remote-pause'); }
  @override
  Future<void> resume() async { events.add('remote-resume'); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  const capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(capability, (_) async => true);
    await CastPlatform.initializeZuno();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(capability, null);
  });

  for (final accept in [true, false]) {
    testWidgets(accept ? 'Cast mobile ferme le local avant le récepteur puis reprend au stop' :
        'Fermer le sélecteur reprend le mobile sans lecture distante', (tester) async {
      final events = <String>[];
      final local = LocalPlayer(events);
      final receiver = Receiver(events);
      final manager = CastManager.forTesting(transportFactory: (_) => receiver,
        probe: (url) async => StreamProbeResult(originalUrl: url, finalUrl: url, success: true));
      const device = CastDevice(id: 'fixture', name: 'Écran test', kind: CastDeviceKind.roku,
        host: '192.0.2.1', port: 8060, controlUrl: 'http://192.0.2.1');
      addTearDown(() async { await manager.disconnect(); manager.dispose(); local.dispose(); });
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: Scaffold(body: DesktopCastControls(controller: local, manager: manager,
          streamUrl: 'http://stream.invalid/live.ts', title: 'Chaîne test',
          picker: (context, {required streamUrl, required title, imageUrl}) async {
            expect(events, ['local-stop']);
            if (accept) await manager.castTo(device, streamUrl: streamUrl, title: title);
          })),
      ));
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      if (accept) {
        expect(events.take(2), ['local-stop', 'remote-play']);
        expect(events, isNot(contains('local-resume')));
        await tester.tap(find.byIcon(Icons.stop_circle_outlined));
        await tester.pumpAndSettle();
        expect(events.indexOf('remote-stop'), lessThan(events.indexOf('local-resume')));
      } else {
        expect(events, ['local-stop', 'local-resume']);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
