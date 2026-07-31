// =========================================================
//  fleet_reporter.dart — Rapport Boîte noire 1×/24 h vers la maison mère
// =========================================================
//  Chaque application du parc (téléphone 7 MOTION + box DeFew TV, partout
//  dans le monde) envoie AU PLUS une fois par 24 h un résumé ANONYME de sa
//  Boîte noire au backend : les échecs de lecture (chaîne, code d'erreur
//  Media3 stable, cause, verdict humain — JAMAIS l'URL du flux ni les
//  identifiants, même règle que playback_failure_log), la version de
//  l'app, la plateforme et la langue. Le PAYS n'est pas envoyé : il est
//  déduit côté serveur (Cloudflare). Le panel « Rapports » agrège tout ça
//  pour voir OÙ et SUR QUOI l'application souffre — et l'améliorer.
//
//  VIE PRIVÉE / SOBRIÉTÉ :
//    • identifiant = le MAC virtuel DeviceIdentity (déjà la clé de
//      l'abonnement — aucune donnée nouvelle) ;
//    • une requête par jour maximum, ~quelques Ko, fail-open total :
//      réseau KO ou serveur muet → on réessaiera demain, JAMAIS de
//      gêne pour l'utilisateur, jamais de crash.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/device/data/device_identity.dart';
import '../../features/subscription/data/subscription_backend.dart';
import '../../features/tv/data/playback_failure_log.dart';
import '../app/app_platform.dart';

class FleetReporter {
  FleetReporter._();
  static final FleetReporter instance = FleetReporter._();

  static const String _kLastSentKey = 'fleet_report.last_sent.v1';
  static const Duration _kInterval = Duration(hours: 24);

  bool _inFlight = false;

  /// Construit le corps du rapport (PUR, testé) à partir des entrées de la
  /// Boîte noire. Aucune URL de flux : uniquement chaîne + hôte + codes.
  @visibleForTesting
  static Map<String, Object?> buildPayload({
    required String device,
    required bool isTv,
    required String versionName,
    required int versionCode,
    required String platform,
    required String locale,
    required List<PlaybackFailureEntry> failures,
  }) {
    return <String, Object?>{
      'device': device,
      'app': isTv ? 'tv' : 'phone',
      'version_name': versionName,
      'version_code': versionCode,
      'platform': platform,
      'locale': locale,
      'failures': failures
          .take(50)
          .map((PlaybackFailureEntry e) => <String, Object?>{
                'ts': e.timestamp.toIso8601String(),
                'channel': e.channelName,
                'host': e.streamHost,
                'code': e.errorCodeName ?? e.errorCode?.toString() ?? '',
                'cause': e.cause ?? '',
                'verdict': e.verdict,
              })
          .toList(growable: false),
    };
  }

  /// Envoie le rapport si le dernier date de plus de 24 h. Fail-open :
  /// toute erreur → silence, on retentera au prochain passage. L'horodatage
  /// n'est armé QUE si le serveur a répondu 200 (sinon on réessaie demain
  /// dès la prochaine ouverture).
  Future<void> maybeSend() async {
    if (_inFlight || kIsWeb) return;
    _inFlight = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int last = prefs.getInt(_kLastSentKey) ?? 0;
      final int now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _kInterval.inMilliseconds) return;

      await PlaybackFailureLog.instance.ensureLoaded();
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String device = await DeviceIdentity.instance.mac;
      String platform = '';
      String locale = '';
      try {
        platform =
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
        locale = Platform.localeName;
      } catch (_) {
        // Plateforme exotique → champs vides, le rapport part quand même.
      }
      final Map<String, Object?> payload = buildPayload(
        device: device,
        isTv: AppPlatform.isTv,
        versionName: info.version,
        versionCode: int.tryParse(info.buildNumber) ?? 0,
        platform: platform,
        locale: locale,
        failures: PlaybackFailureLog.instance.entries,
      );
      final http.Response r = await http
          .post(
            Uri.parse('$kSubscriptionBaseUrl/api/reports'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        await prefs.setInt(_kLastSentKey, now);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FleetReporter] $e');
    } finally {
      _inFlight = false;
    }
  }
}
