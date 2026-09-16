// =========================================================
//  iptv_cert_store.dart — Confiance TLS des panels IPTV (TOFU)
// =========================================================
//  Les panels ont souvent un certificat auto-signé. `return true`
//  global = n'importe quel MITM vole user/pass Xtream. On pin le
//  premier SHA-256 vu par hôte : ça marche chez IBO/VLC au 1er
//  contact, et un attaquant qui arrive APRÈS est refusé.
//
//  JAMAIS pour nos hôtes (7themotion / pages.dev) : le backend
//  garde la validation système.
// =========================================================
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IptvCertTrust {
  IptvCertTrust._();

  static const String _kPrefs = 'net.iptv_cert_pins.v1';
  static const int _kMaxPins = 256;
  static final Map<String, String> _pins = <String, String>{};
  static bool _loaded = false;

  static bool isOurBackend(String host) {
    final String h = host.toLowerCase();
    return h.endsWith('7themotion.com') || h.contains('pages.dev');
  }

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await _hydrate();
  }

  static Future<void> _hydrate() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final String? raw = p.getString(_kPrefs);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((Object? k, Object? v) {
          if (k is String && v is String && k.isNotEmpty && v.isNotEmpty) {
            _pins.putIfAbsent(k.toLowerCase(), () => v);
          }
        });
      }
    } catch (_) {
      // best-effort
    }
  }

  static void forgetAll() {
    _pins.clear();
    SharedPreferences.getInstance()
        .then((SharedPreferences p) => p.remove(_kPrefs))
        .catchError((Object _) => false);
  }

  static void forget(String host) {
    _pins.remove(host.toLowerCase());
    _persist();
  }

  /// Callback [HttpClient.badCertificateCallback].
  static bool allow(X509Certificate cert, String host, int port) {
    if (!_loaded) {
      _loaded = true;
      // ignore: discarded_futures
      _hydrate();
    }
    if (isOurBackend(host)) return false;
    final String h = host.toLowerCase();
    final String pin = sha256.convert(cert.der).toString();
    final String? seen = _pins[h];
    if (seen == null) {
      if (_pins.length >= _kMaxPins) _pins.clear();
      _pins[h] = pin;
      _persist();
      return true;
    }
    return seen == pin;
  }

  static void _persist() {
    SharedPreferences.getInstance()
        .then((SharedPreferences p) =>
            p.setString(_kPrefs, jsonEncode(_pins)))
        .catchError((Object _) => false);
  }
}
