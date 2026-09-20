// =========================================================
//  subscription_backend.dart — Client backend côté souscription
// =========================================================
//  Pendant Dart du couple :
//
//    POST /api/heartbeat            (app → worker)
//    GET  /api/status/:mac          (app → worker)
//
//  Ces routes sont PUBLIQUES (pas d'auth admin) : l'identifiant
//  est le MAC virtuel du device, comme pour /config/:mac.
//
//  Le serveur retourne {status, paid, days_left, expired, frozen,
//  banned, trial_until}. L'app utilise ces champs pour afficher
//  un écran de blocage si le client ne doit plus pouvoir utiliser
//  l'app (gelé par l'admin, banni, ou essai expiré sans paiement).
//
//  Fallback hors-ligne : si le serveur est inaccessible, l'app
//  retombe sur une GRÂCE COURTE (heures, cf. kOfflineGraceHours).
//  Plus d'essai local de plusieurs jours — « offline forever = free TV ».
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/app/app_platform.dart';
import '../../../core/app/build_info.dart';
import '../../../core/update/build_flags.dart';
import '../../../core/backend/backend_hosts.dart';
//  La note du banc d'essai vient de la boîte noire, qui la calcule à
//  partir de ses PROPRES lignes. Rien n'est compté ici : ce fichier ne
//  fait que la transporter (cf. core/observability/banc_essai.dart).
import '../../../core/observability/banc_essai.dart';
import '../../../core/observability/black_box.dart';
import '../../../core/observability/ressources_moniteur.dart';
import '../../../core/privacy/privacy_shield.dart';
import '../../device/data/device_identity.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/playlist.dart';
import 'now_playing.dart';

/// URL du Worker Cloudflare — DOIT être le MÊME backend que celui
/// utilisé par le panneau admin (admin-panel, `VITE_API_BASE`), sinon
/// l'app lit un autre serveur que celui où le panel écrit les
/// activations/sources → « l'app ne se connecte pas avec le panel ».
///
/// FAILOVER : ce n'est plus une adresse EN DUR mais un getter vers
/// [BackendHosts.current]. Le heartbeat sonde `app.7themotion.com`
/// puis, s'il ne répond pas, l'adresse Cloudflare native du MÊME
/// worker — et toute l'app (sources, thème, annonces, sauvegarde…)
/// bascule d'un coup sur l'hôte qui marche. Voir backend_hosts.dart.
String get kSubscriptionBaseUrl => BackendHosts.current;

/// Snapshot de l'état renvoyé par le serveur. Immuable.
@immutable
class RemoteSubscriptionStatus {
  const RemoteSubscriptionStatus({
    required this.exists,
    required this.status,
    required this.paid,
    required this.plan,
    required this.paidUntil,
    required this.daysLeft,
    required this.expired,
    required this.frozen,
    required this.banned,
    required this.trialUntil,
    this.graceDays = 0,
    this.graceHours = 0,
    this.loaned = false,
  });

  /// `true` si le serveur connaît ce MAC (= il a déjà fait un
  /// heartbeat). `false` la 1ère fois (création en cours).
  final bool exists;

  /// `'active'` | `'frozen'` | `'banned'` | `'unknown'`
  final String status;

  /// Abonnement payant valide.
  final bool paid;

  /// Type d'abonnement pour l'affichage :
  /// `'lifetime'` (à vie) | `'paid'`/`'1y'`/`'custom'` (durée limitée) |
  /// `'trial'` | `'expired'` | `'frozen'` | `'banned'` | `'unknown'`.
  final String plan;

  /// Fin de l'abonnement payant (ms epoch). `0` = aucune date connue
  /// (essai, ou abonnement à vie → voir `plan == 'lifetime'`).
  final int paidUntil;

  /// `true` si l'abonnement est à vie.
  bool get isLifetime => plan == 'lifetime';

  /// Jours d'essai restants (0 si épuisé ou inconnu).
  final int daysLeft;

  /// Essai épuisé ET non payé.
  final bool expired;

  /// Compte gelé par l'admin.
  final bool frozen;

  /// Compte banni par l'admin.
  final bool banned;

  /// Timestamp (ms epoch) d'expiration de l'essai.
  final int trialUntil;

  /// Ancien champ `grace_days` (jours). Ignoré côté app si > 0 : la
  /// grâce est désormais en HEURES (anti-freeloader). Conservé pour
  /// ne pas casser un Worker plus ancien qui l'enverrait encore.
  final int graceDays;

  /// Tolérance hors-ligne (heures) DÉCIDÉE PAR LE SERVEUR (`grace_hours`).
  /// `0` = absent → l'app applique kOfflineGraceHours, plafonné à 12 h.
  final int graceHours;

  /// Le propriétaire a prêté son abo : plus de lecture ici.
  final bool loaned;

