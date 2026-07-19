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
import 'package:shared_preferences/shared_preferences.dart';

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

/// Verdict d'une vérification MANUELLE (bouton « Vérifier les mises à
/// jour » des Réglages) : on distingue « déjà à jour » d'une « erreur
/// réseau » pour afficher le bon message (l'auto-MAJ, elle, se contente
/// d'un `UpdateInfo?` : `null` = ne rien proposer, silencieux).
enum UpdateAvailability {
  /// Une version plus récente est dispo (voir [UpdateCheckResult.info]).
  available,

  /// Le serveur a répondu et cette app est déjà la dernière version.
  upToDate,

  /// Impossible de vérifier (réseau KO, serveur injoignable, build Play).
  unavailable,
}

class UpdateCheckResult {
  const UpdateCheckResult(this.status, {this.info, this.versionName});
  final UpdateAvailability status;

  /// Détails de la MAJ quand [status] == available.
  final UpdateInfo? info;

  /// Nom de version distant (ex. « 0.3.2 ») si le serveur a répondu —
  /// sert au message « Tu as déjà la dernière version (0.3.2) ».
  final String? versionName;
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
  /// sinon `null`. Fail-open : toute erreur → `null`. Utilisé par
  /// l'auto-MAJ (silencieuse).
  Future<UpdateInfo?> check() async {
    final UpdateCheckResult r = await checkDetailed();
    return r.status == UpdateAvailability.available ? r.info : null;
  }

  /// Version DÉTAILLÉE de [check] pour le bouton MANUEL des Réglages :
  /// distingue « à jour » d'une « erreur réseau » (afin d'afficher le bon
  /// message). L'auto-MAJ passe par [check] et ne voit que `UpdateInfo?`.
  Future<UpdateCheckResult> checkDetailed() async {
    // Play Store : les MAJ viennent du Store, jamais du sideload GitHub.
    if (kIsPlayBuild) {
      return const UpdateCheckResult(UpdateAvailability.upToDate);
    }
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final int current = int.tryParse(info.buildNumber) ?? 0;

      final http.Response r = await http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) {
        return const UpdateCheckResult(UpdateAvailability.unavailable);
      }

      final Map<String, dynamic> j =
          jsonDecode(r.body) as Map<String, dynamic>;
      final int latest = (j['versionCode'] as num?)?.toInt() ?? 0;
      final String versionName = (j['versionName'] ?? '').toString();
      final String url = (j['url'] ?? '').toString();

      if (latest <= current || url.isEmpty) {
        // Serveur joignable ET rien de plus récent → déjà à jour.
        return UpdateCheckResult(
          UpdateAvailability.upToDate,
          versionName: versionName,
        );
      }

      final UpdateInfo update = UpdateInfo(
        versionCode: latest,
        versionName: versionName,
        url: url,
        mandatory: j['mandatory'] == true,
      );
      return UpdateCheckResult(
        UpdateAvailability.available,
        info: update,
        versionName: versionName,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Update] check error: $e');
      return const UpdateCheckResult(UpdateAvailability.unavailable);
    }
  }

  // ============================================================
  //  ANTI-HARCÈLEMENT (auto-MAJ) — mémoire par versionCode
  // ============================================================
  //  BUG corrigé : l'auto-MAJ rouvrait la boîte SYSTÈME Android « Mettre à
  //  jour cette application ? » à CHAQUE reprise d'app / tick tant que le
  //  client n'avait pas installé (ou tant que son build restait plus ancien
  //  que la version publiée). Résultat : dialogue d'installation en boucle —
  //  agaçant, et un mauvais réflexe de sécurité (on apprend au client à taper
  //  « Installer » sans réfléchir).
  //
  //  Correctif : on MÉMORISE le dernier versionCode pour lequel on a ouvert
  //  l'installateur, avec l'horodatage. On ne le rouvre PAS pour la MÊME
  //  version avant [_kAutoInstallCooldown]. Une version ENCORE plus récente
  //  lève aussitôt le silence ; s'il a installé, le buildNumber rejoint la
  //  cible → `check()` renvoie `null` et il n'y a plus rien à proposer.
  //  Le bouton MANUEL des Réglages n'est PAS concerné (geste volontaire).

  static const String _kAutoInstallCodeKey = 'update_auto_install_code_v1';
  static const String _kAutoInstallAtKey = 'update_auto_install_at_v1';
  static const Duration _kAutoInstallCooldown = Duration(hours: 24);

  /// Auto-MAJ : faut-il (RE)lancer l'installateur système pour [versionCode] ?
  /// `false` si on l'a déjà lancé pour CETTE version il y a moins de
  /// [_kAutoInstallCooldown] (→ on n'importune plus le client à chaque reprise).
  /// En cas de doute (lecture prefs KO), on renvoie `true` : ne jamais BLOQUER
  /// une vraie mise à jour.
  Future<bool> shouldAutoInstall(int versionCode) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final int lastCode = p.getInt(_kAutoInstallCodeKey) ?? 0;
      if (lastCode != versionCode) return true; // nouvelle version → oui
      final int lastAt = p.getInt(_kAutoInstallAtKey) ?? 0;
      final int now = DateTime.now().millisecondsSinceEpoch;
      return now - lastAt >= _kAutoInstallCooldown.inMilliseconds;
    } catch (_) {
      return true;
    }
  }

  /// Mémorise qu'on VIENT d'ouvrir l'installateur pour [versionCode] (auto-MAJ),
  /// pour ne pas rouvrir la boîte système à chaque reprise d'app.
  Future<void> markAutoInstallLaunched(int versionCode) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setInt(_kAutoInstallCodeKey, versionCode);
      await p.setInt(
          _kAutoInstallAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // best-effort : au pire on repropose une fois de trop, jamais un crash.
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
