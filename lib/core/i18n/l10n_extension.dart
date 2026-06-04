// =========================================================
//  l10n_extension.dart — Accès ergonomique aux traductions
// =========================================================
//  Au lieu d'écrire partout :
//      AppLocalizations.of(context).settingsTitle
//  on écrit simplement :
//      context.l10n.settingsTitle
//
//  POURQUOI ce fichier existe (le vrai bug « changer de langue ne
//  fait rien ») :
//    Les fichiers `app_<code>.arb` étaient bien traduits (FR/EN/ES/
//    SV/DA/NB/AR/SW) et `gen-l10n` générait bien la classe
//    `AppLocalizations`. MAIS AUCUN écran ne l'utilisait : tout le
//    texte était écrit en dur en français (`Text('Réglages')`…).
//    Résultat : choisir « Svenska » changeait bien `MaterialApp.locale`
//    mais aucun libellé ne bougeait. On branche donc l'UI sur
//    `AppLocalizations` via ce raccourci.
//
//  `AppLocalizations.of(context)` ne renvoie JAMAIS null ici, parce
//  que `l10n.yaml` est configuré avec `nullable-getter: false`.
// =========================================================

import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

/// Extension sur `BuildContext` pour récupérer les traductions
/// de l'écran courant en une seule expression : `context.l10n`.
extension AppLocalizationsX on BuildContext {
  /// Les chaînes traduites correspondant à la langue active
  /// (choisie par l'utilisateur dans Réglages, ou langue de l'OS).
  AppLocalizations get l10n => AppLocalizations.of(this);
}
