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

import '../branding/brand_config.dart';
import '../i18n/l10n_now.dart';

abstract final class VipSupport {
  /// Numéro affiché à l'utilisateur (avec espaces pour lisibilité).
  static const String displayNumber = '+1 807 788 8909';

  /// Numéro normalisé pour les URLs `wa.me` (chiffres uniquement,
  /// avec indicatif pays, sans "+").
  static const String _waNumber = '18077888909';

  /// Message pré-rempli quand l'utilisateur ouvre WhatsApp. Indique
  /// l'origine (nom de l'app, surchargeable via le panel « Thème »)
  /// pour que le support sache d'où vient le contact. Encodé URL-safe
  /// par `Uri`. Recalculé à chaque ouverture via `l10nNow` : suit la
  /// langue active (texte éphémère, hors arbre de widgets).
  static String get _defaultPrefill =>
      l10nNow.vipWhatsappPrefill(BrandConfig.instance.appName);

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
