// =========================================================
//  catalog_disk.dart — Catalogue films / séries sur la box
// =========================================================
//  Le catalogue Xtream est gros et le serveur coupe souvent. On le
//  range SUR LA BOX pour l'afficher tout de suite, même sans réseau.
//
//  Dossier (rien à voir avec les favoris, l'historique, les profils) :
//
//    <racine>/<signature>/movie|series/
//       live/      ← ce que l'écran a le droit de lire
//       staging/   ← téléchargement en cours (invisible)
//       bak/       ← l'ancien live, le temps du remplacement
//
//  Remplacement ATOMIQUE :
//    1. on écrit tout dans staging ;
//    2. on vérifie que c'est complet et non vide ;
//    3. on renomme live → bak, puis staging → live ;
//    4. si l'app est tuée entre les deux, la lecture suivante remet bak
//       à la place de live.
//
//  Une réponse vide, un fichier illisible, ou un morceau manquant ne
//  touche JAMAIS à live.
//
//  Le fichier ne contient NI mot de passe, NI identifiant, NI URL de
//  lecture (l'URL est reconstruite au moment de lire, depuis le compte
//  déjà enregistré sur la box). Rien de ce dossier n'est envoyé nulle part.
// =========================================================

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/cinema_models.dart';
import 'catalog_cache_policy.dart';

/// En-tête d'un catalogue publié (catégories + date, pas les titres).
class CatalogHeader {
  const CatalogHeader({
    required this.version,
    required this.kind,
    required this.updatedAt,
    required this.complete,
    required this.titleCount,
    required this.categories,
  });

  final int version;
  final CinemaKind kind;
  final DateTime updatedAt;
  final bool complete;
  final int titleCount;
  final List<CatalogCategoryRecord> categories;
}

/// Où en est le téléchargement (staging seulement).
class CatalogProgress {
  const CatalogProgress({
    required this.fingerprint,
    required this.doneKeys,
    required this.categories,
    required this.bytes,
    required this.budgetBlocked,
  });

  final String fingerprint;
  final List<String> doneKeys;
  final List<CatalogCategoryRecord> categories;
  final int bytes;
  final bool budgetBlocked;

  bool get isDone =>
      categories.isNotEmpty && doneKeys.length == categories.length;
}

/// Une catégorie telle qu'on l'écrit sur le disque.
class CatalogCategoryRecord {
  const CatalogCategoryRecord({
    required this.key,
    required this.name,
    required this.parts,
    required this.fileId,
    this.languageKey,
    this.isAdult = false,
    this.isKids = false,
  });

  final String key;
  final String name;
  final String? languageKey;
  final bool isAdult;
  final bool isKids;
  final List<CatalogPartRecord> parts;

  /// Nom du fichier de titres (`titles/<fileId>.json`).
  final String fileId;

  CatalogCategoryRecord copyWith({String? fileId}) => CatalogCategoryRecord(
        key: key,
        name: name,
        parts: parts,
        fileId: fileId ?? this.fileId,
        languageKey: languageKey,
        isAdult: isAdult,
        isKids: isKids,
      );

  CinemaCategory toCinemaCategory() => CinemaCategory(
        key: key,
        name: name,
        parts: <CategoryRef>[
          for (final CatalogPartRecord part in parts)
            CategoryRef(part.sourceKey, part.categoryId),
        ],
        languageKey: languageKey,
        isAdult: isAdult,
        isKids: isKids,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'name': name,
        'lang': languageKey,
        'adult': isAdult,
        'kids': isKids,
        'file': fileId,
        'parts': <Map<String, Object?>>[
          for (final CatalogPartRecord part in parts) part.toJson(),
        ],
      };

