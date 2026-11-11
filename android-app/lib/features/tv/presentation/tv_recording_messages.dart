// =========================================================
//  tv_recording_messages.dart — Textes du résultat d'export galerie
// =========================================================
//  Un seul endroit traduit le résultat natif de la copie vers la galerie
//  (succès ou code d'erreur) en phrase lisible. Il est partagé par :
//    - la liste « Mes enregistrements » (bouton « Enregistrer dans la
//      galerie (MP4) ») ;
//    - le lecteur, qui sauvegarde AUTOMATIQUEMENT chaque REC terminé.
//  Ainsi les deux écrans disent toujours exactement la même chose.
// =========================================================
import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../recordings/data/gallery_exporter.dart';

/// Phrase à afficher pour le résultat [result] d'un export vers la galerie.
String tvGalleryExportMessage(BuildContext context, GalleryExportResult result) {
  if (result.success) return context.l10n.tvRecordingExportSuccess;
  switch (result.errorCode) {
    case 'SRC_MISSING':
      return context.l10n.tvRecordingNotFoundBody;
    case 'SRC_EMPTY':
      return context.l10n.tvRecordingEmpty;
    case 'PERMISSION_DENIED':
      return context.l10n.tvRecordingExportPermission;
    case 'UNSUPPORTED_CODEC':
    case 'CONVERSION_FAILED':
      return context.l10n.tvRecordingExportFormat;
    case 'EXPORT_IN_PROGRESS':
      return context.l10n.tvRecordingExportInProgress;
    default:
      return context.l10n.tvRecordingExportFailed;
  }
}
