// =========================================================
//  multicast_lock.dart — Pont vers le MulticastLock natif
// =========================================================
//  Wrapper Dart au-dessus du MethodChannel
//  `com.manzilionellm.tvking/multicast`, implémenté côté Kotlin
//  par `MulticastLockBridge.kt`.
//
//  POURQUOI c'est vital pour le cast :
//    Sur Android, la puce WiFi ignore par défaut les paquets
//    multicast qui ne lui sont pas directement adressés (économie
//    de batterie). Conséquence : la découverte mDNS des Chromecast
//    (`_googlecast._tcp` sur 224.0.0.251) et la découverte SSDP des
//    TVs DLNA (239.255.255.250) ENVOIENT leurs requêtes mais ne
//    REÇOIVENT jamais les réponses. Le picker affiche alors 0
//    appareil et "le cast ne marche pas".
//
//    Tenir un `WifiManager.MulticastLock` pendant le scan force la
//    puce à remonter ces paquets. On le prend au DÉBUT de la
//    découverte et on le relâche à la FIN (le garder en permanence
//    viderait la batterie).
//
//  Usage typique (cf. mdns_discovery.dart / ssdp_discovery.dart) :
//
//    await MulticastLock.instance.acquire();
//    try {
//      // ... découverte ...
//    } finally {
//      await MulticastLock.instance.release();
//    }
//
//  Robustesse : sur les plateformes sans bridge natif (iOS, Web,
//  tests unitaires), `acquire()` renvoie `false` sans lever, et la
//  découverte continue quand même (elle peut fonctionner sur
//  certains environnements qui ne filtrent pas le multicast).
// =========================================================

import 'package:flutter/services.dart';

import '../../../core/observability/structured_logger.dart';

class MulticastLock {
  MulticastLock._();
  static final MulticastLock instance = MulticastLock._();

  /// Doit être IDENTIQUE au CHANNEL de MulticastLockBridge.kt.
  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/multicast');

  /// Résultat de la DERNIÈRE tentative `acquire()`. Lu par le
  /// CastManager : si la découverte ne trouve rien ET que ce flag est
  /// `false`, on affiche un message UX actionnable (permissions WiFi /
  /// réseau) au lieu d'un échec muet.
  bool lastAcquireOk = false;

  /// Prend le lock multicast. Retourne `true` si le lock a bien été
  /// acquis côté natif, `false` sinon (pas de bridge, pas de WiFi,
  /// permission absente). On NE lève PAS : l'appelant continue la
  /// découverte de toute façon.
  Future<bool> acquire() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('acquire');
      lastAcquireOk = ok ?? false;
      if (!lastAcquireOk) {
        StructuredLogger.instance.warn(
          domain: 'cast',
          event: 'multicast_lock.acquire_failed',
          ctx: const <String, Object?>{'reason': 'native_returned_false'},
        );
      }
      return lastAcquireOk;
    } on MissingPluginException {
      // Pas d'implémentation native (iOS / Web / test) — on laisse
      // la découverte tenter sa chance.
      lastAcquireOk = false;
      StructuredLogger.instance.warn(
        domain: 'cast',
        event: 'multicast_lock.acquire_failed',
        ctx: const <String, Object?>{'reason': 'missing_plugin'},
      );
      return false;
    } on PlatformException catch (e) {
      lastAcquireOk = false;
      StructuredLogger.instance.warn(
        domain: 'cast',
        event: 'multicast_lock.acquire_failed',
        ctx: <String, Object?>{
          'reason': 'platform_exception',
          'code': e.code,
          'message': e.message,
        },
      );
      return false;
    }
  }

  /// Relâche le lock. Best-effort : on n'a aucune action de secours
  /// utile si ça échoue, et un lock orphelin sera de toute façon
  /// nettoyé quand le process meurt.
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } on MissingPluginException {
      // rien à faire
    } on PlatformException catch (e) {
      StructuredLogger.instance.warn(
        domain: 'cast',
        event: 'multicast_lock.release_failed',
        ctx: <String, Object?>{'code': e.code, 'message': e.message},
      );
    }
  }
}
