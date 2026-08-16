// =========================================================
//  announcement_repository.dart — Annonces « broadcast » admin → apps
// =========================================================
//  Le panneau admin (Worker Cloudflare) permet d'écrire UN message qui
//  doit s'afficher dans TOUTES les apps installées. Côté serveur c'est
//  déjà en place :
//    - GET  /api/announcement  (public) → dernière annonce ou {}
//    - POST /api/announcement  (admin)  → crée l'annonce
//    - DELETE /api/announcement (admin) → efface tout
//
//  Ici, côté APP, on se contente de LIRE la dernière annonce et de
//  retenir l'id déjà « lu/fermé » par l'utilisateur (SharedPreferences),
//  pour ne pas réafficher en boucle le même bandeau.
//
//  Aucune dépendance au cast : ce fichier ne touche QUE le réseau HTTP
//  et le stockage local.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/l10n_now.dart';
import '../../subscription/data/subscription_backend.dart';

/// Une annonce telle que renvoyée par le Worker. Immuable.
@immutable
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.url,
    required this.kind,
    required this.cta,
    required this.createdAt,
  });

  /// Identifiant unique côté serveur (auto-incrément). Sert à savoir si
  /// l'utilisateur a déjà fermé CETTE annonce.
  final int id;
  final String title;
  final String body;

  /// Lien optionnel (ex. page promo). Vide si absent.
  final String url;

  /// Catégorie : `nouveaute` | `promo` | `info` | `maintenance` (ou vide).
  /// Pilote l'icône + la couleur du bandeau (cf. AnnouncementBanner).
  final String kind;

  /// Libellé du bouton d'action associé à [url] (ex. « En profiter »).
  /// Vide → bouton générique « Ouvrir » si un lien est présent.
  final String cta;

  /// Timestamp epoch (ms) de création côté serveur.
  final int createdAt;

  /// Construit depuis le JSON du Worker. Renvoie `null` si la charge utile
  /// est vide (`{}` = aucune annonce) ou invalide.
  static Announcement? fromJson(Map<String, dynamic> json) {
    final Object? rawId = json['id'];
    if (rawId == null) return null; // {} → pas d'annonce
    final int id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    final String title = (json['title'] ?? '').toString();
    final String body = (json['body'] ?? '').toString();
    // Une annonce sans titre NI corps n'a rien à montrer.
    if (title.isEmpty && body.isEmpty) return null;
    final Object? rawTs = json['created_at'];
    final int createdAt =
        rawTs is int ? rawTs : int.tryParse('$rawTs') ?? 0;
    return Announcement(
      id: id,
      title: title,
      body: body,
      url: (json['url'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      cta: (json['cta'] ?? '').toString(),
      createdAt: createdAt,
    );
  }
}

abstract final class AnnouncementRepository {
  /// Clé SharedPreferences : id de la dernière annonce fermée par l'user.
  static const String _kDismissedIdKey = 'announcement_dismissed_id';

  /// Signal « une annonce vient (peut-être) de changer » — incrémenté par
  /// le temps réel (RealtimeSyncService, évènement `sync config`) quand
  /// l'admin publie/retire une annonce depuis le panel. La bannière
  /// d'accueil l'écoute et re-fetch aussitôt : l'annonce apparaît en
  /// direct, sans attendre un remontage du widget ni un redémarrage.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// À appeler quand le serveur signale un changement de config.
  static void notifyChanged() => revision.value++;

  /// Récupère la dernière annonce publiée, ou `null` si aucune / erreur
  /// réseau. On reste SILENCIEUX en cas d'échec : une annonce est un
  /// bonus, jamais bloquant.
  static Future<Announcement?> fetchLatest() async {
    try {
      // LANGUE DU CLIENT : le revendeur écrit son annonce dans UNE langue ;
      // le backend la traduit (et la met en cache) dans celle de l'app.
      // Sans ce paramètre, un client arabophone recevait le texte français.
      final String lang = l10nNow.localeName.split('_').first;
      final http.Response resp = await http
          .get(Uri.parse(
              '$kSubscriptionBaseUrl/api/announcement?lang=$lang'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;
      return Announcement.fromJson(decoded);
    } catch (e) {
      if (kDebugMode) debugPrint('[Announcement] fetch: $e');
      return null;
    }
  }

  /// `true` si l'utilisateur a déjà fermé cette annonce précise.
  static Future<bool> isDismissed(int id) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_kDismissedIdKey) == id;
    } catch (_) {
      return false;
    }
  }

  /// Mémorise que l'utilisateur a fermé l'annonce [id] → ne plus la
  /// réafficher (une annonce PLUS RÉCENTE, d'id supérieur, repassera).
  static Future<void> dismiss(int id) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kDismissedIdKey, id);
    } catch (_) {
      // best-effort
    }
  }
}
