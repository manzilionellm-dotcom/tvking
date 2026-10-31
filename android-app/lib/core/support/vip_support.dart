// =========================================================
//  vip_support.dart — Numéro VIP + ouverture WhatsApp
// =========================================================
//  Numéro unique de support — centralisé pour ne le changer
//  qu'à un seul endroit le jour où on passera sur un autre
//  canal (Telegram, Discord, ligne dédiée).
//
//  Format wa.me : pas de "+", pas d'espaces, pas de tirets.
//  On stocke aussi la version humaine pour l'affichage.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_platform.dart';
import '../branding/brand_config.dart';
import '../../features/device/data/device_identity.dart';
import '../../features/subscription/data/subscription_state.dart';

abstract final class VipSupport {
  /// Numéro affiché à l'utilisateur (avec espaces pour lisibilité).
  static const String displayNumber = '+44 7307 410512';

  /// Numéro normalisé pour les URLs `wa.me` (chiffres uniquement,
  /// avec indicatif pays, sans "+").
  static const String _waNumber = '447307410512';

  /// Le message appartient toujours au client : on ouvre WhatsApp avec
  /// un brouillon, jamais un envoi automatique. Pas de lien M3U, mot de passe,
  /// identifiant Xtream, Android ID ou secret de licence dans ce diagnostic.
  static const String _defaultPrefill =
      'Bonjour, j\'ai besoin d\'aide avec l\'application.';

  /// Texte pur pour garder le contrat de confidentialité testable.
  /// Un statut « non vérifié » évite de présenter un essai local comme
  /// une activation payante confirmée par le serveur.
  @visibleForTesting
  static String composeSupportMessage({
    required String appName,
    required String mac,
    required String status,
    required String version,
    String? customMessage,
  }) {
    final String intro = customMessage?.trim().isNotEmpty == true
        ? customMessage!.trim()
        : _defaultPrefill;
    final String name = appName.trim().isEmpty ? 'ZUNO' : appName.trim();
    final String device = mac.trim().isEmpty ? 'indisponible' : mac.trim();
    final String build = version.trim().isEmpty ? 'indisponible' : version.trim();
    final String code = status.trim().isEmpty ? 'non vérifié' : status.trim();
    // Évite de répéter la MAC si l'écran d'activation l'a déjà ajoutée.
    final String macLine = intro.contains(device) ? '' : '\nMAC : $device';
    return '$intro\n\nApplication : $name$macLine\nStatut : $code\nVersion : $build';
  }

  /// Prépare le diagnostic UNIQUEMENT au tap sur « Message ».
  /// On lit l'état serveur déjà connu de l'application, sans lancer une
  /// activation, un achat, un appel réseau supplémentaire ni une collecte.
  static Future<String> _messageForCurrentDevice(String? customMessage) async {
    String appName = AppPlatform.isTv ? 'ZUNO' : 'Application';
    try {
      if (!AppPlatform.isTv) appName = BrandConfig.instance.appName;
    } catch (_) {
      // Aucun nom distant n'est obligatoire pour contacter le support.
    }
    String mac = '';
    try {
      mac = await DeviceIdentity.instance.mac;
    } catch (_) {
      // Le brouillon reste utilisable sans identité chargée.
    }

    final remote = SubscriptionState.instance.remote;
    final String status = !remote.exists
        ? 'non vérifié'
        : remote.banned
            ? 'bloqué'
            : remote.frozen
                ? 'suspendu'
                : remote.paid
                    ? 'payant'
                    : remote.expired
                        ? 'expiré'
                        : remote.trialUntil > DateTime.now().millisecondsSinceEpoch
                            ? 'test'
                            : 'non actif';

    String version = '';
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // Les builds de test peuvent ne pas exposer PackageInfo.
    }
    return composeSupportMessage(
      appName: appName,
      mac: mac,
      status: status,
      version: version,
      customMessage: customMessage,
    );
  }

  /// Ouvre WhatsApp (app native si installée, sinon web) et laisse l'envoi
  /// au client. Renvoie true si l'OS a lancé l'URL, false sinon.
  static Future<bool> openWhatsApp({String? customMessage}) async {
    final String message = await _messageForCurrentDevice(customMessage);
    final Uri uri = Uri.https('wa.me', '/$_waNumber', <String, String>{
      'text': message,
    });
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) debugPrint('[VipSupport] launchUrl error: $e');
      return false;
    }
  }

  /// Compose le numéro de support dans l'appli Téléphone du système.
  /// Sur Android, ça OUVRE l'écran de composition pré-rempli — le
  /// client doit valider d'un tap pour lancer l'appel (Android n'a
  /// jamais le droit de lancer un appel sans confirmation user).
  ///
  /// Sur les appareils SANS module téléphonie (tablettes Wi-Fi, TV,
  /// Fire TV), `launchUrl` retourne false. L'appelant doit afficher
  /// un toast 'Cet appareil ne peut pas appeler' et proposer le
  /// canal Message à la place.
  static Future<bool> openPhoneCall() async {
    // On garde le numéro affichage (avec +) car `tel:` accepte le
    // format E.164. On retire seulement les espaces — les tirets et
    // le + sont tolérés par tous les OS.
    final String dialNumber = displayNumber.replaceAll(' ', '');
    final Uri uri = Uri.parse('tel:$dialNumber');
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[VipSupport] phone launchUrl error: $e');
      return false;
    }
  }
}
