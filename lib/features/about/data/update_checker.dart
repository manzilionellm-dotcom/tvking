// =========================================================
//  update_checker.dart — Vérification de nouvelle version
// =========================================================
//  Au lancement de l'app, on demande à GitHub la dernière
//  release publiée du repo et on compare au numéro de version
//  embarqué dans l'APK courant.
//
//  Si une version plus récente existe → on expose une
//  notification que l'écran "About" peut afficher.
//
//  API : https://api.github.com/repos/{owner}/{repo}/releases/latest
//  (publique, sans token, mais limitée à 60 req/h par IP — c'est
//  largement suffisant puisqu'on n'appelle qu'au démarrage).
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.publishedAt,
    required this.notes,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final DateTime publishedAt;
  final String notes;

  bool get hasUpdate =>
      _compareVersions(currentVersion, latestVersion) < 0;
}

class UpdateChecker {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  static const String _owner = 'manzilionellm-dotcom';
  static const String _repo = 'tvking';

  UpdateInfo? _last;
  UpdateInfo? get last => _last;

  Future<UpdateInfo?> check({Duration timeout = const Duration(seconds: 8)}) async {
    try {
      final PackageInfo pkg = await PackageInfo.fromPlatform();
      final String currentVersion = pkg.version;

      final Uri uri = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );
      final http.Response resp = await http
          .get(uri, headers: <String, String>{
            'Accept': 'application/vnd.github+json',
          })
          .timeout(timeout);

      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[UpdateChecker] HTTP ${resp.statusCode}');
        }
        return null;
      }

      final Map<String, dynamic> data =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final String tag = (data['tag_name'] as String? ?? '')
          .replaceFirst(RegExp(r'^v'), '');
      if (tag.isEmpty) return null;

      final UpdateInfo info = UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: tag,
        releaseUrl: data['html_url']?.toString() ?? '',
        publishedAt:
            DateTime.tryParse(data['published_at']?.toString() ?? '') ??
                DateTime.now(),
        notes: data['body']?.toString() ?? '',
      );
      _last = info;
      if (kDebugMode) {
        debugPrint(
          '[UpdateChecker] current=$currentVersion latest=$tag '
          '(update available: ${info.hasUpdate})',
        );
      }
      return info;
    } on TimeoutException {
      if (kDebugMode) debugPrint('[UpdateChecker] timeout');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[UpdateChecker] error: $e');
      return null;
    }
  }
}

/// Compare deux versions semver-like.
/// Retourne <0 si a<b, 0 si égales, >0 si a>b.
int _compareVersions(String a, String b) {
  final List<int> ap = _parseVersion(a);
  final List<int> bp = _parseVersion(b);
  final int len = ap.length > bp.length ? ap.length : bp.length;
  for (int i = 0; i < len; i++) {
    final int av = i < ap.length ? ap[i] : 0;
    final int bv = i < bp.length ? bp[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

List<int> _parseVersion(String v) {
  return v
      .split(RegExp(r'[.\-+]'))
      .map((String s) => int.tryParse(s) ?? 0)
      .toList();
}