  /// True si le client a le droit d'utiliser l'app.
  bool get canUse =>
      !banned && !frozen && !loaned && (paid || !expired);

  /// True si on doit afficher un écran bloquant.
  bool get shouldBlock =>
      banned || frozen || loaned || (expired && !paid);

  factory RemoteSubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return RemoteSubscriptionStatus(
      exists: json['exists'] == true,
      status: (json['status'] as String?) ?? 'unknown',
      paid: json['paid'] == true,
      plan: (json['plan'] as String?) ?? 'unknown',
      paidUntil: (json['paid_until'] as num?)?.toInt() ?? 0,
      daysLeft: (json['days_left'] as num?)?.toInt() ?? 0,
      expired: json['expired'] == true,
      frozen: json['frozen'] == true,
      banned: json['banned'] == true,
      trialUntil: (json['trial_until'] as num?)?.toInt() ?? 0,
      graceDays: (json['grace_days'] as num?)?.toInt() ?? 0,
      graceHours: (json['grace_hours'] as num?)?.toInt() ?? 0,
      loaned: json['loaned'] == true,
    );
  }

  /// État vide utilisé quand le serveur est inaccessible — l'app
  /// retombera sur le trial local pour la durée de l'incident.
  static const RemoteSubscriptionStatus unknown = RemoteSubscriptionStatus(
    exists: false,
    status: 'unknown',
    paid: false,
    plan: 'unknown',
    paidUntil: 0,
    daysLeft: 0,
    expired: false,
    frozen: false,
    banned: false,
    trialUntil: 0,
    loaned: false,
  );
}

