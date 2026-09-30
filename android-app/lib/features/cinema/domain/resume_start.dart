// =========================================================
//  resume_start.dart — Où reprendre un film ou un épisode
// =========================================================
//  La rangée « Reprendre » (accueil et cinéma) ne doit pas
//  relancer au générique si la personne s'était arrêtée au
//  milieu. La règle de la position (5 s plus tôt, pas avant
//  30 s, épisode « suivant » au début) vit dans WatchEntry.
//  Ici on décide SEULEMENT ce que le bouton lance : la reprise,
//  ou le début si on l'a demandé (« Depuis le début »).
//
//  Pur : pas d'écran, pas de disque. openVod s'en sert, les
//  tests aussi.
// =========================================================

import '../data/watch_progress.dart';

/// Point de départ choisi pour un film ou un épisode.
class ResumeStart {
  const ResumeStart({required this.at, required this.resumes});

  /// Où appeler setUrl. Zéro = début du fichier.
  final Duration at;

  /// true seulement si on reprend VRAIMENT plus loin que le début.
  final bool resumes;

  /// [fromStart] : le bouton « Depuis le début » ignore la mémoire.
  /// Sans entrée, on ne peut rien reprendre.
  static ResumeStart decide({
    WatchEntry? entry,
    bool fromStart = false,
  }) {
    if (fromStart || entry == null) {
      return const ResumeStart(at: Duration.zero, resumes: false);
    }
    final Duration at = entry.resumeAt;
    return ResumeStart(at: at, resumes: at > Duration.zero);
  }
}
