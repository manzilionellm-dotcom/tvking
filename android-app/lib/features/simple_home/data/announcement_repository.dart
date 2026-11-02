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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
    this.expiresAt = 0,
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

  /// Fin décidée par le panel (0 = sans expiration). La box retire aussi
  /// localement une annonce échue si le réseau disparaît entre-temps.
  final int expiresAt;

  /// Construit depuis le JSON du Worker. Renvoie `null` si la charge utile
  /// est vide (`{}` = aucune annonce) ou invalide.
  static Announcement? fromJson(Map<String, dynamic> json) {
    final Object? rawId = json['id'];
    if (rawId == null || json['active'] == false || json['active'] == 0) {
      return null;
    }
    final int id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    if (id <= 0) return null;
    final int expiresAt = int.tryParse('${json['expires_at'] ?? 0}') ?? 0;
    if (expiresAt > 0 && expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      return null;
    }
    final String title = (json['title'] ?? '').toString();
    final String body = (json['body'] ?? '').toString();
    // Une annonce sans titre NI corps n'a rien à montrer.
    if (title.isEmpty && body.isEmpty) return null;
    final Object? rawTs = json['created_at'];
    final int createdAt = rawTs is int ? rawTs : int.tryParse('$rawTs') ?? 0;
    return Announcement(
      id: id,
      title: title,
      body: body,
      url: (json['url'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      cta: (json['cta'] ?? '').toString(),
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}

abstract final class AnnouncementRepository {
  /// Clé SharedPreferences : id de la dernière annonce fermée par l'user.
  static const String _kDismissedIdKey = 'announcement_dismissed_id';

  /// Dernière annonce VALIDE lue (ou `null` = le serveur dit « aucune »).
  /// Mise à jour par [fetchLatest], donc aussi par le canal « signal »
  /// quand le panel publie : l'accueil box écoute ici et se redessine
  /// sans relire le réseau lui-même. Une erreur réseau ne l'efface pas.
  static final ValueNotifier<Announcement?> latest =
      ValueNotifier<Announcement?>(null);

  static int _lastFetchMs = 0;
  static Future<Announcement?>? _pending;
  static Timer? _expiry;
  static int _generation = 0;

  @visibleForTesting
  static http.Client? client;
  @visibleForTesting
  static String? baseUrl;

  /// Une seule requête part même si le signal et l'accueil se réveillent
  /// ensemble. Une réponse 200 vide retire l'annonce ; une panne conserve
  /// l'annonce précédente jusqu'à sa date d'expiration.
  static Future<Announcement?> fetchLatest({bool strict = false}) async {
    final int generation = _generation;
    final Future<Announcement?> request = _pending ??= _fetch().whenComplete(
      () {
        if (generation == _generation) _pending = null;
      },
    );
    try {
      return await request;
    } catch (e) {
      // Un ordre du panel ne doit pas être accusé reçu après une panne.
      // Le bandeau garde, lui, sa dernière valeur jusqu'à son expiration.
      if (strict) rethrow;
      if (kDebugMode) debugPrint('[Announcement] fetch: $e');
      return latest.value;
    }
  }

  static Future<Announcement?> _fetch() async {
    final int generation = _generation;
    final http.Client c = client ?? http.Client();
    final bool owned = client == null;
    try {
      final http.Response resp = await c
          .get(Uri.parse('${baseUrl ?? kSubscriptionBaseUrl}/api/announcement'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        throw StateError('Annonce : HTTP ${resp.statusCode}');
      }
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic> ||
          (decoded.isNotEmpty &&
              (int.tryParse('${decoded['id']}') ?? 0) <= 0)) {
        throw const FormatException('Annonce invalide');
      }
      if (generation != _generation) return latest.value;
      final Announcement? parsed = Announcement.fromJson(decoded);
      _lastFetchMs = DateTime.now().millisecondsSinceEpoch;
      _replace(parsed);
      return parsed;
    } finally {
      if (owned) c.close();
    }
  }

  static void _replace(Announcement? next) {
    _expiry?.cancel();
    final Announcement? before = latest.value;
    if (next?.id != before?.id ||
        next?.title != before?.title ||
        next?.body != before?.body ||
        next?.url != before?.url ||
        next?.kind != before?.kind ||
        next?.cta != before?.cta ||
        next?.expiresAt != before?.expiresAt) {
      latest.value = next;
    }
    if (next != null && next.expiresAt > 0) {
      final int remaining =
          next.expiresAt - DateTime.now().millisecondsSinceEpoch;
      _expiry = Timer(
        Duration(milliseconds: remaining < 0 ? 0 : remaining),
        () {
          // Ne jamais supprimer une nouvelle annonce arrivée entre-temps.
          if (latest.value?.id == next.id &&
              latest.value?.expiresAt == next.expiresAt) {
            _replace(null);
          }
        },
      );
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _generation++;
    _expiry?.cancel();
    _expiry = null;
    _pending = null;
    _lastFetchMs = 0;
    client = null;
    baseUrl = null;
    latest.value = null;
  }

  /// Comme [fetchLatest], mais pas plus d'une fois par [maxAge] : l'accueil
  /// box revient souvent (retour du lecteur), le canal « signal » fait
  /// déjà le travail quand le panel publie.
  static Future<void> fetchIfStale({
    Duration maxAge = const Duration(minutes: 10),
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFetchMs < maxAge.inMilliseconds) return;
    await fetchLatest();
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