  static CatalogCategoryRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String key = _str(raw['key']) ?? '';
    final String name = _str(raw['name']) ?? '';
    if (key.isEmpty || name.isEmpty) return null;
    final List<CatalogPartRecord> parts = <CatalogPartRecord>[];
    final Object? rawParts = raw['parts'];
    if (rawParts is List) {
      for (final Object? item in rawParts) {
        final CatalogPartRecord? part = CatalogPartRecord.fromJson(item);
        if (part != null) parts.add(part);
      }
    }
    return CatalogCategoryRecord(
      key: key,
      name: name,
      languageKey: _str(raw['lang']),
      isAdult: raw['adult'] == true,
      isKids: raw['kids'] == true,
      fileId: _str(raw['file']) ?? '',
      parts: parts,
    );
  }
}

class CatalogPartRecord {
  const CatalogPartRecord(this.sourceKey, this.categoryId);
  final String sourceKey;
  final String categoryId;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': sourceKey,
        'id': categoryId,
      };

  static CatalogPartRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String source = _str(raw['source']) ?? '';
    final String id = _str(raw['id']) ?? '';
    if (source.isEmpty || id.isEmpty) return null;
    return CatalogPartRecord(source, id);
  }
}

/// Un film ou une série, SANS secret et SANS URL de lecture.
class CatalogTitleRecord {
  const CatalogTitleRecord({
    required this.id,
    required this.kind,
    required this.sourceKey,
    required this.remoteId,
    required this.name,
    required this.categoryKey,
    required this.searchKey,
    required this.addedAt,
    required this.containerExt,
    this.posterUrl,
    this.rating,
    this.year,
    this.plot,
  });

  final String id;
  final CinemaKind kind;
  final String sourceKey;
  final String remoteId;
  final String name;
  final String categoryKey;
  final String searchKey;
  final String? posterUrl;
  final double? rating;
  final String? year;
  final int addedAt;
  final String containerExt;
  final String? plot;

  factory CatalogTitleRecord.fromCinemaTitle(CinemaTitle title) {
    String? plot = title.plot;
    if (plot != null && plot.length > kCatalogPlotMax) {
      plot = plot.substring(0, kCatalogPlotMax);
    }
    return CatalogTitleRecord(
      id: title.id,
      kind: title.kind,
      sourceKey: title.sourceKey,
      remoteId: title.remoteId,
      name: title.name,
      categoryKey: title.categoryKey,
      searchKey: title.searchKey,
      posterUrl: title.posterUrl,
      rating: title.rating,
      year: title.year,
      addedAt: title.addedAt,
      containerExt: title.containerExt,
      plot: plot,
    );
  }

  /// Reconstruit l'objet affiché. L'URL de lecture n'existe que si le
  /// compte est encore sur la box : elle n'est pas dans le fichier.
  CinemaTitle toCinemaTitle(CinemaSource? source) {
    final bool movie = kind == CinemaKind.movie;
    return CinemaTitle(
      id: id,
      kind: kind,
      sourceKey: sourceKey,
      remoteId: remoteId,
      name: name,
      categoryKey: categoryKey,
      searchKey: searchKey,
      posterUrl: posterUrl,
      rating: rating,
      year: year,
      addedAt: addedAt,
      containerExt: containerExt,
      streamUrl: movie && source != null
          ? source.movieUrl(remoteId, containerExt)
          : null,
      plot: plot,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        'src': sourceKey,
        'rid': remoteId,
        'name': name,
        'cat': categoryKey,
        'q': searchKey,
        'poster': posterUrl,
        'rating': rating,
        'year': year,
        'added': addedAt,
        'ext': containerExt,
        'plot': plot,
      };

  static CatalogTitleRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String id = _str(raw['id']) ?? '';
    final String name = _str(raw['name']) ?? '';
    final String remoteId = _str(raw['rid']) ?? '';
    if (id.isEmpty || name.isEmpty || remoteId.isEmpty) return null;
    final String kindName = _str(raw['kind']) ?? '';
    final CinemaKind kind = kindName == CinemaKind.series.name
        ? CinemaKind.series
        : CinemaKind.movie;
    final Object? ratingRaw = raw['rating'];
    return CatalogTitleRecord(
      id: id,
      kind: kind,
      sourceKey: _str(raw['src']) ?? '',
      remoteId: remoteId,
      name: name,
      categoryKey: _str(raw['cat']) ?? '',
      searchKey: _str(raw['q']) ?? '',
      posterUrl: _str(raw['poster']),
      rating: ratingRaw is num ? ratingRaw.toDouble() : null,
      year: _str(raw['year']),
      addedAt: raw['added'] is num ? (raw['added'] as num).toInt() : 0,
      containerExt: _str(raw['ext']) ?? 'mp4',
      plot: _str(raw['plot']),
    );
  }
}

