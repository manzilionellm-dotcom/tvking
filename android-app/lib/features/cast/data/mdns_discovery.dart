// =========================================================
//  mdns_discovery.dart — Découverte Chromecast / Google TV
// =========================================================
//  Les appareils Google Cast (Chromecast dongles, Google TV,
//  Android TV avec Cast intégré, Vizio SmartCast) s'annoncent
//  via mDNS sur le service `_googlecast._tcp.local`. On émet
//  un PTR, on suit les SRV/TXT pour récupérer le nom et l'IP.
//
//  Pour cette première version, on n'utilise PAS le protocole
//  CASTV2 natif (énorme implémentation protobuf + TLS). À la
//  place, dès que l'utilisateur sélectionne un Chromecast dans
//  le picker, on bascule automatiquement sur le fallback web
//  via QR code — qui marche parfaitement sur Google TV puisque
//  ces appareils ont tous un navigateur Chrome.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

import '../../../core/observability/structured_logger.dart';
import '../domain/cast_device.dart';
import 'multicast_lock.dart';

class MdnsDiscovery {
  MdnsDiscovery._();
  static final MdnsDiscovery instance = MdnsDiscovery._();

  static const String _kCastService = '_googlecast._tcp.local';

  /// Lance une découverte de durée [timeout] et émet un CastDevice
  /// pour chaque Chromecast / Google TV trouvé sur le LAN.
  ///
  /// 2026-07-09 — TOUT le travail du MDnsClient tourne dans une ZONE
  /// GARDÉE (`runZonedGuarded`). Le package `multicast_dns` fait ses
  /// envois UDP en asynchrone : quand le réseau tombe / que l'OS
  /// restreint l'app en arrière-plan, ses sockets internes lèvent des
  /// `SocketException: Send failed (errno = 1)` NON rattachées à un
  /// Future qu'on attend. Sans zone dédiée, elles remontaient à la zone
  /// globale → salves d'erreurs « crash » dans la boîte noire toutes
  /// les 60 s de warmup (constaté post-mortem 2026-07-09, port 5353).
  /// Ici on les capture, on journalise UNE fois par scan en `warn`
  /// (domaine cast) et la découverte s'arrête proprement.
  Stream<CastDevice> discover({
    Duration timeout = const Duration(seconds: 4),
  }) {
    final StreamController<CastDevice> controller =
        StreamController<CastDevice>();
    MDnsClient? client;
    bool lockAcquired = false;
    bool finished = false;
    bool zoneErrorLogged = false;

    Future<void> finish() async {
      if (finished) return;
      finished = true;
      try {
        client?.stop();
      } catch (_) {
        // stop() best-effort — le client peut déjà être arrêté.
      }
      if (lockAcquired) await MulticastLock.instance.release();
      if (!controller.isClosed) await controller.close();
    }

    // L'appelant (CastManager) annule l'abonnement à la deadline du
    // scan : on ferme alors socket + lock immédiatement, comme le
    // faisait le `finally` du générateur async* historique.
    controller.onCancel = finish;

    runZonedGuarded(() async {
      // INDISPENSABLE sur Android : sans MulticastLock, la puce WiFi
      // filtre les réponses mDNS (224.0.0.251) et on ne découvre AUCUN
      // Chromecast / Google TV. Pris pour la durée du scan, relâché
      // dans `finish()` (ne pas le garder = batterie).
      await MulticastLock.instance.acquire();
      lockAcquired = true;
      final MDnsClient c = MDnsClient();
      client = c;
      final Set<String> seenTargets = <String>{};
      try {
        await c.start();

        await for (final PtrResourceRecord ptr in c
            .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(_kCastService),
            )
            .timeout(timeout, onTimeout: (EventSink<PtrResourceRecord> sink) {
              sink.close();
            })) {
          if (controller.isClosed) break;
          // Pour chaque service trouvé, on demande SRV (port + target
          // hostname) et TXT (métadonnées dont le friendly name).
          final String serviceName = ptr.domainName;
          if (seenTargets.contains(serviceName)) continue;
          seenTargets.add(serviceName);

          final SrvResourceRecord? srv = await _firstOrNull(
            c.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(serviceName),
            ),
          );
          if (srv == null) continue;

          final List<TxtResourceRecord> txts = await c
              .lookup<TxtResourceRecord>(
                ResourceRecordQuery.text(serviceName),
              )
              .toList();
          final Map<String, String> meta = _parseTxt(txts);

          final IPAddressResourceRecord? ip = await _firstOrNull(
            c.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            ),
          );
          if (ip == null) continue;

          final String friendlyName = meta['fn'] ??
              meta['n'] ??
              srv.target.split('.').first;
          final String model = meta['md'] ?? 'Chromecast';
          final String uniqueId = meta['id'] ?? serviceName;

          if (controller.isClosed) break;
          controller.add(CastDevice(
            id: 'chromecast:$uniqueId',
            name: friendlyName,
            kind: CastDeviceKind.chromecast,
            host: ip.address.address,
            port: srv.port,
            controlUrl: 'mdns://${ip.address.address}:${srv.port}',
            manufacturer: 'Google Cast',
            model: model,
          ));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[mDNS] error: $e');
      } finally {
        await finish();
      }
    }, (Object e, StackTrace st) {
      // Erreur asynchrone orpheline des sockets internes du package —
      // journalisée UNE fois par scan, en warn cast (pas en crash).
      if (!zoneErrorLogged) {
        zoneErrorLogged = true;
        StructuredLogger.instance.warn(
          domain: 'cast',
          event: 'mdns.socket_error',
          ctx: <String, Object?>{'error': e.toString()},
        );
      }
    });

    return controller.stream;
  }

  Future<T?> _firstOrNull<T>(Stream<T> s) async {
    await for (final T item in s) {
      return item;
    }
    return null;
  }

  /// Les enregistrements TXT mDNS portent des `clef=valeur`. On
  /// agrège tout dans une map. Le Chromecast publie typiquement :
  ///   fn=<friendly name>, md=<model>, id=<uuid>, rs=<status>,
  ///   ic=<icon path>, ve=<version>, ca=<capabilities bitmask>.
  Map<String, String> _parseTxt(List<TxtResourceRecord> records) {
    final Map<String, String> out = <String, String>{};
    for (final TxtResourceRecord r in records) {
      for (final String entry in r.text.split('\n')) {
        final int eq = entry.indexOf('=');
        if (eq <= 0) continue;
        out[entry.substring(0, eq).trim()] = entry.substring(eq + 1).trim();
      }
    }
    return out;
  }
}
