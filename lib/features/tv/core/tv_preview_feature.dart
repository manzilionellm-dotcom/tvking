// =========================================================
//  tv_preview_feature.dart — L'interrupteur « aperçu en direct »
// =========================================================
//  DÉCISION DU PROPRIÉTAIRE (17/09/2026, minuit passé), devant sa box :
//
//    « Je pense que la cause, c'est ces petits écrans. Il faut les
//      enlever. Il faut seulement mettre les derniers vus, mais les
//      petits écrans qui montrent que le journal est en cours, il faut
//      les enlever. Je pense que c'est ça qui ramène le problème de
//      retourner en arrière. »
//
//  ---------------------------------------------------------
//  IL AVAIT RAISON, ET VOICI POURQUOI
//  ---------------------------------------------------------
//  `TvLivePreview` n'affiche pas une image : il ouvre un VRAI lecteur
//  ExoPlayer/Media3 — le MÊME moteur que le plein écran. Quand le client
//  regarde une chaîne et que la liste montre l'aperçu, la box décode
//  DEUX FLUX VIDÉO EN MÊME TEMPS.
//
//  Sur une box à 1 Go, avec l'interface, le cache de logos et les
//  tampons du lecteur principal, le deuxième décodeur est ce qui reste
//  à sacrifier. La boîte noire d'une box en clientèle le montre en
//  toutes lettres :
//
//    21:23:17 WARN memoire.pressure.purge {count: 4}
//    21:20:43 WARN memoire.pressure.purge {count: 3}
//    21:17:35 WARN memoire.pressure.purge {count: 2}
//    21:23:30 INFO lifecycle.boot       ← le système a tué l'app
//
//  Le garde-mémoire existant (`tv_memory_guard.dart`) allège bien l'app,
//  mais son profil « petite box » ne se déclenche qu'en dessous de
//  800 Mo. Une box de 1 à 2 Go — le parc courant — gardait donc l'aperçu
//  ET ses deux décodeurs. Le seuil protégeait les Fire TV Stick et
//  laissait passer exactement les machines du client.
//
//  ---------------------------------------------------------
//  L'ARBITRAGE N'EST PAS SERRÉ
//  ---------------------------------------------------------
//  Une vignette animée pendant qu'on parcourt la liste est un CONFORT.
//  Une box qui redémarre en pleine émission est un client perdu. Le même
//  raisonnement que FLAG_SECURE : bloquer les captures était un confort,
//  une box qui ne montre plus rien est une panne.
//
//  ---------------------------------------------------------
//  CE QUI RESTE À L'ÉCRAN
//  ---------------------------------------------------------
//  TOUT, sauf la vidéo. La tuile garde sa place, son cadre et le LOGO de
//  la chaîne — c'est déjà ce que l'aperçu affiche pendant son chargement
//  et en cas d'échec. Les « DERNIERS VUS », la fiche du programme en
//  cours et sa barre de progression ne sont pas touchés : ils ne coûtent
//  rien, ils viennent du guide, pas d'un décodeur.
//
//  ---------------------------------------------------------
//  UNE SEULE IMPLÉMENTATION, AUTANT D'APPELANTS QU'ON VEUT
//  ---------------------------------------------------------
//  Quatre écrans posent un aperçu : le Lanceur, les Rails, le TiviMate et
//  la liste des chaînes. Le garde n'est PAS chez eux — il est dans
//  `TvLivePreview._start()`, la seule méthode qui ouvre un lecteur.
//
//  Quatre gardes, c'est trois occasions d'en oublier un. Et celui qu'on
//  oublie est celui qui tue la box, un soir, chez un client.
// =========================================================

import 'package:flutter/foundation.dart';

/// Ce que dit la COMPILATION. Éteint par défaut ; se rallume sans toucher
/// une ligne de code :
///
/// ```sh
/// flutter build apk --dart-define=APERCU_DIRECT=true
/// ```
///
/// Avant de le rallumer : mesure la mémoire sur une VRAIE box de 1 Go,
/// avec une chaîne en plein écran ET la liste ouverte. C'est ce cas-là
/// qui a fait redémarrer les box, pas l'aperçu tout seul.
const bool kApercuDirectCompile =
    bool.fromEnvironment('APERCU_DIRECT', defaultValue: false);

bool _apercu = kApercuDirectCompile;

/// L'aperçu vidéo en direct des listes est-il actif ?
///
/// Une variable et non une `const`, pour la même raison que
/// `kFamilleActivee` : les tests de `TvLivePreview` décrivent ce que
/// l'aperçu fait QUAND IL MARCHE. Les jeter aurait éteint deux fois — la
/// deuxième sans pouvoir revenir.
bool get kApercuDirectActif => _apercu;

/// Rallume/éteint l'aperçu LE TEMPS D'UN TEST.
///
/// Appelle [reinitialiserApercuPourTest] en `tearDown` : un test qui
/// laisse l'interrupteur dans l'autre position contamine ceux qui suivent,
/// et le coupable est celui qui échoue — pas celui qui a triché.
@visibleForTesting
set apercuDirectPourTest(bool v) => _apercu = v;

/// Remet l'interrupteur sur ce que dit la compilation.
@visibleForTesting
void reinitialiserApercuPourTest() => _apercu = kApercuDirectCompile;
