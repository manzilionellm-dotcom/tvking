// =========================================================
//  remote_typing_hub.dart — Où va le texte tapé sur le téléphone
// =========================================================
//  L'écran de recherche (Direct ou Cinéma) s'inscrit ici pendant
//  qu'il est affiché. Le dernier inscrit gagne : c'est l'écran du
//  dessus. Si personne n'écoute, le texte est ignoré (il n'est pas
//  transformé en touches au hasard dans l'interface).
//
//  Un champ de saisie focalisé (ajouter une source, par exemple)
//  est traité AVANT ce hub, dans la couche présentation : le texte
//  du téléphone remplit le champ, il ne part pas dans une recherche
//  cachée derrière.
// =========================================================

class RemoteTypingHub {
  RemoteTypingHub._();
  static final RemoteTypingHub instance = RemoteTypingHub._();

  final List<bool Function(String text)> _handlers = <bool Function(String)>[];

  void register(bool Function(String text) handler) {
    if (!_handlers.contains(handler)) _handlers.add(handler);
  }

  void unregister(bool Function(String text) handler) {
    _handlers.remove(handler);
  }

  /// Vrai si un écran a pris le texte.
  bool apply(String text) {
    for (int i = _handlers.length - 1; i >= 0; i--) {
      if (_handlers[i](text)) return true;
    }
    return false;
  }
}
