// =========================================================
//  gist_repository.dart — Lecture/écriture du gist GitHub
// =========================================================
//  Encapsule les appels à l'API GitHub pour lire et mettre à
//  jour le fichier `config.json` d'un gist secret.
//
//  Pour la LECTURE : on peut passer par l'URL "Raw" sans token
//  (notre RemoteConfigRepository le fait déjà chez les clients).
//  Mais quand l'admin manipule le gist, on passe par l'API
//  authentifiée pour avoir les métadonnées (description, dates,
//  liste des fichiers) et pour éviter le cache CDN qui peut
//  servir une version vieille de plusieurs minutes après une
//  écriture.
//
//  Pour l'ÉCRITURE : impératif d'avoir un PAT GitHub avec le
//  scope `gist`. Sans ça l'API retourne 403.
//
//  Endpoints utilisés :
//    GET    https://api.github.com/gists/<id>
//    PATCH  https://api.github.com/gists/<id>
//
//  Format de body PATCH :
//    { "files": { "config.json": { "content": "<JSON serialized>" } } }
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'admin_client.dart';

class GistReadResult {
  const GistReadResult({
    required this.clients,
    required this.fileName,
    required this.rawJson,
  });

  /// Liste des clients parsés depuis le `config.json`.
  final List<AdminClient> clients;

  /// Nom du fichier où le JSON est stocké (généralement `config.json`).
  final String fileName;

  /// Le JSON brut tel que stocké dans le gist — utile pour
  /// préserver d'éventuelles clefs custom qu'on n'aurait pas
  /// modélisées dans AdminClient.
  final Map<String, dynamic> rawJson;
}

abstract final class GistRepository {
  static const String _apiBase = 'https://api.github.com';

  /// Lit le gist [gistId]. Si [pat] est fourni, utilise l'API
  /// authentifiée (recommandé : pas de cache, on voit les écritures
  /// immédiatement). Sinon, fallback sur l'API publique (rate
  /// limited à 60 req/h par IP, mais ça suffit largement).
  static Future<GistReadResult> read({
    required String gistId,
    String? pat,
  }) async {
    final Uri uri = Uri.parse('$_apiBase/gists/$gistId');
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      if (pat != null && pat.isNotEmpty) 'Authorization': 'Bearer $pat',
    };

    final http.Response resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode == 404) {
      throw const GistException(
        'Gist introuvable. Vérifie l\'ID copié depuis l\'URL.',
      );
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const GistException(
        'Accès refusé. Le PAT GitHub est invalide ou n\'a pas le scope `gist`.',
      );
    }
    if (resp.statusCode != 200) {
      throw GistException('Erreur GitHub HTTP ${resp.statusCode}');
    }

    final Map<String, dynamic> envelope =
        jsonDecode(resp.body) as Map<String, dynamic>;
    final Map<String, dynamic> files =
        (envelope['files'] as Map<String, dynamic>?) ??
            <String, dynamic>{};

    if (files.isEmpty) {
      throw const GistException('Ce gist ne contient aucun fichier.');
    }

    // On prend le 1er fichier .json — généralement `config.json`,
    // mais on est tolérant si l'admin a nommé différemment.
    String? targetName;
    Map<String, dynamic>? targetFile;
    for (final MapEntry<String, dynamic> e in files.entries) {
      if (e.key.toLowerCase().endsWith('.json')) {
        targetName = e.key;
        targetFile = e.value as Map<String, dynamic>;
        break;
      }
    }
    // Pas de .json ? On prend le 1er fichier quand même.
    if (targetFile == null) {
      final MapEntry<String, dynamic> first = files.entries.first;
      targetName = first.key;
      targetFile = first.value as Map<String, dynamic>;
    }

    final String content = (targetFile!['content'] as String?) ?? '{}';
    final Map<String, dynamic> raw =
        content.trim().isEmpty
            ? <String, dynamic>{}
            : jsonDecode(content) as Map<String, dynamic>;

    final List<AdminClient> clients = <AdminClient>[];
    for (final MapEntry<String, dynamic> e in raw.entries) {
      if (e.value is! Map<String, dynamic>) continue;
      clients.add(
        AdminClient.fromJson(e.key, e.value as Map<String, dynamic>),
      );
    }
    // Tri : les plus récents d'abord (added_at desc), les sans-date à la fin
    clients.sort((AdminClient a, AdminClient b) {
      final int aT = a.addedAt ?? 0;
      final int bT = b.addedAt ?? 0;
      return bT.compareTo(aT);
    });

    return GistReadResult(
      clients: clients,
      fileName: targetName!,
      rawJson: raw,
    );
  }

  /// Écrit la liste de [clients] dans le fichier [fileName] du gist
  /// [gistId] via l'API GitHub. Renvoie `true` si succès.
  ///
  /// On reconstruit l'objet JSON complet à partir de la liste —
  /// on écrase donc tout. Pour préserver des clefs custom non
  /// modélisées, lire `rawJson` avant et fusionner côté caller.
  static Future<bool> write({
    required String gistId,
    required String fileName,
    required List<AdminClient> clients,
    required String pat,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    for (final AdminClient c in clients) {
      body[c.mac] = c.toJson();
    }
    final String content = const JsonEncoder.withIndent('  ').convert(body);

    final Uri uri = Uri.parse('$_apiBase/gists/$gistId');
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Authorization': 'Bearer $pat',
      'Content-Type': 'application/json',
    };
    final String requestBody = jsonEncode(<String, dynamic>{
      'files': <String, dynamic>{
        fileName: <String, dynamic>{'content': content},
      },
    });

    final http.Response resp = await http
        .patch(uri, headers: headers, body: requestBody)
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const GistException(
        'Accès refusé. Vérifie que le PAT a bien le scope `gist`.',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint('[Gist] write failed ${resp.statusCode}\n${resp.body}');
      }
      throw GistException(
        'Erreur écriture gist (HTTP ${resp.statusCode}).',
      );
    }
    return true;
  }
}

class GistException implements Exception {
  const GistException(this.message);
  final String message;

  @override
  String toString() => message;
}
