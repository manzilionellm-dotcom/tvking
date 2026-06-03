// =========================================================
//  roku_ecp_transport.dart — Cast vers Roku
// =========================================================
//  Roku expose l'External Control Protocol (ECP) — une API
//  HTTP simple sur le port 8060 de chaque appareil. On lance
//  la chaîne "Roku Media Player" (channel ID 2213) avec l'URL
//  du flux passée en query string.
//
//  Limitations connues :
//    - Roku Media Player ne lit PAS le MPEG-TS brut (.ts). Pour
//      les flux IPTV traditionnels (Xtream Codes en TS), il
//      faut un endpoint HLS (.m3u8) côté serveur. La majorité
//      des serveurs Xtream exposent les deux : on essaie le
//      .m3u8 d'abord, sinon on demande au serveur de transmuxer.
//    - Pas de contrôle Play/Pause natif sur Media Player en
//      ECP ; on simule via les boutons distance (keypress).
//
//  Documentation : https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/cast_device.dart';
import 'cast_transport.dart';

class RokuEcpTransport implements CastTransport {
  RokuEcpTransport(this.device);

  final CastDevice device;

  /// Channel ID du "Roku Media Player" (préinstallé sur tous les Roku).
  static const String _kMediaPlayerChannelId = '2213';

  /// Base URL de l'ECP — Roku écoute sur le port 8060 par défaut.
  String get _base => 'http://${device.host}:${device.port}';

  @override
  Future<void> playStream({
    required String streamUrl,
    String title = 'BLACK7 ROYAL',
    String? imageUrl,
  }) async {
    final String videoFormat = _detectFormat(streamUrl);

    // Phase 1+/G1 : Roku ECP `launch` accepte un parametre optionnel
    // `posterUrl` que le channel media player utilise pour le visuel
    // d'attente. On le passe quand on l'a — Roku ignore les params
    // qu'il ne reconnait pas, donc sans risque sur les chaines tierces.
    final Map<String, String> params = <String, String>{
      'u': streamUrl,
      't': 'v',
      'videoFormat': videoFormat,
      'Title': title,
      if (imageUrl != null && imageUrl.isNotEmpty) 'posterUrl': imageUrl,
    };

    final Uri uri = Uri.parse(
      '$_base/launch/$_kMediaPlayerChannelId',
    ).replace(queryParameters: params);

    final http.Response resp = await http
        .post(uri)
        .timeout(const Duration(seconds: 5));

    if (resp.statusCode >= 400) {
      if (kDebugMode) {
        debugPrint('[Roku] launch → HTTP ${resp.statusCode}\n${resp.body}');
      }
      throw Exception(
        'Roku a refusé le flux (HTTP ${resp.statusCode}). '
        'Format $videoFormat probablement non supporté.',
      );
    }
  }

  @override
  Future<void> pause() => _keypress('Play');

  @override
  Future<void> resume() => _keypress('Play');

  @override
  Future<void> stop() => _keypress('Home');

  Future<void> _keypress(String key) async {
    final Uri uri = Uri.parse('$_base/keypress/${Uri.encodeComponent(key)}');
    await http.post(uri).timeout(const Duration(seconds: 3));
  }

  /// Devine le format vidéo à partir de l'extension/du chemin pour
  /// que Roku choisisse le bon décodeur. Roku Media Player accepte :
  /// `hls`, `dash`, `mp4`, `mkv`, `ism` (Smooth Streaming).
  String _detectFormat(String url) {
    final String lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'hls';
    if (lower.contains('.mpd')) return 'dash';
    if (lower.contains('.mp4')) return 'mp4';
    if (lower.contains('.mkv')) return 'mkv';
    if (lower.contains('.ism')) return 'ism';
    // Par défaut → on tente HLS, qui est le plus courant en IPTV.
    return 'hls';
  }

  /// Récupère les infos détaillées d'un Roku — utile pour afficher
  /// le modèle exact dans le picker. Appelé une fois lors de la
  /// découverte SSDP, pas pendant la lecture.
  static Future<Map<String, String>> queryDeviceInfo(String host) async {
    try {
      final http.Response resp = await http
          .get(Uri.parse('http://$host:8060/query/device-info'))
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return <String, String>{};
      return _parseSimpleXml(resp.body);
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Mini-parser XML pour la réponse query/device-info de Roku.
  /// On évite de dépendre du package `xml` ici pour rester léger ;
  /// la réponse est suffisamment plate (un seul niveau de balises).
  static Map<String, String> _parseSimpleXml(String body) {
    final RegExp tagRx = RegExp(r'<([a-zA-Z\-]+)>([^<]*)</\1>');
    final Map<String, String> out = <String, String>{};
    for (final RegExpMatch m in tagRx.allMatches(body)) {
      out[m.group(1)!] = HtmlUnescape.decode(m.group(2)!.trim());
    }
    return out;
  }
}

/// Mini-helper de décodage HTML — évite d'ajouter une dépendance
/// pour un usage aussi marginal.
class HtmlUnescape {
  static String decode(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}

