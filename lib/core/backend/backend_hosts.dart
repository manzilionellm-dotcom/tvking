// =========================================================
//  backend_hosts.dart — FAILOVER multi-adresses du backend
// =========================================================
//  Le worker Cloudflare `seven-motion-backend` répond sur DEUX adresses
//  qui pointent sur le MÊME code et la MÊME base D1 :
//
//    1. https://app.7themotion.com                       (domaine maison)
//    2. https://seven-motion-backend.manzilionel-lm.workers.dev
//                                                        (adresse Cloudflare
//                                                         native, indépendante
//                                                         du DNS du domaine)
//
//  Si le domaine maison casse (DNS Hostinger/Cloudflare, expiration,
//  blocage), le heartbeat bascule sur l'adresse de secours et TOUTE
//  l'app suit (les ~20 modules qui parlent au serveur lisent
//  `kSubscriptionBaseUrl`, qui est un getter vers [current]).
//
//  Auto-guérison : à chaque heartbeat on retente d'abord le domaine
//  maison → dès qu'il répond de nouveau, tout le monde y revient.
//  Le dernier hôte qui marche est mémorisé (SharedPreferences) pour
//  démarrer directement dessus au boot suivant.
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class BackendHosts {
  /// Domaine maison — TOUJOURS essayé en premier (auto-guérison).
  static const String primary = 'https://app.7themotion.com';

  /// Adresse Cloudflare native du MÊME worker — ne dépend pas du DNS
  /// du domaine maison. Secours uniquement.
  static const String backup =
      'https://seven-motion-backend.manzilionel-lm.workers.dev';

  static const String _kPrefKey = 'backend.preferred_host';

  /// Hôte servi à toute l'app via `kSubscriptionBaseUrl`.
  static String current = primary;

  /// Ordre d'essai pour les sondes (heartbeat/status) : le domaine
  /// maison D'ABORD — c'est ce qui fait revenir tout le monde dessus
  /// dès qu'il remarche — puis le secours.
  static List<String> candidates() => const <String>[primary, backup];

  /// Mémorise l'hôte qui vient de répondre : bascule immédiate de toute
  /// l'app + persistance pour le prochain démarrage. Best-effort.
  static Future<void> markGood(String base) async {
    if (current == base) return;
    current = base;
    debugPrint('[BackendHosts] bascule sur $base');
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefKey, base);
    } catch (_) {}
  }

  /// Recharge l'hôte mémorisé au boot (si le domaine maison était KO au
  /// dernier lancement, on repart directement sur le secours — le retour
  /// au domaine maison se fera tout seul au prochain heartbeat réussi).
  static Future<void> loadPreferred() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_kPrefKey);
      if (saved == backup) current = backup;
    } catch (_) {}
  }
}
