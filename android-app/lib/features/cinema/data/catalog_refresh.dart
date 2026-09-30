// =========================================================
//  catalog_refresh.dart — Téléchargement du catalogue, en douceur
// =========================================================
//  Un passage :
//    1. catégories (petit fichier) ;
//    2. une catégorie de titres à la fois ;
//    3. pause entre les morceaux (débit) ;
//    4. si la lecture vidéo est en cours, on ATTEND ;
//    5. si un morceau échoue : nouvel essai, délai qui double, avec jitter ;
//    6. si l'app s'arrête, le staging reste : le prochain passage reprend
//       les catégories déjà écrites ;
//    7. on ne publie le résultat qu'une fois TOUT validé.
//
//  Le réseau est injecté (fonctions [fetchCategories] / [fetchTitles]) :
//  les tests n'ouvrent aucune socket. `null` dans le résultat = échec.
//  Une liste vide = le serveur a vraiment répondu « rien ».
// =========================================================

import '../domain/cinema_models.dart';
import 'catalog_cache_policy.dart';
import 'catalog_disk.dart';

/// Résultat d'un appel serveur. [failed] = pas de réponse utilisable.
class CatalogFetchResult<T> {
  const CatalogFetchResult.ok(this.value) : failed = false;
  const CatalogFetchResult.fail()
      : value = null,
        failed = true;

  final T? value;
  final bool failed;
}

enum CatalogRefreshStatus {
  /// Le nouveau catalogue est complet et a remplacé l'ancien.
  published,

  /// L'ancien catalogue (s'il existe) est resté en place.
  keptPrevious,
}

class CatalogRefreshResult {
  const CatalogRefreshResult(this.status, {this.publishedTitles = 0});
  final CatalogRefreshStatus status;
  final int publishedTitles;
}

class CatalogRefresher {
  const CatalogRefresher({
    this.gap = kCatalogChunkGap,
    this.busyPoll = const Duration(seconds: 5),
    this.maxAttempts = 5,
  });

  /// Pause entre deux catégories téléchargées.
  final Duration gap;

  /// Pause tant qu'une lecture exigeante est ouverte.
  final Duration busyPoll;

  /// Essais d'un même morceau avant d'abandonner CE passage.
  /// Les morceaux déjà écrits restent dans le staging.
  final int maxAttempts;

