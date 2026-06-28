// =========================================================
//  screen_cast_service.dart — « Caster sur un écran » (cross-réseau)
// =========================================================
//  Caster sur N'IMPORTE QUEL écran avec un navigateur (Smart TV, PC,
//  vidéoprojecteur…), même si la TV et le téléphone ne sont PAS sur le
//  même Wi-Fi. Tout passe par le Worker (cf. cloudflare/worker.js
//  handleScreen + screen_receiver.js) : on crée une session, on affiche
//  un QR pointant vers app.7themotion.com/e/<CODE>, la TV ouvre ce lien
//  dans son navigateur et lit le flux proxifié en HTTPS par le Worker.
//
//  Ce service ne fait QUE parler au Worker (créer la session, pousser
//  des commandes play/pause/stop). L'affichage du QR + le pilotage sont
//  dans la couche présentation. Tout est best-effort / fail-open : une
//  erreur réseau ne casse jamais la lecture locale.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../subscription/data/subscription_backend.dart';

/// Une session « écran » créée côté Worker.
@immutable
class ScreenSession {
  const ScreenSession({required this.code, required this.url});

  /// Code court (4 caractères, ex. « K7Q2 ») affiché sur la TV.
  final String code;

  /// URL complète à encoder dans le QR (ex. https://app.7themotion.com/e/K7Q2).
  final String url;
}

class ScreenCastService {
  ScreenCastService._();
  static final ScreenCastService instance = ScreenCastService._();

  static const Duration _timeout = Duration(seconds: 15);

  /// Crée une session d'écran. Renvoie `null` si indisponible (réseau,
  /// backend non configuré) → l'UI affiche un message au lieu de crasher.
  Future<ScreenSession?> create() async {
    try {
      final http.Response resp = await http
          .post(Uri.parse('$kSubscriptionBaseUrl/api/screen/new'))
          .timeout(_timeout);
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('[ScreenCast] new HTTP ${resp.statusCode}');
        return null;
      }
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final String? code = body['code'] as String?;
      final String? url = body['url'] as String?;
      if (code == null || url == null) return null;
      return ScreenSession(code: code, url: url);
    } catch (e) {
      if (kDebugMode) debugPrint('[ScreenCast] create error: $e');
      return null;
    }
  }

  /// Demande à l'écran de jouer `streamUrl` (flux IPTV brut — le Worker
  /// le proxifie en HTTPS pour la TV). Renvoie `true` si accepté.
  Future<bool> play(String code, String streamUrl, {String title = ''}) =>
      _command(code, <String, String>{
        'action': 'play',
        'url': streamUrl,
        'title': title,
      });

  Future<bool> pause(String code) =>
      _command(code, <String, String>{'action': 'pause'});

  Future<bool> resume(String code) =>
      _command(code, <String, String>{'action': 'resume'});

  Future<bool> stop(String code) =>
      _command(code, <String, String>{'action': 'stop'});

  Future<bool> _command(String code, Map<String, String> payload) async {
    try {
      final http.Response resp = await http
          .post(
            Uri.parse('$kSubscriptionBaseUrl/api/screen/$code/command'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('[ScreenCast] command error: $e');
      return false;
    }
  }
}
