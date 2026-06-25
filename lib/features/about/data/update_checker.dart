// =========================================================
//  update_checker.dart — Détection de mise à jour (par flavor)
// =========================================================
//  Les APK sont distribués hors store (sideload / Downloader) via des
//  releases GitHub à TAG ROULANT :
//    - 7 MOTION  → tag `latest`        , asset `7motion.apk`
//    - Red Room  → tag `redroom-latest`, asset `redroom.apk`
//
//  Comme le tag n'est pas une version sémantique, on ne compare pas des
//  numéros : on regarde la DATE de publication de l'APK (asset
//  `updated_at`). Si elle est plus récente que la dernière version que
//  l'utilisateur a déjà "vue" (acquittée), c'est qu'une mise à jour est
//  dispo.
//
//  Anti-spam : au tout premier lancement on mémorise la date courante
//  SANS prévenir. Quand l'utilisateur appuie sur « Télécharger » ou
//  « Plus tard », on acquitte cette date → il ne sera pas re-sollicité
//  pour la même build (y compris après l'avoir installée).
//
//  `releaseUrl` pointe DIRECTEMENT sur l'APK → le téléchargement part
//  tout de suite (Downloader / navigateur).
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/update/build_flags.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.publishedAt,
    required this.notes,
    required this.hasUpdate,
    required this.ackKey,
    required this.latestTs,
  });

  final String currentVersion;
  final String latestVersion;

  /// URL DIRECTE de l'APK (téléchargement immédiat).
  final String releaseUrl;
  final DateTime publishedAt;
  final String notes;

  /// `true` si une build plus récente que celle acquittée est dispo.
  final bool hasUpdate;

  /// Clé SharedPreferences servant à acquitter cette build.
  final String ackKey;

  /// Date de publication de l'APK (ms epoch) — sert d'acquittement.
  final int latestTs;
}

class UpdateChecker {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  static const String _owner = 'manzilionellm-dotcom';
  static const String _repo = 'tvking';

  UpdateInfo? _last;
  UpdateInfo? get last => _last;

  Future<UpdateInfo?> check(
      {Duration timeout = const Duration(seconds: 8)}) async {
    // Play Store : pas d'updater sideload GitHub (MAJ via le Store).
    if (kIsPlayBuild) return null;
    try {
      final PackageInfo pkg = await PackageInfo.fromPlatform();
      final String current = pkg.version;

      // Produit unique (mobile 7 MOTION) : release « latest », APK 7motion.apk.
      const String tag = 'latest';
      const String apk = '7motion.apk';

      final Uri uri = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/tags/$tag',
      );
      final http.Response resp = await http.get(
        uri,
        headers: const <String, String>{
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(timeout);
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('[UpdateChecker] HTTP ${resp.statusCode}');
        return null;
      }

      final Map<String, dynamic> data =
          jsonDecode(resp.body) as Map<String, dynamic>;

      // URL directe de l'APK + date de publication (asset `updated_at`).
      String downloadUrl =
          'https://github.com/$_owner/$_repo/releases/download/$tag/$apk';
      int latestTs = 0;
      final Object? assets = data['assets'];
      if (assets is List) {
        for (final Object? a in assets) {
          if (a is Map && a['name'] == apk) {
            final Object? u = a['browser_download_url'];
            if (u is String && u.isNotEmpty) downloadUrl = u;
            latestTs = DateTime.tryParse(a['updated_at']?.toString() ?? '')
                    ?.millisecondsSinceEpoch ??
                0;
            break;
          }
        }
      }
      if (latestTs == 0) {
        latestTs =
            DateTime.tryParse(data['published_at']?.toString() ?? '')
                    ?.millisecondsSinceEpoch ??
                0;
      }

      // Détection par acquittement.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String ackKey = 'update.acked.$tag';
      final int? acked = prefs.getInt(ackKey);
      bool hasUpdate;
      if (acked == null) {
        // 1er passage : on mémorise sans déranger.
        await prefs.setInt(ackKey, latestTs);
        hasUpdate = false;
      } else {
        hasUpdate = latestTs > acked;
      }

      final DateTime published = DateTime.fromMillisecondsSinceEpoch(
        latestTs == 0 ? DateTime.now().millisecondsSinceEpoch : latestTs,
      );
      final String label = '${published.day.toString().padLeft(2, '0')}/'
          '${published.month.toString().padLeft(2, '0')}/${published.year}';

      final UpdateInfo info = UpdateInfo(
        currentVersion: current,
        latestVersion: label,
        releaseUrl: downloadUrl,
        publishedAt: published,
        notes: data['body']?.toString() ?? '',
        hasUpdate: hasUpdate,
        ackKey: ackKey,
        latestTs: latestTs,
      );
      _last = info;
      if (kDebugMode) {
        debugPrint('[UpdateChecker] $tag ts=$latestTs acked=$acked '
            'update=$hasUpdate');
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

  /// Acquitte la build vue (ne plus re-prévenir pour celle-ci).
  Future<void> acknowledge(UpdateInfo info) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(info.ackKey, info.latestTs);
    } catch (_) {}
  }
}
