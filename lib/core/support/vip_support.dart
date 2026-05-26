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
import 'package:url_launcher/url_launcher.dart';

abstract final class VipSupport {
  /// Numéro affiché à l'utilisateur (avec espaces pour lisibilité).
  static const String displayNumber = '+44 7307 410512';

  /// Numéro normalisé pour les URLs `wa.me` (chiffres uniquement,
  /// avec indicatif pays, sans "+").
  static const String _waNumber = '447307410512';

  /// Message pré-rempli quand l'utilisateur ouvre WhatsApp. Indique
  /// l'origine (7 MOTION) pour que le support sache d'où vient le
  /// contact. Encodé URL-safe par `Uri`.
  static const String _defaultPrefill =
      'Bonjour 7 MOTION, j\'ai besoin d\'aide avec l\'application.';

  /// Ouvre WhatsApp (app native si installée, sinon web). Renvoie
  /// `true` si l'OS a pu lancer l'URL, `false` sinon.
  static Future<bool> openWhatsApp({String? customMessage}) async {
    final String message = customMessage ?? _defaultPrefill;
    final Uri uri = Uri.parse(
      'https://wa.me/$_waNumber?text=${Uri.encodeComponent(message)}',
    );
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[VipSupport] launchUrl error: $e');
      return false;
    }
  }
}
