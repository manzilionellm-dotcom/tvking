// =========================================================
//  single_flight.dart — Un seul travail à la fois, résultat partagé
// =========================================================
//  « Single flight » : quand PLUSIEURS appelants demandent la même chose
//  en même temps, un seul travail part réellement ; les autres attendent
//  ce même travail et reçoivent son résultat.
//
//  POURQUOI ÇA EXISTE (terrain du 22/08, photo client « le Cinéma côté
//  mobile tarde à venir ») : l'accueil PRÉCHAUFFE le catalogue de films
//  en tâche de fond, et le client peut ouvrir le Cinéma pendant ce
//  temps-là. Sans garde, les deux appels partaient chacun télécharger le
//  catalogue ENTIER — plusieurs mégaoctets en double, sur le même petit
//  réseau, avec deux isolates de parsing. On DOUBLAIT très exactement
//  l'attente qu'on cherchait à supprimer.
//
//  RÈGLES (toutes verrouillées par les tests) :
//    1. deux appels simultanés → UN SEUL travail, deux fois le même
//       résultat ;
//    2. une fois le travail TERMINÉ, l'appel suivant en relance un neuf
//       (ce n'est pas un cache : c'est un anti-doublon d'instant) ;
//    3. une ERREUR se propage à TOUS les appelants en attente, puis la
//       place est libérée — un échec ne condamne jamais les ouvertures
//       suivantes à ce même échec.
// =========================================================

/// Déduplique les appels CONCURRENTS à un même travail asynchrone.
class SingleFlight<T> {
  Future<T>? _pending;

  /// `true` tant qu'un travail est en vol (utile pour un diagnostic).
  bool get isRunning => _pending != null;

  /// Lance [task], ou s'accroche au travail déjà en cours.
  Future<T> run(Future<T> Function() task) {
    final Future<T>? pending = _pending;
    if (pending != null) return pending;
    // `task()` peut lever AVANT son premier `await` (erreur synchrone) :
    // on l'enveloppe pour que ce cas suive le même chemin que les autres.
    final Future<T> started = Future<T>.sync(task);
    _pending = started;
    return started.whenComplete(() {
      // `identical` : si un travail plus récent a déjà pris la place (cas
      // limite d'un enchaînement très serré), on ne l'efface pas.
      if (identical(_pending, started)) _pending = null;
    });
  }
}
