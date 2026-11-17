// =========================================================
//  novatube_tv_edition.dart — Interrupteur de l'édition NovaTube TV
// =========================================================
//  NovaTube TV n'est PAS une nouvelle application écrite à côté : c'est
//  l'application TV existante (lecteur, listes M3U/Xtream, activation par
//  code MK, boîte noire…) compilée avec UNE constante en plus :
//
//      flutter build apk --target=lib/main_tv.dart \
//        --dart-define=NOVATUBE_TV=true
//
//  Pourquoi une constante de COMPILATION (`bool.fromEnvironment`) et pas
//  un réglage lu au démarrage ?
//    • Elle est connue du compilateur : quand elle vaut `false` (build
//      Zuno habituel), toutes les branches NovaTube sont supprimées du code
//      machine. Zuno reste donc strictement identique à avant.
//    • Elle ne peut pas changer pendant la vie de l'app : pas d'écran qui
//      clignote entre deux thèmes, pas de préférence à corrompre.
//    • Elle est `const` : on peut l'utiliser dans des `static const Color`
//      (voir tv_tokens.dart), ce qui est impossible avec une préférence.
//
//  Ce que l'édition change (et UNIQUEMENT cela) :
//    1. le nom affiché (« NovaTube ») et le logo sans cadre ;
//    2. la palette vert pétrole / noir / turquoise, DÉFINITIVE : le thème
//       envoyé par le panel pour les box Zuno ne s'applique pas ;
//    3. l'accueil de premier démarrage « Bienvenue sur NovaTube ».
//
//  Ce qu'elle NE change PAS : le moteur vidéo (même lecteur natif, mêmes
//  décodeurs matériels, mêmes réglages HDR / Dolby Vision / audio), le
//  format du code appareil `MK:XX:XX:XX:XX:XX`, le stockage des listes.
// =========================================================

/// `true` seulement dans un build compilé avec `--dart-define=NOVATUBE_TV=true`.
///
/// Trois fichiers partagés relisent ce MÊME define sans importer ce fichier
/// (feedback_repository.dart, default_servers.dart,
/// remote_theme_repository.dart) : la chaîne du téléphone 7 MOTION les
/// recopie tels quels dans un arbre où ce fichier n'existe pas. Renommer le
/// define impose de les modifier aussi (contrôlé par
/// test/novatube_tv/novatube_mobile_overlay_test.dart).
const bool kNovatubeTv = bool.fromEnvironment('NOVATUBE_TV');

/// Nom commercial affiché à l'écran dans l'édition NovaTube TV.
/// (Jamais le nom du panel d'administration : le client ne doit pas le voir.)
const bool kNovatubeMax = kNovatubeTv && bool.fromEnvironment('NOVATUBE_MAX');
const String kNovatubeTvName = kNovatubeMax ? 'NovaTube MAX' : 'NovaTube';
