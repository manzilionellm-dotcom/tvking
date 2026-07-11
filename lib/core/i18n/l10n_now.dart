// =========================================================
//  l10n_now.dart — Traductions SANS BuildContext
// =========================================================
//  `context.l10n` (cf. l10n_extension.dart) couvre les widgets.
//  Mais une partie des textes visibles par l'utilisateur naît
//  HORS de l'arbre de widgets :
//    - messages de progression / d'erreur du CastManager,
//    - corps et titres de notifications Android,
//    - libellés produits par des services (sports, curation…).
//
//  Pour ces cas, `l10nNow` retourne l'objet AppLocalizations de
//  la langue ACTIVE, résolue exactement comme MaterialApp le
//  fait :
//    1. langue forcée dans Réglages (LocaleRepository.locale),
//    2. sinon langue du téléphone (PlatformDispatcher),
//    3. si non supportée → français (langue par défaut de l'app,
//       première de `supportedLocales`).
//
//  ATTENTION : contrairement à `context.l10n`, une chaîne prise
//  via `l10nNow` n'est PAS re-rendue quand la langue change —
//  n'utiliser que pour des textes éphémères (toasts, progression,
//  notifications) recalculés à chaque émission.
// =========================================================

import 'dart:ui' show Locale, PlatformDispatcher;

import '../../l10n/generated/app_localizations.dart';
import 'locale_repository.dart';

/// Traductions de la langue active, utilisable hors widget.
AppLocalizations get l10nNow {
  final Locale wanted =
      LocaleRepository.instance.locale ?? PlatformDispatcher.instance.locale;
  final bool supported = AppLocalizations.supportedLocales
      .any((Locale l) => l.languageCode == wanted.languageCode);
  return lookupAppLocalizations(
      supported ? Locale(wanted.languageCode) : const Locale('fr'));
}
