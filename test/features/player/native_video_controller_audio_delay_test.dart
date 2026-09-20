// =========================================================
//  native_video_controller_audio_delay_test.dart — synchro son / image
// =========================================================
//  Signalement du propriétaire (20/09/2026) : « sur la box, les sons et
//  les images ne correspondent pas ». Le remède est un décalage manuel
//  (±50 ms, mémorisé) appliqué à l'horloge audio du lecteur natif.
//
//  Ce que ces tests verrouillent côté Dart :
//    • un décalage demandé AVANT l'attach est REJOUÉ à l'attach (l'écran
//      le règle à la création du controller, la vue native n'existe pas
//      encore) — sinon le réglage mémorisé serait perdu à chaque zap ;
//    • un décalage nul n'envoie rien à l'attach (pas de commande inutile
//      sur une box qui n'a rien demandé) ;
//    • après l'attach, chaque réglage part tout de suite au natif.
// =========================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<MethodCall> spyChannel(String name) {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name),
            (MethodCall call) async {
      calls.add(call);
      return null;
    });
    return calls;
  }

  test('un décalage réglé AVANT l\'attach est rejoué à l\'attach', () async {
    const String channelName = 'native_video_player/test-delay-pending';
    final List<MethodCall> calls = spyChannel(channelName);
    final NativeVideoController controller = NativeVideoController();

    controller.setAudioDelay(150); // canal absent : rien ne part encore
    expect(controller.audioDelayMs, 150);
    controller.debugAttachChannel(channelName);
    await Future<void>.delayed(Duration.zero);

    final MethodCall delay =
        calls.singleWhere((MethodCall c) => c.method == 'setAudioDelay');
    expect((delay.arguments as Map<Object?, Object?>)['ms'], 150);
  });

  test('décalage nul : aucune commande de synchro à l\'attach', () async {
    const String channelName = 'native_video_player/test-delay-zero';
    final List<MethodCall> calls = spyChannel(channelName);
    final NativeVideoController controller = NativeVideoController();

    controller.debugAttachChannel(channelName);
    await Future<void>.delayed(Duration.zero);

    expect(calls.where((MethodCall c) => c.method == 'setAudioDelay'),
        isEmpty);
  });

  test('après l\'attach, chaque réglage part tout de suite, signe compris',
      () async {
    const String channelName = 'native_video_player/test-delay-live';
    final List<MethodCall> calls = spyChannel(channelName);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(channelName);

    controller.setAudioDelay(-100);
    controller.setAudioDelay(0);
    await Future<void>.delayed(Duration.zero);

    final List<Object?> envoyes = calls
        .where((MethodCall c) => c.method == 'setAudioDelay')
        .map((MethodCall c) => (c.arguments as Map<Object?, Object?>)['ms'])
        .toList();
    expect(envoyes, <Object?>[-100, 0]);
    expect(controller.audioDelayMs, 0);
  });
}
