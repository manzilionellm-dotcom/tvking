// =========================================================
//  novatube_atlas.dart — Activation Atlas propre à NovaTube TV
// =========================================================
//  Édition NovaTube TV uniquement (kNovatubeTv). La box parle à SON
//  application Atlas (`app_novatube4k`), par les routes authentifiées déjà
//  en production, et JAMAIS aux routes historiques indexées par la seule
//  MAC (/api/heartbeat, /api/status, /api/device-source, /api/box/…) :
//  celles-ci pourraient créer une fiche Zuno en double, avec un autre essai.
//
//    POST /api/novatube4k/register  { raw_mac }   → fiche + essai serveur
//    POST /api/novatube4k/state     { raw_mac }   → licence + listes du panel
//    POST /api/novatube4k/redeem    { raw_mac, access_code } → accès ou récupération
//    POST /api/novatube4k/ack       { raw_mac, source_rev, applied, app_version }
//    POST /api/novatube4k/panel     { raw_mac, model, … } → présence, signaux
//    POST /api/novatube4k/blackbox  { raw_mac, text }    → journal de la box
//  Toutes avec l'en-tête X-Device-Key (clé d'installation, voir
//  novatube_identity.dart). Le serveur calcule l'essai de 10 jours, les
//  échéances et le blocage : la box AFFICHE, elle ne décide pas.
//
//  La réponse `state` est traduite dans le format historique
//  [RemoteSubscriptionStatus] : tout le reste de l'app (porte d'accès,
//  accueil, mode hors ligne, veille) fonctionne sans changement.
//  Les identifiants des listes ne sont JAMAIS journalisés ici.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/app/build_info.dart';
import '../../device/data/device_identity.dart';
import '../../device/data/novatube_identity.dart';
import '../../../core/blackbox/black_box_redaction.dart';
import 'subscription_backend.dart';

/// Réponse brute d'une route NovaTube (code HTTP + corps JSON s'il existe).
@immutable
class NovatubeReply {
  const NovatubeReply(this.status, this.body);
  final int status;
  final Map<String, dynamic>? body;
  bool get ok => status == 200 && body?['ok'] == true;
}

/// Verdict d'un code d'accès, sans le code lui-même ni un corps serveur
/// susceptible de contenir des informations privées. « accepted » signifie
/// seulement que le serveur l'a reconnu : la licence se relit par `state`.
enum NovatubeRedemption {
  accepted,
  invalidCode,
  deviceAuthRequired,
  conflict,
  rateLimited,
  unavailable,
}

class NovatubeAtlas {
  NovatubeAtlas._();
  static final NovatubeAtlas instance = NovatubeAtlas._();

  static const String _prefix = '/api/novatube4k/';

  /// Présence « riche » (modèle, version, listes sans mot de passe) : au
  /// plus toutes les 5 minutes. La présence simple suit chaque `state`.
  static const Duration telemetryEvery = Duration(minutes: 5);

  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;
  @visibleForTesting
  static String baseUrl = kSubscriptionBaseUrl;

  bool _registered = false;
  DateTime _lastTelemetry = DateTime.fromMillisecondsSinceEpoch(0);

  /// Listes servies par le panel lors du dernier `state` complet :
  /// `{ sources: [...], rev: n }`, lues par RemoteSourceRepository. `null`
  /// tant qu'aucune réponse fiable n'est arrivée : on GARDE alors les
  /// listes locales (une panne de catalogue n'est pas une suppression).
  Map<String, dynamic>? servedSources;

  /// Code d'assistance temporaire, affiché quand la clé d'installation ne
  /// correspond plus à la fiche (données de l'app effacées). L'administrateur
  /// l'approuve dans le panel : la fiche, la licence et les listes restent.
  final ValueNotifier<String?> recoveryCode = ValueNotifier<String?>(null);

  /// Lit l'état de la licence. `telemetry` : envoyer aussi la présence riche
  /// (au plus toutes les [telemetryEvery]).
  Future<RemoteStatusRead> readStatus({bool telemetry = false}) async {
    try {
      // `register` est idempotent côté serveur (même clé = même fiche) :
      // il est utilisé au premier appel de chaque démarrage, puis `state`.
      final NovatubeReply r =
          await post(_registered ? 'state' : 'register', const <String, Object?>{});
      final Map<String, dynamic>? body = r.body;
      if (r.ok && body != null) {
        _registered = true;
        recoveryCode.value = null;
        _keepServedSources(body);
        // Signaux du panel (demande de journal…), même format qu'avant.
        try {
          SubscriptionBackend.onStatusBody?.call(body);
        } catch (_) {}
        if (telemetry) unawaited(_maybeTelemetry());
        return RemoteStatusRead(status: mapState(body), reached: true);
      }
      if (r.status == 409 && body != null) {
        // Fiche existante, autre clé : réassociation à faire approuver.
        final Object? recovery = body['recovery'];
        recoveryCode.value =
            recovery is Map && recovery['code'] is String ? recovery['code'] as String : null;
        return const RemoteStatusRead(status: pendingStatus, reached: true);
      }
      if (r.status == 401 || body?['error'] == 'device_registration_missing') {
        // Fiche inconnue (supprimée côté panel) : on se réinscrit au tour suivant.
        _registered = false;
      }
      return RemoteStatusRead.offline;
    } catch (_) {
      return RemoteStatusRead.offline;
    }
  }

