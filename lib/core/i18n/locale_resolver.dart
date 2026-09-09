// =========================================================
//  locale_resolver.dart — LA règle de langue, une seule fois
// =========================================================
//  Signalé par le propriétaire (09/09/2026) : « l'app Windows ne
//  traduit pas les langues automatiquement ». Diagnostic ci-dessous,
//  parce qu'il explique pourquoi ce fichier existe.
//
//  ---------------------------------------------------------
//  CE QUI CLOCHAIT
//  ---------------------------------------------------------
//  Un système ne déclare pas UNE langue, il en déclare une LISTE, par
//  ordre de préférence. `TvApp` — qui sert la box ET le PC — utilisait
//  `localeResolutionCallback`, qui ne reçoit que la PREMIÈRE de cette
//  liste. Tout le reste était jeté.
//
//  Sur une box Android il n'y en a qu'une : le défaut ne se voyait pas.
//  Un PC en déclare plusieurs. Si la première n'était pas traduite, on
//  repliait sur l'anglais SANS REGARDER les suivantes — alors que la
//  langue de l'utilisateur pouvait être juste en dessous.
//
//  Le téléphone, lui, n'a jamais eu ce défaut : il ne posait aucun
//  rappel, donc Flutter parcourait la liste entière tout seul.
//
//  La correction tient en une phrase : PARCOURIR TOUTE LA LISTE au
//  lieu de ne regarder que le premier élément.
//
//  ---------------------------------------------------------
//  POURQUOI C'EST UN FICHIER À PART
//  ---------------------------------------------------------
//  La même question se posait à TROIS endroits, et ils ne répondaient
//  PAS pareil :
//    - `tv_app.dart`   (TV + Windows) : repli ANGLAIS
//    - `main.dart`     (téléphone)    : repli FRANÇAIS (défaut Flutter)
//    - `l10n_now.dart` (hors widgets) : repli FRANÇAIS
//  Une même app pouvait donc afficher son écran en anglais et ses
//  notifications en français. Une seule implémentation, autant
//  d'appelants qu'on veut — même raison que `cloudflare/app_versions.js`
//  ou `ci/build_label.sh`.
//
//  Fonction PURE (aucun Flutter, aucun système) : c'est ce qui la rend
//  testable, et donc prouvable.
// =========================================================

import 'dart:ui' show Locale;

/// Langue de repli quand RIEN ne correspond.
///
/// Anglais, et pas la première de la liste supportée. La raison est
/// écrite dans l'historique du projet : la liste générée commence par
/// l'arabe selon l'ordre alphabétique, et un repli naïf affichait
/// « tout le monde en arabe ». L'anglais est le choix sûr : c'est la
/// langue que le plus de gens déchiffrent à défaut de la leur.
const Locale kFallbackLocale = Locale('en');

/// Choisit la langue à afficher.
///
/// [forced]    : le choix explicite fait dans Réglages (`null` = « Système »).
/// [preferred] : les langues du système, DANS L'ORDRE de préférence.
/// [supported] : les langues pour lesquelles on a des traductions.
///
/// L'ordre des règles compte :
///   1. le choix de l'humain gagne toujours ;
///   2. sinon on prend la première langue système qu'on sait parler,
///      en privilégiant une correspondance EXACTE (langue + pays) avant
///      de se rabattre sur la langue seule ;
///   3. sinon anglais.
Locale resolveAppLocale({
  required Locale? forced,
  required List<Locale> preferred,
  required List<Locale> supported,
}) {
  if (supported.isEmpty) return kFallbackLocale;

  // 1) Choix explicite. On le valide quand même : une préférence
  //    enregistrée par une ancienne version peut désigner une langue
  //    qu'on ne livre plus.
  if (forced != null) {
    final Locale? exact = _findExact(forced, supported);
    if (exact != null) return exact;
    final Locale? parLangue = _findByLanguage(forced, supported);
    if (parLangue != null) return parLangue;
  }

  // 2) TOUTE la liste système, dans l'ordre. C'est ici que se joue le
  //    correctif Windows : s'arrêter au premier élément revenait à
  //    lire le clavier au lieu de la langue d'affichage.
  //
  //    Deux passes, et pas une seule : on veut que « pt-BR » choisisse
  //    le portugais du Brésil s'il existe, plutôt que le portugais tout
  //    court croisé plus tôt dans la liste.
  for (final Locale p in preferred) {
    final Locale? exact = _findExact(p, supported);
    if (exact != null) return exact;
  }
  for (final Locale p in preferred) {
    final Locale? parLangue = _findByLanguage(p, supported);
    if (parLangue != null) return parLangue;
  }

  // 3) Repli sûr.
  final Locale? anglais = _findByLanguage(kFallbackLocale, supported);
  return anglais ?? supported.first;
}

/// Correspondance stricte : même langue ET même pays.
Locale? _findExact(Locale wanted, List<Locale> supported) {
  for (final Locale s in supported) {
    if (s.languageCode == wanted.languageCode &&
        s.countryCode == wanted.countryCode) {
      return s;
    }
  }
  return null;
}

/// Correspondance par langue seule : « fr-CA » accepte « fr ».
/// C'est le cas courant — on ne livre que des langues sans pays.
Locale? _findByLanguage(Locale wanted, List<Locale> supported) {
  for (final Locale s in supported) {
    if (s.languageCode == wanted.languageCode) return s;
  }
  return null;
}
