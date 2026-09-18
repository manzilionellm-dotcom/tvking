// =========================================================
//  privacy_shield.dart — Mode Bouclier (vie privée du client)
// =========================================================
//  CE QUE C'EST. Un interrupteur par appareil qui rend l'app la plus
//  discrète possible vis-à-vis de l'extérieur : le fournisseur de chaînes,
//  le réseau, et nous-mêmes (le panel).
//
//  CE QU'IL FAIT, honnêtement, point par point :
//
//    1. COUPE-CIRCUIT VPN (`requireVpn`) : aucune lecture RÉSEAU ne part si
//       aucun VPN n'est actif sur l'appareil. Le client voit un message
//       clair et la lecture repart toute seule dès que le VPN revient.
//       C'est ce qui cache son adresse IP et son pays au fournisseur.
//    2. HTTPS PRÉFÉRÉ (`preferHttps`) : quand le serveur du fournisseur
//       répond en HTTPS, on l'utilise, pour que l'identifiant et le mot de
//       passe qui voyagent dans l'URL ne passent plus en clair sur le réseau.
//       On le vérifie une fois par serveur (jamais sur l'URL du flux, pour
//       ne pas consommer une connexion), et on s'en souvient.
//    3. TÉLÉMÉTRIE MINIMALE (`minimalTelemetry`) : la chaîne regardée,
//       l'inventaire des sources et l'historique ne quittent plus la box.
//       Le panel sait seulement que l'appareil est en ligne.
//
//  CE QU'IL NE FAIT PAS, et qu'on écrit noir sur blanc dans l'écran de
//  réglage : le fournisseur voit TOUJOURS quelle chaîne la ligne demande,
//  puisque c'est lui qui l'envoie. Aucun bouclier ne peut cacher ça.
//
//  ARCHITECTURE. Singleton observable (ChangeNotifier), même patron que
//  DisplaySettings / PlayerSettings : réglages en SharedPreferences, état
//  VPN rafraîchi par le canal natif `com.manzilionellm.tvking/device`
//  (méthode `isVpnActive`, plugin tvking_device + MainActivity mobile).
//  Les deux sondes (VPN, HTTPS) sont INJECTABLES pour les tests.
//
//  Le tunnel WireGuard INTÉGRÉ (l'app devient son propre VPN) est la
//  version 2 : il se branchera ici, derrière le même coupe-circuit.
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sonde « un VPN est-il actif sur l'appareil ? ».
typedef VpnProbe = Future<bool> Function();

/// Sonde « ce serveur répond-il en HTTPS ? » (URI = racine du serveur).
typedef HttpsProbe = Future<bool> Function(Uri serverRoot);

class PrivacyShield extends ChangeNotifier {
  PrivacyShield._();
  static final PrivacyShield instance = PrivacyShield._();

  // ----- Clés de persistance -----
  static const String _kEnabled = 'privacy_shield_enabled';
  static const String _kRequireVpn = 'privacy_shield_require_vpn';
  static const String _kPreferHttps = 'privacy_shield_prefer_https';
  static const String _kMinimalTelemetry = 'privacy_shield_minimal_telemetry';
  static const String _kHttpsHosts = 'privacy_shield_https_hosts_v1';

  /// Canal natif partagé avec DeviceIdentity (même nom, méthode ajoutée).
  static const MethodChannel _device =
      MethodChannel('com.manzilionellm.tvking/device');

  /// Cadence de la ronde VPN quand le coupe-circuit est armé. Court : c'est
  /// la fenêtre pendant laquelle un VPN tombé laisserait passer l'IP réelle
  /// avant que la lecture soit coupée.
  static const Duration vpnWatchEvery = Duration(seconds: 5);

  /// Durée de validité d'un verdict HTTPS mémorisé par serveur.
  static const Duration httpsMemoryTtl = Duration(days: 7);

  bool _enabled = false;
  bool _requireVpn = true;
  bool _preferHttps = true;
  bool _minimalTelemetry = true;
  bool _vpnActive = false;
  bool _loaded = false;
  Timer? _vpnWatch;
  Future<bool>? _vpnRefreshInFlight;

  /// `host:port` → (`true` = HTTPS OK, `false` = non) + horodatage.
  final Map<String, _HttpsVerdict> _httpsHosts = <String, _HttpsVerdict>{};

  /// Sondes injectables (tests). Défaut : natif / HttpClient.
  @visibleForTesting
  VpnProbe vpnProbe = _nativeVpnProbe;
  @visibleForTesting
  HttpsProbe httpsProbe = _defaultHttpsProbe;

