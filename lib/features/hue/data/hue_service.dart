// =========================================================
//  hue_service.dart — Philips Hue : « image et lumière »
// =========================================================
//  L'idée (demande client, 2026-07-17, correctif connexion 2026-09-12) :
//  si des ampoules Philips Hue sont sur le MÊME Wi-Fi que la box, le
//  Cinéma teinte la pièce avec la couleur de l'affiche — film lancé →
//  les lampes plongent dans cette teinte (repli rouge braise), pause →
//  la lumière remonte un peu, fin → tout revient EXACTEMENT comme avant.
//
//  CE QUE CE N'EST PAS : pas l'Entertainment API (sync image-par-image
//  via UDP/DTLS). Ça exigerait un SDK Hue, une « entertainment area »
//  et un flood réseau pendant la lecture — interdit sur Firestick.
//  Groupe CLIP v1 « 0 » = toutes les lampes, UN appel au start/pause/fin.
//
//  COMMENT ÇA MARCHE (aucune dépendance Hue, aucun compte Philips) :
//   1. DÉCOUVERTE : SSDP local (signature `hue-bridgeid`) AVEC le
//      MulticastLock Android — SANS ce lock la puce Wi-Fi Firestick
//      avale les réponses multicast et la recherche « ne trouve rien ».
//      Repli : https://discovery.meethue.com (IP locale du pont derrière
//      la même box internet). Repli ultime : saisie IP manuelle.
//   2. ASSOCIATION : POST /api {"devicetype":…} → un appui physique
//      sur le gros bouton du pont, puis une clé d'app persistée.
//   3. PILOTAGE : CLIP v1 locale HTTP (HTTPS en repli, certif auto-signé
//      du pont v2 accepté UNIQUEMENT sur IP privée).
//
//  BEST-EFFORT ABSOLU : la lumière ne doit JAMAIS gêner la lecture. Tout
//  est try/catch + timeouts courts ; sans pont, sans clé ou hors ligne,
//  chaque appel se termine en silence.
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../cast/data/multicast_lock.dart';

/// État mémorisé d'une lampe avant la scène cinéma — le strict nécessaire
/// pour la remettre comme elle était (y compris « éteinte »).
class HueLightState {
  const HueLightState({
    required this.id,
    required this.on,
    this.bri,
    this.hue,
    this.sat,
    this.ct,
    this.colormode,
  });

  final String id;
  final bool on;
  final int? bri;
  final int? hue;
  final int? sat;
  final int? ct;
  final String? colormode;

  /// Corps JSON du PUT de restauration. Une lampe éteinte se restaure en
  /// `{"on":false}` SEULEMENT — renvoyer bri/hue sur une lampe qu'on
  /// rallume la ferait flasher. Le mode couleur d'origine décide quels
  /// champs renvoyer : `ct` (blanc chaud/froid) OU `hue`+`sat` (couleur).
  Map<String, Object?> restoreBody({int transitionDs = 20}) {
    if (!on) return <String, Object?>{'on': false};
    final Map<String, Object?> body = <String, Object?>{
      'on': true,
      'transitiontime': transitionDs,
    };
    if (bri != null) body['bri'] = bri;
    if (colormode == 'ct' && ct != null) {
      body['ct'] = ct;
    } else {
      if (hue != null) body['hue'] = hue;
      if (sat != null) body['sat'] = sat;
    }
    return body;
  }

  /// Parse l'entrée `state` d'une lampe du GET /api/<clé>/lights.
  static HueLightState? fromLightJson(String id, Map<String, dynamic> light) {
    final Object? st = light['state'];
    if (st is! Map<String, dynamic>) return null;
    return HueLightState(
      id: id,
      on: st['on'] == true,
      bri: (st['bri'] as num?)?.toInt(),
      hue: (st['hue'] as num?)?.toInt(),
      sat: (st['sat'] as num?)?.toInt(),
      ct: (st['ct'] as num?)?.toInt(),
      colormode: st['colormode'] as String?,
    );
  }
}

enum HuePairResult { success, linkButtonNotPressed, error }

class HueService extends ChangeNotifier {
  HueService._();
  static final HueService instance = HueService._();

  static const String _kIpKey = 'hue.bridge_ip.v1';
  static const String _kUserKey = 'hue.app_key.v1';
  static const String _kEnabledKey = 'hue.cinema_enabled.v1';

