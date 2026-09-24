// =========================================================
//  dlna_capabilities.dart — Récupération des profils supportés
// =========================================================
//  Chaque MediaRenderer DLNA expose un service "ConnectionManager"
//  avec une action `GetProtocolInfo` qui renvoie deux champs :
//
//    - Source : ce que le device peut PUBLIER (souvent vide pour
//      un récepteur pur).
//    - Sink   : la liste de TOUS les `protocolInfo` qu'il accepte
//      en LECTURE — exactement ce dont on a besoin pour décider
//      si notre flux va passer ou pas.
//
//  Exemple (Samsung 2020) :
//    http-get:*:video/mp2t:DLNA.ORG_PN=MPEG_TS_SD_NA_ISO,
//    http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_BL_CIF15_AAC_520,
//    http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_HP_HD_AAC,
//    http-get:*:video/mpeg:*,
//    http-get:*:application/octet-stream:*
//
//  On cache le résultat par device id pour éviter de réinterroger
//  à chaque cast. Les capacités ne changent pas pendant la session
//  d'app (et même rarement entre sessions).
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../domain/cast_device.dart';

@immutable
class DlnaSink {
  const DlnaSink({
    required this.deviceId,
    required this.entries,
    required this.fetchedAt,
  });

  final String deviceId;

  /// Liste brute des chaînes `protocolInfo` annoncées. Format :
  ///   http-get:*:<MIME>:<DLNA-flags>
  final List<String> entries;

  final DateTime fetchedAt;

  bool get isEmpty => entries.isEmpty;

  /// Renvoie la liste des MIMEs uniques détectés (lowercased).
  /// Utile pour des décisions rapides ("ce récepteur fait du
  /// video/mp2t ?").
  Set<String> get mimeTypes {
    final Set<String> out = <String>{};
    for (final String e in entries) {
      final List<String> parts = e.split(':');
      if (parts.length >= 3) out.add(parts[2].toLowerCase());
    }
    return out;
  }
}

class DlnaCapabilities {
  DlnaCapabilities._();
  static final DlnaCapabilities instance = DlnaCapabilities._();

  /// Cache mémoire : on évite de réinterroger le device pendant
  /// la même session d'app (les caps DLNA ne bougent pas).
  final Map<String, DlnaSink> _cache = <String, DlnaSink>{};

  /// Récupère (ou réutilise) la Sink d'un device. Sur un échec
  /// (device down, service inexistant), on cache une Sink vide
  /// pour ne pas retenter en boucle pendant le failover.
  Future<DlnaSink> fetchSink(
    CastDevice device, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final DlnaSink? cached = _cache[device.id];
    if (cached != null) return cached;

    final DlnaSink sink = await _fetchSink(device, timeout: timeout);
    _cache[device.id] = sink;
    return sink;
  }

  Future<DlnaSink> _fetchSink(
    CastDevice device, {
    required Duration timeout,
  }) async {
    // Le controlUrl du device pointe vers le service AVTransport ;
    // ConnectionManager est UN AUTRE service du même device. On
    // déduit son URL en gardant le même schéma + host + port et en
    // remplaçant le chemin par /ConnectionManager/control (variante
    // la plus courante), ET en tentant /upnp/control/ConnectionManager
    // si la première répond 404.
    final Uri base = Uri.parse(device.controlUrl);
    final List<String> candidates = <String>[
      base.replace(path: '/ConnectionManager/control').toString(),
      base.replace(path: '/upnp/control/ConnectionManager').toString(),
      base.replace(path: '/dmr/control_3').toString(),
      // Beaucoup de devices exposent ConnectionManager au même chemin
      // de base que AVTransport, juste sous /ConnectionManager au lieu
      // de /AVTransport :
      base
          .replace(
            path: base.path.replaceAll('AVTransport', 'ConnectionManager'),
          )
          .toString(),
    ];

    for (final String url in candidates) {
      try {
        final List<String> entries =
            await _callGetProtocolInfo(url, timeout: timeout);
        if (entries.isNotEmpty) {
          return DlnaSink(
            deviceId: device.id,
            entries: entries,
            fetchedAt: DateTime.now(),
          );
        }
      } on Exception catch (e) {
        if (kDebugMode) debugPrint('[DLNA caps] $url → $e');
        // continue vers le candidat suivant
      }
    }

    // Aucun candidat n'a répondu — Sink vide = on cast quand même
    // mais sans vérification de compat (best effort).
    return DlnaSink(
      deviceId: device.id,
      entries: const <String>[],
      fetchedAt: DateTime.now(),
    );
  }

  Future<List<String>> _callGetProtocolInfo(
    String controlUrl, {
    required Duration timeout,
  }) async {
    const String service =
        'urn:schemas-upnp-org:service:ConnectionManager:1';
    const String envelope =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:GetProtocolInfo xmlns:u="$service"/>'
        '</s:Body>'
        '</s:Envelope>';

    final http.Response resp = await http
        .post(
          Uri.parse(controlUrl),
          headers: const <String, String>{
            'Content-Type': 'text/xml; charset=utf-8',
            'SOAPAction': '"$service#GetProtocolInfo"',
            'Connection': 'close',
          },
          body: envelope,
        )
        .timeout(timeout);

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }

    // Parse l'enveloppe SOAP pour extraire <Sink>...</Sink>
    final XmlDocument doc = XmlDocument.parse(resp.body);
    final Iterable<XmlElement> sinks = doc.findAllElements('Sink');
    if (sinks.isEmpty) return const <String>[];
    final String raw = sinks.first.innerText.trim();
    if (raw.isEmpty) return const <String>[];

    // La Sink est une liste séparée par des virgules. Attention :
    // certains profils contiennent eux-mêmes des `,` dans les flags
    // (ex. DLNA.ORG_PN=AVC,XYZ). Heureusement le format dit "comma-
    // separated protocolInfo entries" — chaque entry commence par
    // un schéma (http-get, rtsp-rtp-udp...). On splitte par virgule
    // PUIS on agrège les fragments qui ne commencent pas par un
    // schéma reconnu (ils appartiennent à l'entry précédente).
    final List<String> split = raw.split(',');
    final List<String> out = <String>[];
    for (final String chunk in split) {
      final String trimmed = chunk.trim();
      if (trimmed.isEmpty) continue;
      if (_looksLikeProtocolEntry(trimmed)) {
        out.add(trimmed);
      } else if (out.isNotEmpty) {
        // Recolle à l'entry précédente avec la virgule retirée
        out[out.length - 1] = '${out.last},$trimmed';
      }
    }
    return out;
  }

  bool _looksLikeProtocolEntry(String s) {
    return s.startsWith('http-get:') ||
        s.startsWith('rtsp-rtp-udp:') ||
        s.startsWith('internal:');
  }

  /// Permet d'invalider le cache manuellement (debug, "réessayer").
  void clearCache() => _cache.clear();
}
