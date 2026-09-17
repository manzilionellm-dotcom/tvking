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

  test('stop() attend la fermeture TCP réelle (awaitNetworkIdle) — les '
      'appelants qui n\'attendent que stop() ne croisent pas le flux suivant',
      () async {
    const String name = 'native_video_player/test-stop-wait';
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    await fromNative('netActive', true);
    bool resolved = false;
    final Future<void> stopped = controller.stop().then((_) {
      resolved = true;
    });
    // Laisse invokeMethod('stop') se résoudre : on ne doit PAS revenir
    // tant que le natif n'a pas signalé netActive:false.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(resolved, isFalse,
        reason: 'stop() ne doit pas revenir avant la fermeture TCP');
    expect(controller.isStopped, isTrue);

    await fromNative('netActive', false);
    await stopped;
    expect(resolved, isTrue);
  });

  test('stop() revient IMMÉDIATEMENT si déjà idle (aucune socket ouverte)',
      () async {
    const String name = 'native_video_player/test-stop-idle';
    fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    final Stopwatch sw = Stopwatch()..start();
    await controller.stop();
    expect(sw.elapsed, lessThan(const Duration(milliseconds: 500)));
    expect(controller.isStopped, isTrue);
  });

  test('stop() n\'est PAS levé si la socket ne se ferme pas (timeout 2 s)',
      () async {
    const String name = 'native_video_player/test-stop-timeout';
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    await fromNative('netActive', true);
    await controller.stop();
    expect(controller.isStopped, isTrue);
    controller.dispose();
  });

  // =========================================================
  //  L'ÉVÉNEMENT PEUT SE PERDRE — LA RÉPONSE, NON (18/09/2026)
  // =========================================================
  //  Le propriétaire envoie la Boîte noire de sa box :
  //
  //    [creneau] Fermeture réseau NON confirmée : une socket du lecteur
  //    était encore ouverte 5211 ms après la sortie (stop natif : 2209 ms)
  //
  //  Deux mensonges dans une seule ligne.
  //
  //  1. 5211 ms n'était pas une observation : c'était la somme de NOS
  //     propres délais (2 s dans `stop()` + 3 s chez l'appelant). On
  //     n'avait jamais vu de socket ouverte à 5211 ms — on avait cessé
  //     d'attendre. Même défaut que `uaTried: 0` corrigé la veille.
  //
  //  2. « stop natif : 2209 ms » incluait 2 s d'attente réseau. L'arrêt
  //     natif réel prend ~200 ms. On a cherché une lenteur inexistante.
  //
  //  LA CAUSE : Dart n'apprenait « plus aucune socket » QUE par
  //  l'événement `netActive:false`. Or cet événement se perd —
  //  `notifyNetActive` l'abandonne si la vue est déjà démontée. Pendant
  //  ce temps, la réponse du canal `stop`, qui vient d'un natif ayant
  //  SONDÉ son compteur de transferts, était jetée (`invokeMethod<void>`).
  //
  //  On mesurait la bonne chose et on la mettait à la poubelle.

  test('la RÉPONSE de stop suffit : plus besoin d\'attendre l\'événement',
      () async {
    const String name = 'native_video_player/test-stop-reponse-true';
    // `fakeNative` d'abord (il installe un canal qui répond null à tout),
    // PUIS on le remplace : ce natif-ci répond `true` à `stop` — il a
    // sondé, tout est fermé — et n'envoie JAMAIS l'événement
    // `netActive:false`. C'est exactement le cas qui faisait écrire
    // « NON confirmée » à tort.
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name),
            (MethodCall call) async => call.method == 'stop' ? true : null);

    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);
    await fromNative('netActive', true);
    expect(controller.netActive, isTrue);

    final Stopwatch sw = Stopwatch()..start();
    await controller.stop();
    sw.stop();

    expect(controller.netActive, isFalse,
        reason: 'la réponse du natif vaut constat : plus aucune socket');
    expect(controller.lastNetIdleAt, isNotNull,
        reason: 'la chronologie de la Boîte noire en dépend');
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)),
        reason: 'aucune raison d\'attendre 2 s un événement dont la réponse '
            'vient de donner le contenu');

    // Et le contrôle qui compte : un appelant qui redemande obtient TRUE,
    // donc la Boîte noire écrit « terminée » au lieu de « NON confirmée ».
    expect(await controller.awaitNetworkIdle(), isTrue);
  });

  test('une réponse `false` garde son sens : là, on n\'a PAS confirmé',
      () async {
    const String name = 'native_video_player/test-stop-reponse-false';
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name),
            (MethodCall call) async => call.method == 'stop' ? false : null);

    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);
    await fromNative('netActive', true);

    // `false` = le natif a atteint son plafond ET compte encore une socket.
    // C'est le SEUL cas où « non confirmée » est mérité — on ne doit pas
    // l'effacer en même temps que le faux positif.
    await controller.stop(awaitIdle: false);
    expect(controller.netActive, isTrue,
        reason: 'un vrai chevauchement doit rester visible dans le journal');
    controller.dispose();
  });

  test('awaitIdle:false rend la main tout de suite — plus de triple attente',
      () async {
    const String name = 'native_video_player/test-stop-sans-attente';
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    await fromNative('netActive', true);

    // La même condition était attendue à trois étages : le natif sonde
    // (2 s), `stop()` attendait (2 s), l'appelant attendait encore (3 s).
    // Sept secondes possibles en quittant une chaîne. L'appelant qui fait
    // sa propre attente passe `false` et ne paie plus celle du milieu.
    final Stopwatch sw = Stopwatch()..start();
    await controller.stop(awaitIdle: false);
    sw.stop();

    expect(sw.elapsed, lessThan(const Duration(milliseconds: 500)),
        reason: 'avec awaitIdle:false, stop() ne doit rien attendre');
    expect(controller.isStopped, isTrue);
    controller.dispose();
  });

  test('par DÉFAUT stop() attend encore — les autres appelants sont intacts',
      () async {
    // Une quinzaine d'écrans appellent `stop()` sans rien attendre d'autre.
    // Changer leur comportement en même temps aurait transformé un
    // correctif ciblé en pari sur toute l'app.
    const String name = 'native_video_player/test-stop-defaut';
    final Future<void> Function(String, Object?) fromNative = fakeNative(name);
    final NativeVideoController controller = NativeVideoController();
    controller.debugAttachChannel(name);

    await fromNative('netActive', true);
    bool rendu = false;
    final Future<void> arret = controller.stop().then((_) => rendu = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rendu, isFalse, reason: 'le défaut doit rester bloquant');

    await fromNative('netActive', false);
    await arret;
    expect(rendu, isTrue);
  });
}
