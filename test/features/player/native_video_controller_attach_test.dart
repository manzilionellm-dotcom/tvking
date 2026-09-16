// =========================================================
//  native_video_controller_attach_test.dart — ce qui se joue à l'attach
// =========================================================
//  Enquête « connexion fantôme » (19/08, ligne Xtream 1-connexion) : la vue
//  native joue à l'attach `_pendingUrl ?? _lastUrl ?? initialUrl`. Le
//  lecteur TV plein écran était créé avec initialUrl = l'URL panel DIRECTE :
//  quand l'attach (~100-300 ms) arrivait avant que l'écran ait obtenu le
//  créneau réseau et posé l'URL du relais (jusqu'à 1,2 s si un aperçu se
//  démonte), ExoPlayer ouvrait sa propre connexion amont — HORS relais et
//  HORS créneau — qui se chevauchait avec la suivante → « limite de
//  connexions (1/1) ». Ces tests verrouillent le contrat des deux côtés :
//    • un controller AVEC initialUrl joue dès l'attach (c'est le mécanisme
//      du bug — l'écran TV ne doit plus jamais l'utiliser pour un flux) ;
//    • un controller SANS initialUrl ne joue RIEN tant que l'écran n'a pas
//      décidé de l'URL par le chemin officiel (setUrl).
// =========================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Branche un espion sur le canal natif [name] et collecte les appels.
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

  test('avec initialUrl, l\'attach joue l\'URL immédiatement (le mécanisme '
      'du bug 1-connexion)', () async {
    const String channelName = 'native_video_player/test-initial';
    final List<MethodCall> calls = spyChannel(channelName);
    final NativeVideoController controller =
        NativeVideoController(initialUrl: 'http://panel.example/live/1.ts');

    controller.debugAttachChannel(channelName);
    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setUrl');
    expect((calls.single.arguments as Map<Object?, Object?>)['url'],
        'http://panel.example/live/1.ts');
  });

  test('sans initialUrl, RIEN ne se joue à l\'attach — la connexion attend '
      'la décision de l\'écran (créneau → relais/direct)', () async {
    const String channelName = 'native_video_player/test-vierge';
    final List<MethodCall> calls = spyChannel(channelName);
    final NativeVideoController controller = NativeVideoController();

    controller.debugAttachChannel(channelName);
    await Future<void>.delayed(Duration.zero);

    expect(calls, isEmpty,
        reason: 'aucune connexion ne doit partir avant que l\'écran ait '
            'obtenu le créneau et choisi l\'URL');

    controller.setUrl('http://127.0.0.1:1234/s?u=abc');
    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setUrl');
    expect((calls.single.arguments as Map<Object?, Object?>)['url'],
        'http://127.0.0.1:1234/s?u=abc');
  });

  test('un setUrl demandé AVANT l\'attach est rejoué tel quel à l\'attach '
      '(l\'URL du relais gagne toujours sur initialUrl)', () async {
    const String channelName = 'native_video_player/test-pending';
    final List<MethodCall> calls = spyChannel(channelName);
    final NativeVideoController controller =
        NativeVideoController(initialUrl: 'http://panel.example/live/1.ts');

    // L'écran a fini son chemin officiel AVANT l'attach : c'est l'URL du
    // relais qui doit se jouer, jamais l'URL panel directe.
    controller.setUrl('http://127.0.0.1:1234/s?u=abc');
    controller.debugAttachChannel(channelName);
    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect((calls.single.arguments as Map<Object?, Object?>)['url'],
        'http://127.0.0.1:1234/s?u=abc');
  });

  // ---- Crash terrain 20/08 : « dispose on channel native_video_player/t1 »
  //  MissingPluginException NON RATTRAPÉE au dispose d'une vue déjà détruite.
  test('dispose sur un canal MORT (MissingPluginException) ne remonte JAMAIS',
      () async {
    const String channelName = 'native_video_player/test-dead';
    // Handler qui simule un canal natif disparu : toute commande lève
    // MissingPluginException (exactement ce que renvoie la plateforme quand
    // la PlatformView est déjà détruite).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName),
            (MethodCall call) async {
      throw MissingPluginException(
          'No implementation found for method ${call.method}');
    });
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(channelName);

    // Aucun de ces appels « tire-et-oublie » ne doit faire remonter une
    // exception non rattrapée (avant le correctif, dispose crashait la zone).
    controller.play();
    controller.pause();
    controller.setVolume(0);
    controller.seekTo(const Duration(seconds: 5));
    controller.dispose();

    // Laisse les Futures des invokeMethod se résoudre (et leurs catchError
    // avaler l'exception) : si un seul ne rattrapait pas, le test échouerait
    // sur une erreur asynchrone non gérée.
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });

  // ---- Chemin de rendu : défaut TV = texture (l'image suit l'UI)
  group('NativeVideoRender.mode — défaut TV = texture', () {
    setUp(NativeVideoRender.debugResetCache);
    tearDown(() {
      NativeVideoRender.debugResetCache();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('native_video_player/info'), null);
    });

    void mockGetRenderMode(String? value) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('native_video_player/info'),
              (MethodCall call) async {
        if (call.method == 'getRenderMode') return value;
        return null;
      });
    }

    test('échec canal / tests → texture', () async {
      NativeVideoRender.debugResetCache();
      expect(await NativeVideoRender.mode(), NativeVideoRender.texture);
    });

    test('null / inconnu côté natif → texture', () async {
      NativeVideoRender.debugResetCache();
      mockGetRenderMode(null);
      expect(await NativeVideoRender.mode(), NativeVideoRender.texture);

      NativeVideoRender.debugResetCache();
      mockGetRenderMode('unknown');
      expect(await NativeVideoRender.mode(), NativeVideoRender.texture);
    });

    test('surface mémorisé explicitement → surface', () async {
      NativeVideoRender.debugResetCache();
      mockGetRenderMode(NativeVideoRender.surface);
      expect(await NativeVideoRender.mode(), NativeVideoRender.surface);
    });

    test('texture mémorisé → texture', () async {
      NativeVideoRender.debugResetCache();
      mockGetRenderMode(NativeVideoRender.texture);
      expect(await NativeVideoRender.mode(), NativeVideoRender.texture);
    });

    test('setMode(texture) est conservé par le cache', () async {
      NativeVideoRender.debugResetCache();
      await NativeVideoRender.setMode(NativeVideoRender.texture);
      expect(await NativeVideoRender.mode(), NativeVideoRender.texture);
    });
  });

  // ---- Ticks live : pas de notifyListeners sur position/buffered
  test('position/buffered sur un DIRECT (duration==0) mettent à jour les '
      'champs SANS notifyListeners', () async {
    const String name = 'native_video_player/test-live-ticks';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(name), (MethodCall call) async => null);
    Future<void> fromNative(String method, Object? args) async {
      final ByteData? message =
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(name, message, (ByteData? _) {});
    }

    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);
    int notifies = 0;
    controller.addListener(() => notifies++);

    expect(controller.duration, Duration.zero);
    await fromNative('position', 1500);
    expect(controller.position, const Duration(milliseconds: 1500));
    expect(notifies, 0,
        reason: 'un tick position live ne doit pas reconstruire l\'écran');

    await fromNative('buffered', 2000);
    expect(controller.buffered, const Duration(milliseconds: 2000));
    expect(notifies, 0,
        reason: 'un tick buffered live ne doit pas reconstruire l\'écran');

    await fromNative('playing', true);
    expect(controller.isPlaying, isTrue);
    expect(notifies, 1);

    await fromNative('buffering', false);
    expect(controller.isBuffering, isFalse);
    expect(notifies, 2);

    await fromNative('firstFrame', null);
    expect(controller.firstFrame, isTrue);
    expect(notifies, 3);

    await fromNative('duration', 60000);
    expect(controller.duration, const Duration(milliseconds: 60000));
    expect(notifies, 4);

    await fromNative('position', 2500);
    expect(controller.position, const Duration(milliseconds: 2500));
    expect(notifies, 5,
        reason: 'VOD (duration > 0) : position DOIT notifier (barre)');

    controller.dispose();
  });

  test('error / ended / tracks / cueText / netActive / videoSize notifient '
      'toujours (même en direct)', () async {
    const String name = 'native_video_player/test-always-notify';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(name), (MethodCall call) async => null);
    Future<void> fromNative(String method, Object? args) async {
      final ByteData? message =
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(name, message, (ByteData? _) {});
    }

    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);
    int notifies = 0;
    controller.addListener(() => notifies++);

    await fromNative('error', <String, Object>{'message': 'boom'});
    expect(controller.hasError, isTrue);
    expect(notifies, 1);

    await fromNative('ended', null);
    expect(controller.isEnded, isTrue);
    expect(notifies, 2);

    await fromNative('tracks', <String, Object>{
      'audio': <Object>[],
      'text': <Object>[],
    });
    expect(notifies, 3);

    await fromNative('cueText', 'bonjour');
    expect(controller.subtitleText, 'bonjour');
    expect(notifies, 4);

    await fromNative('netActive', true);
    expect(controller.netActive, isTrue);
    expect(notifies, 5);

    await fromNative('videoSize', <String, Object>{'width': 1920, 'height': 1080});
    expect(controller.videoWidth, 1920);
    expect(notifies, 6);

    controller.dispose();
  });
}
