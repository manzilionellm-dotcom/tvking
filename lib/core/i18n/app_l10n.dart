// =========================================================
//  app_l10n.dart — Traductions HORS BuildContext (couche data)
// =========================================================
//  Certains textes visibles par l'utilisateur naissent loin de
//  l'arbre de widgets : statuts de cast (CastManager), erreurs de
//  chargement de playlist, notifications… Là-bas il n'y a pas de
//  `context`, donc pas de `context.l10n`.
//
//  Ce helper résout la langue ACTIVE avec exactement la même
//  logique que `TvApp.localeResolutionCallback` :
//    1) choix explicite de l'utilisateur (LocaleRepository) ;
//    2) langue de l'OS/TV si on la supporte (match par code) ;
//    3) repli sûr = anglais.
//  puis charge les chaînes via `lookupAppLocalizations` (généré).
//
//  RÈGLE : dans un widget, préférer TOUJOURS `context.l10n`
//  (rebuild automatique au changement de langue). `AppL10n.current`
//  est réservé aux couches sans context ; les messages qu'il
//  produit sont des instantanés (recalculés à chaque émission).
// =========================================================

import 'dart:ui' show Locale, PlatformDispatcher;

import '../../l10n/generated/app_localizations.dart';
import 'locale_repository.dart';

class AppL10n {
  AppL10n._();

  /// Les chaînes traduites dans la langue active, sans BuildContext.
  static AppLocalizations get current => lookupAppLocalizations(_resolve());

  static Locale _resolve() {
    final Locale? forced = LocaleRepository.instance.locale;
    if (forced != null && _isSupported(forced)) return Locale(forced.languageCode);
    for (final Locale device in PlatformDispatcher.instance.locales) {
      if (_isSupported(device)) return Locale(device.languageCode);
    }
    return const Locale('en');
  }

  static bool _isSupported(Locale locale) => AppLocalizations.supportedLocales
      .any((Locale s) => s.languageCode == locale.languageCode);
}
