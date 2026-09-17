// =========================================================
//  family_feature.dart — L'interrupteur « famille »
// =========================================================
//  DÉCISION DU PROPRIÉTAIRE (17/09/2026).
//
//    « Désactive carrément les trucs de famille, que ce soit une
//      application normale qui n'a pas de trucs de famille, des users. »
//
//  ---------------------------------------------------------
//  CE QU'ON COUPE, ET POURQUOI ÇA SE VOYAIT DANS LA BOÎTE NOIRE
//  ---------------------------------------------------------
//  La box du client, journal du 17/09 au soir, toutes les 2-3 minutes :
//
//    21:14:51 WARN profiles.remote.sync_fail
//             {Failed host lookup: 'seven-motion-backend…workers.dev',
//              errno = 7}
//    21:09:57 WARN profiles.remote.sync_fail   {la même}
//
//  C'est la synchronisation des PROFILS qui réveillait le réseau pour
//  aller chercher des profils que ce client n'a jamais créés. Elle
//  échouait, elle recommençait, elle remplissait le journal — et elle
//  masquait les vraies lignes au milieu du bruit.
//
//  Une fonctionnalité que personne n'utilise mais qui travaille quand
//  même, c'est le pire des deux mondes : elle coûte, elle ne rapporte
//  rien, et elle cache les pannes qui comptent.
//
//  ---------------------------------------------------------
//  CE QU'ON NE COUPE SURTOUT PAS
//  ---------------------------------------------------------
//  Le mot « famille » désigne DEUX choses dans ce projet, et les
//  confondre couperait les abonnements :
//
//   1. LES PROFILS (papa, maman, les enfants, « Qui regarde ? », les
//      codes PIN, le partage de position de lecture). C'est ÇA qu'on
//      éteint ici. C'est du confort d'interface, rien de plus.
//
//   2. `familyStatusForMac` / `familyOwnerOf` CÔTÉ SERVEUR
//      (`cloudflare/worker.js`). Malgré son nom, ce n'est PAS du
//      confort : c'est la GRILLE DE LICENCE. C'est elle qui décide si
//      une MAC a le droit de recevoir sa playlist, et elle fait hériter
//      une box de la source de son propriétaire. Y toucher, c'est
//      couper la source de tout le parc.
//      → LE SERVEUR N'EST PAS MODIFIÉ. Pas une ligne.
//
//  ---------------------------------------------------------
//  POURQUOI UN INTERRUPTEUR ET PAS UNE SUPPRESSION
//  ---------------------------------------------------------
//  Supprimer 3 500 lignes d'un coup, c'est 3 500 lignes de risque un
//  soir où le parc est déjà instable. Un interrupteur se vérifie en
//  lisant UNE constante, et se rallume en changeant UN mot si le
//  propriétaire revend un jour du multi-profil.
//
//  Les écrans restent donc dans le dépôt, mais plus AUCUN chemin ne
//  permet de les atteindre, et plus AUCUN travail de fond ne part.
//
//  ---------------------------------------------------------
//  UNE SEULE IMPLÉMENTATION, AUTANT D'APPELANTS QU'ON VEUT
//  ---------------------------------------------------------
//  Même règle que `device_profiles.js`, `app_versions.js` ou
//  `ci/build_label.sh` : la condition vit ICI et nulle part ailleurs.
//  Le jour où une copie dit « oui » pendant que l'original dit « non »,
//  on se retrouve avec un bouton qui ouvre un écran mort.
//
//  Et l'interrupteur est branché À LA SOURCE (dans les dépôts, dans la
//  synchro), pas seulement sur les boutons : un appelant peut être
//  oublié, une source ne peut pas l'être.
// =========================================================

import 'package:flutter/foundation.dart';

/// Ce que dit la COMPILATION. Éteint par défaut ; se rallume sans toucher
/// une ligne de code :
///
/// ```sh
/// flutter build apk --dart-define=FAMILLE=true
/// ```
///
/// Si tu la rallumes, vérifie d'abord que
/// `seven-motion-backend…workers.dev` répond : c'est son absence qui a
/// motivé l'extinction.
const bool kFamilleCompilee =
    bool.fromEnvironment('FAMILLE', defaultValue: false);

bool _famille = kFamilleCompilee;

/// La fonctionnalité « famille / profils » est-elle active ?
///
/// ---------------------------------------------------------
/// POURQUOI UNE VARIABLE ET PAS UNE `const`
/// ---------------------------------------------------------
/// Une `const` aurait été plus élégante — et elle aurait fait TOMBER dix
/// tests d'un coup : ceux qui décrivent le multi-profil (les cinq profils
/// du panel, le PIN, la coupure à distance, le profil fait main qui
/// survit à une poussée). Ces tests sont la PREUVE que la fonctionnalité
/// remarche si le propriétaire la rallume un jour.
///
/// Les supprimer aurait été le vrai coût : on aurait éteint la
/// fonctionnalité ET jeté la garantie qu'elle est encore entière. Ils
/// rallument donc l'interrupteur pour leur durée, avec
/// [familleActiveePourTest].
///
/// Le prix : ce booléen n'est plus éliminé à la compilation. Quelques
/// écrans déjà présents restent dans le binaire. C'est tout — et ça n'a
/// jamais fait redémarrer une box.
bool get kFamilleActivee => _famille;

/// Rallume/éteint la famille LE TEMPS D'UN TEST.
///
/// Appelle [reinitialiserFamillePourTest] en `tearDown` : un test qui
/// laisse l'interrupteur dans l'autre position contamine ceux qui suivent,
/// et le coupable est celui qui échoue — pas celui qui a triché.
@visibleForTesting
set familleActiveePourTest(bool v) => _famille = v;

/// Remet l'interrupteur sur ce que dit la compilation.
@visibleForTesting
void reinitialiserFamillePourTest() => _famille = kFamilleCompilee;
