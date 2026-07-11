// =========================================================
//  aspect_mode_label.dart — Libellés LOCALISÉS des modes d'affichage
// =========================================================
//  L'enum `AspectRatioMode` (data/player_settings.dart) reste PUR :
//  son champ `label` en dur ne sert plus que de repli technique.
//  L'affichage utilisateur passe par cette extension presentation,
//  qui mappe chaque mode vers sa clé AppLocalizations — ainsi les
//  chips « Contenir / Remplir / Étirer » suivent la langue du
//  téléphone. Les ratios « 16:9 » et « 4:3 » sont des libellés
//  techniques universels : on les garde tels quels.
// =========================================================

import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../data/player_settings.dart';

/// Libellé traduit d'un [AspectRatioMode], pour chips et boutons.
extension AspectRatioModeLabel on AspectRatioMode {
  String localizedLabel(BuildContext context) {
    switch (this) {
      case AspectRatioMode.fit:
        return context.l10n.aspectFit;
      case AspectRatioMode.fill:
        return context.l10n.aspectFill;
      case AspectRatioMode.stretch:
        return context.l10n.aspectStretch;
      case AspectRatioMode.ratio169:
        return '16:9'; // technique, identique dans toutes les langues
      case AspectRatioMode.ratio43:
        return '4:3'; // technique, identique dans toutes les langues
      case AspectRatioMode.ratio219:
        return context.l10n.aspectCinemaScope;
    }
  }
}
