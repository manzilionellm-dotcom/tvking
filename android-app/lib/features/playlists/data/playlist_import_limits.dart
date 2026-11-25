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

import '../../../core/app/box_memory_budget.dart';

/// Taille max d'un téléchargement M3U accepté (octets). ~60 Mo couvre des
/// playlists légitimes énormes (100k+ lignes), tout en coupant les sources
/// aberrantes/malveillantes avant l'OOM. Le flux est interrompu dès dépassement.
const int kMaxM3uBytes = 60 * 1024 * 1024;

/// Taille max d'une réponse JSON Xtream (`get_live_streams`/VOD) acceptée.
/// Le JSON Xtream est plus lourd que le M3U équivalent (clés répétées) → on
/// laisse un peu plus large. Coupé en streaming dès dépassement.
const int kMaxXtreamJsonBytes = 80 * 1024 * 1024;

/// Taille au-delà de laquelle `get_live_streams` n'est PLUS importé d'un bloc
/// mais CATÉGORIE PAR CATÉGORIE, sur une box ≤ 1 Go (palier « serré »).
///
/// Historique : 10 Mo, parce que le décodage d'un bloc construisait l'ARBRE
/// JSON complet (10 Mo de JSON → ~100 Mo d'objets) et faisait tuer les box à
/// 1 Go. Depuis le 11/11/2026, le bloc est décodé ÉLÉMENT PAR ÉLÉMENT
/// (JsonArrayStream, 7 champs lus) : le pic d'un bloc ≈ ses octets. Or
/// l'import par catégorie coûte 919 requêtes (~35-40 s sur un réseau réel)
/// contre UN téléchargement de quelques secondes : c'est ce qui faisait
/// attendre le client après l'envoi de sa liste depuis le panel.
const int kXtreamSingleShotBytes = 24 * 1024 * 1024;

/// Même seuil pour une box de 1 à 2 Go (palier « équilibré »).
const int kXtreamSingleShotBytesBalanced = 48 * 1024 * 1024;

/// Même seuil au-delà de 2 Go (palier « large »). Reste sous le plafond dur
/// [kMaxXtreamJsonBytes].
const int kXtreamSingleShotBytesRoomy = 64 * 1024 * 1024;

/// Seuil du téléchargement en un bloc selon la mémoire de la box
/// (même échelle que BoxMemoryBudget : RAM non lue = palier serré).
int xtreamSingleShotBytesFor(BoxRamTier tier) => switch (tier) {
      BoxRamTier.tight => kXtreamSingleShotBytes,
      BoxRamTier.balanced => kXtreamSingleShotBytesBalanced,
      BoxRamTier.roomy => kXtreamSingleShotBytesRoomy,
    };

/// Durée MAXIMALE d'un téléchargement en un bloc. Le délai d'attente du bloc
/// est un délai d'INACTIVITÉ (aucun octet pendant 20 s), pas un délai total :
/// une liste de 24 Mo sur un Wi-Fi à 5 Mbit/s prend ~40 s et ne doit plus
/// échouer. Au-delà de cette durée, repli par catégorie.
const Duration kXtreamSingleShotMaxDuration = Duration(minutes: 3);

/// Plafond DUR de chaînes matérialisées en mémoire lors d'UN import. Aligné
/// sur le plafond de LECTURE (`PlaylistRepository.kMaxInMemoryChannels`) pour
/// que lecture et écriture aient la même borne. Au-delà, on s'arrête (les
/// chaînes en trop ne sont ni gardées en RAM ni insérées — la source reste
/// utilisable, juste tronquée à une taille tenable sur box faible).
const int kMaxChannelsPerImport = 50000;

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

/// Import Xtream PAR CATÉGORIE (liste > [kXtreamSingleShotBytes]) : nombre
/// de catégories téléchargées en même temps. 4 = 914 catégories en ~230
/// vagues au lieu de 914 appels en série (mesuré 136 s le 06/10/2026), sans
/// rafale qui ferait refuser la box par le fournisseur. Repli :
/// `zuno.xtream.per_category_serial`.
const int kXtreamCategoryConcurrency = 4;
