// =========================================================
//  iptv_exit.dart — « Sortie réseau » (IP) par appareil
// =========================================================
//  PROBLÈME MÉTIER (terrain) : un fournisseur IPTV verrouille souvent le
//  compte Xtream sur UNE seule IP (celle du 1er visionnage). Quand le
//  client voyage (Suède → Allemagne), le fournisseur voit une IP
//  différente et coupe tout. L'admin doit pouvoir, à distance, faire
//  passer CE client par une sortie fixe (un proxy que l'admin contrôle,
//  situé dans le bon pays) — sans que le client touche à rien.
//
//  MÉCANISME : ce singleton porte le proxy assigné à l'appareil (récupéré
//  du panel via /api/device-net/:mac, livré instantanément par la synchro).
//  On l'applique au SEUL point de passage réseau IPTV de l'app :
//    1. `createIptvHttpClient()` (API Xtream, M3U, health) → HttpClient.findProxy
//    2. le relais local de lecture (chemin vidéo TV) → même findProxy
//    3. le lecteur mobile mpv → propriété `http-proxy`
//  Quand AUCUNE sortie n'est assignée, `directive` vaut « DIRECT » et
//  `mpvProxy` est vide → comportement identique à aujourd'hui (zéro
//  régression). On ne touche JAMAIS le trafic vers NOTRE backend.
// =========================================================

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Sortie réseau active (proxy). Vide = trafic direct (défaut).
class IptvExit {
  IptvExit._();
  static final IptvExit instance = IptvExit._();

  /// Proxy sous forme lisible : 'http://[user:pass@]host:port' ou
  /// 'socks5://host:port'. Vide = pas de sortie (direct).
  String _proxy = '';

  /// Libellé affiché (ex. « Suède 🇸🇪 ») — purement informatif.
  String _label = '';

  /// Notifie les écrans lecteur ouverts qu'ils doivent ré-appliquer le
  /// proxy (ex. l'admin change la sortie pendant que la TV joue).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String get label => _label;
  bool get isActive => _hostPort() != null;

  /// Met à jour la sortie. Renvoie true si elle a changé (→ l'appelant
  /// peut relancer la lecture pour que le nouveau chemin prenne effet).
  bool update({required String proxy, String label = ''}) {
    final String p = proxy.trim();
    if (p == _proxy && label == _label) return false;
    _proxy = p;
    _label = label.trim();
    revision.value++;
    if (kDebugMode) {
      debugPrint('[IptvExit] sortie = ${_proxy.isEmpty ? "DIRECT" : _proxy}');
    }
    return true;
  }

  void clear() => update(proxy: '', label: '');

  /// (scheme, host, port, user, pass) extrait du proxy, ou null si vide/invalide.
  ({String scheme, String host, int port, String? user, String? pass})?
      _parsed() {
    if (_proxy.isEmpty) return null;
    // Tolère « host:port » nu (sans schéma) → http par défaut.
    final String raw =
        _proxy.contains('://') ? _proxy : 'http://$_proxy';
    final Uri? u = Uri.tryParse(raw);
    if (u == null || u.host.isEmpty || !u.hasPort) return null;
    final String scheme = u.scheme.isEmpty ? 'http' : u.scheme.toLowerCase();
    String? user;
    String? pass;
    if (u.userInfo.isNotEmpty) {
      final int i = u.userInfo.indexOf(':');
      if (i >= 0) {
        user = u.userInfo.substring(0, i);
        pass = u.userInfo.substring(i + 1);
      } else {
        user = u.userInfo;
      }
    }
    return (scheme: scheme, host: u.host, port: u.port, user: user, pass: pass);
  }

  ({String host, int port})? _hostPort() {
    final p = _parsed();
    if (p == null) return null;
    return (host: p.host, port: p.port);
  }

  /// Directive pour `HttpClient.findProxy` : 'PROXY host:port' (HTTP),
  /// 'SOCKS5 host:port' (SOCKS), ou 'DIRECT' si aucune sortie.
  String get directive {
    final p = _parsed();
    if (p == null) return 'DIRECT';
    if (p.scheme.startsWith('socks')) return 'SOCKS5 ${p.host}:${p.port}';
    return 'PROXY ${p.host}:${p.port}';
  }

  /// Proxy pour mpv (lecteur mobile) : 'http://[user:pass@]host:port' ou
  /// 'socks5://...'. Vide si aucune sortie (mpv le remet alors à direct).
  String get mpvProxy {
    final p = _parsed();
    if (p == null) return '';
    return _proxy.contains('://') ? _proxy : 'http://$_proxy';
  }

  /// Applique la sortie à un [HttpClient] IPTV : findProxy + éventuelles
  /// identifiants d'authentification proxy. No-op si aucune sortie → le
  /// client reste en direct (comportement historique).
  void applyTo(HttpClient client) {
    final p = _parsed();
    if (p == null) return; // pas de sortie → direct, on ne touche à rien
    client.findProxy = (_) => directive;
    if (p.user != null && p.user!.isNotEmpty) {
      // HTTP proxy authentifié (Basic). Sans effet sur un proxy ouvert.
      client.addProxyCredentials(
        p.host, p.port, '', HttpClientBasicCredentials(p.user!, p.pass ?? ''),
      );
    }
  }
}
