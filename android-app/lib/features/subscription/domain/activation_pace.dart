// =========================================================
//  activation_pace.dart — Rythme « panel → box »
// =========================================================
//  Le revendeur active la MAC dans le panel. La box doit s'ouvrir
//  quelques secondes plus tard, SANS que chaque box du parc n'écrive
//  en base plusieurs fois par minute.
//
//  Tout ici est du calcul pur (pas de réseau, pas de Flutter) pour
//  pouvoir le vérifier par des tests.
// =========================================================

/// Délai avant la prochaine lecture du statut.
///
/// - [waiting] : la box n'a pas encore le droit d'ouvrir l'accueil,
///   OU elle l'a mais aucune chaîne n'est encore en cache. On lit
///   souvent (3 s), le temps que le clic du panel descende.
/// - Sinon : la box est déjà en service. On lit plus tranquillement
///   (4 s). Une nouvelle source, ou une liste retirée, arrive dans
///   la même poignée de secondes, sans noyer le Worker.
/// - [failures] : lectures ratées d'affilée (Wi-Fi coupé, Worker
///   injoignable). On double l'attente à chaque échec, jusqu'à 45 s.
///   Dès qu'une lecture réussit, on revient au rythme normal.
abstract final class ActivationPace {
  /// En attente d'activation ou de la première source.
  static const Duration fast = Duration(seconds: 3);

  /// Box déjà ouverte, avec des chaînes en cache.
  /// 4 s : une liste retirée dans le panel disparaît dans la
  /// même poignée de secondes, et une box ne fait qu'environ
  /// 15 lectures légères par minute (plafond Worker : 120).
  static const Duration calm = Duration(seconds: 4);

  /// Canal long ouvert : la box est déjà prévenue dès qu'un ordre
  /// arrive. On ne relit le statut qu'en filet, toutes les 25 s.
  static const Duration parked = Duration(seconds: 25);

  /// Plafond quand le réseau ne répond plus.
  static const Duration ceiling = Duration(seconds: 45);

  static Duration next({required bool waiting, required int failures}) {
    final int base = (waiting ? fast : calm).inMilliseconds;
    if (failures <= 0) return Duration(milliseconds: base);
    // 1 échec → ×2, 2 → ×4, … plafonné pour ne pas dépasser [ceiling].
    final int shift = failures > 4 ? 4 : failures;
    final int grown = base << shift;
    final int cap = ceiling.inMilliseconds;
    return Duration(milliseconds: grown > cap ? cap : grown);
  }
}

/// Faut-il télécharger les codes IPTV (GET /api/device-source) ?
///
/// Le statut (GET /api/status) est léger. Le fichier des codes, lui,
/// contient les mots de passe : on ne le redemande QUE si le panel a
/// changé quelque chose, et JAMAIS pendant qu'une chaîne joue.
abstract final class SourceFetchDecision {
  static bool shouldFetch({
    required bool networkOk,
    required bool playbackBusy,
    required bool sourceRevKnown,
    required int? sourceRev,
    required int? lastFetchedRev,
    required bool hasChannels,
  }) {
    // Coupure : on garde la liste déjà sur la box.
    if (!networkOk) return false;
    // Direct ou lecteur ouvert : importer une grosse liste fige
    // l'image. On attend le retour à l'accueil.
    if (playbackBusy) return false;
    // Ancien Worker (pas de source_rev) : on relit au rythme de la
    // veille, déjà espacé par ActivationPace.
    if (!sourceRevKnown) return true;
    final int rev = sourceRev ?? 0;
    if (rev <= 0) {
      // Plus de ligne côté panel, alors qu'on en avait lu une :
      // la source a été retirée, il faut relire les tombstones.
      if (lastFetchedRev != null && lastFetchedRev > 0) return true;
      // Rien d'assigné. Une seule vérification tant qu'on n'a pas
      // de chaîne, pour ne pas rater une source posée dans la même
      // seconde que l'activation. Ensuite on attend que le numéro
      // change.
      return !hasChannels && lastFetchedRev != 0;
    }
    return rev != lastFetchedRev;
  }
}

/// Une lecture ratée (timeout, DNS, HTTP différent de 200) ne doit
/// jamais effacer le dernier statut reçu. Sinon une seconde sans
/// Wi-Fi renverrait la box sur l'écran d'activation, ou ferait
/// croire qu'une chaîne en cours n'est plus autorisée.
bool keepLastStatusOnFailure({required bool reached}) => !reached;
