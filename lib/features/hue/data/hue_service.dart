// =========================================================
//  hue_service.dart — Philips Hue : mode « salle de cinéma »
// =========================================================
//  L'idée (demande client, 2026-07-17) : si des ampoules Philips Hue sont
//  sur le MÊME Wi-Fi que la box, le Cinéma pilote la lumière de la pièce —
//  film lancé → les lampes plongent dans un ROUGE BRAISE doux (l'ambiance
//  de la salle qui s'éteint), pause → la lumière remonte un peu, fin du
//  film → tout revient EXACTEMENT comme avant.
//
//  COMMENT ÇA MARCHE (aucune dépendance, aucun cloud, aucun compte) :
//   1. DÉCOUVERTE : le pont Hue répond au protocole SSDP — le même
//      broadcast UDP que notre découverte DLNA (cast). Sa réponse se
//      reconnaît à l'en-tête `hue-bridgeid`. Repli : saisie IP manuelle.
//   2. ASSOCIATION : POST /api {"devicetype":…} → le pont exige UN appui
//      physique sur son gros bouton (sécurité officielle Philips), puis
//      rend une clé d'app (`username`) qu'on garde en SharedPreferences.
//   3. PILOTAGE : API locale CLIP v1 en HTTP simple (http://<ip>/api/…),
//      supportée par TOUS les ponts (v1 et v2). On capture l'état de
//      chaque lampe AVANT la scène (on/bri/hue/sat/ct) pour pouvoir le
//      RESTAURER à la sortie — jamais de « lumières cassées » après un
//      film. La scène elle-même s'applique en UN appel de groupe (groupe
//      0 = toutes les lampes) avec une transition douce.
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

  Future<void> _persistBridge() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (_bridgeIp != null) await prefs.setString(_kIpKey, _bridgeIp!);
      if (_appKey != null) await prefs.setString(_kUserKey, _appKey!);
    } catch (_) {}
  }

  // ---- 1. DÉCOUVERTE (SSDP, comme la découverte cast) ------------------

  /// Reconnaît la réponse SSDP d'un pont Hue et en extrait l'IP.
  /// Le pont s'annonce avec l'en-tête `hue-bridgeid` (sa signature) et un
  /// LOCATION du type `http://192.168.1.34:80/description.xml`. Pur →
  /// testé unitairement.
  @visibleForTesting
  static String? parseSsdpForBridgeIp(String response) {
    final String lower = response.toLowerCase();
    if (!lower.contains('hue-bridgeid') && !lower.contains('ipbridge')) {
      return null;
    }
    final RegExpMatch? m = RegExp(r'location:\s*http://([0-9.]+)',
            caseSensitive: false)
        .firstMatch(response);
    return m?.group(1);
  }

  /// Cherche le pont sur le LAN (~4 s). Mémorise l'IP trouvée (l'ASSOCIATION
  /// reste à faire si c'est un nouveau pont). null = rien trouvé.
  Future<String?> discoverBridge() async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final InternetAddress ssdp = InternetAddress('239.255.255.250');
      // Deux cibles : `basic:1` (le type UPnP du pont) + ssdp:all (filet —
      // certains firmwares ne répondent qu'à lui).
      for (final String target in <String>[
        'urn:schemas-upnp-org:device:Basic:1',
        'ssdp:all',
      ]) {
        final String msearch = 'M-SEARCH * HTTP/1.1\r\n'
            'HOST: 239.255.255.250:1900\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: $target\r\n\r\n';
        socket.send(utf8.encode(msearch), ssdp, 1900);
      }
      final Completer<String?> found = Completer<String?>();
      final StreamSubscription<RawSocketEvent> sub =
          socket.listen((RawSocketEvent e) {
        if (e != RawSocketEvent.read) return;
        final Datagram? dg = socket?.receive();
        if (dg == null) return;
        final String? ip = parseSsdpForBridgeIp(utf8.decode(dg.data,
            allowMalformed: true));
        if (ip != null && !found.isCompleted) found.complete(ip);
      });
      final String? ip = await found.future
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      await sub.cancel();
      if (ip != null) {
        _bridgeIp = ip;
        await _persistBridge();
        notifyListeners();
      }
      return ip;
    } catch (e) {
      debugPrint('[Hue] discover: $e');
      return null;
    } finally {
      socket?.close();
    }
  }

  /// Saisie manuelle de l'IP du pont (repli si le SSDP est bloqué par le
  /// routeur). Vérifie que ça ressemble à un pont avant de garder.
  Future<bool> setBridgeIpManually(String ip) async {
    try {
      final String body =
          await _httpGet(Uri.parse('http://$ip/api/config'));
      // /api/config répond SANS clé avec au moins name + bridgeid.
      final Map<String, dynamic> cfg =
          jsonDecode(body) as Map<String, dynamic>;
      if (cfg['bridgeid'] == null && cfg['name'] == null) return false;
      _bridgeIp = ip;
      await _persistBridge();
      notifyListeners();
      return true;
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
      final String body = await _httpSend(
          'POST', Uri.parse('http://$ip/api'),
          jsonEncode(<String, String>{'devicetype': '7motion#tv'}));
      final ({HuePairResult result, String? appKey}) parsed =
          parsePairResponse(body);
      if (parsed.result == HuePairResult.success) {
        _appKey = parsed.appKey;
        await _persistBridge();
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
      final String body =
          await _httpGet(Uri.parse('http://$ip/api/$key/lights'));
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
      await _httpSend('PUT',
          Uri.parse('http://$ip/api/$key/groups/0/action'), jsonEncode(body));
    } catch (e) {
      debugPrint('[Hue] group: $e');
    }
  }

  Future<void> _putLightState(String id, Map<String, Object?> body) async {
    final String? ip = _bridgeIp;
    final String? key = _appKey;
    if (ip == null || key == null) return;
    try {
      await _httpSend('PUT',
          Uri.parse('http://$ip/api/$key/lights/$id/state'), jsonEncode(body));
    } catch (e) {
      debugPrint('[Hue] light $id: $e');
    }
  }

  Future<String> _httpGet(Uri uri) => _httpSend('GET', uri, null);

  Future<String> _httpSend(String method, Uri uri, String? body) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final HttpClientRequest req = await client.openUrl(method, uri);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(body);
      }
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 4));
      return await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
    } finally {
      client.close();
    }
  }
}
