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

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../app/repair_flags.dart';
import '../blackbox/black_box.dart';
import 'build_flags.dart';
import 'update_manifest.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
    this.mandatory = false,
  });

  final int versionCode;
  final String versionName;
  final String url;

  /// Empreinte SHA-256 hex (64 caractères) annoncée par version.json.
  final String sha256;

  /// Taille exacte du fichier, en octets.
  final int sizeBytes;
  final bool mandatory;

  /// Délai maximum d'un téléchargement. Au-delà, on abandonne
  /// plutôt que de laisser une barre immobile.
  static const Duration downloadTimeout = Duration(minutes: 3);
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// `version.json` publie par le CI. Defaut = release `latest` (telephone).
  /// L'app TV (Zuno) pointe sur SA release au boot (main_tv.dart) : chaque
  /// produit ne voit que ses propres mises a jour.
  static String manifestUrl =
      'https://github.com/manzilionellm-dotcom/tvking/releases/download/latest/version.json';

  /// Manifestes EN PLUS de [manifestUrl]. Vide pour les clients. La box
  /// de test (build `test_box`) y met sa release de test : son bouton
  /// « Mise à jour » voit alors le dernier build, test OU client, le plus
  /// récent des deux (pickNewestManifest).
  static List<String> extraManifestUrls = const <String>[];

  /// Prefixe du fichier APK temporaire (pour un nom lisible dans l'installateur).
  static String apkPrefix = '7motion';

  /// Vrai quand le dernier essai a trouvé que Zuno n'a pas le droit
  /// d'installer une application, et que l'écran Android pour l'autoriser
  /// a été ouvert. L'écran Réglages affiche alors la marche à suivre.
  bool needsInstallPermission = false;

  static const MethodChannel _device =
      MethodChannel('com.manzilionellm.tvking/device');

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

      // Chaque manifeste est lu séparément : une release injoignable ne
      // cache pas l'autre. Repli `zuno.update.legacy` : un seul manifeste.
      final List<String> urls = <String>[
        manifestUrl,
        if (!RepairFlags.updateLegacy) ...extraManifestUrls,
      ];
      final List<Object?> decodedList = <Object?>[];
      for (final String url in urls) {
        decodedList.add(await _readManifest(url));
      }
      final UpdateManifest? manifest =
          pickNewestManifest(decodedList, currentBuild: current);
      int announced = 0;
      for (final Object? decoded in decodedList) {
        final int code = decoded is Map
            ? ((decoded['versionCode'] as num?)?.toInt() ?? 0)
            : 0;
        if (code > announced) announced = code;
      }
      BlackBox.instance.info('MAJ',
          'installee $current · disponible $announced (${urls.length} source(s))');
      if (manifest == null) {
        // Plus récent mais sans empreinte, ou déjà à jour, ou JSON cassé.
        if (announced > current) {
          BlackBox.instance.warn(
            'MAJ',
            'manifeste sans empreinte ou sans taille — mise à jour refusée',
          );
        }
        return null;
      }

      return UpdateInfo(
        versionCode: manifest.versionCode,
        versionName: manifest.versionName,
        url: manifest.url,
        sha256: manifest.sha256,
        sizeBytes: manifest.sizeBytes,
        mandatory: manifest.mandatory,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Update] check error: $e');
      BlackBox.instance.warn('MAJ', 'verification impossible : $e');
      return null;
    }
  }

  /// Lit un version.json. `null` si injoignable, code HTTP ≠ 200 ou JSON
  /// cassé : pickNewestManifest l'ignore.
  Future<Object?> _readManifest(String url) async {
    try {
      final http.Response r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body);
    } catch (e) {
      BlackBox.instance.warn('MAJ', 'manifeste illisible : $e');
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
      // La taille doit être EXACTEMENT celle du manifeste. Un fichier
      // coupé, même au-dessus de 1 Mo, n'est pas une mise à jour.
      if (await f.exists() && await f.length() == update.sizeBytes) {
        return f;
      }
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
      final bool legacy = RepairFlags.updateLegacy;
      // Nouveau : on abandonne si rien n'arrive pendant 45 s, ou après
      // 20 min. Un débit lent mais régulier va au bout (box en Wi-Fi
      // faible). Repli : 3 minutes au total, comme avant.
      final Duration total =
          legacy ? UpdateDownloadLimits.legacyTotal : UpdateDownloadLimits.total;
      final Duration idle =
          legacy ? UpdateDownloadLimits.legacyTotal : UpdateDownloadLimits.idle;
      final http.StreamedResponse resp = await client
          .send(http.Request('GET', Uri.parse(update.url)))
          .timeout(legacy ? total : UpdateDownloadLimits.connect);
      if (resp.statusCode != 200) {
        BlackBox.instance.warn('MAJ', 'telechargement HTTP ${resp.statusCode}');
        return null;
      }
      final int? announcedLength = resp.contentLength;
      int received = 0;
      sink = part.openWrite();
      // Empreinte calculée au fil de l'eau : on ne recharge pas
      // l'APK entier en mémoire (box à peu de RAM).
      final HashSink hasher = Sha256().newHashSink();
      final Stopwatch watch = Stopwatch()..start();
      await for (final List<int> chunk in resp.stream.timeout(idle)) {
        if (watch.elapsed > total) {
          throw TimeoutException('téléchargement trop long');
        }
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        progress.value = received / update.sizeBytes;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hasher.close();
      if (!apkSizeMatches(
        received: received,
        expected: update.sizeBytes,
        contentLength: announcedLength,
      )) {
        BlackBox.instance.warn(
          'MAJ',
          'APK refusé ($received octets, attendu ${update.sizeBytes})',
        );
        try {
          await part.delete();
        } catch (_) {}
        return null;
      }
      final Hash hash = await hasher.hash();
      final String got = hash.bytes
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      if (got != update.sha256) {
        BlackBox.instance.warn('MAJ', 'empreinte différente — fichier refusé');
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
    needsInstallPermission = false;
    try {
      final File? file = await prefetch(update);
      if (file == null) return false;
      // Android 8+ : sans l'autorisation « applications inconnues » pour
      // Zuno, l'installateur refuse (et certaines box n'offrent même pas
      // le bouton Paramètres). On ouvre nous-mêmes le bon écran ; l'APK
      // déjà vérifié reste prêt pour le prochain appui.
      if (!RepairFlags.updateLegacy && !await _canInstallPackages()) {
        final bool opened = await _openInstallPermission();
        needsInstallPermission = true;
        BlackBox.instance.warn('MAJ',
            'autorisation « applications inconnues » absente · réglage ${opened ? 'ouvert' : 'introuvable'}');
        return false;
      }
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

  Future<bool> _canInstallPackages() async {
    try {
      return await _device.invokeMethod<bool>('canInstallPackages') ?? true;
    } catch (_) {
      // Ancienne version du plugin ou autre plateforme : on laisse
      // l'installateur système décider, comme avant.
      return true;
    }
  }

  Future<bool> _openInstallPermission() async {
    try {
      return await _device.invokeMethod<bool>('openInstallPermission') ?? false;
    } catch (_) {
      return false;
    }
  }
}
