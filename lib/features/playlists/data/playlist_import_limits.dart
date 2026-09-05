// =========================================================
//  playlist_import_limits.dart — Garde-fous mémoire à l'IMPORT
// =========================================================
//  Cause racine n°1 du redémarrage des box TV bas de gamme : un import de
//  source géante (Xtream/M3U de 50k-100k+ chaînes) chargé d'un bloc en RAM
//  (corps HTTP entier + JSON décodé + liste complète d'objets) → pic mémoire
//  qui dépasse le budget d'une box 1 Go → crash natif (OOM) → boucle de
//  redémarrage que AUCUN try/catch Dart ne peut rattraper.
//
//  Ces constantes BORNENT l'import :
//    - on REFUSE de télécharger au-delà d'un plafond d'octets (on coupe le
//      flux dès qu'il est dépassé, AVANT de tout matérialiser) ;
//    - on PLAFONNE le nombre de chaînes matérialisées en mémoire/insérées ;
//    - on insère/parse par lots bornés.
//
//  Au-delà des plafonds, la source n'est PAS « perdue » silencieusement : on
//  lève une erreur claire (cf. PlaylistImportTooLarge) que l'UI affiche —
//  jamais de fallback muet qui masquerait le problème.
// =========================================================

/// Taille max d'un téléchargement M3U accepté (octets).
///
///  RELEVÉ DE 60 À 320 Mo LE 05/09/2026, et voici le raisonnement exact.
///
///  MESURE : une entrée dans un M3U de fournisseur pèse ~204 octets
///  (ligne `#EXTINF` complète + ligne URL). Donc :
///
///      60 Mo  →  ~308 000 entrées      ← l'ancien plafond
///     320 Mo  →  ~1 640 000 entrées
///
///  Le propriétaire demande un MILLION de chaînes et de films. À
///  204 octets pièce, un million pèse 195 Mo : l'ancien plafond le
///  refusait avant même d'essayer, avec un message qui parlait de
///  taille alors que le vrai problème était ailleurs.
///
///  POURQUOI C'EST SÛR MAINTENANT, ET NE L'ÉTAIT PAS AVANT. Le plafond
///  bas était le SEUL rempart contre l'OOM, parce que le parseur
///  chargeait tout le fichier en mémoire : 480 Mo de pic mesurés pour
///  un fichier de 204 Mo. Depuis `M3uParser.parseStream`, la mémoire
///  d'analyse est CONSTANTE — 1 Mo mesuré sur le même fichier. Le
///  plafond n'a donc plus à protéger la RAM ; il ne sert plus qu'à
///  couper une source aberrante ou malveillante avant qu'elle ne
///  remplisse le disque.
///
///  320 Mo et non « illimité » : une source qui dépasse 1,6 million
///  d'entrées est presque sûrement un défaut du fournisseur, et un
///  garde-fou qui s'arrête quelque part vaut mieux qu'un disque plein.
///
///  ⚠ La protection des PETITES box ne vient plus d'ici mais de
///  `DeviceMemory.channelCap`, qui borne ce qu'on matérialise en RAM
///  (1 500 sur une 512 Mo). Le téléchargement peut être gros ; ce qui
///  vit en mémoire, non.
const int kMaxM3uBytes = 320 * 1024 * 1024;

/// Taille max d'une réponse JSON Xtream (`get_live_streams`/VOD) acceptée.
/// Le JSON Xtream est plus lourd que le M3U équivalent (clés répétées) → on
/// laisse un peu plus large. Coupé en streaming dès dépassement.
const int kMaxXtreamJsonBytes = 80 * 1024 * 1024;

/// Plafond de SÉCURITÉ ABSOLU (dernier filet) du nombre de chaînes
/// matérialisées lors d'UN import. Ce n'est PAS le plafond réel : le vrai
/// plafond, ADAPTÉ À LA RAM de l'appareil, est `DeviceMemory.channelCap`
/// (5 000 sur une box 1 Go … jusqu'à 800 000 sur une box haut de gamme) et
/// c'est LUI que les vrais appelants (M3U + Xtream) passent en `maxChannels`.
///
/// Cette constante ne sert que de valeur par défaut si un appelant oubliait de
/// fournir le plafond adapté. On la met TRÈS HAUT (1 million) pour qu'elle ne
/// bride JAMAIS silencieusement une grosse source à un petit nombre rond : la
/// seule borne qui doit s'appliquer est celle de la RAM. (Auparavant fixée à
/// 50 000, elle faisait afficher « Toutes : 50000 » — un plafond, pas le vrai
/// total — sur les grosses sources.)
const int kMaxChannelsPerImport = 1000000;

/// Taille d'un lot d'insertion SQLite à l'import (compromis débit / pic mémoire
/// transitoire des lignes brutes).
const int kImportBatchSize = 1000;

/// Levée quand une source dépasse [kMaxM3uBytes] / [kMaxXtreamJsonBytes].
/// Message destiné à l'utilisateur (affiché tel quel par l'UI d'ajout).
class PlaylistImportTooLarge implements Exception {
  const PlaylistImportTooLarge(this.message);
  final String message;
  @override
  String toString() => message;
}
