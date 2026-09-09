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
import 'locale_resolver.dart';

/// Traductions de la langue active, utilisable hors widget.
///
/// CORRIGÉ le 09/09/2026 : ce chemin appliquait SA PROPRE règle — il ne
/// regardait que la première langue du système et repliait sur le
/// FRANÇAIS, quand l'écran, lui, repliait sur l'ANGLAIS. Une même app
/// pouvait donc afficher ses menus en anglais et ses notifications en
/// français. Il passe maintenant par `resolveAppLocale`, comme l'écran,
/// et hérite du même coup du correctif Windows.
AppLocalizations get l10nNow {
  final Locale choisie = resolveAppLocale(
    forced: LocaleRepository.instance.locale,
    // `locales` (au pluriel) et non `locale` : la liste ENTIÈRE des
    // préférences, comme ce que MaterialApp reçoit. L'ancienne version
    // ne lisait que la première — le même défaut que l'écran TV/PC.
    preferred: PlatformDispatcher.instance.locales,
    supported: AppLocalizations.supportedLocales,
  );
  return lookupAppLocalizations(choisie);
}
