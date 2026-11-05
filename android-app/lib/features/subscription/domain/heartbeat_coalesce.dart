// =========================================================
//  heartbeat_coalesce.dart — Un seul heartbeat en vol
// =========================================================
//  Le lecteur envoie déjà un heartbeat à chaque chaîne ouverte
//  (NowPlaying + POST /api/heartbeat). Si une écriture est déjà
//  en cours (timeout jusqu'à 8 s), l'appel suivant répondait
//  « occupé » et le nom de chaîne était perdu jusqu'au filet
//  de 3 minutes.
//
//  On retient UN seul renvoi, pas une file : le prochain envoi
//  lit NowPlaying à ce moment-là, donc c'est la dernière chaîne.
//  Deux écritures ne partent jamais en même temps.
//
//  Seul un heartbeat refusé demande ce renvoi. La lecture de statut
//  repasse d'elle-même (1 à 2 s sans le canal) : si elle en
//  demandait un, chaque lecture tombée pendant un POST lent
//  relancerait un POST, et la veille deviendrait une suite
//  d'écritures sur le Worker.
// =========================================================

/// Verrou d'une écriture panel, avec au plus un renvoi en attente.
class HeartbeatCoalesce {
  bool _busy = false;
  bool _again = false;

  /// Vrai : cette tâche peut partir. Faux : une lecture ou une
  /// écriture est déjà en vol. Avec [resend] (heartbeat), elle sera
  /// refaite une fois à la fin ; sans (lecture de statut), rien
  /// n'est rejoué.
  bool start({bool resend = true}) {
    if (_busy) {
      if (resend) _again = true;
      return false;
    }
    _busy = true;
    return true;
  }

  /// À appeler dans un `finally`. Vrai : il faut relancer une
  /// écriture (la chaîne a changé pendant la précédente).
  bool finish() {
    _busy = false;
    if (!_again) return false;
    _again = false;
    return true;
  }
}
