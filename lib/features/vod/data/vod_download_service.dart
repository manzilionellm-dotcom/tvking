// =========================================================
//  vod_download_service.dart — Téléchargements Cinéma (hors-ligne)
// =========================================================
//  « Regarder plus tard, sans connexion » (comme Netflix). MODULE
//  INDÉPENDANT : télécharge le FICHIER du film ou de l'épisode (VOD
//  Xtream = un vrai fichier mp4/mkv, déjà compressé par le fournisseur)
//  vers le stockage PRIVÉ de l'app, puis la lecture passe HORS-LIGNE par
//  le lecteur EXISTANT (fichier local → ExoPlayer, isLive:false → mêmes
//  commandes Netflix ±10 s). Le dossier est invisible pour l'utilisateur
//  (Android/data/<app>/…) et purgé automatiquement à la désinstallation.
//
//  « INTELLIGENT comme Netflix » — trois mécanismes, tous ici :
//
//   1. FILE SÉRIELLE : UN téléchargement à la fois, les autres attendent
//      en `queued`. C'est ce que fait Netflix : la bande passante entière
//      pour un fichier = terminé plus vite, jamais 3 films à moitié.
//
//   2. COURTOISIE RÉSEAU (spécifique IPTV) : beaucoup de comptes Xtream
//      n'autorisent qu'UNE connexion. Un téléchargement pendant une
//      lecture en STREAMING volerait le créneau → écran « chaîne vide ou
//      bloquée » (bug terrain connu). Le lecteur nous signale donc ses
//      lectures RÉSEAU (setPlaybackHold) : pendant ce temps, la file
//      patiente. Une lecture LOCALE (fichier téléchargé) ne bloque rien —
//      c'est là que la boucle devient magique : on regarde l'épisode
//      téléchargé PENDANT que le suivant se télécharge.
//
//   3. TÉLÉCHARGEMENTS INTELLIGENTS (épisodes) : quand un épisode se
//      termine, on SUPPRIME son fichier (il est vu — la place se libère
//      toute seule) et on met LE SUIVANT en file. L'espace occupé reste
//      donc constant (~1-2 épisodes), peu importe la longueur de la
//      série. Désactivable dans « Mes téléchargements ».
//
//  GARDE D'ESPACE : avant de démarrer (et en cours de route), on lit
//  l'espace libre réel du volume (`df`, présent sur Android/toybox). En
//  dessous du seuil, le téléchargement passe en `noSpace` au lieu de
//  remplir la box jusqu'à l'os. Best-effort : si `df` n'existe pas
//  (desktop de dev), on ne bloque pas.
//
//  STOCKAGE : fichiers dans <stockage privé app>/Downloads ; métadonnées
//  en JSON (SharedPreferences). Reprise HTTP Range → zéro octet
//  re-téléchargé après une coupure ou un redémarrage.
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/playback/stream_slot.dart';
import '../domain/vod_movie.dart';

enum VodDownloadStatus { queued, downloading, paused, done, error, noSpace }

/// Un contenu (film OU épisode) en cours / terminé de téléchargement.
class VodDownload {
  VodDownload({
    required this.id,
    required this.name,
    required this.filePath,
    required this.streamUrl,
    this.posterUrl,
    this.category = '',
    this.year,
    this.rating,
    this.isEpisode = false,
    this.groupName = '',
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = VodDownloadStatus.queued,
  });

  final String id;
  final String name;
  final String filePath;
  final String streamUrl;
  final String? posterUrl;
  final String category;
  final String? year;
  final String? rating;

  /// Épisode de série (true) ou film (false). Seuls les ÉPISODES sont
  /// supprimés automatiquement une fois vus — jamais un film.
  final bool isEpisode;

  /// Nom de la série (épisodes) — affiché dans la rangée « Téléchargés ».
  final String groupName;

