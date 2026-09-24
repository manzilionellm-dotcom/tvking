// =========================================================
//  now_playing.dart — chaîne en cours de visionnage (léger)
// =========================================================
//  Un petit porte-état global : le lecteur y écrit le nom de la chaîne
//  qu'on regarde, et le heartbeat le joint à chaque envoi. Le panel
//  « En ligne » affiche ainsi « qui regarde quoi ».
//
//  Volontairement minimal (pas de provider) : c'est une donnée éphémère,
//  remise à '' dès qu'on quitte le lecteur.
// =========================================================
class NowPlaying {
  NowPlaying._();
  static final NowPlaying instance = NowPlaying._();

  String _current = '';

  /// Nom de la chaîne en cours ('' = on ne regarde rien).
  String get current => _current;

  /// Le lecteur appelle ceci quand une chaîne démarre.
  void set(String channelName) {
    _current = channelName.trim();
  }

  /// À la fermeture du lecteur : plus rien en cours.
  void clear() {
    _current = '';
  }
}