  Future<CatalogRefreshResult> run({
    required CatalogDisk disk,
    required String signature,
    required CinemaKind kind,
    required Future<CatalogFetchResult<List<CatalogCategoryRecord>>> Function()
        fetchCategories,
    required Future<CatalogFetchResult<List<CatalogTitleRecord>>> Function(
            CatalogCategoryRecord category)
        fetchTitles,
    required bool Function() playbackBusy,
    required Future<void> Function(Duration delay) sleep,
    required int Function() jitterPermille,
    DateTime Function()? clock,
    bool Function()? cancelled,
  }) async {
    bool stop() => cancelled?.call() ?? false;
    final DateTime Function() now = clock ?? DateTime.now;

    if (stop()) {
      return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
    }

    final CatalogProgress? existing = await disk.readProgress(signature, kind);
    if (existing != null && existing.budgetBlocked) {
      return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
    }

    List<CatalogCategoryRecord> categories;
    if (existing != null &&
        existing.categories.isNotEmpty &&
        existing.fingerprint.isNotEmpty) {
      categories = existing.categories;
    } else {
      final CatalogFetchResult<List<CatalogCategoryRecord>> fetched =
          await _fetchCategoriesWithRetry(
        fetchCategories: fetchCategories,
        playbackBusy: playbackBusy,
        sleep: sleep,
        jitterPermille: jitterPermille,
        stop: stop,
      );
      if (stop()) {
        return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
      }
      if (fetched.failed || fetched.value == null || fetched.value!.isEmpty) {
        // Vide ou erreur : on ne commence même pas un staging, et on
        // n'efface pas le catalogue déjà publié.
        return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
      }
      categories = await disk.beginStaging(signature, kind, fetched.value!);
    }

    // Relecture : beginStaging a pu créer un progrès tout neuf.
    final CatalogProgress? progress = await disk.readProgress(signature, kind);
    final Set<String> done = <String>{};
    if (progress != null) done.addAll(progress.doneKeys);

    int fetchedChunks = 0;
    for (int i = 0; i < categories.length; i++) {
      final CatalogCategoryRecord category = categories[i];
      if (done.contains(category.key)) continue;
      if (stop()) {
        return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
      }
      if (!await _waitUntilCalm(
        playbackBusy: playbackBusy,
        sleep: sleep,
        stop: stop,
      )) {
        return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
      }

      List<CatalogTitleRecord>? titles;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        final CatalogFetchResult<List<CatalogTitleRecord>> chunk =
            await fetchTitles(category);
        if (!chunk.failed && chunk.value != null) {
          titles = chunk.value;
          break;
        }
        if (attempt >= maxAttempts || stop()) break;
        await sleep(catalogBackoff(
          attempt: attempt,
          jitterPermille: jitterPermille(),
        ));
        if (!await _waitUntilCalm(
          playbackBusy: playbackBusy,
          sleep: sleep,
          stop: stop,
        )) {
          return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
        }
      }
      if (titles == null) {
        // Ce morceau n'est pas fiable. On garde le staging (reprise) et
        // surtout le catalogue déjà publié.
        return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
      }
      final bool wrote =
          await disk.addChunk(signature, kind, category.key, titles);
      if (!wrote) {
        return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
      }
      done.add(category.key);
      fetchedChunks++;
      final bool more = categories.any(
        (CatalogCategoryRecord item) => !done.contains(item.key),
      );
      if (more && fetchedChunks > 0 && gap > Duration.zero) {
        await sleep(gap);
      }
    }

    final bool published = await disk.commit(
      signature: signature,
      kind: kind,
      updatedAt: now(),
    );
    if (!published) {
      // Staging COMPLET mais refusé (réponse vide, fichier illisible) :
      // on le jette pour ne pas rejouer indéfiniment un échec déjà connu.
      // Un staging PARTIEL (coupure) n'arrive pas ici : on est sorti plus haut.
      // Le catalogue publié, lui, n'est pas effacé.
      final CatalogProgress? after = await disk.readProgress(signature, kind);
      if (after != null && after.isDone) {
        await disk.discardStaging(signature, kind);
      }
      return const CatalogRefreshResult(CatalogRefreshStatus.keptPrevious);
    }
    final CatalogHeader? header = await disk.readHeader(signature, kind);
    return CatalogRefreshResult(
      CatalogRefreshStatus.published,
      publishedTitles: header?.titleCount ?? 0,
    );
  }

  Future<CatalogFetchResult<List<CatalogCategoryRecord>>>
      _fetchCategoriesWithRetry({
    required Future<CatalogFetchResult<List<CatalogCategoryRecord>>> Function()
        fetchCategories,
    required bool Function() playbackBusy,
    required Future<void> Function(Duration delay) sleep,
    required int Function() jitterPermille,
    required bool Function() stop,
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!await _waitUntilCalm(
        playbackBusy: playbackBusy,
        sleep: sleep,
        stop: stop,
      )) {
        return const CatalogFetchResult<List<CatalogCategoryRecord>>.fail();
      }
      final CatalogFetchResult<List<CatalogCategoryRecord>> fetched =
          await fetchCategories();
      if (!fetched.failed) return fetched;
      if (attempt >= maxAttempts || stop()) break;
      await sleep(catalogBackoff(
        attempt: attempt,
        jitterPermille: jitterPermille(),
      ));
    }
    return const CatalogFetchResult<List<CatalogCategoryRecord>>.fail();
  }

  Future<bool> _waitUntilCalm({
    required bool Function() playbackBusy,
    required Future<void> Function(Duration delay) sleep,
    required bool Function() stop,
  }) async {
    while (playbackBusy()) {
      if (stop()) return false;
      await sleep(busyPoll);
      if (stop()) return false;
    }
    return !stop();
  }
}