  /// Masque du format serveur, identique quelle que soit la langue de la box.
  static const String accessCodeMask = 'NVMAX-XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX';

  /// Les codes sont saisis ou collés. On tolère la casse et les espaces
  /// autour, mais on ne corrige pas un caractère ambigu à la place du client.
  /// Ce format n'accorde aucun accès : seul le serveur peut accepter le code.
  static String? normalizeAccessCode(String input) {
    final String code = input.trim().toUpperCase();
    return RegExp(r'^NVMAX-(?:[0-9A-F]{8}-){3}[0-9A-F]{8}$').hasMatch(code)
        ? code
        : null;
  }

  /// Échange explicite d'un code contre une licence pour CET appareil.
  /// La clé d'installation et la MAC suivent le même canal que `state`.
  /// Le code n'est ni sauvegardé, ni journalisé, ni utilisé pour fabriquer
  /// un état payé local. Après succès, l'écran relit l'état normal du serveur.
  Future<NovatubeRedemption> redeemAccessCode(String input) async {
    final String? code = normalizeAccessCode(input);
    if (code == null) return NovatubeRedemption.invalidCode;
    try {
      // Un utilisateur peut ouvrir le dialogue avant la première veille.
      // On attend donc l'inscription authentifiée normale avant l'échange.
      if (!_registered) {
        await readStatus();
        if (!_registered && recoveryCode.value == null) {
          return NovatubeRedemption.unavailable;
        }
      }
      // Après réinstallation, seul un code déjà lié à une attribution
      // admissible peut réassocier la nouvelle clé côté serveur. Un conflit
      // d'inscription n'empêche donc pas cette vérification explicite ; il
      // n'autorise aucune réassociation ni licence du côté de l'application.
      final NovatubeReply reply =
          await post('redeem', <String, Object?>{'access_code': code});
      if (reply.ok) {
        _registered = true;
        recoveryCode.value = null;
        return NovatubeRedemption.accepted;
      }
      switch (reply.status) {
        case 400:
        case 403:
          return NovatubeRedemption.invalidCode;
        case 401:
          // La fiche a pu être supprimée depuis la dernière lecture :
          // le prochain essai repassera par l'inscription habituelle.
          _registered = false;
          return NovatubeRedemption.deviceAuthRequired;
        case 409:
          return NovatubeRedemption.conflict;
        case 429:
          return NovatubeRedemption.rateLimited;
        default:
          return NovatubeRedemption.unavailable;
      }
    } catch (_) {
      // Aucun détail réseau (et surtout aucun code) dans le journal.
      return NovatubeRedemption.unavailable;
    }
  }

  /// Accusé « listes enregistrées sur la box » pour la révision servie.
  Future<bool> ack(int sourceRev) async {
    try {
      final String version = await _appVersion();
      final NovatubeReply r = await post('ack', <String, Object?>{
        'source_rev': sourceRev,
        'applied': true,
        'app_version': version,
      });
      return r.ok;
    } catch (_) {
      return false;
    }
  }