  // ----- Lecture de l'état -----
  bool get enabled => _enabled;
  bool get requireVpn => _requireVpn;
  bool get preferHttps => _preferHttps;
  bool get minimalTelemetry => _minimalTelemetry;
  bool get isLoaded => _loaded;

  /// Dernier verdict connu de la sonde VPN.
  bool get vpnActive => _vpnActive;

  /// La détection VPN n'existe que là où le canal natif l'implémente
  /// (Android : plugin tvking_device + MainActivity mobile). Ailleurs
  /// (Windows, Tizen), le coupe-circuit est sans objet : on ne bloque jamais
  /// une lecture sur un « je ne sais pas ».
  bool get vpnDetectionSupported => !kIsWeb && Platform.isAndroid;

  /// La télémétrie doit-elle être réduite au strict minimum ?
  bool get minimalTelemetryActive => _enabled && _minimalTelemetry;

  /// Le coupe-circuit interdit-il, MAINTENANT, toute lecture réseau ?
  bool get blocksNetworkPlayback =>
      _enabled && _requireVpn && vpnDetectionSupported && !_vpnActive;

  /// Une URL « locale » (fichier téléchargé) ne passe par aucun réseau : le
  /// bouclier ne la concerne pas.
  static bool isLocalUrl(String url) =>
      url.startsWith('file:') || url.startsWith('/');