abstract final class SubscriptionBackend {
  /// Pingue le serveur : il crée la fiche du MAC s'il ne la connaît
  /// pas (trial 10 j auto), ou rafraîchit son `last_seen_at` sinon.
  /// Renvoie le statut courant. Timeout court (8 s) — pas question
  /// que l'app traîne au boot si le réseau est nase.
  static Future<RemoteSubscriptionStatus> heartbeat(
    String mac, {
    int hop = 0,
  }) async {
    try {
      // Infos appareil → le panel recense chaque Android où l'app tourne
      // (même partagée via WhatsApp), avec son modèle + numéro de build.
      final Map<String, String> info =
          await DeviceIdentity.instance.deviceInfo();
      // ANDROID_ID brut (graine de la MAC) + version lisible de l'app : le
      // panel pro peut ainsi rechercher/vérifier par identifiant Android réel
      // et afficher la version installée.
      final String androidId = await DeviceIdentity.instance.androidId();
      final String appVersion = await _appVersion();
      final bool shielded = PrivacyShield.instance.minimalTelemetryActive;
      final Map<String, Object?> payload = <String, Object?>{
        'mac': mac,
        'model': info['model'] ?? '',
        'manufacturer': info['manufacturer'] ?? '',
        'android': info['release'] ?? '',
        'sdk': info['sdk'] ?? '',
        'build': info['build'] ?? '',
        'androidId': androidId,
        'appVersion': appVersion,
        'appBuild': kBuildTs,
        // NUMÉRO LISIBLE de la maison — 19881, 19882… (cf. AGENTS.md,
        // « la règle de la maison »). C'est celui que le panel affiche à
        // côté de la MAC, et qu'il compare au dernier publié pour dire
        // « dernière version » ou « ancienne version ». Vide sur un build
        // local sans --dart-define : le serveur n'écrase alors rien.
        'buildLabel': kBuildLabel,
        // Chaîne en cours de visionnage (vide si rien) → panel « En ligne ».
        // MODE BOUCLIER (télémétrie minimale) : la chaîne, l'inventaire des
        // sources et l'historique NE QUITTENT PAS l'appareil. Le panel sait
        // seulement que la box est en ligne (cf. core/privacy/privacy_shield).
        'channel': shielded ? '' : NowPlaying.instance.current,
        // « En lecture » (booléen, sans le nom de la chaîne) : c'est ce que
        // la FAMILLE voit (« Papa regarde en ce moment », une seule lecture
        // à la fois sur la ligne). Envoyé même sous bouclier : un booléen
        // n'est pas ce que le client regarde.
        'playing': NowPlaying.instance.current.isNotEmpty,
        // mobile / tv → le panel distingue les deux apps.
        'platform': AppPlatform.id,
        // BUILD MAGASIN (Play / Amazon) — 20/09/2026. Dans ce build, l'app
        // est un lecteur « apporte ta liste » : elle IGNORE les sources
        // poussées par le panel (RemoteSourceRepository.storeBuild, décidé
        // après le refus Amazon du 19/08). Sans ce drapeau, le revendeur
        // pousse une liste, rien n'arrive, et personne ne sait pourquoi —
        // c'est arrivé au propriétaire lui-même. Avec, le panel le DIT.
        'store': kIsPlayBuild,
        // INVENTAIRE des sources réellement présentes sur l'appareil (celles
        // poussées par le panel ET celles que le client a ajoutées lui-même).
        // Sert au panel : « tout ce que le client a dans le ventre » pour mieux
        // l'aider. SANS mot de passe (vie privée) — serveur + identifiant
        // suffisent au diagnostic. Best-effort : ne casse jamais le heartbeat.
        'sources': shielded
            ? const <Map<String, Object?>>[]
            : _sourcesInventory(),
        // HISTORIQUE de visionnage (ids de chaînes, du + récent au + ancien) :
        // sauvegardé côté serveur → restauré sur une 2e box (cf. /api/history).
        'recent': shielded ? const <String>[] : _recentInventory(),
        // =========================================================
        //  LA NOTE DE CE BUILD (18/09/2026)
        // =========================================================
        //  « Fais un benchmark » — demande du propriétaire. Sans cette
        //  remontée, la note reste sur la box et il faut la
        //  photographier une par une ; elle ne se compare donc pas d'un
        //  build à l'autre, ce qui est tout l'objet du banc.
        //
        //  ENVOYÉE SEULEMENT QUAND ELLE EXISTE. Sous une heure
        //  d'observation le banc refuse de noter (cf. banc_essai.dart) :
        //  on n'envoie alors rien du tout. Répéter « je ne sais pas »
        //  toutes les trente secondes ne remplirait que la base.
        //
        //  MODE BOUCLIER : rien non plus. Ce paquet ne dit pourtant rien
        //  de ce que le client regarde — uniquement si NOTRE app a
        //  flanché. Mais « télémétrie minimale » est un choix qu'il a
        //  fait, et un banc d'essai est notre confort, pas son besoin.
        if (!shielded) ..._bancSiNotable(),
        // =========================================================
        //  RAM ET CPU RÉELS (19/09/2026)
        // =========================================================
        //  « Pour savoir quelles box vivent au bord. » Mo résidents de
        //  NOTRE processus et pourcentage de l'appareil, relevés chaque
        //  minute, avec le pic de l'heure écoulée (ressources_moniteur).
        //  Absent tant qu'aucun relevé n'existe ; absent aussi sous le
        //  bouclier, par la même règle que le banc : c'est notre
        //  confort, pas le besoin du client.
        if (!shielded) ..._ressources(),
      };
      // FAILOVER : domaine maison d'abord (auto-guérison), puis l'adresse
      // Cloudflare de secours. Le premier hôte qui répond 200 devient
      // l'hôte COURANT de toute l'app (BackendHosts.markGood).
      final String body = jsonEncode(payload);
      for (final String base in BackendHosts.candidates()) {
        try {
          final http.Response resp = await http
              .post(
                Uri.parse('$base/api/heartbeat'),
                headers: const <String, String>{
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
                body: body,
              )
              .timeout(const Duration(seconds: 8));
          if (resp.statusCode != 200) {
            if (kDebugMode) {
              debugPrint(
                  '[Subscription] heartbeat HTTP ${resp.statusCode} ($base)');
            }
            continue; // hôte joignable mais en erreur → on tente l'autre
          }
          await BackendHosts.markGood(base);
          final Map<String, dynamic> json =
              jsonDecode(resp.body) as Map<String, dynamic>;
          // Filet HTTP (Doze / WS mort) : le Worker dit « cette MAC
          // n'existe plus, voici le nouveau numéro ». On ADOPTE puis
          // on re-pingue — sinon l'écran référence reste l'ancien.
          if (hop < 1) {
            final String? next = DeviceIdentity.newMacFromReassigned(
              json['mac_reassigned'],
            );
            if (next != null && next != mac) {
              final bool changed = await DeviceIdentity.instance.adopt(next);
              if (changed) {
                return heartbeat(next, hop: hop + 1);
              }
            }
          }
          return RemoteSubscriptionStatus.fromJson(json);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Subscription] heartbeat error ($base): $e');
          }
          // Réseau/timeout → hôte suivant.
        }
      }
      return RemoteSubscriptionStatus.unknown;
    } catch (e) {
      if (kDebugMode) debugPrint('[Subscription] heartbeat error: $e');
      return RemoteSubscriptionStatus.unknown;
    }
  }

  /// Construit l'inventaire COMPACT des sources présentes sur l'appareil
  /// (max 5), pour que le panel voie « tout ce que le client a ». On NE
  /// transmet JAMAIS le mot de passe : type, nom, serveur, identifiant,
  /// nombre de chaînes et « active » suffisent à diagnostiquer. Tout est
  /// gardé dans un try/catch pour ne jamais faire échouer le heartbeat.
  /// La note du banc d'essai, ou RIEN.
  ///
  ///  Un `Map` vide se répand sans effet dans le payload (`...`), donc
  ///  « pas de note » veut dire « pas de champ » — le serveur n'a rien
  ///  à écraser et la base ne se remplit pas de « je ne sais pas ».
  ///
  ///  Best-effort, comme tout ce qui entoure le heartbeat : si la boîte
  ///  noire n'est pas encore prête ou jette, on n'envoie pas de note.
  ///  Un banc d'essai ne doit JAMAIS empêcher une box de dire au
  ///  serveur qu'elle est vivante.
  static Map<String, Object?> _bancSiNotable() {
    try {
      final BancVerdict v = BlackBox.instance.bench();
      if (v.note == null) return const <String, Object?>{};
      return <String, Object?>{'bench': v.toJson()};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  /// RAM / CPU de l'app, ou RIEN (même contrat que [_bancSiNotable]).
  static Map<String, Object?> _ressources() {
    try {
      final Map<String, Object?> r = RessourcesMoniteur.instance.toJson();
      if (r.isEmpty) return const <String, Object?>{};
      return <String, Object?>{'res': r};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  static List<Map<String, Object?>> _sourcesInventory() {
    try {
      final List<Playlist> all =
          PlaylistRepository.instance.currentPlaylists;
      return all.take(5).map((Playlist p) {
        final bool xtream = p.type == PlaylistType.xtream;
        return <String, Object?>{
          'type': xtream ? 'xtream' : 'm3u',
          'name': p.name,
          // Une URL M3U porte presque toujours `username=…&password=…` :
          // on ne remonte que l'ORIGINE (schéma + hôte + port), jamais la
          // requête. Le commentaire « SANS mot de passe » redevient vrai.
          'server': xtream
              ? (p.xtreamServer ?? '')
              : _originOnly(p.m3uUrl ?? ''),
          'username': xtream ? (p.xtreamUsername ?? '') : '',
          'channels': p.channelCount,
          'active': p.isActive,
        };
      }).toList();
    } catch (_) {
      return const <Map<String, Object?>>[];
    }
  }

  /// Origine seule d'une URL (`http://hote:port`), sans chemin ni requête :
  /// suffisant pour le diagnostic, et jamais un identifiant dedans. Une
  /// chaîne qui n'est pas une URL est renvoyée vide.
  @visibleForTesting
  static String originOnly(String url) => _originOnly(url);

  static String _originOnly(String url) {
    final Uri? u = Uri.tryParse(url.trim());
    if (u == null || !u.hasScheme || u.host.isEmpty) return '';
    return u.hasPort ? '${u.scheme}://${u.host}:${u.port}' : '${u.scheme}://${u.host}';
  }

  /// Liste COMPACTE des chaînes récemment regardées (ids, max 50) à
  /// sauvegarder côté serveur pour la synchro multi-box. Best-effort.
  static List<String> _recentInventory() {
    try {
      return RecentlyWatchedRepository.instance.current.take(50).toList();
    } catch (_) {
      return const <String>[];
    }
  }

  /// Lit l'état courant du serveur sans toucher au `last_seen_at`.
  /// Utilisé par le `SubscriptionCard` pour rafraîchir l'UI sans
  /// déclencher un nouveau heartbeat (eg. après un pull-to-refresh).
  static Future<RemoteSubscriptionStatus> getStatus(
    String mac, {
    int hop = 0,
  }) async {
    // Même failover que le heartbeat : domaine maison puis secours.
    for (final String base in BackendHosts.candidates()) {
      try {
        final http.Response resp = await http
            .get(
              Uri.parse('$base/api/status/$mac'),
              headers: const <String, String>{
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) continue;
        await BackendHosts.markGood(base);
        final Map<String, dynamic> body =
            jsonDecode(resp.body) as Map<String, dynamic>;
        if (hop < 1) {
          final String? next = DeviceIdentity.newMacFromReassigned(
            body['mac_reassigned'],
          );
          if (next != null && next != mac) {
            final bool changed = await DeviceIdentity.instance.adopt(next);
            if (changed) {
              return getStatus(next, hop: hop + 1);
            }
          }
        }
        return RemoteSubscriptionStatus.fromJson(body);
      } catch (e) {
        if (kDebugMode) debugPrint('[Subscription] getStatus error ($base): $e');
      }
    }
    return RemoteSubscriptionStatus.unknown;
  }

  // Version lisible de l'app (ex. « 0.3.0 »), mise en cache. Best-effort.
  static String? _appVersionCache;
  static Future<String> _appVersion() async {
    if (_appVersionCache != null) return _appVersionCache!;
    try {
      final PackageInfo pkg = await PackageInfo.fromPlatform();
      _appVersionCache = pkg.version;
    } catch (_) {
      _appVersionCache = '';
    }
    return _appVersionCache!;
  }
}
