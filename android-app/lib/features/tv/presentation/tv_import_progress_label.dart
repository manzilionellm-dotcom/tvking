// =========================================================
//  tv_import_progress_label.dart — Met en mots la progression d'un import
// =========================================================
//  La couche données (ImportProgressBus) publie des FAITS (étape + chiffres) ;
//  ici on les transforme en phrase dans la langue de l'utilisateur, via les
//  clés `tvImp*` des fichiers .arb. Utilisé par les écrans « Ajouter ma liste »
//  (Xtream) et « Ajouter une liste M3U » pour le libellé du bouton.
// =========================================================
import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/import_progress.dart';

/// Libellé traduit pour l'étape [p] (nombres avec séparateur de milliers).
String importProgressLabel(BuildContext context, ImportProgress p) {
  final String Function(int) n = ImportProgressBus.n;
  switch (p.stage) {
    case ImportStage.connecting:
      return context.l10n.tvImpConnecting;
    case ImportStage.categories:
      return context.l10n.tvImpCategories;
    case ImportStage.downloading:
      return context.l10n.tvImpDownloading(p.mb);
    case ImportStage.decoding:
      return context.l10n.tvImpDecoding(p.mb);
    case ImportStage.category:
      return context.l10n.tvImpCategory(
          p.index.toString(), p.total.toString(), n(p.count));
    case ImportStage.found:
      return context.l10n.tvImpFound(n(p.count));
    case ImportStage.saving:
      return context.l10n.tvImpSaving(n(p.index), n(p.total));
    case ImportStage.done:
      return context.l10n.tvImpDone(n(p.count));
  }
}
