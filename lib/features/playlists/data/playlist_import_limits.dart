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

/// Taille max d'un téléchargement M3U accepté (octets). ~60 Mo couvre des
/// playlists légitimes énormes (100k+ lignes), tout en coupant les sources
/// aberrantes/malveillantes avant l'OOM. Le flux est interrompu dès dépassement.
const int kMaxM3uBytes = 60 * 1024 * 1024;

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