  // ----- Chargement / réglages -----
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
      _requireVpn = prefs.getBool(_kRequireVpn) ?? true;
      _preferHttps = prefs.getBool(_kPreferHttps) ?? true;
      _minimalTelemetry = prefs.getBool(_kMinimalTelemetry) ?? true;
      _loadHttpsMemory(prefs.getStringList(_kHttpsHosts) ?? const <String>[]);
    } catch (_) {
      // Prefs illisibles : défauts sûrs (bouclier éteint), jamais un crash.
    }
    _loaded = true;
    _syncVpnWatch();
    notifyListeners();
    if (_enabled) unawaited(refreshVpnStatus());
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    _syncVpnWatch();
    notifyListeners();
    if (value) unawaited(refreshVpnStatus());
    await _save(_kEnabled, value);
  }

  Future<void> setRequireVpn(bool value) async {
    _requireVpn = value;
    _syncVpnWatch();
    notifyListeners();
    if (value) unawaited(refreshVpnStatus());
    await _save(_kRequireVpn, value);
  }

  Future<void> setPreferHttps(bool value) async {
    _preferHttps = value;
    notifyListeners();
    await _save(_kPreferHttps, value);
  }

  Future<void> setMinimalTelemetry(bool value) async {
    _minimalTelemetry = value;
    notifyListeners();
    await _save(_kMinimalTelemetry, value);
  }

  Future<void> _save(String key, bool value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // best-effort : le réglage vaut au moins pour la session en cours.
    }
  }

  // ----- VPN -----

  /// Interroge la sonde VPN et met l'état à jour. Une seule interrogation en
  /// vol à la fois (les appelants concurrents partagent la même future).
  /// Renvoie le verdict. Ne lève jamais.
  Future<bool> refreshVpnStatus() {
    final Future<bool>? inFlight = _vpnRefreshInFlight;
    if (inFlight != null) return inFlight;
    final Future<bool> f = () async {
      bool active = false;
      try {
        active = await vpnProbe().timeout(const Duration(seconds: 3));
      } catch (_) {
        active = false;
      }
      if (active != _vpnActive) {
        _vpnActive = active;
        notifyListeners();
      }
      return active;
    }();
    _vpnRefreshInFlight = f;
    unawaited(f.whenComplete(() => _vpnRefreshInFlight = null));
    return f;
  }

  /// Le lecteur peut-il ouvrir [url] ? Rafraîchit la sonde avant de répondre
  /// (un VPN qui vient de se connecter ne doit pas être refusé).
  Future<bool> allowsPlayback(String url) async {
    if (!_enabled || !_requireVpn || !vpnDetectionSupported) return true;
    if (isLocalUrl(url)) return true;
    return refreshVpnStatus();
  }

  void _syncVpnWatch() {
    final bool wanted = _enabled && _requireVpn && vpnDetectionSupported;
    if (wanted && _vpnWatch == null) {
      _vpnWatch = Timer.periodic(vpnWatchEvery, (_) => refreshVpnStatus());
    } else if (!wanted && _vpnWatch != null) {
      _vpnWatch!.cancel();
      _vpnWatch = null;
      // Sans coupe-circuit, l'état VPN n'a plus d'effet : on l'efface pour
      // que `blocksNetworkPlayback` reparte d'un état neutre.
      _vpnActive = false;
    }
  }

  static Future<bool> _nativeVpnProbe() async {
    try {
      final bool? v = await _device.invokeMethod<bool>('isVpnActive');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  // ----- HTTPS préféré -----

  /// Renvoie l'URL à ouvrir : la variante HTTPS si le serveur la sert, sinon
  /// [url] inchangée. Jamais de sonde sur l'URL du flux elle-même (elle
  /// ouvrirait une connexion comptée par le fournisseur) : on sonde la RACINE
  /// du serveur, une fois, puis on s'en souvient [httpsMemoryTtl].
  Future<String> preferredUrl(String url) async {
    if (!_enabled || !_preferHttps) return url;
    final Uri? u = Uri.tryParse(url);
    if (u == null || u.scheme != 'http' || u.host.isEmpty) return url;
    final String key = '${u.host}:${u.hasPort ? u.port : 80}';
    final _HttpsVerdict? known = _httpsHosts[key];
    bool ok;
    if (known != null && !known.isStale) {
      ok = known.supportsHttps;
    } else {
      // Racine du serveur, sans chemin ni requête : jamais l'URL du flux
      // (elle contient les identifiants et ouvrirait une connexion comptée).
      final Uri root = Uri(
        scheme: 'https',
        host: u.host,
        port: u.hasPort ? u.port : null,
        path: '/',
      );
      try {
        ok = await httpsProbe(root).timeout(const Duration(seconds: 4));
      } catch (_) {
        ok = false;
      }
      _httpsHosts[key] = _HttpsVerdict(ok, DateTime.now());
      unawaited(_saveHttpsMemory());
    }
    return ok ? u.replace(scheme: 'https').toString() : url;
  }

  /// Oublie les verdicts HTTPS (bouton « re-tester » ou tests).
  Future<void> forgetHttpsMemory() async {
    _httpsHosts.clear();
    await _saveHttpsMemory();
  }

  static Future<bool> _defaultHttpsProbe(Uri root) async {
    // Même tolérance de certificat que le reste de l'app (iptv_http.dart) :
    // un panel en HTTPS auto-signé protège quand même l'URL en transit.
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
    try {
      final HttpClientRequest req = await client.headUrl(root);
      req.followRedirects = false;
      final HttpClientResponse resp = await req.close();
      await resp.drain<void>();
      // N'importe quelle réponse HTTP prouve que TLS est servi là.
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void _loadHttpsMemory(List<String> raw) {
    _httpsHosts.clear();
    for (final String line in raw) {
      // Format : host:port|1|<ms epoch>
      final List<String> parts = line.split('|');
      if (parts.length != 3) continue;
      final int? ms = int.tryParse(parts[2]);
      if (ms == null) continue;
      _httpsHosts[parts[0]] = _HttpsVerdict(
        parts[1] == '1',
        DateTime.fromMillisecondsSinceEpoch(ms),
      );
    }
  }

  Future<void> _saveHttpsMemory() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> raw = _httpsHosts.entries
          .where((MapEntry<String, _HttpsVerdict> e) => !e.value.isStale)
          .map((MapEntry<String, _HttpsVerdict> e) =>
              '${e.key}|${e.value.supportsHttps ? '1' : '0'}|'
              '${e.value.at.millisecondsSinceEpoch}')
          .toList(growable: false);
      await prefs.setStringList(_kHttpsHosts, raw);
    } catch (_) {
      // best-effort : au pire on re-sonde une fois de plus.
    }
  }

  /// Verdicts HTTPS connus (tests / écran de diagnostic).
  @visibleForTesting
  Map<String, bool> get httpsMemoryForTest => <String, bool>{
        for (final MapEntry<String, _HttpsVerdict> e in _httpsHosts.entries)
          e.key: e.value.supportsHttps,
      };

  @visibleForTesting
  void resetForTest() {
    _vpnWatch?.cancel();
    _vpnWatch = null;
    _enabled = false;
    _requireVpn = true;
    _preferHttps = true;
    _minimalTelemetry = true;
    _vpnActive = false;
    _loaded = false;
    _vpnRefreshInFlight = null;
    _httpsHosts.clear();
    vpnProbe = _nativeVpnProbe;
    httpsProbe = _defaultHttpsProbe;
  }
}

class _HttpsVerdict {
  const _HttpsVerdict(this.supportsHttps, this.at);
  final bool supportsHttps;
  final DateTime at;
  bool get isStale =>
      DateTime.now().difference(at) > PrivacyShield.httpsMemoryTtl;
}
