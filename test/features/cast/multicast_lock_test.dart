// =========================================================
//  multicast_lock_test.dart — Correctif #2
// =========================================================
//  Vérifie que MulticastLock.acquire() :
//    - mémorise le résultat dans `lastAcquireOk`,
//    - ne lève jamais (false sur MissingPlugin / refus natif),
//  pour que le CastManager puisse diagnostiquer un picker vide.
// =========================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/multicast_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel('com.manzilionellm.tvking/multicast');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    MulticastLock.instance.lastAcquireOk = false;
  });

  test('acquire renvoie true → lastAcquireOk = true', () async {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return call.method == 'acquire' ? true : null;
    });
    final bool ok = await MulticastLock.instance.acquire();
    expect(ok, isTrue);
    expect(MulticastLock.instance.lastAcquireOk, isTrue);
  });

  test('acquire renvoie false → lastAcquireOk = false', () async {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async => false);
    final bool ok = await MulticastLock.instance.acquire();
    expect(ok, isFalse);
    expect(MulticastLock.instance.lastAcquireOk, isFalse);
  });

  test('aucun bridge natif (MissingPlugin) → false sans crash', () async {
    // Pas de handler → MissingPluginException côté MethodChannel.
    messenger.setMockMethodCallHandler(channel, null);
    final bool ok = await MulticastLock.instance.acquire();
    expect(ok, isFalse);
    expect(MulticastLock.instance.lastAcquireOk, isFalse);
  });
}
