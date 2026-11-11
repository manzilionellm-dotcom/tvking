// =========================================================
//  gallery_exporter.dart — Export d'enregistrements vers Galerie
// =========================================================
//  Wrapper Dart au-dessus du MethodChannel
//  `com.manzilionellm.tvking/gallery` (impl Kotlin dans
//  android_overlay/google_cast/GalleryExporter.kt).
//
//  Le `RecordingRepository` actuel sauvegarde les .ts dans
//  `/storage/emulated/0/Android/data/<package>/files/Recordings`
//  (storage privé app), qui :
//    - Est INVISIBLE dans la Galerie photo du téléphone
//    - Est PERDU à la désinstallation de l'app
//
//  Cette classe copie l'enregistrement vers `Movies/` via MediaStore —
//  accessible à toutes les apps (Galerie, YouTube, WhatsApp upload, etc.)
//  et survit à la désinstallation.
//
//  Le natif produit un MP4 H.264/AAC : copie des pistes sans ré-encodage
//  lorsqu'elles sont compatibles, conversion sinon. Un TS simplement
//  renommé ou une conversion incomplète ne vaut jamais succès d'export.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class GalleryExporter {
  GalleryExporter._();

  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/gallery');
  static final Map<String, Future<GalleryExportResult>> _inFlight =
      <String, Future<GalleryExportResult>>{};

  /// Fichiers déjà copiés AVEC SUCCÈS dans la galerie depuis le lancement de
  /// l'app. Sert à la sauvegarde automatique : elle ne recrée jamais un
  /// second MP4 identique si l'utilisateur a déjà exporté ce fichier.
  static final Set<String> _exported = <String>{};

  /// `true` si ce fichier a déjà été copié dans la galerie (ce lancement).
  static bool wasExported(String srcPath) => _exported.contains(srcPath);

  /// Nom du MP4 dans la galerie : même nom que l'enregistrement, extension
  /// `.mp4` (le natif range le fichier dans `Movies/NOVATUBE/`).
  static String displayNameFor(String srcPath) =>
      '${p.basenameWithoutExtension(srcPath)}.mp4';

  /// Se termine quand AUCUN export n'est plus en cours. Le natif n'accepte
  /// qu'un export à la fois (`EXPORT_IN_PROGRESS` sinon) : la sauvegarde
  /// automatique attend ici son tour au lieu d'échouer.
  static Future<void> whenIdle() async {
    final List<Future<GalleryExportResult>> running =
        _inFlight.values.toList();
    if (running.isEmpty) return;
    try {
      await Future.wait<GalleryExportResult>(running);
    } catch (_) {
      // Un export qui échoue libère aussi la place : rien à faire de plus.
    }
  }

  /// Remet l'état partagé à zéro entre deux tests. Pas d'usage en production.
  @visibleForTesting
  static void resetForTesting() {
    _inFlight.clear();
    _exported.clear();
  }

  /// Une vue rouverte peut reprendre l'attente, sans relancer le natif.
  static Future<GalleryExportResult>? pendingExportFor(String srcPath) =>
      _inFlight[srcPath];

  /// Résultat de l'export. Contient un flag de succès et, en cas
  /// d'échec, le code + message d'erreur côté natif pour qu'on puisse
  /// l'afficher dans le snackbar (au lieu d'un "indisponible" vague).
  static Future<GalleryExportResult> exportVideo({
    required String srcPath,
    required String displayName,
  }) {
    // Un retour vers la liste pendant une conversion native ne doit pas
    // lancer une seconde copie du même fichier. Les deux vues attendent
    // le résultat de la même opération jusqu'à sa fin effective.
    return _inFlight.putIfAbsent(srcPath, () {
      return _exportVideo(srcPath: srcPath, displayName: displayName)
          .then((GalleryExportResult result) {
        if (result.success) _exported.add(srcPath);
        return result;
      }).whenComplete(() {
        _inFlight.remove(srcPath);
      });
    });
  }

  static Future<GalleryExportResult> _exportVideo({
    required String srcPath,
    required String displayName,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'exportVideo',
        <String, dynamic>{
          'srcPath': srcPath,
          'displayName': displayName,
        },
      );
      return GalleryExportResult(success: result ?? false);
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[Gallery] export ${e.code}: ${e.message}');
      }
      return GalleryExportResult(
        success: false,
        errorCode: e.code,
        errorMessage: e.message,
      );
    } on MissingPluginException {
      // Channel pas câblé (ex. iOS, ou build sans overlay)
      if (kDebugMode) debugPrint('[Gallery] channel manquant');
      return const GalleryExportResult(
        success: false,
        errorCode: 'NO_CHANNEL',
        errorMessage: 'Bridge natif manquant',
      );
    }
  }
}

class GalleryExportResult {
  const GalleryExportResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
  });

  final bool success;
  final String? errorCode;
  final String? errorMessage;

  /// Texte court pour le snackbar quand on échoue.
  String get userFacingError {
    if (success) return '';
    final String code = errorCode ?? 'UNKNOWN';
    final String msg = errorMessage ?? '';
    return msg.isEmpty ? code : '$code · $msg';
  }
}