  int totalBytes;
  int downloadedBytes;
  VodDownloadStatus status;

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
  bool get isComplete => status == VodDownloadStatus.done;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'filePath': filePath,
        'streamUrl': streamUrl,
        'posterUrl': posterUrl,
        'category': category,
        'year': year,
        'rating': rating,
        'isEpisode': isEpisode,
        'groupName': groupName,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        // Un téléchargement interrompu reprend en 'paused' (jamais
        // 'downloading' au rechargement de l'app). `noSpace` redevient
        // 'queued' : l'utilisateur a pu libérer de la place entre-temps.
        'status': switch (status) {
          VodDownloadStatus.downloading => VodDownloadStatus.paused,
          VodDownloadStatus.noSpace => VodDownloadStatus.queued,
          _ => status,
        }
            .name,
      };

  factory VodDownload.fromJson(Map<String, dynamic> j) => VodDownload(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        filePath: j['filePath'] as String,
        streamUrl: (j['streamUrl'] as String?) ?? '',
        posterUrl: j['posterUrl'] as String?,
        category: (j['category'] as String?) ?? '',
        year: j['year'] as String?,
        rating: j['rating'] as String?,
        isEpisode: (j['isEpisode'] as bool?) ?? false,
        groupName: (j['groupName'] as String?) ?? '',
        totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
        downloadedBytes: (j['downloadedBytes'] as num?)?.toInt() ?? 0,
        status: VodDownloadStatus.values.firstWhere(
          (VodDownloadStatus s) => s.name == j['status'],
          orElse: () => VodDownloadStatus.paused,
        ),
      );
}

/// Ce qu'il faut savoir d'un ÉPISODE SUIVANT pour l'enchaîner en
/// téléchargement (champs plats : le service ne dépend d'aucun modèle UI).
class VodNextEpisode {
  const VodNextEpisode({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.posterUrl,
    this.groupName = '',
  });
  final String id;
  final String name;
  final String streamUrl;
  final String? posterUrl;
  final String groupName;
}

class VodDownloadService extends ChangeNotifier {
  VodDownloadService._() {
    // La file est un CONSOMMATEUR DE CONNEXION comme un autre : toute lecture
    // qui reclame le creneau la fait taire d'abord (cf. StreamSlot). Sans ca,
    // le telechargeur pouvait detenir la seule connexion du compte au moment
    // ou le client lance une chaine.
    StreamSlot.instance.register(
      this,
      group: StreamSlot.groupDownloads,
      label: 'telechargements',
      teardown: () async => setPlaybackHold(true),
    );
  }
  static final VodDownloadService instance = VodDownloadService._();

  static const String _kKey = 'vod_downloads.v1';
  static const String _kSmartKey = 'vod_downloads.smart.v1';
  static const String _kWatchSaveKey = 'vod_downloads.watch_save.v1';

  /// Seuils d'espace libre : on REFUSE de démarrer sous 500 Mo, et on
  /// SUSPEND un téléchargement en cours sous 200 Mo. Marge volontaire :
  /// une box qui suffoque (0 octet libre) casse TOUT le système, pas
  /// seulement notre fichier.
  static const int kMinFreeToStart = 500 * 1024 * 1024;
  static const int kMinFreeWhileRunning = 200 * 1024 * 1024;

  final Map<String, VodDownload> _items = <String, VodDownload>{};
  final Map<String, HttpClient> _clients = <String, HttpClient>{};
  bool _loaded = false;
  bool _smart = true;

  /// Id du job actuellement au robinet (file SÉRIELLE : un seul).
  String? _activeId;

  /// true tant que le lecteur streame en RÉSEAU (live ou VOD distante) —
  /// la file patiente pour ne pas voler le créneau 1-connexion du panel.
  bool _playbackHold = false;

