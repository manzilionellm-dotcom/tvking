// =========================================================
//  backend_repository.dart — Client du Worker Cloudflare
// =========================================================
//  Encapsule les appels HTTP à notre Cloudflare Worker (cf.
//  cloudflare/worker.js). Ce repository REMPLACE l'ancien
//  GistRepository qui passait par l'API GitHub.
//
//  Endpoints utilisés :
//    GET    {baseUrl}/admin/clients          (liste)
//    POST   {baseUrl}/admin/clients          (créer)
//    PUT    {baseUrl}/admin/clients/{mac}    (modifier)
//    DELETE {baseUrl}/admin/clients/{mac}    (supprimer)
//
//  Auth : header `X-Admin-Secret: <secret>` sur chaque requête.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/i18n/app_l10n.dart';
import 'admin_client.dart';

class BackendReadResult {
  const BackendReadResult({required this.clients});
  final List<AdminClient> clients;
}

abstract final class BackendRepository {
  static Map<String, String> _headers(String secret) => <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Admin-Secret': secret,
      };

  /// Lit la liste de tous les clients depuis le Worker.
  static Future<BackendReadResult> read({
    required String baseUrl,
    required String adminSecret,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/admin/clients');
    final http.Response resp = await http
        .get(uri, headers: _headers(adminSecret))
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode == 401) {
      throw BackendException(AppL10n.current.adminErrSecretRefusedSetup);
    }
    if (resp.statusCode == 404) {
      throw BackendException(AppL10n.current.adminErrUrlNotFound);
    }
    if (resp.statusCode != 200) {
      throw BackendException(AppL10n.current.adminErrHttp(
        resp.statusCode,
        resp.body.length > 200 ? '${resp.body.substring(0, 200)}…' : resp.body,
      ));
    }

    try {
      final List<dynamic> raw = jsonDecode(resp.body) as List<dynamic>;
      final List<AdminClient> clients = <AdminClient>[];
      for (final dynamic entry in raw) {
        if (entry is! Map<String, dynamic>) continue;
        final String? mac = entry['mac'] as String?;
        if (mac == null || mac.isEmpty) continue;
        clients.add(AdminClient.fromJson(mac, entry));
      }
      return BackendReadResult(clients: clients);
    } catch (e) {
      throw BackendException(
          AppL10n.current.adminErrUnreadableResponse('$e'));
    }
  }

  /// Crée OU met à jour un client. Le Worker fait un upsert
  /// idempotent côté KV. Renvoie le client tel que sauvegardé.
  static Future<AdminClient> upsert({
    required String baseUrl,
    required String adminSecret,
    required AdminClient client,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/admin/clients/${client.mac}');
    final Map<String, dynamic> body = client.toJson()..['mac'] = client.mac;
    final http.Response resp = await http
        .put(uri, headers: _headers(adminSecret), body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode == 401) {
      throw BackendException(AppL10n.current.adminErrSecretRefused);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint('[Backend] upsert failed ${resp.statusCode}\n${resp.body}');
      }
      String hint = '';
      try {
        final Map<String, dynamic> err =
            jsonDecode(resp.body) as Map<String, dynamic>;
        if (err['error'] is String) {
          hint = '\n${AppL10n.current.adminErrDetail('${err['error']}')}';
        }
      } catch (_) {}
      throw BackendException(
        '${AppL10n.current.adminErrSaveFailed(resp.statusCode)}$hint',
      );
    }

    return client;
  }

  /// Supprime un client par sa MAC.
  static Future<void> delete({
    required String baseUrl,
    required String adminSecret,
    required String mac,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/admin/clients/$mac');
    final http.Response resp = await http
        .delete(uri, headers: _headers(adminSecret))
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode == 401) {
      throw BackendException(AppL10n.current.adminErrSecretRefused);
    }
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw BackendException(
        AppL10n.current.adminErrDeleteFailed(resp.statusCode),
      );
    }
  }

  /// Petit ping pour valider rapidement les credentials saisis
  /// par l'admin AVANT d'ouvrir le dashboard.
  static Future<bool> ping({
    required String baseUrl,
    required String adminSecret,
  }) async {
    try {
      await read(baseUrl: baseUrl, adminSecret: adminSecret);
      return true;
    } on BackendException {
      rethrow;
    } catch (e) {
      throw BackendException(
          AppL10n.current.adminErrServerUnreachable('$e'));
    }
  }
}

class BackendException implements Exception {
  const BackendException(this.message);
  final String message;

  @override
  String toString() => message;
}
