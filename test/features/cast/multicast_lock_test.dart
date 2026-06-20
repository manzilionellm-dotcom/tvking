// =========================================================
//  multicast_lock_test.dart — contrat du pont MulticastLock
// =========================================================
//  Vérifie que MulticastLock.acquire() :
//    - renvoie `true` quand le natif accorde le lock ;
//    - renvoie `false` quand le natif refuse ;
//    - renvoie `false` SANS lever quand il n'y a pas de bridge natif
//      (MissingPluginException : iOS / Web / test) — l'appelant doit pouvoir
//      continuer la découverte de toute façon.
//
//  NB : l'API ne mémorise plus le résultat dans un champ `lastAcquireOk`
//  (supprimé lors d'un refactor) ; on vérifie donc directement la valeur
//  RENVOYÉE par acquire(), qui est le contrat actuel (cf. multicast_lock.dart).
// =========================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/multicast_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel('com.manzilionellm.tvking/multicast');
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('acquire renvoie true quand le natif accorde le lock', () async {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return call.method == 'acquire' ? true : null;
    });
    expect(await MulticastLock.instance.acquire(), isTrue);
  });

  test('acquire renvoie false quand le natif refuse', () async {
    messenger.setMockMethodCallHandler(
        channel, (MethodCall call) async => false);
    expect(await MulticastLock.instance.acquire(), isFalse);
  });

  test('aucun bridge natif (MissingPlugin) → false sans crash', () async {
    // Pas de handler → MissingPluginException côté MethodChannel.
    messenger.setMockMethodCallHandler(channel, null);
    expect(await MulticastLock.instance.acquire(), isFalse);
  });
}
