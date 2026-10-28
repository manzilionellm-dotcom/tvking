import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/player/data/image_prefs.dart';
import 'package:tv_king/features/player/data/video_quality_prefs.dart';
import 'package:tv_king/features/player/presentation/video_quality_setting.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

class _QualityBackend implements NativeVideoBackend {
  final events = <String>[];
  @override void bind(NativeVideoController controller) {}
  @override void open(Map<String, dynamic> args) => events.add('open');
  @override void play() {}
  @override void pause() {}
  @override void seekTo(Duration position) {}
  @override void selectTrack(NativeTrack track) {}
  @override void disableSubtitles() {}
  @override void silence() {}
  @override void setClearVoice(bool enabled) {}
  @override void setImageEngine(String engine) => events.add('engine:$engine');
  @override void setFrameRateMatch(bool enabled) {}
  @override void setLightContrast(bool enabled) {}
  @override void setVideoQuality(String quality) => events.add('quality:$quality');
  @override Widget buildView(BuildContext context) => const SizedBox();
  @override void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VideoQualityPrefs.resetForTesting();
    NativeVideoController.backendFactory = null;
  });
  tearDown(() => NativeVideoController.backendFactory = null);

  test('préférence absente ou inconnue : sélection adaptative Auto', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{VideoQualityPrefs.key: 'ultra-ai'});
    await VideoQualityPrefs.load();
    expect(VideoQualityPrefs.value, VideoQuality.auto);
  });

  test('le choix survit au redémarrage sans modifier moteur et cadence', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ImagePrefs.engineKey: 'software', ImagePrefs.frameRateKey: true,
    });
    await VideoQualityPrefs.set(VideoQuality.maximum);
    VideoQualityPrefs.resetForTesting();
    await VideoQualityPrefs.load();
    expect(VideoQualityPrefs.value, VideoQuality.maximum);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ImagePrefs.engineKey), 'software');
    expect(prefs.getBool(ImagePrefs.frameRateKey), isTrue);
  });

  test('des changements rapides mémorisent le dernier choix', () async {
    await Future.wait(<Future<void>>[
      VideoQualityPrefs.set(VideoQuality.maximum),
      VideoQualityPrefs.set(VideoQuality.auto),
      VideoQualityPrefs.set(VideoQuality.maximum),
    ]);
    expect((await SharedPreferences.getInstance()).getString(VideoQualityPrefs.key), 'maximum');
  });

  test('Maximum puis Auto ne rouvre pas le flux ni le moteur', () {
    final backend = _QualityBackend();
    NativeVideoController.backendFactory = () => backend;
    final c = NativeVideoController();
    c.setUrl('https://fixture.invalid/video.m3u8');
    c.setVideoQuality('maximum');
    c.setVideoQuality('maximum');
    c.setVideoQuality('auto');
    expect(backend.events, <String>['open', 'quality:maximum', 'quality:auto']);
    c.dispose();
    c.setVideoQuality('maximum');
    expect(backend.events.length, 3);
  });

  test('résolution réelle filtrée pendant le zap et remise à zéro', () {
    final c = NativeVideoController();
    c.setUrl('https://fixture.invalid/video.ts');
    c.applyBackendEvent('videoFormat', <String, Object>{'width': 3840, 'height': 2160});
    expect(c.videoSizeLabel, isEmpty);
    c.applyBackendEvent('ack', 1);
    c.applyBackendEvent('videoFormat', <String, Object>{'width': 720, 'height': 576});
    expect(c.videoSizeLabel, '720 × 576');
    c.setUrl('https://fixture.invalid/other.ts');
    expect(c.videoSizeLabel, isEmpty);
    c.applyBackendEvent('ack', 2);
    c.applyBackendEvent('videoFormat', <String, Object>{'width': -1, 'height': double.infinity});
    expect(c.videoSizeLabel, isEmpty);
    c.dispose();
  });

  testWidgets('la télécommande active Maximum puis revient à Auto', (tester) async {
    await VideoQualityPrefs.load();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Padding(padding: EdgeInsets.all(40),
          child: VideoQualitySetting(autofocus: true))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Auto'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Définition maximale'), findsOneWidget);
    expect(VideoQualityPrefs.value, VideoQuality.maximum);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Auto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
