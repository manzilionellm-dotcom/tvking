// =========================================================
//  black_box_upload.dart — La boîte noire part vers le panel
// =========================================================
//  Même lien que l'activation : le Worker déjà utilisé par
//  l'app (kSubscriptionBaseUrl), la même MAC virtuelle, la
//  même base. On n'ouvre pas un deuxième serveur.
//
//  L'envoi a lieu :
//    • à l'ouverture (quelques secondes après le boot, le
//      temps que les premières lignes soient écrites) ;
//    • toutes les 45 s tant que l'app tourne ;
//    • à la demande : écran Boîte noire ouvert, ou le panel
//      a posé `blackbox_pull` dans le statut que la box lit
//      déjà (toutes les 3 à 4 s).
//
//  Le texte est filtré AVANT de partir (black_box_redaction).
//  L'interrupteur SharedPreferences coupe tout. Un échec
//  réseau ne bloque jamais la télé : on réessaiera au tour
//  suivant. On n'écrit pas le journal dans le debug (il peut
//  encore contenir un nom de chaîne, inutile dans logcat).
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/device/data/device_identity.dart';
import '../../features/subscription/data/subscription_backend.dart';
import 'black_box.dart';
import 'black_box_redaction.dart';
import 'black_box_upload_flag.dart';

class BlackBoxUpload {
  BlackBoxUpload._();
  static final BlackBoxUpload instance = BlackBoxUpload._();

  /// Assez souvent pour que le panel ne soit pas en retard,
  /// assez rare pour ne pas écrire en base à chaque seconde.
  static const Duration period = Duration(seconds: 45);

  Timer? _timer;
  bool _started = false;
  bool _busy = false;
  bool _again = false;
  int _lastPull = 0;

  /// À appeler une fois, après l'init de la boîte noire.
  /// Branche aussi l'écoute du statut (le panel qui demande).
  void start() {
    if (_started) return;
    _started = true;
    SubscriptionBackend.onStatusBody = _onStatus;
    Future<void>.delayed(const Duration(seconds: 2), () {
      send('ouverture');
    });
    _timer = Timer.periodic(period, (_) => send('périodique'));
  }

  /// Écran Boîte noire ouvert, ou le panel vient de demander.
  void nudge() => send('demande');

  @visibleForTesting
  void stopForTesting() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _busy = false;
    _again = false;
    if (SubscriptionBackend.onStatusBody == _onStatus) {
      SubscriptionBackend.onStatusBody = null;
    }
  }

  void _onStatus(Map<String, dynamic> body) {
    final int pull = (body['blackbox_pull'] as num?)?.toInt() ?? 0;
    if (pull <= 0 || pull <= _lastPull) return;
    _lastPull = pull;
    nudge();
  }

  /// Best-effort. Ne throw pas. Si un envoi est déjà en cours,
  /// on en refera un juste après (la demande du panel ne se perd pas).
  Future<void> send(String reason) async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      await _once(reason);
    } catch (e) {
      if (kDebugMode) debugPrint('[BlackBox] envoi ignoré : $e');
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        await send(reason);
      }
    }
  }

  Future<void> _once(String reason) async {
    await blackBoxUploadFlag.load();
    if (!blackBoxUploadFlag.value) return;
    // Même nombre de lignes que l'écran (400). Le filtre et la
    // coupe à 32 Ko se font ensuite : le panel voit ces lignes,
    // secrets masqués, les plus récentes en priorité.
    final List<String> lines = await BlackBox.instance.tail(max: 400);
    final String? text = prepareBlackBoxUpload(lines.join('\n'), enabled: true);
    if (text == null) return;
    final String mac = (await DeviceIdentity.instance.mac).trim().toUpperCase();
    if (mac.isEmpty) return;
    final http.Response resp = await http
        .post(
          Uri.parse('$kSubscriptionBaseUrl/api/blackbox'),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, String>{'mac': mac, 'text': text}),
        )
        .timeout(const Duration(seconds: 8));
    if (kDebugMode && resp.statusCode != 200) {
      debugPrint('[BlackBox] envoi $reason HTTP ${resp.statusCode}');
    }
  }
}