  /// « Télécharger pendant que je regarde » (façon YouTube). Ces ids ont le
  /// DROIT de se télécharger MÊME pendant une lecture réseau (2e connexion).
  /// Réservé au film qu'on est en train de regarder → à la fin, il est déjà
  /// hors-ligne. Sur un compte « 1 connexion » ça peut échouer : le back-off
  /// du moteur encaisse, la lecture reste prioritaire.
  final Set<String> _playAlong = <String>{};

  /// Liste (ordre d'insertion — les récents en dernier).
  List<VodDownload> get all => _items.values.toList(growable: false);
  VodDownload? byId(String id) => _items[id];
  bool isDownloaded(String id) => _items[id]?.isComplete ?? false;

  /// Téléchargements intelligents (épisodes) — ON par défaut, persisté.
  bool get smartEnabled => _smart;
  Future<void> setSmartEnabled(bool v) async {
    _smart = v;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSmartKey, v);
    } catch (_) {}
  }

  /// « Télécharger pendant que je regarde » — OFF par défaut (2e connexion :
  /// à activer par ceux dont le compte l'autorise). Persisté.
  bool _watchAndSave = false;
  bool get watchAndSaveEnabled => _watchAndSave;
  Future<void> setWatchAndSaveEnabled(bool v) async {
    _watchAndSave = v;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kWatchSaveKey, v);
    } catch (_) {}
  }

  /// Le lecteur signale « je regarde CE film en réseau » : si l'option
  /// « pendant la lecture » est active et que le film n'est pas déjà
  /// (télé)chargé, on le met en file EN PARALLÈLE de la lecture (façon
  /// YouTube) — à la fin, il est hors-ligne. No-op si option OFF, contenu
  /// local, ou déjà présent.
  Future<void> watchAlong({
    required String id,
    required String name,
    required String streamUrl,
    String? posterUrl,
    String category = '',
    bool isEpisode = false,
    String groupName = '',
  }) async {
    await load();
    if (!_watchAndSave) return;
    if (streamUrl.isEmpty || streamUrl.startsWith('file:')) return;
    if (_items[id]?.isComplete ?? false) return;
    _playAlong.add(id);
    await enqueue(
      id: id,
      name: name,
      streamUrl: streamUrl,
      posterUrl: posterUrl,
      category: category,
      isEpisode: isEpisode,
      groupName: groupName,
    );
  }

  /// Fichier local prêt à lire (null si pas terminé). LE point d'entrée du
  /// lecteur : si non-null, la lecture est instantanée et 100 % hors réseau.
  String? localFile(String id) {
    final VodDownload? d = _items[id];
    if (d == null || !d.isComplete) return null;
    return d.filePath;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _smart = prefs.getBool(_kSmartKey) ?? true;
      _watchAndSave = prefs.getBool(_kWatchSaveKey) ?? false;
      final String raw = prefs.getString(_kKey) ?? '[]';
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      _items.clear();
      for (final dynamic e in list) {
        if (e is Map<String, dynamic>) {
          final VodDownload d = VodDownload.fromJson(e);
          _items[d.id] = d;
        }
      }
    } catch (e) {
      debugPrint('[VodDl] load: $e');
    }
    notifyListeners();
  }

  // ---- courtoisie réseau (appelé par le lecteur TV) ---------------------

  /// Le lecteur déclare ses lectures RÉSEAU. true = un flux distant joue
  /// (on suspend la file, statut `queued`, Range → reprise sans perte) ;
  /// false = réseau libre (fin de lecture, ou lecture d'un fichier LOCAL)
  /// → la file repart toute seule.
  void setPlaybackHold(bool hold) {
    if (_playbackHold == hold) return;
    _playbackHold = hold;
    _releaseGrace?.cancel();
    _releaseGrace = null;
    if (hold) {
      final String? id = _activeId;
      if (id != null) {
        final VodDownload? d = _items[id];
        _clients.remove(id)?.close(force: true);
        if (d != null && d.status == VodDownloadStatus.downloading) {
          d.status = VodDownloadStatus.queued; // reprendra tout seul
          notifyListeners();
        }
      }
      return;
    }
    // RÉPIT AVANT REPRISE (bug terrain : « je quitte le cinéma, je lance
    // France 2 → un autre flux est déjà en cours »).
    //
    // Le lecteur lève le verrou dans son `dispose`, donc AU MOMENT EXACT où
    // l'utilisateur quitte le film — et c'est presque toujours pour lancer
    // autre chose. La file repartait dans la milliseconde et reprenait le
    // créneau du compte AVANT que la chaîne suivante n'ait eu le temps de
    // s'ouvrir : le panel refusait la chaîne, et le client accusait le
    // lecteur alors que le voleur était le téléchargeur.
    //
    // On laisse donc passer la vague : si une lecture redémarre pendant ce
    // répit, `setPlaybackHold(true)` annule le timer et rien n'a bougé.
    _releaseGrace = Timer(_kResumeGrace, () {
      _releaseGrace = null;
      if (!_playbackHold) _pump();
    });
  }

  /// Délai d'attente avant de relancer la file après une lecture réseau.
  /// Assez long pour couvrir « je quitte le film et je zappe aussitôt »,
  /// assez court pour que les téléchargements ne s'endorment pas.
  static const Duration _kResumeGrace = Duration(seconds: 12);
  Timer? _releaseGrace;

  Future<Directory> _dir() async {
    // Stockage PRIVÉ de l'app (Android/data/<pkg>/files) : invisible dans
    // les gestionnaires de fichiers grand public, purgé à la
    // désinstallation — « on ne sait même pas où c'est, et ça reste là ».
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(base.path, 'Downloads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kKey,
          jsonEncode(
              _items.values.map((VodDownload d) => d.toJson()).toList()));
    } catch (e) {
      debugPrint('[VodDl] persist: $e');
    }
  }

  /// Lance (ou reprend) le téléchargement d'un FILM. Idempotent.
  Future<void> downloadMovie(VodMovie m) => enqueue(
        id: m.id,
        name: m.name,
        streamUrl: m.streamUrl,
        posterUrl: m.posterUrl,
        category: m.category,
        year: m.year,
        rating: m.rating,
        containerExt: m.containerExt,
      );

  /// Entrée GÉNÉRIQUE (film ou épisode). Idempotent : déjà fini → rien ;
  /// déjà en cours/en file → rien. Sinon crée la fiche et alimente la file.
  Future<void> enqueue({
    required String id,
    required String name,
    required String streamUrl,
    String? posterUrl,
    String category = '',
    String? year,
    String? rating,
    String containerExt = '',
    bool isEpisode = false,
    String groupName = '',
  }) async {
    await load();
    if (streamUrl.isEmpty || streamUrl.startsWith('file:')) return;
    final VodDownload? existing = _items[id];
    if (existing != null) {
      if (existing.isComplete ||
          existing.status == VodDownloadStatus.downloading ||
          existing.status == VodDownloadStatus.queued) {
        return;
      }
      // paused / error / noSpace → on le remet simplement en file.
      existing.status = VodDownloadStatus.queued;
      notifyListeners();
      await _persist();
      _pump();
      return;
    }
    final Directory dir = await _dir();
    final String ext = containerExt.isNotEmpty
        ? containerExt
        : _extFromUrl(streamUrl) ?? 'mp4';
    final String safe = name.replaceAll(RegExp(r'[^\w\d\-_. ]+'), '_');
    final String path = p.join(dir.path, '${id}_$safe.$ext');
    _items[id] = VodDownload(
      id: id,
      name: name,
      filePath: path,
      streamUrl: streamUrl,
      posterUrl: posterUrl,
      category: category,
      year: year,
      rating: rating,
      isEpisode: isEpisode,
      groupName: groupName,
    );
    notifyListeners();
    await _persist();
    _pump();
  }

  /// « .mkv » dans l'URL → « mkv » (repli quand l'extension conteneur
  /// n'est pas fournie, ex. enchaînement d'épisodes depuis le lecteur).
  static String? _extFromUrl(String url) {
    final String path = Uri.tryParse(url)?.path ?? url;
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    final String ext = path.substring(dot + 1).toLowerCase();
    if (ext.length > 5 || !RegExp(r'^[a-z0-9]+$').hasMatch(ext)) return null;
    return ext;
  }

  // ---- TÉLÉCHARGEMENTS INTELLIGENTS (épisodes) --------------------------

  /// À appeler quand un ÉPISODE vient d'être terminé (générique atteint).
  /// Fait les deux gestes Netflix, si l'option est active :
  ///   1. l'épisode VU était téléchargé → son fichier est SUPPRIMÉ (la
  ///      place se libère toute seule, un film n'est JAMAIS touché) ;
  ///   2. l'épisode SUIVANT (s'il existe et n'est pas déjà là) est mis en
  ///      file — il démarrera dès que le réseau sera libre (courtoisie).
  Future<void> onEpisodeWatched({
    required String watchedId,
    VodNextEpisode? next,
  }) async {
    await load();
    if (!_smart) return;
    final VodDownload? watched = _items[watchedId];
    final bool watchedWasEpisode = watched?.isEpisode ?? false;
    if (watched != null && watchedWasEpisode) {
      await remove(watchedId);
      debugPrint('[VodDl] smart: épisode vu supprimé ($watchedId)');
    }
    // On n'enchaîne le suivant QUE dans une logique d'épisodes : soit le vu
    // était un épisode téléchargé, soit le suivant est explicitement fourni
    // par le lecteur en fin d'épisode (jamais après un film).
    if (next == null || next.streamUrl.isEmpty) return;
    if (_items[next.id]?.isComplete ?? false) return;
    await enqueue(
      id: next.id,
      name: next.name,
      streamUrl: next.streamUrl,
      posterUrl: next.posterUrl,
      isEpisode: true,
      groupName: next.groupName.isNotEmpty
          ? next.groupName
          : (watched?.groupName ?? ''),
    );
    debugPrint('[VodDl] smart: épisode suivant en file (${next.id})');
  }

  /// Met en pause (coupe la connexion, garde l'octet déjà écrit → reprise).
  Future<void> pause(String id) async {
    final VodDownload? d = _items[id];
    if (d == null) return;
    _clients.remove(id)?.close(force: true);
    if (d.status == VodDownloadStatus.downloading ||
        d.status == VodDownloadStatus.queued) {
      d.status = VodDownloadStatus.paused;
      notifyListeners();
      await _persist();
    }
  }

  Future<void> resume(String id) async {
    final VodDownload? d = _items[id];
    if (d == null || d.isComplete) return;
    d.status = VodDownloadStatus.queued;
    notifyListeners();
    await _persist();
    _pump();
  }

  /// Supprime le téléchargement ET le fichier local (libère la place).
  Future<void> remove(String id) async {
    _clients.remove(id)?.close(force: true);
    final VodDownload? d = _items.remove(id);
    if (d != null) {
      try {
        final File f = File(d.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    notifyListeners();
    await _persist();
  }

  // ---- file sérielle ----------------------------------------------------

  /// Démarre le prochain job en attente — si le robinet est libre ET que le
  /// lecteur ne streame pas. Appelé après chaque événement (enqueue, fin,
  /// erreur, resume, fin de lecture réseau).
  void _pump() {
    if (_activeId != null && _clients.containsKey(_activeId)) return;
    // Pendant une lecture réseau, la file patiente — SAUF les items
    // « pendant la lecture » (le film qu'on regarde, façon YouTube), qui
    // ont le droit à leur propre connexion.
    final Iterable<VodDownload> pool = _playbackHold
        ? _items.values.where((VodDownload d) => _playAlong.contains(d.id))
        : _items.values;
    final VodDownload? nextUp = pickNext(pool);
    if (nextUp == null) {
      _activeId = null;
      return;
    }
    _activeId = nextUp.id;
    unawaited(_run(nextUp.id));
  }

  /// Choix du prochain job : premier `queued` (ordre d'insertion). Pur et
  /// statique → testable sans IO.
  @visibleForTesting
  static VodDownload? pickNext(Iterable<VodDownload> items) {
    for (final VodDownload d in items) {
      if (d.status == VodDownloadStatus.queued) return d;
    }
    return null;
  }

  // ---- garde d'espace disque ---------------------------------------------

  /// Espace libre (octets) du volume portant `path` — via `df -k`, présent
  /// sur Android (toybox), Linux et macOS. null = indisponible (on ne
  /// bloque pas : best-effort, comme tout le service).
  static Future<int?> freeDiskBytes(String path) async {
    try {
      final ProcessResult r = await Process.run('df', <String>['-k', path]);
      if (r.exitCode != 0) return null;
      return parseDfAvailableBytes(r.stdout.toString());
    } catch (_) {
      return null;
    }
  }

  /// Parse la sortie de `df -k` : avant-dernière colonne numérique de la
  /// dernière ligne = Ko disponibles. Pur → testé unitairement.
  @visibleForTesting
  static int? parseDfAvailableBytes(String dfOutput) {
    final List<String> lines = dfOutput
        .trim()
        .split('\n')
        .where((String l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    // Colonnes toybox/GNU : Filesystem 1K-blocks Used Available Use% Mounted
    final List<String> cols = lines.last.trim().split(RegExp(r'\s+'));
    if (cols.length < 4) return null;
    // « Available » est la 4e colonne — mais un nom de FS avec espace peut
    // décaler : on prend la colonne juste avant le pourcentage (xx%).
    for (int i = cols.length - 1; i >= 1; i--) {
      if (cols[i].endsWith('%')) {
        final int? kb = int.tryParse(cols[i - 1]);
        return kb == null ? null : kb * 1024;
      }
    }
    return null;
  }

  /// Espace libre du volume des téléchargements — pour l'affichage
  /// « X libres » dans « Mes téléchargements ». null = indisponible.
  Future<int?> freeSpace() async {
    try {
      final Directory dir = await _dir();
      return freeDiskBytes(dir.path);
    } catch (_) {
      return null;
    }
  }

  /// Cœur : GET avec REPRISE (HTTP Range) → écrit en append. Reconnexion
  /// auto avec back-off. La progression est notifiée de façon throttlée.
  Future<void> _run(String id) async {
    final VodDownload? d = _items[id];
    if (d == null || d.isComplete) return;
    if (_clients.containsKey(id)) return; // déjà en cours

    // GARDE D'ESPACE avant d'ouvrir la connexion.
    final int? free = await freeDiskBytes(p.dirname(d.filePath));
    if (free != null && free < kMinFreeToStart) {
      d.status = VodDownloadStatus.noSpace;
      if (_activeId == id) _activeId = null;
      notifyListeners();
      await _persist();
      return;
    }

    d.status = VodDownloadStatus.downloading;
    notifyListeners();

    final File file = File(d.filePath);
    int already = 0;
    try {
      if (await file.exists()) {
        already = await file.length();
      } else {
        await file.create(recursive: true);
      }
    } catch (_) {
      already = 0;
    }
    d.downloadedBytes = already;

    int attempt = 0;
    const int maxAttempts = 6;
    while (d.status == VodDownloadStatus.downloading && attempt < maxAttempts) {
      final HttpClient client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      _clients[id] = client;
      try {
        final HttpClientRequest req =
            await client.getUrl(Uri.parse(d.streamUrl));
        req.headers.set(HttpHeaders.userAgentHeader, 'VLC/3.0.20 LibVLC/3.0.20');
        // REPRISE : on demande la suite à partir de l'octet déjà écrit.
        if (already > 0) {
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=$already-');
        }
        final HttpClientResponse resp = await req.close();

        // Le serveur ignore la reprise (200 au lieu de 206) → on repart de 0.
        if (already > 0 && resp.statusCode == HttpStatus.ok) {
          already = 0;
          d.downloadedBytes = 0;
          final IOSink truncate = file.openWrite(mode: FileMode.write);
          await truncate.flush();
          await truncate.close();
        }
        if (resp.statusCode != HttpStatus.ok &&
            resp.statusCode != HttpStatus.partialContent) {
          throw HttpException('HTTP ${resp.statusCode}');
        }

        // Taille totale = octets déjà là + ce qui reste à recevoir.
        final int? cl = resp.contentLength > 0 ? resp.contentLength : null;
        if (cl != null) d.totalBytes = already + cl;

        final IOSink sink = file.openWrite(mode: FileMode.append);
        int sinceNotify = 0;
        int sinceSpaceCheck = 0;
        await for (final List<int> chunk in resp) {
          if (d.status != VodDownloadStatus.downloading) break;
          sink.add(chunk);
          d.downloadedBytes += chunk.length;
          sinceNotify += chunk.length;
          sinceSpaceCheck += chunk.length;
          // Throttle : on ne rafraîchit l'UI que ~tous les 512 Ko.
          if (sinceNotify >= 512 * 1024) {
            sinceNotify = 0;
            notifyListeners();
          }
          // GARDE D'ESPACE en cours de route (~tous les 64 Mo) : si le
          // volume frôle la saturation, on suspend PROPREMENT (Range →
          // reprise sans perte quand la place revient).
          if (sinceSpaceCheck >= 64 * 1024 * 1024) {
            sinceSpaceCheck = 0;
            final int? nowFree = await freeDiskBytes(p.dirname(d.filePath));
            if (nowFree != null && nowFree < kMinFreeWhileRunning) {
              d.status = VodDownloadStatus.noSpace;
              break;
            }
          }
        }
        await sink.flush();
        await sink.close();

        if (d.status != VodDownloadStatus.downloading) break; // pausé/annulé

        // Terminé si on a atteint la taille annoncée (ou pas de taille connue
        // mais le flux s'est terminé proprement).
        if (d.totalBytes == 0 || d.downloadedBytes >= d.totalBytes) {
          d.totalBytes = d.downloadedBytes;
          d.status = VodDownloadStatus.done;
          _clients.remove(id)?.close();
          if (_activeId == id) _activeId = null;
          notifyListeners();
          await _persist();
          _pump(); // au suivant de la file
          return;
        }
        // Sinon (coupure au milieu) → on reprendra à la boucle suivante.
        already = d.downloadedBytes;
        attempt++;
      } catch (e) {
        debugPrint('[VodDl] $id attempt $attempt: $e');
        already = d.downloadedBytes;
        attempt++;
        _clients.remove(id)?.close(force: true);
        if (d.status != VodDownloadStatus.downloading) break;
        // Back-off 2,4,6…16 s avant de reprendre (Range → zéro re-téléchargé).
        await Future<void>.delayed(
            Duration(seconds: (attempt * 2).clamp(2, 16)));
        continue;
      }
    }

    _clients.remove(id)?.close(force: true);
    if (_activeId == id) _activeId = null;
    if (d.status == VodDownloadStatus.downloading) {
      // Sorti de la boucle sans finir → erreur (max essais atteint).
      d.status = d.downloadedBytes > 0
          ? VodDownloadStatus.paused
          : VodDownloadStatus.error;
    }
    notifyListeners();
    await _persist();
    _pump(); // la file continue même après un échec
  }

  /// « 1,2 Go » / « 640 Mo » — taille lisible.
  static String fmtBytes(int b) {
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
    }
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).round()} Mo';
    if (b >= 1024) return '${(b / 1024).round()} Ko';
    return '$b o';
  }
}