/// Nom de dossier stable pour une signature de comptes.
/// Le texte d'origine (serveur, identifiant) n'apparaît PAS dans le chemin.
String catalogFolderName(String signatureMaterial) {
  var hash = 2166136261;
  for (final int unit in signatureMaterial.codeUnits) {
    hash = (hash ^ unit) * 16777619;
    hash &= 0x7fffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Empreinte de la liste de catégories. Si elle change, le staging
/// repart de zéro (l'ancien live, lui, reste).
String catalogFingerprint(List<CatalogCategoryRecord> categories) {
  final List<String> keys = <String>[
    for (final CatalogCategoryRecord category in categories) category.key,
  ]..sort();
  return keys.join('\u0001');
}

class CatalogDisk {
  CatalogDisk(this.root, {int? maxBytes})
      : maxBytes = maxBytes ?? kCatalogMaxBytes;

  final Directory root;
  final int maxBytes;

  /// Lit le catalogue PUBLIÉ. Le staging n'est jamais renvoyé ici.
  /// Un fichier cassé ne remplace pas une sauvegarde encore bonne.
  Future<CatalogHeader?> readHeader(String signature, CinemaKind kind) async {
    if (!_safeSignature(signature)) return null;
    final Directory dir = _kindDir(signature, kind);
    await _recoverInterruptedCommit(dir);
    final CatalogHeader? live = await _readHeaderFile(_liveDir(dir));
    if (live != null) {
      final Directory bak = _bakDir(dir);
      if (await bak.exists()) {
        await bak.delete(recursive: true);
      }
      return live;
    }
    final CatalogHeader? backup = await _readHeaderFile(_bakDir(dir));
    if (backup == null) return null;
    final Directory liveDir = _liveDir(dir);
    if (await liveDir.exists()) {
      await liveDir.delete(recursive: true);
    }
    await _bakDir(dir).rename(liveDir.path);
    return backup;
  }

  /// Titres d'UNE catégorie publiée. `null` si le fichier n'existe pas
  /// ou ne se lit pas (on ne fabrique pas une liste vide à la place).
  Future<List<CatalogTitleRecord>?> readTitles(
    String signature,
    CinemaKind kind,
    String categoryKey,
  ) async {
    final CatalogHeader? header = await readHeader(signature, kind);
    if (header == null) return null;
    CatalogCategoryRecord? category;
    for (final CatalogCategoryRecord item in header.categories) {
      if (item.key == categoryKey) {
        category = item;
        break;
      }
    }
    if (category == null || category.fileId.isEmpty) return null;
    return _readTitleFile(_liveDir(_kindDir(signature, kind)), category.fileId);
  }

  Future<CatalogProgress?> readProgress(
      String signature, CinemaKind kind) async {
    if (!_safeSignature(signature)) return null;
    final File file = File(
        p.join(_stagingDir(_kindDir(signature, kind)).path, 'progress.json'));
    final Object? decoded = await _readJson(file);
    if (decoded is! Map) return null;
    if (decoded['v'] != kCatalogFormatVersion) return null;
    final List<CatalogCategoryRecord> categories =
        _parseCategories(decoded['categories']);
    final List<String> done = <String>[];
    final Object? rawDone = decoded['done'];
    if (rawDone is List) {
      for (final Object? item in rawDone) {
        final String? key = _str(item);
        if (key != null && key.isNotEmpty) done.add(key);
      }
    }
    final Object? bytesRaw = decoded['bytes'];
    return CatalogProgress(
      fingerprint: _str(decoded['fingerprint']) ?? '',
      doneKeys: done,
      categories: categories,
      bytes: bytesRaw is num ? bytesRaw.toInt() : 0,
      budgetBlocked: decoded['budgetBlocked'] == true,
    );
  }

  /// Ouvre (ou reprend) le staging. N'efface JAMAIS `live`.
  /// Si la liste de catégories est la même, les morceaux déjà écrits restent.
  Future<List<CatalogCategoryRecord>> beginStaging(
    String signature,
    CinemaKind kind,
    List<CatalogCategoryRecord> categories,
  ) async {
    _checkSignature(signature);
    final Directory staging = _stagingDir(_kindDir(signature, kind));
    final String fingerprint = catalogFingerprint(categories);
    final CatalogProgress? existing = await readProgress(signature, kind);
    if (existing != null &&
        existing.fingerprint == fingerprint &&
        existing.categories.isNotEmpty &&
        !existing.budgetBlocked) {
      return existing.categories;
    }
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);
    final Set<String> used = <String>{};
    final List<CatalogCategoryRecord> stored = <CatalogCategoryRecord>[];
    for (final CatalogCategoryRecord category in categories) {
      stored.add(category.copyWith(fileId: _fileId(category.key, used)));
    }
    await _writeJson(
      File(p.join(staging.path, 'progress.json')),
      <String, Object?>{
        'v': kCatalogFormatVersion,
        'fingerprint': fingerprint,
        'done': <String>[],
        'bytes': 0,
        'budgetBlocked': false,
        'categories': <Map<String, Object?>>[
          for (final CatalogCategoryRecord category in stored)
            category.toJson(),
        ],
      },
    );
    return stored;
  }

  /// Ajoute un morceau. `false` = plafond de stockage atteint : le morceau
  /// n'est PAS gardé, et le live n'est pas touché.
  Future<bool> addChunk(
    String signature,
    CinemaKind kind,
    String categoryKey,
    List<CatalogTitleRecord> titles,
  ) async {
    final CatalogProgress? progress = await readProgress(signature, kind);
    if (progress == null || progress.budgetBlocked) return false;
    CatalogCategoryRecord? category;
    for (final CatalogCategoryRecord item in progress.categories) {
      if (item.key == categoryKey) {
        category = item;
        break;
      }
    }
    if (category == null || category.fileId.isEmpty) return false;
    final Directory titlesDir = Directory(
        p.join(_stagingDir(_kindDir(signature, kind)).path, 'titles'));
    await titlesDir.create(recursive: true);
    final File dest = File(p.join(titlesDir.path, '${category.fileId}.json'));
    final Map<String, Object?> payload = <String, Object?>{
      'v': kCatalogFormatVersion,
      'key': category.key,
      'ok': true,
      'titles': <Map<String, Object?>>[
        for (final CatalogTitleRecord title in titles) title.toJson(),
      ],
    };
    final String encoded = jsonEncode(payload);
    final int nextBytes = progress.bytes + encoded.length;
    if (nextBytes > maxBytes) {
      await _writeJson(
        File(p.join(
            _stagingDir(_kindDir(signature, kind)).path, 'progress.json')),
        _progressJson(progress, progress.doneKeys, progress.bytes,
            blocked: true),
      );
      return false;
    }
    await _writeAtomic(dest, encoded);
    final List<String> done = <String>[...progress.doneKeys];
    if (!done.contains(categoryKey)) done.add(categoryKey);
    await _writeJson(
      File(
          p.join(_stagingDir(_kindDir(signature, kind)).path, 'progress.json')),
      _progressJson(progress, done, nextBytes, blocked: false),
    );
    return true;
  }

  /// Publie le staging SEULEMENT s'il est complet, lisible et non vide.
  /// Sinon le live reste exactement comme avant.
  Future<bool> commit({
    required String signature,
    required CinemaKind kind,
    required DateTime updatedAt,
  }) async {
    final CatalogProgress? progress = await readProgress(signature, kind);
    if (progress == null || progress.budgetBlocked) return false;
    final Directory kindDir = _kindDir(signature, kind);
    final Directory staging = _stagingDir(kindDir);
    int titleCount = 0;
    int covered = 0;
    for (final CatalogCategoryRecord category in progress.categories) {
      if (!progress.doneKeys.contains(category.key)) continue;
      final List<CatalogTitleRecord>? titles =
          await _readTitleFile(staging, category.fileId);
      if (titles == null) continue;
      covered++;
      titleCount += titles.length;
    }
    final bool publish = shouldPublishCatalog(
      version: kCatalogFormatVersion,
      complete: progress.isDone && covered == progress.categories.length,
      categoryCount: progress.categories.length,
      coveredCategories: covered,
      titleCount: titleCount,
    );
    if (!publish) return false;
    await _writeJson(
      File(p.join(staging.path, 'header.json')),
      <String, Object?>{
        'v': kCatalogFormatVersion,
        'kind': kind.name,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'complete': true,
        'titleCount': titleCount,
        'categories': <Map<String, Object?>>[
          for (final CatalogCategoryRecord category in progress.categories)
            category.toJson(),
        ],
      },
    );
    final Directory live = _liveDir(kindDir);
    final Directory bak = _bakDir(kindDir);
    try {
      if (await bak.exists()) await bak.delete(recursive: true);
      if (await live.exists()) {
        await live.rename(bak.path);
      }
      await staging.rename(live.path);
    } catch (_) {
      if (!await live.exists() && await bak.exists()) {
        await bak.rename(live.path);
      }
      return false;
    }
    if (await bak.exists()) {
      await bak.delete(recursive: true);
    }
    return true;
  }

  /// Jette le téléchargement en cours. Ne touche pas au catalogue publié.
  Future<void> discardStaging(String signature, CinemaKind kind) async {
    final Directory staging = _stagingDir(_kindDir(signature, kind));
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
  }

  /// Garde le dossier du compte courant et au plus [extras] autres
  /// (les plus récents). N'écrit rien en dehors de [root].
  Future<void> pruneSignatures(String keep, {int extras = 1}) async {
    if (!await root.exists()) return;
    final List<Directory> dirs = <Directory>[];
    await for (final FileSystemEntity entity in root.list()) {
      if (entity is Directory) dirs.add(entity);
    }
    dirs.sort((Directory a, Directory b) {
      final DateTime am = a.statSync().modified;
      final DateTime bm = b.statSync().modified;
      return bm.compareTo(am);
    });
    int keptExtras = 0;
    for (final Directory dir in dirs) {
      final String name = p.basename(dir.path);
      if (name == keep) continue;
      if (keptExtras < extras) {
        keptExtras++;
        continue;
      }
      await dir.delete(recursive: true);
    }
  }

  Future<void> _recoverInterruptedCommit(Directory kindDir) async {
    final Directory live = _liveDir(kindDir);
    final Directory bak = _bakDir(kindDir);
    if (!await live.exists() && await bak.exists()) {
      await bak.rename(live.path);
    }
  }

  Future<CatalogHeader?> _readHeaderFile(Directory dir) async {
    final Object? decoded =
        await _readJson(File(p.join(dir.path, 'header.json')));
    if (decoded is! Map) return null;
    final Object? version = decoded['v'];
    if (version != kCatalogFormatVersion) return null;
    final String? when = _str(decoded['updatedAt']);
    final DateTime? updatedAt = when == null ? null : DateTime.tryParse(when);
    if (updatedAt == null) return null;
    if (decoded['complete'] != true) return null;
    final List<CatalogCategoryRecord> categories =
        _parseCategories(decoded['categories']);
    if (categories.isEmpty) return null;
    final Object? countRaw = decoded['titleCount'];
    final int titleCount = countRaw is num ? countRaw.toInt() : 0;
    if (titleCount <= 0) return null;
    final String kindName = _str(decoded['kind']) ?? '';
    return CatalogHeader(
      version: kCatalogFormatVersion,
      kind: kindName == CinemaKind.series.name
          ? CinemaKind.series
          : CinemaKind.movie,
      updatedAt: updatedAt,
      complete: true,
      titleCount: titleCount,
      categories: categories,
    );
  }

  Future<List<CatalogTitleRecord>?> _readTitleFile(
      Directory dir, String fileId) async {
    if (fileId.isEmpty || fileId.contains('/') || fileId.contains('..')) {
      return null;
    }
    final Object? decoded =
        await _readJson(File(p.join(dir.path, 'titles', '$fileId.json')));
    if (decoded is! Map) return null;
    if (decoded['v'] != kCatalogFormatVersion) return null;
    if (decoded['ok'] != true) return null;
    final Object? rawTitles = decoded['titles'];
    if (rawTitles is! List) return null;
    final List<CatalogTitleRecord> out = <CatalogTitleRecord>[];
    for (final Object? item in rawTitles) {
      final CatalogTitleRecord? title = CatalogTitleRecord.fromJson(item);
      if (title != null) out.add(title);
    }
    return out;
  }

  Directory _kindDir(String signature, CinemaKind kind) =>
      Directory(p.join(root.path, signature, kind.name));

  Directory _liveDir(Directory kindDir) =>
      Directory(p.join(kindDir.path, 'live'));
  Directory _stagingDir(Directory kindDir) =>
      Directory(p.join(kindDir.path, 'staging'));
  Directory _bakDir(Directory kindDir) =>
      Directory(p.join(kindDir.path, 'bak'));

  Map<String, Object?> _progressJson(
    CatalogProgress progress,
    List<String> done,
    int bytes, {
    required bool blocked,
  }) {
    return <String, Object?>{
      'v': kCatalogFormatVersion,
      'fingerprint': progress.fingerprint,
      'done': done,
      'bytes': bytes,
      'budgetBlocked': blocked,
      'categories': <Map<String, Object?>>[
        for (final CatalogCategoryRecord category in progress.categories)
          category.toJson(),
      ],
    };
  }

  bool _safeSignature(String signature) =>
      RegExp(r'^[a-f0-9]{8}$').hasMatch(signature);

  void _checkSignature(String signature) {
    if (!_safeSignature(signature)) {
      throw ArgumentError.value(
          signature, 'signature', 'nom de dossier refusé');
    }
  }
}

List<CatalogCategoryRecord> _parseCategories(Object? raw) {
  final List<CatalogCategoryRecord> out = <CatalogCategoryRecord>[];
  if (raw is! List) return out;
  for (final Object? item in raw) {
    final CatalogCategoryRecord? category =
        CatalogCategoryRecord.fromJson(item);
    if (category != null) out.add(category);
  }
  return out;
}

String _fileId(String key, Set<String> used) {
  var hash = 2166136261;
  for (final int unit in key.codeUnits) {
    hash = (hash ^ unit) * 16777619;
    hash &= 0x7fffffff;
  }
  String name = hash.toRadixString(16);
  if (used.contains(name)) {
    name = '$name-${key.length}';
  }
  used.add(name);
  return name;
}

Future<Object?> _readJson(File file) async {
  try {
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  } catch (_) {
    return null;
  }
}

Future<void> _writeJson(File file, Map<String, Object?> json) {
  return _writeAtomic(file, jsonEncode(json));
}

Future<void> _writeAtomic(File file, String contents) async {
  await file.parent.create(recursive: true);
  final File tmp = File('${file.path}.tmp');
  await tmp.writeAsString(contents, flush: true);
  if (await file.exists()) {
    await file.delete();
  }
  await tmp.rename(file.path);
}

String? _str(Object? value) {
  if (value == null) return null;
  final String text = value.toString();
  if (text.isEmpty || text == 'null') return null;
  return text;
}
