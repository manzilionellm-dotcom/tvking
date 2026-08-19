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
}
