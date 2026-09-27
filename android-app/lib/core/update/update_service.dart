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

import '../blackbox/black_box.dart';
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

  /// `version.json` publie par le CI. Defaut = release `latest` (telephone).
  /// L'app TV (Zuno) pointe sur SA release au boot (main_tv.dart) : chaque
  /// produit ne voit que ses propres mises a jour.
  static String manifestUrl =
      'https://github.com/manzilionellm-dotcom/tvking/releases/download/latest/version.json';

  /// Prefixe du fichier APK temporaire (pour un nom lisible dans l'installateur).
  static String apkPrefix = '7motion';

  /// Retourne les infos de MAJ si une version PLUS RECENTE est dispo,
  /// sinon `null`. Fail-open : toute erreur → `null`.
  Future<UpdateInfo?> check() async {
    // Play Store : les MAJ viennent du Store, jamais du sideload GitHub.
    if (kIsPlayBuild) return null;
    // PC (Zuno Windows) : un .apk ne s'installe pas sur Windows.
    if (!Platform.isAndroid) return null;
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final int current = int.tryParse(info.buildNumber) ?? 0;

      final http.Response r = await http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;

      final Map<String, dynamic> j = jsonDecode(r.body) as Map<String, dynamic>;
      final int latest = (j['versionCode'] as num?)?.toInt() ?? 0;
      BlackBox.instance.info('MAJ', 'installee $current · disponible $latest');
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
      BlackBox.instance.warn('MAJ', 'verification impossible : $e');
      return null;
    }
  }

  // ---------------------------------------------------------------
  //  PRÉ-TÉLÉCHARGEMENT (demande du propriétaire 27/09/2026) :
  //  « le client appuie sur Mise à jour et ça s'installe rapidement ».
  //  Dès qu'une nouvelle version est détectée (boot de la box ou ouverture
  //  des Paramètres), l'APK est téléchargé EN ARRIÈRE-PLAN. Quand le client
  //  appuie, le fichier est déjà là → l'installateur Android s'ouvre tout de
  //  suite, au lieu d'attendre ~50 Mo de téléchargement.
  //
  //  Sûreté :
  //   • écriture dans un « .part » puis renommage : un fichier coupé (box
  //     éteinte, réseau perdu) n'est JAMAIS pris pour un APK complet ;
  //   • taille vérifiée contre Content-Length quand le serveur la donne ;
  //   • un seul téléchargement à la fois (le bouton rejoint celui en cours
  //     et affiche sa progression au lieu d'en relancer un second) ;
  //   • les APK des versions précédentes sont supprimés (place disque).
  // ---------------------------------------------------------------

  /// Progression du téléchargement en cours (0..1), `null` si aucun.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);

  Future<File?>? _inflight;
  int? _inflightCode;

  Future<File> _apkFile(int versionCode) async {
    final Directory dir = await getTemporaryDirectory();
    return File('${dir.path}/$apkPrefix-$versionCode.apk');
  }

  /// APK déjà complet pour [update] (pré-téléchargé), sinon `null`.
  Future<File?> readyApk(UpdateInfo update) async {
    try {
      final File f = await _apkFile(update.versionCode);
      if (await f.exists() && await f.length() > 1024 * 1024) return f;
    } catch (_) {}
    return null;
  }

  /// Lance (ou rejoint) le téléchargement de l'APK de [update]. Renvoie le
  /// fichier complet, ou `null` en cas d'échec. Ne lance jamais deux
  /// téléchargements en parallèle.
  Future<File?> prefetch(UpdateInfo update) {
    if (!Platform.isAndroid || kIsPlayBuild) return Future<File?>.value(null);
    final Future<File?>? cur = _inflight;
    if (cur != null && _inflightCode == update.versionCode) return cur;
    final Future<File?> f = _download(update).whenComplete(() {
      _inflight = null;
      _inflightCode = null;
    });
    _inflight = f;
    _inflightCode = update.versionCode;
    return f;
  }

  Future<File?> _download(UpdateInfo update) async {
    final File? ready = await readyApk(update);
    if (ready != null) return ready;
    http.Client? client;
    IOSink? sink;
    try {
      final File file = await _apkFile(update.versionCode);
      final File part = File('${file.path}.part');
      await _purgeOld(file);
      BlackBox.instance.breadcrumb(
          'Mise a jour : telechargement build ${update.versionCode}');
      progress.value = 0;

      client = http.Client();
      final http.StreamedResponse resp =
          await client.send(http.Request('GET', Uri.parse(update.url)));
      if (resp.statusCode != 200) {
        BlackBox.instance.warn('MAJ', 'telechargement HTTP ${resp.statusCode}');
        return null;
      }
      final int total = resp.contentLength ?? 0;
      int received = 0;
      sink = part.openWrite();
      await for (final List<int> chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (total > 0 && received != total) {
        BlackBox.instance
            .warn('MAJ', 'APK incomplet ($received / $total octets)');
        try {
          await part.delete();
        } catch (_) {}
        return null;
      }
      final File done = await part.rename(file.path);
      BlackBox.instance.info('MAJ',
          'APK pret (${(received / (1024 * 1024)).toStringAsFixed(1)} Mo) · build ${update.versionCode}');
      return done;
    } catch (e) {
      if (kDebugMode) debugPrint('[Update] download error: $e');
      BlackBox.instance.error('MAJ', 'echec telechargement', e);
      return null;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client?.close();
      progress.value = null;
      BlackBox.instance.breadcrumb('');
    }
  }

  /// Supprime les APK / fichiers partiels des AUTRES versions.
  Future<void> _purgeOld(File keep) async {
    try {
      final Directory dir = keep.parent;
      await for (final FileSystemEntity e in dir.list()) {
        final String name =
            e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
        if (!name.startsWith('$apkPrefix-')) continue;
        if (e.path == keep.path || e.path == '${keep.path}.part') continue;
        try {
          await e.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Vérifie puis pré-télécharge en silence (appelé au démarrage de la box).
  /// Ne fait rien si l'app est à jour.
  Future<void> checkAndPrefetch() async {
    final UpdateInfo? u = await check();
    if (u != null) await prefetch(u);
  }

  /// Télécharge l'APK si besoin (ou utilise celui déjà pré-téléchargé) puis
  /// lance l'installateur système Android. Retourne `true` si
  /// l'installateur a bien été lancé (le client confirme ensuite : Android
  /// l'exige pour toute app installée hors Play Store).
  Future<bool> downloadAndInstall(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    void relay() {
      final double? v = progress.value;
      if (v != null) onProgress?.call(v);
    }

    progress.addListener(relay);
    try {
      final File? file = await prefetch(update);
      if (file == null) return false;
      // Lance l'installateur Android (necessite la permission
      // REQUEST_INSTALL_PACKAGES, ajoutee au manifest par le CI).
      BlackBox.instance
          .info('MAJ', 'installateur Android → build ${update.versionCode}');
      final OpenResult res = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (res.type != ResultType.done) {
        BlackBox.instance
            .warn('MAJ', 'installateur non lance : ${res.type} ${res.message}');
      }
      return res.type == ResultType.done;
    } catch (e) {
      if (kDebugMode) debugPrint('[Update] install error: $e');
      BlackBox.instance.error('MAJ', 'echec installation', e);
      return false;
    } finally {
      progress.removeListener(relay);
    }
  }
}
