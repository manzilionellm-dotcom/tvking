// =========================================================
//  engagement_service.dart — Streak quotidien & paliers
// =========================================================
//  Boucle d'habitude (Hook — investissement + récompense) : chaque JOUR
//  où l'utilisateur regarde quelque chose, son « streak » monte. Des
//  paliers (3 / 7 / 30 / 100 / 365 jours) déclenchent un moment de
//  célébration à l'accueil.
//
//  100 % LOCAL (SharedPreferences), aucune donnée envoyée au serveur.
//
//  ÉTHIQUE (condition des « 20 ans ») : c'est une RÉCOMPENSE, jamais une
//  punition. Casser un streak n'affiche AUCUN message négatif — on ne
//  culpabilise pas l'utilisateur, on le félicite quand il revient.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EngagementService extends ChangeNotifier {
  EngagementService._();
  static final EngagementService instance = EngagementService._();

  static const String _kStreak = 'engagement.streak';
  static const String _kLastDay = 'engagement.last_day'; // clé AAAAMMJJ (int)
  static const String _kBestStreak = 'engagement.best';

  /// Paliers célébrés. Modifiable sans risque (un palier retiré ne casse
  /// rien, un palier ajouté sera célébré à la prochaine atteinte).
  static const List<int> milestones = <int>[3, 7, 30, 100, 365];

  int _streak = 0;
  int _best = 0;
  int _pendingMilestone = 0; // > 0 si un palier vient d'être atteint

  /// Jours consécutifs de visionnage (0 si jamais / réinitialisé).
  int get streak => _streak;

  /// Meilleur streak historique (pour l'écran stats).
  int get bestStreak => _best;

  /// Palier en attente de célébration (0 = rien). L'UI le consomme via
  /// [consumeMilestone] après avoir montré l'animation.
  int get pendingMilestone => _pendingMilestone;

  bool _loaded = false;

  /// À appeler une fois au boot (idempotent).
  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _streak = p.getInt(_kStreak) ?? 0;
      _best = p.getInt(_kBestStreak) ?? 0;
    } catch (e) {
      debugPrint('[Engagement] load: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static DateTime _fromKey(int k) =>
      DateTime(k ~/ 10000, (k ~/ 100) % 100, k % 100);

  /// À appeler quand l'utilisateur commence RÉELLEMENT à regarder (à la
  /// 1ʳᵉ frame décodée). Idempotent dans la journée : ne compte qu'une
  /// fois par jour, quel que soit le nombre d'ouvertures.
  Future<void> registerWatch() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      final int today = _dayKey(DateTime.now());
      final int last = p.getInt(_kLastDay) ?? 0;
      if (last == today) return; // déjà compté aujourd'hui

      // Jour consécutif ? (via DateTime pour gérer proprement les fins de
      // mois / d'année). 1 jour d'écart = streak +1, sinon on repart à 1.
      final bool consecutive = last != 0 &&
          DateTime.now()
                  .difference(_fromKey(last))
                  .inDays ==
              1;
      _streak = consecutive ? _streak + 1 : 1;

      await p.setInt(_kStreak, _streak);
      await p.setInt(_kLastDay, today);
      if (_streak > _best) {
        _best = _streak;
        await p.setInt(_kBestStreak, _best);
      }
      if (milestones.contains(_streak)) _pendingMilestone = _streak;
      notifyListeners();
    } catch (e) {
      debugPrint('[Engagement] registerWatch: $e');
    }
  }

  /// L'UI appelle ceci après avoir affiché la célébration du palier.
  void consumeMilestone() {
    if (_pendingMilestone == 0) return;
    _pendingMilestone = 0;
    notifyListeners();
  }
}
