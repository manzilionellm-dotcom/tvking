// =========================================================
//  xtream_server_clock.dart — Fuseau horaire des serveurs Xtream
// =========================================================
//  Pourquoi ?
//  ----------
//  Le catch-up Xtream s'écrit
//    /timeshift/USER/PASS/MINUTES/AAAA-MM-JJ:HH-MM/ID.ts
//  et l'heure « AAAA-MM-JJ:HH-MM » est lue par le serveur DANS SON PROPRE
//  fuseau horaire, pas dans celui de la box. Avant, l'app écrivait l'heure
//  locale de la box : dès que le client et le serveur n'étaient pas dans le
//  même fuseau (cas courant), le retour en arrière démarrait une ou plusieurs
//  heures à côté du programme choisi, ou sur rien du tout.
//
//  Le serveur annonce son fuseau à la connexion (`server_info.timezone`,
//  ex. « Europe/Paris »). On le retient par serveur (hôte:port), en mémoire
//  et dans les préférences, pour que le catch-up reste juste après un
//  redémarrage. Fuseau inconnu ou invalide → on garde l'ancien comportement
//  (heure de la box) : rien ne régresse.
//
//  Dépendance : `timezone` (déjà utilisée par les rappels de programmes),
//  pour convertir une heure UTC vers un fuseau nommé, heure d'été comprise.
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

abstract final class XtreamServerClock {
  static const String _prefix = 'zuno.xtream.server_tz.v1.';

  /// hôte:port (minuscules) → nom de fuseau IANA.
  static final Map<String, String> _zones = <String, String>{};
  static bool _tzReady = false;

  /// Clé d'un serveur : « hôte » ou « hôte:port », en minuscules. Vide si
  /// l'adresse n'est pas exploitable.
  static String keyOf(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return '';
    final String host = uri.host.toLowerCase();
    return uri.hasPort ? '$host:${uri.port}' : host;
  }

  /// Recharge les fuseaux déjà connus (appelé au démarrage). Ne lève jamais.
  static Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      for (final String key in prefs.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        final String? zone = prefs.getString(key);
        if (zone != null && zone.isNotEmpty) {
          _zones.putIfAbsent(key.substring(_prefix.length), () => zone);
        }
      }
    } catch (_) {
      // Préférences indisponibles : le catch-up garde l'heure de la box.
    }
  }

  /// Retient le fuseau annoncé par le serveur ([serverInfo] = le bloc
  /// `server_info` de la réponse de connexion). Ne lève jamais : une
  /// connexion réussie ne doit pas échouer pour un fuseau.
  static Future<void> remember(String serverUrl, Object? serverInfo) async {
    try {
      final String key = keyOf(serverUrl);
      if (key.isEmpty || serverInfo is! Map) return;
      final String zone = (serverInfo['timezone']?.toString() ?? '').trim();
      // Forme attendue : « Région/Ville » ou « UTC ». On refuse le reste
      // (texte libre, valeur vide) plutôt que d'enregistrer n'importe quoi.
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_+\-/]{1,63}$').hasMatch(zone)) return;
      if (_zones[key] == zone) return;
      _zones[key] = zone;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', zone);
    } catch (_) {
      // Mémoire seulement : valable jusqu'à la fermeture de l'app.
    }
  }

  /// Fuseau connu du serveur de [streamUrl], ou null.
  static String? zoneOf(String streamUrl) => _zones[keyOf(streamUrl)];

  /// L'instant [epochMs] vu par l'horloge murale du serveur de [streamUrl].
  /// Null si le fuseau du serveur est inconnu ou invalide.
  static DateTime? wallClock(String streamUrl, int epochMs) {
    final String? zone = zoneOf(streamUrl);
    if (zone == null) return null;
    try {
      if (!_tzReady) {
        // Une seule fois, au premier catch-up (base déjà embarquée).
        tzdata.initializeTimeZones();
        _tzReady = true;
      }
      return tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.getLocation(zone),
        epochMs,
      );
    } catch (_) {
      return null; // fuseau inconnu de la base → heure de la box
    }
  }

  @visibleForTesting
  static void debugSetZone(String serverUrl, String? zone) {
    final String key = keyOf(serverUrl);
    if (key.isEmpty) return;
    if (zone == null) {
      _zones.remove(key);
    } else {
      _zones[key] = zone;
    }
  }

  @visibleForTesting
  static void debugReset() => _zones.clear();
}