  // Teinte Hue : 0..65535 sur la roue chromatique. ~1500 = rouge braise
  // chaud (le rouge pur est à 0/65535 ; on tire très légèrement vers
  // l'orangé pour rester doux). Luminosité de scène volontairement basse
  // (36/254 ≈ 14 %) : on ÉCLAIRE l'ambiance, on n'illumine pas la pièce.
  static const int kCinemaHue = 1500;
  static const int kCinemaSat = 250;
  static const int kCinemaBri = 36;
  static const int kPauseBri = 90; // pause → on y voit assez pour bouger

  static const String _kCloudDiscoveryUrl = 'https://discovery.meethue.com';

  String? _bridgeIp;
  String? _appKey;
  bool _enabled = false;
  bool _loaded = false;

  /// Lampes capturées AVANT la scène (id → état) — non vide = scène active.
  final Map<String, HueLightState> _captured = <String, HueLightState>{};

  String? get bridgeIp => _bridgeIp;
  bool get isPaired => _bridgeIp != null && _appKey != null;
  bool get enabled => _enabled;
  bool get sceneActive => _captured.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _bridgeIp = prefs.getString(_kIpKey);
      _appKey = prefs.getString(_kUserKey);
      _enabled = prefs.getBool(_kEnabledKey) ?? false;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabledKey, v);
    } catch (_) {}
  }

  /// Oublie pont + clé. POURQUOI : un IP périmé (box changée, DHCP) laisse
  /// l'UI « associée » alors que plus rien ne répond — le client croit que
  /// Hue est cassé. On efface pour recommencer la recherche.
  Future<void> forgetBridge() async {
    _bridgeIp = null;
    _appKey = null;
    _enabled = false;
    _captured.clear();
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kIpKey);
      await prefs.remove(_kUserKey);
      await prefs.setBool(_kEnabledKey, false);
    } catch (_) {}
  }

  Future<void> _persistBridge() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (_bridgeIp != null) await prefs.setString(_kIpKey, _bridgeIp!);
      if (_appKey != null) await prefs.setString(_kUserKey, _appKey!);
    } catch (_) {}
  }

  // ---- 0. Parseurs purs (testés sans pont) ------------------------------

  /// IPv4 dotted-quad, rien d'autre (pas de hostname, pas d'IPv6).
  @visibleForTesting
  static bool isIpv4(String raw) {
    final List<String> parts = raw.split('.');
    if (parts.length != 4) return false;
    for (final String p in parts) {
      final int? n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// RFC1918 + link-local. Le certificat auto-signé du pont n'est accepté
  /// QUE sur ces plages — jamais vers une IP publique.
  @visibleForTesting
  static bool isPrivateIpv4(String raw) {
    if (!isIpv4(raw)) return false;
    final List<int> o =
        raw.split('.').map((String p) => int.parse(p)).toList(growable: false);
    if (o[0] == 10) return true;
    if (o[0] == 192 && o[1] == 168) return true;
    if (o[0] == 169 && o[1] == 254) return true;
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true;
    return false;
  }

  /// Nettoie une saisie TV (« http://192.168.1.34:80/ ») → host IPv4 ou null.
  @visibleForTesting
  static String? normalizeBridgeIp(String raw) {
    String s = raw.trim();
    s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    s = s.split(RegExp(r'[/?#]')).first;
    final String host = s.split(':').first;
    return isIpv4(host) ? host : null;
  }

  /// GET /api/config sans clé : un pont répond au moins `name` ou `bridgeid`.
  @visibleForTesting
  static bool parseHueConfigLooksLikeBridge(String body) {
    try {
      final Object? parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        return parsed['bridgeid'] != null || parsed['name'] != null;
      }
    } catch (_) {}
    return false;
  }

  /// Réponse officielle de discovery.meethue.com → 1re IP privée.
  /// Pur : le réseau n'est pas testé ici (CI sans pont).
  @visibleForTesting
  static String? parseCloudDiscovery(String body) {
    try {
      final Object? parsed = jsonDecode(body);
      if (parsed is! List) return null;
      for (final Object? item in parsed) {
        if (item is Map<String, dynamic>) {
          final Object? ip = item['internalipaddress'];
          if (ip is String && isPrivateIpv4(ip)) return ip;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Signature SSDP Hue (en-tête `hue-bridgeid` ou serveur IpBridge).
  @visibleForTesting
  static bool isHueSsdpResponse(String response) {
    final String lower = response.toLowerCase();
    return lower.contains('hue-bridgeid') || lower.contains('ipbridge');
  }

  // ---- 1. DÉCOUVERTE (SSDP + cloud + saisie) ---------------------------

  /// Reconnaît la réponse SSDP d'un pont Hue et en extrait l'IP.
  /// Tolère http/https et la casse (LOCATION / Location / HTTP://).
  /// Pur → testé unitairement.
  @visibleForTesting
  static String? parseSsdpForBridgeIp(String response) {
    if (!isHueSsdpResponse(response)) return null;
    final RegExpMatch? m = RegExp(
            r'location:\s*https?://([0-9]{1,3}(?:\.[0-9]{1,3}){3})',
            caseSensitive: false)
        .firstMatch(response);
    return m?.group(1);
  }

  /// Cherche le pont sur le LAN (~4 s SSDP, puis ~3 s cloud). Mémorise
  /// l'IP trouvée (l'ASSOCIATION reste à faire si c'est un nouveau pont).
  /// null = rien trouvé — l'UI propose alors la saisie manuelle.
  Future<String?> discoverBridge() async {
    String? ip;
    try {
      ip = await _discoverViaSsdp();
    } catch (e) {
      debugPrint('[Hue] discover ssdp: $e');
    }
    if (ip == null) {
      try {
        ip = await _discoverViaCloud();
      } catch (e) {
        debugPrint('[Hue] discover cloud: $e');
      }
    }
    if (ip == null) return null;
    _bridgeIp = ip;
    await _persistBridge();
    notifyListeners();
    return ip;
  }

  /// SSDP avec MulticastLock + 3 salves. POURQUOI le lock : sur Android /
  /// Firestick la puce Wi-Fi FILTRE le multicast (batterie). Cast l'a déjà
  /// appris (ssdp_discovery.dart) ; Hue oubliait le lock → 0 pont trouvé
  /// alors que le pont répondait bien. On le prend le temps du scan, puis
  /// on le relâche : le garder pendant la lecture viderait la batterie et
  /// n'apporte rien (le pilotage est de l'HTTP unicast).
  Future<String?> _discoverViaSsdp() async {
    RawDatagramSocket? socket;
    await MulticastLock.instance.acquire();
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      final InternetAddress ssdp = InternetAddress('239.255.255.250');
      // basic:1 = type UPnP du pont ; ssdp:all = filet (certains firmwares).
      void sendSearches() {
        for (final String target in <String>[
          'urn:schemas-upnp-org:device:Basic:1',
          'upnp:rootdevice',
          'ssdp:all',
        ]) {
          final String msearch = 'M-SEARCH * HTTP/1.1\r\n'
              'HOST: 239.255.255.250:1900\r\n'
              'MAN: "ssdp:discover"\r\n'
              'MX: 2\r\n'
              'ST: $target\r\n\r\n';
          try {
            socket?.send(utf8.encode(msearch), ssdp, 1900);
          } catch (_) {
            // Envoi multicast refusé (EPERM / socket fermée) : on continue,
            // le repli cloud / saisie manuelle prendra le relais.
          }
        }
      }

      // UDP multicast se PERD facilement (Wi-Fi chargé, Firestick loin
      // du routeur). Cast émet 3 salves ; on fait pareil, coût négligeable.
      sendSearches();
      final List<Timer> resend = <Timer>[
        Timer(const Duration(seconds: 1), sendSearches),
        Timer(const Duration(milliseconds: 2500), sendSearches),
      ];

      final Completer<String?> found = Completer<String?>();
      final StreamSubscription<RawSocketEvent> sub =
          socket.listen((RawSocketEvent e) {
        if (e != RawSocketEvent.read) return;
        final Datagram? dg = socket?.receive();
        if (dg == null) return;
        final String text =
            utf8.decode(dg.data, allowMalformed: true);
        String? ip = parseSsdpForBridgeIp(text);
        // LOCATION parfois absente / IPv6 : l'expéditeur unicast EST le pont
        // si la signature Hue est là et que l'IP est privée.
        if (ip == null &&
            isHueSsdpResponse(text) &&
            isPrivateIpv4(dg.address.address)) {
          ip = dg.address.address;
        }
        if (ip != null && !found.isCompleted) found.complete(ip);
      });
      final String? ip = await found.future
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      for (final Timer t in resend) {
        t.cancel();
      }
      await sub.cancel();
      return ip;
    } catch (e) {
      debugPrint('[Hue] discover: $e');
      return null;
    } finally {
      socket?.close();
      await MulticastLock.instance.release();
    }
  }

  /// Repli officiel Philips : le pont pousse son IP locale vers
  /// discovery.meethue.com. Marche quand le SSDP est filtré (AP isolation
  /// partielle, multicast lock KO) MAIS que box et pont partagent la même
  /// IP publique. On VÉRIFIE ensuite /api/config — le cloud peut renvoyer
  /// une IP périmée (DHCP). Timeout 3 s : pas de pont → on n'attend pas.
  Future<String?> _discoverViaCloud() async {
    final String body = await _httpSend(
      'GET',
      Uri.parse(_kCloudDiscoveryUrl),
      null,
      connectTimeout: const Duration(seconds: 2),
      readTimeout: const Duration(seconds: 3),
    );
    final String? ip = parseCloudDiscovery(body);
    if (ip == null) return null;
    if (!await probeBridge(ip)) return null;
    return ip;
  }

  /// Saisie manuelle de l'IP du pont (repli si SSDP + cloud ratent).
  /// Vérifie que ça ressemble à un pont avant de garder.
  Future<bool> setBridgeIpManually(String raw) async {
    final String? ip = normalizeBridgeIp(raw);
    if (ip == null) return false;
    if (!await probeBridge(ip)) return false;
    _bridgeIp = ip;
    await _persistBridge();
    notifyListeners();
    return true;
  }

  /// GET /api/config — un pont répond SANS clé. HTTP puis HTTPS local.
  @visibleForTesting
  Future<bool> probeBridge(String ip) async {
    try {
      final String body = await _hueCall(
        ip,
        'GET',
        '/api/config',
        null,
      );
      return parseHueConfigLooksLikeBridge(body);
    } catch (_) {
      return false;
    }
  }

  // ---- 2. ASSOCIATION (bouton du pont) ---------------------------------

  /// Parse la réponse du POST /api : clé d'app, « bouton pas pressé »
  /// (erreur 101) ou autre erreur. Pur → testé unitairement.
  @visibleForTesting
  static ({HuePairResult result, String? appKey}) parsePairResponse(
      String body) {
    try {
      final Object? parsed = jsonDecode(body);
      if (parsed is List && parsed.isNotEmpty) {
        final Object? first = parsed.first;
        if (first is Map<String, dynamic>) {
          final Object? success = first['success'];
          if (success is Map<String, dynamic> &&
              success['username'] is String) {
            return (
              result: HuePairResult.success,
              appKey: success['username'] as String
            );
          }
          final Object? error = first['error'];
          if (error is Map<String, dynamic> && error['type'] == 101) {
            return (
              result: HuePairResult.linkButtonNotPressed,
              appKey: null
            );
          }
        }
      }
    } catch (_) {}
    return (result: HuePairResult.error, appKey: null);
  }

  /// UNE tentative d'association (l'écran appelle en boucle pendant que
  /// l'utilisateur va appuyer sur le bouton du pont).
  Future<HuePairResult> tryPair() async {
    final String? ip = _bridgeIp;
    if (ip == null) return HuePairResult.error;
    try {
      final String body = await _hueCall(
        ip,
        'POST',
        '/api',
        jsonEncode(<String, String>{'devicetype': '7motion#tv'}),
      );
      final ({HuePairResult result, String? appKey}) parsed =
          parsePairResponse(body);
      if (parsed.result == HuePairResult.success) {
        _appKey = parsed.appKey;
        // Pairer = le client VEUT la synchro. Sans ça, l'interrupteur
        // restait OFF par défaut → « ça ne se connecte pas » après un
        // appariement réussi.
        _enabled = true;
        await _persistBridge();
        try {
          final SharedPreferences prefs =
              await SharedPreferences.getInstance();
          await prefs.setBool(_kEnabledKey, true);
        } catch (_) {}
        notifyListeners();
      }
      return parsed.result;
    } catch (e) {
      debugPrint('[Hue] pair: $e');
      return HuePairResult.error;
    }
  }

  /// Nombre de lampes joignables (affiché dans les réglages, et sert de
  /// « test de santé » après association). null = pont injoignable.
  Future<int?> lightCount() async {
    final Map<String, HueLightState>? states = await _fetchLightStates();
    return states?.length;
  }

  // ---- 3. SCÈNE CINÉMA --------------------------------------------------

  /// Film lancé → capture l'état des lampes puis plonge la pièce dans une
  /// ambiance douce (transition 3 s). Idempotent : scène déjà active → rien.
  ///
  /// IMMERSION PAR FILM (2026-07-17) : si [hue]/[sat] sont fournis (teinte
  /// dominante de l'affiche, calculée par l'appelant), la pièce prend LA
  /// COULEUR du film — un sci-fi bleu baigne en bleu, un drame chaud en
  /// ambre. Sans couleur → repli sur le rouge braise de la marque.
  Future<void> cinemaStart({int? hue, int? sat}) async {
    await load();
    if (!_enabled || !isPaired || sceneActive) return;
    final Map<String, HueLightState>? states = await _fetchLightStates();
    if (states == null || states.isEmpty) return;
    _captured
      ..clear()
      ..addAll(states);
    await _groupAction(<String, Object?>{
      'on': true,
      'bri': kCinemaBri,
      'hue': hue ?? kCinemaHue,
      // On garde une saturation ÉLEVÉE (ambiance colorée, pas blanchâtre)
      // tout en respectant une teinte plus douce si l'affiche est pâle.
      'sat': (sat ?? kCinemaSat).clamp(140, 254),
      'transitiontime': 30, // 3,0 s — la salle « s'éteint » en douceur
    });
    notifyListeners();
  }

  /// Convertit une couleur RVB (0-255) en (hue 0-65535, sat 0-254) Hue.
  /// Le canal Teinte de Hue est un cercle 0-65535 ; la saturation 0-254.
  /// On ignore la luminosité (la scène impose sa propre intensité basse).
  static ({int hue, int sat}) rgbToHue(int r, int g, int b) {
    final double rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
    final double maxC = [rf, gf, bf].reduce((a, c) => a > c ? a : c);
    final double minC = [rf, gf, bf].reduce((a, c) => a < c ? a : c);
    final double delta = maxC - minC;
    double h = 0;
    if (delta > 0.00001) {
      if (maxC == rf) {
        h = ((gf - bf) / delta) % 6;
      } else if (maxC == gf) {
        h = (bf - rf) / delta + 2;
      } else {
        h = (rf - gf) / delta + 4;
      }
      h *= 60;
      if (h < 0) h += 360;
    }
    final double s = maxC <= 0 ? 0 : delta / maxC;
    return (
      hue: ((h / 360.0) * 65535).round().clamp(0, 65535),
      sat: (s * 254).round().clamp(0, 254),
    );
  }

  /// Teinte dominante d'une image (octets RVBA) → (hue, sat) Hue.
  /// On moyenne les pixels VIFS (on écarte le très sombre et le grisâtre :
  /// ce sont eux qui « salissent » la couleur d'ambiance). [stride] permet
  /// d'échantillonner (1 pixel sur N) pour rester léger sur box modeste.
  static ({int hue, int sat})? dominantFromRgba(
    List<int> rgba, {
    int stride = 4,
  }) {
    if (rgba.length < 4) return null;
    double rs = 0, gs = 0, bs = 0;
    int n = 0;
    final int step = 4 * (stride < 1 ? 1 : stride);
    for (int i = 0; i + 3 < rgba.length; i += step) {
      final int r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      final int maxc = [r, g, b].reduce((a, c) => a > c ? a : c);
      final int minc = [r, g, b].reduce((a, c) => a < c ? a : c);
      // On ne garde que les pixels ni trop sombres ni trop ternes : ce sont
      // eux qui portent la « couleur » du film (néons, ciel, décor).
      if (maxc < 60) continue; // quasi noir
      if (maxc - minc < 40) continue; // gris / blanc cassé
      rs += r;
      gs += g;
      bs += b;
      n++;
    }
    if (n == 0) return null; // affiche terne → l'appelant gardera le braise
    return rgbToHue((rs / n).round(), (gs / n).round(), (bs / n).round());
  }

  /// Pause → la lumière remonte un peu (on retrouve ses pop-corns).
  Future<void> cinemaPause() async {
    if (!sceneActive) return;
    await _groupAction(<String, Object?>{
      'bri': kPauseBri,
      'transitiontime': 10,
    });
  }

  /// Reprise → retour à l'ambiance basse.
  Future<void> cinemaResume() async {
    if (!sceneActive) return;
    await _groupAction(<String, Object?>{
      'bri': kCinemaBri,
      'transitiontime': 10,
    });
  }

  /// Fin/sortie du film → chaque lampe revient EXACTEMENT comme avant
  /// (y compris celles qui étaient éteintes).
  Future<void> cinemaEnd() async {
    if (!sceneActive) return;
    final List<HueLightState> toRestore =
        _captured.values.toList(growable: false);
    _captured.clear();
    for (final HueLightState s in toRestore) {
      await _putLightState(s.id, s.restoreBody());
    }
    notifyListeners();
  }

  /// « Tester l'ambiance » depuis les réglages : plonge 4 s puis restaure.
  Future<void> testScene() async {
    final bool wasEnabled = _enabled;
    _enabled = true; // le test doit marcher même si l'option est OFF
    await cinemaStart();
    _enabled = wasEnabled;
    await Future<void>.delayed(const Duration(seconds: 4));
    await cinemaEnd();
  }

  // ---- plomberie HTTP (dart:io nu, timeouts courts) ---------------------

  Future<Map<String, HueLightState>?> _fetchLightStates() async {
    final String? ip = _bridgeIp;
    final String? key = _appKey;
    if (ip == null || key == null) return null;
    try {
      final String body = await _hueCall(ip, 'GET', '/api/$key/lights', null);
      final Object? parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) return null;
      final Map<String, HueLightState> out = <String, HueLightState>{};
      parsed.forEach((String id, Object? light) {
        if (light is Map<String, dynamic>) {
          final HueLightState? st = HueLightState.fromLightJson(id, light);
          if (st != null) out[id] = st;
        }
      });
      return out;
    } catch (e) {
      debugPrint('[Hue] lights: $e');
      return null;
    }
  }

  Future<void> _groupAction(Map<String, Object?> body) async {
    final String? ip = _bridgeIp;
    final String? key = _appKey;
    if (ip == null || key == null) return;
    try {
      // Groupe 0 = TOUTES les lampes du pont, en un seul appel.
      // PAS d'Entertainment area : un PUT, pas un stream.
      await _hueCall(
          ip, 'PUT', '/api/$key/groups/0/action', jsonEncode(body));
    } catch (e) {
      debugPrint('[Hue] group: $e');
    }
  }

  Future<void> _putLightState(String id, Map<String, Object?> body) async {
    final String? ip = _bridgeIp;
    final String? key = _appKey;
    if (ip == null || key == null) return;
    try {
      await _hueCall(
          ip, 'PUT', '/api/$key/lights/$id/state', jsonEncode(body));
    } catch (e) {
      debugPrint('[Hue] light $id: $e');
    }
  }

  /// CLIP v1 locale : HTTP d'abord (tous les ponts), HTTPS en repli
  /// (pont v2 dont le HTTP est fermé). Le certif auto-signé n'est accepté
  /// que si [ip] est privée — jamais en clair vers le WAN.
  Future<String> _hueCall(
    String ip,
    String method,
    String path,
    String? body,
  ) async {
    try {
      return await _httpSend(
        method,
        Uri.parse('http://$ip$path'),
        body,
      );
    } catch (e) {
      debugPrint('[Hue] http $path: $e — repli HTTPS local');
      return await _httpSend(
        method,
        Uri.parse('https://$ip$path'),
        body,
        allowPrivateBadCert: isPrivateIpv4(ip),
      );
    }
  }

  Future<String> _httpSend(
    String method,
    Uri uri,
    String? body, {
    Duration connectTimeout = const Duration(seconds: 3),
    Duration readTimeout = const Duration(seconds: 4),
    bool allowPrivateBadCert = false,
  }) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = connectTimeout;
    if (allowPrivateBadCert) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        return isPrivateIpv4(host) ||
            (uri.host.isNotEmpty && isPrivateIpv4(uri.host));
      };
    }
    try {
      final HttpClientRequest req = await client.openUrl(method, uri);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(body);
      }
      final HttpClientResponse resp =
          await req.close().timeout(readTimeout);
      return await resp
          .transform(utf8.decoder)
          .join()
          .timeout(readTimeout);
    } finally {
      client.close();
    }
  }
}
