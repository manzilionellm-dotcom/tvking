// =========================================================
//  playback_health.dart — Qualité de lecture, en pourcentage
// =========================================================
//  Demande du 13/11/2026 : dans le panel, voir pour chaque client
//  « son taux de connexion en % ».
//
//  CE QU'ON MESURE (et rien d'autre) : la part du temps où l'image
//  a vraiment joué, depuis le dernier signal envoyé au serveur.
//    100 % = aucune attente ; 80 % = un cinquième du temps passé à
//    charger ou à se reconnecter.
//  Ce n'est PAS un test de débit : on ne télécharge rien en plus,
//  on regarde seulement ce que le lecteur fait déjà.
//
//  RÈGLES
//   • Une attente de moins de 3 s ne compte pas : c'est le temps
//     normal d'ouverture d'une chaîne au zap.
//   • Moins de 10 s d'observation : pas de chiffre (null). Le panel
//     affiche alors « — », jamais un pourcentage inventé.
//   • Rien ne quitte la box à part ce nombre, dans le signal déjà
//     envoyé au serveur.
// =========================================================

/// Attente trop courte pour être un problème de connexion.
const int kPlaybackGraceMs = 3000;

/// Durée minimale d'observation avant de donner un pourcentage.
const int kPlaybackMinWindowMs = 10000;

enum _Phase { idle, playing, stalled }

class PlaybackHealth {
  PlaybackHealth({int Function()? clock})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  static final PlaybackHealth instance = PlaybackHealth();

  final int Function() _clock;

  _Phase _phase = _Phase.idle;
  int _since = 0;
  int _playMs = 0;
  int _stallMs = 0;

  /// Le lecteur dit où il en est : [stalled] vrai = il charge, il se
  /// reconnecte ou il est en erreur ; faux = l'image joue (ou l'utilisateur
  /// a mis en pause : ce n'est pas la faute de la connexion).
  void mark({required bool stalled}) {
    final _Phase next = stalled ? _Phase.stalled : _Phase.playing;
    if (next == _phase) return;
    _close();
    _phase = next;
  }

  /// Le lecteur est fermé : on arrête de compter.
  void stop() {
    if (_phase == _Phase.idle) return;
    _close();
    _phase = _Phase.idle;
  }

  /// Pourcentage 0–100 depuis le dernier appel, puis remise à zéro.
  /// `null` si on n'a pas assez observé (rien à l'écran, ou trop court).
  int? takePercent() {
    _close();
    final int total = _playMs + _stallMs;
    final int play = _playMs;
    _playMs = 0;
    _stallMs = 0;
    if (total < kPlaybackMinWindowMs) return null;
    final int pct = ((play * 100) / total).round();
    return pct < 0 ? 0 : (pct > 100 ? 100 : pct);
  }

  /// Range le temps écoulé dans la bonne case et repart de maintenant.
  void _close() {
    final int now = _clock();
    final int spent = now - _since;
    if (spent > 0) {
      if (_phase == _Phase.playing) {
        _playMs += spent;
      } else if (_phase == _Phase.stalled) {
        if (spent < kPlaybackGraceMs) {
          _playMs += spent;
        } else {
          _stallMs += spent;
        }
      }
    }
    _since = now;
  }
}
