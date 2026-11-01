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
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_platform.dart';
import '../branding/brand_config.dart';
import '../blackbox/black_box.dart';
import '../blackbox/black_box_redaction.dart';
import '../i18n/locale_repository.dart';
import '../../features/playlists/data/playlist_repository.dart';
import '../../features/playlists/data/import_progress.dart';
import '../../features/subscription/data/subscription_backend.dart';
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

  static Future<bool>? _opening;
  static const Duration _contextDeadline = Duration(milliseconds: 750);

  /// Filtre avant de composer l'URL, même pour une introduction provenant
  /// d'un ancien écran. Les champs libres ne peuvent injecter d'autres lignes
  /// et les données de liste ne quittent jamais le formulaire.
  static String _safe(String value, {int limit = 160}) {
    final String clean =
        redactBlackBox(value).replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return clean.length <= limit ? clean : clean.substring(0, limit);
  }

  /// Texte volontairement bref pour le support francophone. L'introduction
  /// est celle de la langue du client ; les codes techniques restent stables.
  /// Jamais de journal brut, titre de chaîne, URL, identifiant ou mot de passe.
  @visibleForTesting
  static String composeSupportMessage({
    required String appName,
    required String mac,
    required String status,
    required String version,
    String? customMessage,
    String? edition,
    String? device,
    String? locale,
    String? subscriptionDetails,
    int? sourceCount,
    int? channelCount,
    String? syncState,
    String? importState,
    bool? previousSessionAbrupt,
    String? previousExitReason,
  }) {
    String available(String value, [String fallback = 'indisponible']) {
      final String clean = _safe(value);
      return clean.isEmpty ? fallback : clean;
    }

    final String intro = available(customMessage ?? '', _defaultPrefill);
    final String name = available(appName, 'ZUNO');
    final String address = RegExp(r'^(?:MK|[0-9A-F]{2})(?::[0-9A-F]{2}){4,5}$',
                caseSensitive: false)
            .hasMatch(mac.trim())
        ? mac.trim().toUpperCase()
        : 'indisponible';
    final List<String> lines = <String>[
      intro,
      '',
      'Application : $name',
      if (edition != null) 'Édition : ${available(edition)}',
      if (address == 'indisponible' || !intro.contains(address))
        'MAC : $address',
      'Statut : ${available(status, 'non vérifié')}',
      if (subscriptionDetails != null)
        'Abonnement : ${available(subscriptionDetails)}',
      'Version : ${available(version)}',
      if (device != null) 'Appareil : ${available(device)}',
      if (locale != null) 'Langue : ${available(locale)}',
      if (sourceCount != null && sourceCount >= 0)
        'Listes chargées : $sourceCount',
      if (channelCount != null && channelCount >= 0)
        'Chaînes chargées : $channelCount',
      if (syncState != null) 'Panel : ${available(syncState)}',
      if (importState != null) 'Import : ${available(importState)}',
      if (previousSessionAbrupt != null)
        'Session précédente : ${previousSessionAbrupt ? 'arrêt inattendu' : 'sortie normale'}',
      // La description native est libre : seule une raison Android connue
      // est admise. Aucun chemin, fil d'Ariane ou contenu regardé n'est envoyé.
      if (_knownExitReason(previousExitReason) case final String reason)
        'Raison Android : $reason',
    ];
    return lines.join('\n');
  }

  static String? _knownExitReason(String? value) {
    if (value == null) return null;
    for (final String code in const <String>[
      'CRASH_NATIVE',
      'LOW_MEMORY',
      'USER_REQUESTED',
      'USER_STOPPED',
      'EXIT_SELF',
      'ANR',
      'CRASH',
      'SIGNALED',
      'EXCESSIVE_RESOURCE_USAGE',
    ]) {
      if (value == code || value.startsWith('$code ')) return code;
    }
    return null;
  }

  /// Priorité aux blocages, puis au paiement confirmé. Une activation sans
  /// paiement n'est pas présentée comme « payant ». Aucun achat ni heartbeat
  /// n'est déclenché pour ouvrir le support.
  @visibleForTesting
  static String subscriptionStatus(RemoteSubscriptionStatus remote,
      {DateTime? now}) {
    if (!remote.exists) return 'non vérifié';
    if (remote.banned) return 'bloqué';
    if (remote.frozen) return 'suspendu';
    if (remote.paid) return 'payant';
    if (remote.expired) return 'expiré';
    if (remote.trialUntil > (now ?? DateTime.now()).millisecondsSinceEpoch ||
        remote.daysLeft > 0) {
      return 'test';
    }
    return 'non actif';
  }

  static String _subscriptionDetails(RemoteSubscriptionStatus remote) {
    if (!remote.exists) return 'en attente de vérification';
    if (remote.paid && remote.isLifetime) return 'à vie';
    final int deadline = remote.paid ? remote.paidUntil : remote.trialUntil;
    if (deadline <= 0) return 'échéance non disponible';
    try {
      final String date =
          DateTime.fromMillisecondsSinceEpoch(deadline, isUtc: true)
              .toIso8601String()
              .substring(0, 10);
      return 'échéance UTC $date';
    } catch (_) {
      // Une valeur serveur illisible ne doit jamais fermer le contact.
      return 'échéance non disponible';
    }
  }

  static Future<T> _bounded<T>(Future<T> value, T fallback) async {
    try {
      return await value.timeout(_contextDeadline);
    } catch (_) {
      return fallback;
    }
  }

  /// Lectures locales en parallèle, plafonnées à 750 ms au total. Le client
  /// peut joindre le support même si un plugin répond mal ou si le panel est
  /// hors ligne. On réutilise les snapshots déjà chargés, sans importer de liste.
  static Future<String> _messageForCurrentDevice(String? customMessage) async {
    String appName = AppPlatform.isZuno
        ? AppPlatform.zunoEditionName
        : AppPlatform.isTv
            ? 'ZUNO'
            : 'Application';
    try {
      if (!AppPlatform.isZuno && !AppPlatform.isTv) {
        appName = BrandConfig.instance.appName;
      }
    } catch (_) {}
    final List<Object> values = await Future.wait<Object>(<Future<Object>>[
      _bounded<String>(DeviceIdentity.instance.mac, ''),
      _bounded<Map<String, String>>(
          DeviceIdentity.instance.deviceInfo(), const <String, String>{}),
      _bounded<String>(
          PackageInfo.fromPlatform()
              .then((info) => '${info.version} (${info.buildNumber})'),
          ''),
    ]);
    final Map<String, String> device = values[1] as Map<String, String>;
    final remote = SubscriptionState.instance.remote;
    final String? hint = SubscriptionState.instance.syncHint;
    final String panel = hint == 'offline'
        ? 'hors ligne (dernier état connu)'
        : remote.exists
            ? 'dernier état connu'
            : 'non vérifié';
    final String locale = LocaleRepository.instance.locale?.toLanguageTag() ??
        WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    final lastExit = BlackBox.instance.lastExit;
    final progress = ImportProgressBus.current.value;
    int? sourceCount;
    int? channelCount;
    try {
      sourceCount = PlaylistRepository.instance.currentPlaylists.length;
      channelCount = PlaylistRepository.instance.currentChannels.length;
    } catch (_) {
      // Un appel très tôt au démarrage doit rester possible, même avant que
      // la configuration d'édition et le catalogue soient prêts.
    }
    return composeSupportMessage(
      appName: appName,
      mac: values[0] as String,
      status: subscriptionStatus(remote),
      version: values[2] as String,
      customMessage: customMessage,
      edition: AppPlatform.isZuno
          ? AppPlatform.zunoEditionName
          : AppPlatform.isTv
              ? 'TV'
              : 'mobile',
      device: <String>[
        device['manufacturer'] ?? '',
        device['model'] ?? '',
        if (device['release']?.isNotEmpty == true)
          'Android ${device['release']}',
        if (device['sdk']?.isNotEmpty == true) 'API ${device['sdk']}',
      ].where((value) => value.isNotEmpty).join(' '),
      locale: locale,
      subscriptionDetails: _subscriptionDetails(remote),
      sourceCount: sourceCount,
      channelCount: channelCount,
      syncState: panel,
      importState: progress == null ? 'au repos' : progress.stage.name,
      previousSessionAbrupt: lastExit?.brutal,
      previousExitReason: lastExit?.nativeReason,
    );
  }

  /// Une seule ouverture simultanée, même si deux écrans de contact sont
  /// présents. wa.me ouvre WhatsApp ou le navigateur selon les apps installées.
  /// C'est toujours un brouillon : le client choisit ensuite « Envoyer ».
  static Future<bool> openWhatsApp({String? customMessage}) {
    final Future<bool>? pending = _opening;
    if (pending != null) return pending;
    final Future<bool> operation = _openWhatsApp(customMessage);
    _opening = operation;
    return operation.whenComplete(() {
      if (identical(_opening, operation)) _opening = null;
    });
  }

  static Future<bool> _openWhatsApp(String? customMessage) async {
    try {
      final String message = await _messageForCurrentDevice(customMessage);
      final Uri uri =
          Uri.https('wa.me', '/$_waNumber', <String, String>{'text': message});
      return await launchUrl(uri, mode: LaunchMode.externalApplication)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ne pas journaliser l'exception : certaines plateformes y joignent
      // l'URL complète et donc le brouillon du client.
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
