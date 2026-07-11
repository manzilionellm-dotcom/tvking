// =========================================================
//  update_service.dart — Mise a jour in-app (sideload)
// =========================================================
//  L'app n'est PAS distribuee par le Play Store : on gere donc nous-
//  memes la detection + le telechargement + l'installation du nouvel
//  APK, sans que le client desinstalle (la signature stable garantit
//  l'installation par-dessus, favoris/reglages conserves).
//
//  Source de verite : `version.json`, publie par le CI sur la release
//  `latest` a chaque build :
//    { "versionCode": 599, "versionName": "0.3.0",
//      "url": "https://.../releases/download/latest/7motion.apk",
//      "mandatory": false }
//
//  Comparaison : `versionCode` distant vs `buildNumber` local
//  (package_info_plus). Le CI passe --build-number=<run_number>, donc
//  le buildNumber augmente a chaque build → comparaison fiable.
//
//  Fail-open partout : la moindre erreur reseau/parse → on ne propose
//  rien, l'app continue normalement. Jamais de crash a cause de l'updater.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../app/app_platform.dart';
import 'build_flags.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    this.mandatory = false,
  });

  final int versionCode;
  final String versionName;
  final String url;
  final bool mandatory;
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Tag de la release TV où le CI publie `version.json` + `defew-tv.apk`.
  /// Passé au build par --dart-define. La MAISON MÈRE publie sur `tv-prod`
  /// (canal protégé anti-clobber). Défaut `tv-prod` : un APK TV construit
  /// sans le define reste sur le bon canal.
  static const String _tvUpdateTag =
      String.fromEnvironment('TV_UPDATE_TAG', defaultValue: 'tv-prod');

  /// `version.json` publié par le CI de la MAISON MÈRE : `prod` (téléphone)
  /// et `tv-prod` (DeFew TV). L'APK mobile et l'APK TV sont des builds
  /// différents (targets, versionCode) → aiguillage par plateforme, posé au
  /// boot. Ces canaux sont PROTÉGÉS (publiés uniquement par la maison mère),
  /// donc jamais écrasés : l'updater trouve toujours la vraie dernière app.
  static String get manifestUrl => AppPlatform.isTv
      ? 'https://github.com/manzilionellm-dotcom/tvking/releases/download/$_tvUpdateTag/version.json'
      : 'https://github.com/manzilionellm-dotcom/tvking/releases/download/prod/version.json';

  /// Retourne les infos de MAJ si une version PLUS RECENTE est dispo,
  /// sinon `null`. Fail-open : toute erreur → `null`.
  Future<UpdateInfo?> check() async {
    // Play Store : les MAJ viennent du Store, jamais du sideload GitHub.
    if (kIsPlayBuild) return null;
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final int current = int.tryParse(info.buildNumber) ?? 0;

      final http.Response r = await http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;

      final Map<String, dynamic> j =
          jsonDecode(r.body) as Map<String, dynamic>;
      final int latest = (j['versionCode'] as num?)?.toInt() ?? 0;
      if (latest <= current) return null; // deja a jour

      final String url = (j['url'] ?? '').toString();
      if (url.isEmpty) return null;

      return UpdateInfo(
        versionCode: latest,
        versionName: (j['versionName'] ?? '').toString(),
        url: url,
        mandatory: j['mandatory'] == true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Update] check error: $e');
      return null;
    }
  }

  /// Telecharge l'APK (progression 0..1) puis lance l'installateur
  /// systeme Android. Retourne `true` si l'installateur a bien ete
  /// lance (l'utilisateur confirme ensuite l'installation).
  Future<bool> downloadAndInstall(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    http.Client? client;
    IOSink? sink;
    try {
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/7motion-${update.versionCode}.apk');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      client = http.Client();
      final http.StreamedResponse resp =
          await client.send(http.Request('GET', Uri.parse(update.url)));
      if (resp.statusCode != 200) return false;

      final int total = resp.contentLength ?? 0;
      int received = 0;
      sink = file.openWrite();
      await for (final List<int> chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      // Lance l'installateur Android (necessite la permission
      // REQUEST_INSTALL_PACKAGES, ajoutee au manifest par le CI).
      final OpenResult res = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      return res.type == ResultType.done;
    } catch (e) {
      if (kDebugMode) debugPrint('[Update] install error: $e');
      return false;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client?.close();
    }
  }
}
