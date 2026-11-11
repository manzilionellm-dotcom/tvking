// =========================================================
//  recording_gallery_auto_save.dart — Sauvegarde AUTO dans la galerie
// =========================================================
//  Pourquoi ce fichier ?
//  ---------------------
//  Un enregistrement (REC) est d'abord écrit en `.ts` dans le stockage
//  PRIVÉ de l'app : invisible dans la Galerie du téléphone. Avant, il
//  fallait aller dans Réglages → Enregistrements et appuyer sur
//  « Enregistrer dans la galerie (MP4) ». Beaucoup d'utilisateurs ne
//  trouvaient donc jamais leur vidéo « sur le téléphone ».
//
//  Désormais, dès qu'un REC se termine avec de vraies données, le lecteur
//  appelle [RecordingGalleryAutoSave.save] : la vidéo est copiée en MP4
//  dans `Movies/NOVATUBE/` (Galerie, Fichiers, WhatsApp…), sans action
//  de l'utilisateur. Le `.ts` d'origine reste dans l'app (lecture interne,
//  nouvel essai manuel possible si la copie échoue).
//
//  Règles importantes
//  ------------------
//  1. UNE copie à la fois : le natif refuse un 2e export simultané
//     (`EXPORT_IN_PROGRESS`). Les sauvegardes automatiques passent donc
//     dans une FILE d'attente, et si un export manuel occupe déjà le natif,
//     on attend qu'il finisse puis on réessaie (nombre d'essais borné).
//  2. Jamais de doublon : un fichier déjà copié avec succès n'est pas
//     recopié (voir [GalleryExporter.wasExported]), et deux demandes pour le
//     même fichier partagent la même opération native.
//  3. Jamais d'exception vers l'appelant : le lecteur reçoit toujours un
//     [GalleryExportResult] qu'il peut afficher.
//  4. Le REC est déjà interdit dans l'espace +18 (le lecteur ne démarre
//     pas d'enregistrement sur une chaîne adulte) : rien d'adulte n'arrive
//     donc dans la galerie publique.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gallery_exporter.dart';

/// Fonction qui lance réellement la copie. En production c'est
/// [GalleryExporter.exportVideo] ; les tests peuvent la remplacer.
typedef GalleryExportFn = Future<GalleryExportResult> Function({
  required String srcPath,
  required String displayName,
});

class RecordingGalleryAutoSave {
  RecordingGalleryAutoSave._({
    GalleryExportFn? export,
    Duration busyRetryDelay = const Duration(seconds: 2),
    int maxBusyRetries = 5,
  })  : _export = export ?? GalleryExporter.exportVideo,
        _busyRetryDelay = busyRetryDelay,
        _maxBusyRetries = maxBusyRetries;

  /// Instance unique utilisée par l'app.
  static final RecordingGalleryAutoSave instance = RecordingGalleryAutoSave._();

  /// Instance isolée pour les tests (délais courts, export simulé).
  @visibleForTesting
  factory RecordingGalleryAutoSave.forTesting({
    GalleryExportFn? export,
    Duration busyRetryDelay = const Duration(milliseconds: 10),
    int maxBusyRetries = 5,
  }) =>
      RecordingGalleryAutoSave._(
        export: export,
        busyRetryDelay: busyRetryDelay,
        maxBusyRetries: maxBusyRetries,
      );

  final GalleryExportFn _export;

  /// Pause avant de réessayer quand le natif est occupé par un autre export.
  final Duration _busyRetryDelay;

  /// Nombre maximal de nouveaux essais sur `EXPORT_IN_PROGRESS`. Borné pour
  /// ne jamais boucler sans fin si le natif reste bloqué.
  final int _maxBusyRetries;

  /// Fin de la dernière sauvegarde mise en file. Chaque nouvelle demande
  /// s'enchaîne après elle : jamais deux copies automatiques en parallèle.
  Future<void> _queue = Future<void>.value();

  /// Copie [filePath] dans la galerie du téléphone (MP4) et renvoie le
  /// résultat. Ne lève jamais d'exception.
  Future<GalleryExportResult> save(String filePath) {
    final Completer<GalleryExportResult> done =
        Completer<GalleryExportResult>();
    _queue = _queue.then((_) async {
      GalleryExportResult result;
      try {
        result = await _saveNow(filePath);
      } catch (error) {
        if (kDebugMode) debugPrint('[AutoSave] échec inattendu : $error');
        result = const GalleryExportResult(
          success: false,
          errorCode: 'EXPORT_FAILED',
        );
      }
      done.complete(result);
    });
    return done.future;
  }

  Future<GalleryExportResult> _saveNow(String filePath) async {
    // Déjà dans la galerie (export manuel terminé entre-temps) : pas de
    // second MP4 identique.
    if (GalleryExporter.wasExported(filePath)) {
      return const GalleryExportResult(success: true);
    }
    for (int retry = 0;; retry++) {
      final GalleryExportResult result = await _export(
        srcPath: filePath,
        displayName: GalleryExporter.displayNameFor(filePath),
      );
      if (result.errorCode != 'EXPORT_IN_PROGRESS' ||
          retry >= _maxBusyRetries) {
        return result;
      }
      // Un export MANUEL d'un autre fichier occupe le natif : on attend
      // sa fin, puis une courte pause, et on retente.
      await GalleryExporter.whenIdle();
      await Future<void>.delayed(_busyRetryDelay);
      if (GalleryExporter.wasExported(filePath)) {
        return const GalleryExportResult(success: true);
      }
    }
  }
}
