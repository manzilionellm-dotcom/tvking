// =========================================================
//  import_progress.dart — Progression VIVANTE d'un import de source
// =========================================================
//  TERRAIN (2026-07-10) : à l'ajout d'une liste (M3U ou Xtream), le
//  bouton se contentait d'un minuscule spinner « Vérification… ». Sur
//  une grosse liste (téléchargement de plusieurs Mo ou import de
//  dizaines de milliers de chaînes), l'app semblait FIGÉE — le client
//  croit que « ça bouge pas » et abandonne.
//
//  Ce modèle porte des signaux RÉELS de progression, émis par le dépôt
//  pendant l'import, pour alimenter un écran professionnel qui bouge :
//    • la phase en cours (connexion → téléchargement → analyse → …) ;
//    • les octets reçus / total (barre déterminée quand le serveur
//      annonce la taille, sinon compteur d'octets + anim) ;
//    • le nombre de chaînes trouvées (compteur qui grimpe en direct).
//
//  PUR (aucune dépendance Flutter) : réutilisable côté téléphone ET TV.
// =========================================================

/// Étapes d'un import, dans l'ordre où elles surviennent.
enum ImportPhase {
  /// Vérification du compte / première connexion au serveur.
  connecting,

  /// Téléchargement du fichier M3U (octets qui arrivent).
  downloading,

  /// Analyse du contenu / import des chaînes catégorie par catégorie.
  analyzing,

  /// Écriture finale en base + activation de la source.
  saving,

  /// Terminé avec succès.
  done,

  /// Échec (l'UI affiche alors le message d'erreur du dépôt).
  failed,
}

/// Instantané immuable de l'avancement d'un import.
class ImportProgress {
  const ImportProgress({
    required this.phase,
    this.channelsFound = 0,
    this.bytesReceived = 0,
    this.totalBytes,
  });

  /// Phase courante.
  final ImportPhase phase;

  /// Nombre de chaînes trouvées jusqu'ici (grimpe pendant l'import).
  final int channelsFound;

  /// Octets M3U reçus (0 pour un import Xtream par API).
  final int bytesReceived;

  /// Taille totale annoncée par le serveur (`Content-Length`), ou `null`
  /// si inconnue (réponse « chunked » — fréquent en IPTV).
  final int? totalBytes;

  /// Fraction 0..1 du téléchargement quand la taille est connue, sinon
  /// `null` (l'UI bascule alors sur une barre animée + compteur d'octets).
  double? get downloadFraction {
    final int? total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesReceived / total).clamp(0.0, 1.0);
  }

  ImportProgress copyWith({
    ImportPhase? phase,
    int? channelsFound,
    int? bytesReceived,
    int? totalBytes,
  }) {
    return ImportProgress(
      phase: phase ?? this.phase,
      channelsFound: channelsFound ?? this.channelsFound,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }
}

/// Signature du rappel de progression passé aux méthodes d'ajout du
/// dépôt. `null` = appelant qui ne veut pas suivre la progression.
typedef ImportProgressCallback = void Function(ImportProgress progress);