  /// Journal de la boîte noire (déjà filtré des secrets par l'appelant ;
  /// le serveur masque aussi la MAC brute).
  Future<bool> uploadBlackbox(String text) async {
    try {
      final clean = prepareBlackBoxUpload(text, enabled: true);
      if (clean == null) return false;
      final NovatubeReply r =
          await post('blackbox', <String, Object?>{'text': clean});
      return r.status == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _maybeTelemetry() async {
    final DateTime now = DateTime.now();
    if (now.difference(_lastTelemetry) < telemetryEvery) return;
    _lastTelemetry = now;
    try {
      final Map<String, String> info = await DeviceIdentity.instance.deviceInfo();
      await post('panel', <String, Object?>{
        'model': info['model'] ?? '',
        'build': info['build'] ?? '',
        'android': info['release'] ?? '',
        'appVersion': await _appVersion(),
        'appBuild': kBuildTs,
        'platform': 'tv',
        // Inventaire SANS identifiant ni mot de passe (le serveur l'efface
        // de toute façon) : type, nom, serveur, nombre de chaînes.
        'sources': SubscriptionBackend.sourcesInventoryForPanel(),
        'recent': SubscriptionBackend.recentInventoryForPanel(),
      });
    } catch (_) {
      // Présence best-effort : ne bloque jamais la lecture.
    }
  }

  void _keepServedSources(Map<String, dynamic> body) {
    if (body['sources_ok'] != true || body['sources'] is! List) return;
    servedSources = <String, dynamic>{
      'sources': body['sources'],
      'rev': body['source_rev'],
    };
  }

  /// Canal authentifié de la box. Le propriétaire du client peut fermer
  /// immédiatement la requête quand l’application passe en arrière-plan.
  Future<NovatubeReply> waitForChanges(http.Client connection, int after) =>
      post('wait', {'after': after, 'timeout': 18000},
          connection: connection, timeout: const Duration(seconds: 24));

  /// Envoi authentifié d'une action NovaTube. Visible pour les tests.
  @visibleForTesting
  Future<NovatubeReply> post(
    String action,
    Map<String, Object?> extra, {
    http.Client? connection,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final NovatubeIdentity id = NovatubeIdentity.instance;
    final String raw = await id.rawMac;
    final String key = await id.deviceKey;
    final http.Client client = connection ?? clientFactory();
    try {
      final http.Response resp = await client
          .post(
            Uri.parse('$baseUrl$_prefix$action'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-Device-Key': key,
            },
            body: jsonEncode(<String, Object?>{'raw_mac': raw, ...extra}),
          )
          .timeout(timeout);
      Object? decoded;
      try {
        decoded = jsonDecode(resp.body);
      } catch (_) {}
      return NovatubeReply(
        resp.statusCode,
        decoded is Map<String, dynamic> ? decoded : null,
      );
    } finally {
      if (connection == null) client.close();
    }
  }

  /// Fiche connue mais aucune licence ouverte : « en attente d'activation ».
  static const RemoteSubscriptionStatus pendingStatus = RemoteSubscriptionStatus(
    exists: true,
    status: 'inactive',
    paid: false,
    plan: 'none',
    paidUntil: 0,
    daysLeft: 0,
    expired: false,
    frozen: false,
    banned: false,
    trialUntil: 0,
    pending: true,
  );

  /// Traduit la réponse `state` du serveur. Fonction PURE (testée).
  ///   active + trial → essai ; active + paid → licence ; expired → expiré ;
  ///   frozen / disabled → suspendu ; banned → banni ; inactive → en attente.
  static RemoteSubscriptionStatus mapState(Map<String, dynamic> b) {
    final String status = (b['status'] as String?) ?? 'inactive';
    final String kind = (b['access_kind'] as String?) ?? 'none';
    final int now = (b['server_now'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final int? expires = (b['expires_at'] as num?)?.toInt();
    final bool open = status == 'active' &&
        b['active'] == true &&
        b['playback_allowed'] == true;
    final bool paid = open && kind == 'paid';
    final bool trial = open && kind == 'trial';
    const int dayMs = 24 * 60 * 60 * 1000;
    final int daysLeft =
        expires == null || expires <= now ? 0 : ((expires - now) / dayMs).ceil();
    return RemoteSubscriptionStatus(
      exists: true,
      status: status,
      paid: paid,
      // Licence payée sans échéance = à vie (format historique « lifetime »).
      plan: paid && expires == null ? 'lifetime' : ((b['plan'] as String?) ?? 'none'),
      paidUntil: paid ? (expires ?? 0) : 0,
      daysLeft: daysLeft,
      expired: status == 'expired',
      frozen: status == 'frozen' || status == 'disabled',
      banned: status == 'banned',
      trialUntil: trial ? (expires ?? 0) : 0,
      sourceRev: b['sources_ok'] == true ? (b['source_rev'] as num?)?.toInt() : null,
      resetAt: (b['reset_at'] as num?)?.toInt() ?? 0,
      pending: !open &&
          status != 'expired' &&
          status != 'frozen' &&
          status != 'disabled' &&
          status != 'banned',
    );
  }

  static Future<String> _appVersion() async {
    try {
      final PackageInfo p = await PackageInfo.fromPlatform();
      return '${p.version}+${p.buildNumber}';
    } catch (_) {
      return '';
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _registered = false;
    _lastTelemetry = DateTime.fromMillisecondsSinceEpoch(0);
    servedSources = null;
    recoveryCode.value = null;
  }
}
