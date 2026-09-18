// =========================================================
//  native_video_controller_net_idle_test.dart — fermeture RÉELLE des sockets
// =========================================================
//  Enquête « limite de connexions (1/1) » du 20/08, hypothèse H1 : la réponse
//  du canal `stop` prouve que la commande a été exécutée sur le thread
//  lecteur — PAS que la socket est fermée. Dans Media3, stop() est asynchrone
//  en interne : la fermeture réelle (DataSource.close) arrive APRÈS, sur le
//  thread de chargement. Le scénario terrain « je quitte le film, je lance
//  une chaîne » se joue dans cette fenêtre.
//
//  Le natif compte désormais les transferts réseau réels (TransferListener)
//  et signale à Dart les transitions « au moins une socket ↔ plus aucune »
//  (événement `netActive`). Ces tests verrouillent le contrat Dart :
//    • l'événement met à jour l'état et HORODATE la fermeture (la
//      chronologie à la milliseconde de la Boîte noire en dépend) ;
//    • awaitNetworkIdle ne répond true qu'à la fermeture réelle ;
//    • le timeout répond false — l'appelant doit alors le DIRE (journal)
//      au lieu de prétendre que la connexion est rendue ;
//    • dispose libère les attentes en vol (jamais d'attente fantôme).
// =========================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Branche un canal factice côté « plateforme » (les commandes Dart → natif
  /// répondent null) et renvoie une fonction qui SIMULE un événement envoyé
  /// PAR le natif (netActive, position…) exactement comme le ferait le
  /// MethodChannel Kotlin.
  Future<void> Function(String method, Object? args) fakeNative(
      String channelName) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            MethodChannel(channelName), (MethodCall call) async => null);
    return (String method, Object? args) async {
      final ByteData? message =
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channelName, message, (ByteData? _) {});
    };
  }

  test('l\'événement natif netActive met à jour l\'état et horodate la '
      'fermeture réelle des sockets', () async {
    const String name = 'native_video_player/test-net-state';
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    expect(controller.netActive, isFalse,
        reason: 'aucune socket tant que le natif n\'a rien signalé');
    expect(controller.lastNetIdleAt, isNull);

    await fromNative('netActive', true);
    expect(controller.netActive, isTrue);

    final DateTime before = DateTime.now();
    await fromNative('netActive', false);
    expect(controller.netActive, isFalse);
    expect(controller.lastNetIdleAt, isNotNull,
        reason: 'la fermeture réelle doit être horodatée : la chronologie '
            '« sortie du film → ouverture de la chaîne » se lit à la ms');
    expect(controller.lastNetIdleAt!.isBefore(before), isFalse);
  });

  test('awaitNetworkIdle répond true IMMÉDIATEMENT quand aucune socket '
      'n\'est ouverte (film local, lecteur jamais démarré)', () async {
    const String name = 'native_video_player/test-net-immediate';
    fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    expect(await controller.awaitNetworkIdle(), isTrue);
  });

  test('awaitNetworkIdle ne se résout qu\'à la fermeture RÉELLE '
      '(l\'événement net_idle du natif)', () async {
    const String name = 'native_video_player/test-net-wait';
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    await fromNative('netActive', true);
    bool resolved = false;
    final Future<bool> idle = controller
        .awaitNetworkIdle(timeout: const Duration(seconds: 5))
        .then((bool ok) {
      resolved = true;
      return ok;
    });
    // Laisse les microtâches tourner : rien ne doit se résoudre tant que la
    // socket est ouverte — c'est exactement le chevauchement qu'on interdit.
    await Future<void>.delayed(Duration.zero);
    expect(resolved, isFalse,
        reason: 'répondre avant la fermeture réelle recréerait la fenêtre '
            'de chevauchement « deux connexions se croisent »');

    await fromNative('netActive', false);
    expect(await idle, isTrue);
  });

  test('awaitNetworkIdle EXPIRE à false quand la socket ne se ferme jamais '
      '(l\'appelant doit le journaliser, pas prétendre le contraire)',
      () async {
    const String name = 'native_video_player/test-net-timeout';
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    await fromNative('netActive', true);
    expect(
      await controller
          .awaitNetworkIdle(timeout: const Duration(milliseconds: 50)),
      isFalse,
    );
  });

  test('dispose libère les attentes en vol (false : état inconnu, le release '
      'natif fermera les sockets de toute façon)', () async {
    const String name = 'native_video_player/test-net-dispose';
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    await fromNative('netActive', true);
    final Future<bool> idle =
        controller.awaitNetworkIdle(timeout: const Duration(seconds: 30));
    controller.dispose();
    expect(await idle, isFalse,
        reason: 'une attente qui survivrait au dispose bloquerait la '
            'fermeture d\'écran jusqu\'à son timeout complet');
  });
}
