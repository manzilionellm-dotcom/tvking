// =========================================================
//  sleep_timer.dart — Minuterie de veille (TV)
// =========================================================
//  « Éteindre après X minutes » — pratique le soir : si on s'endort, l'app
//  se FERME toute seule → le flux s'arrête (économie de bande passante /
//  data, et l'écran n'affiche plus rien en boucle).
//
//  ISOLATION TOTALE : ce minuteur ne touche PAS au lecteur vidéo. Il compte
//  simplement le temps dans un singleton (qui survit à la navigation) et, à
//  la fin, ferme l'app via SystemNavigator.pop() — un appel système standard.
//  Aucune interaction avec le décodage / le rendu → zéro risque pour l'image.
// =========================================================
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SleepTimer extends ChangeNotifier {
  SleepTimer._();
  static final SleepTimer instance = SleepTimer._();

  /// Durées proposées (en minutes). 0 = désactivé.
  static const List<int> presets = <int>[15, 30, 45, 60, 90];

  Timer? _timer;
  int _remaining = 0; // secondes restantes
  int _selectedMinutes = 0;

  bool get isActive => _timer != null;
  int get remainingSeconds => _remaining;
  int get selectedMinutes => _selectedMinutes;

  /// Démarre (ou redémarre) la minuterie pour [minutes]. 0 = annule.
  void start(int minutes) {
    cancel();
    if (minutes <= 0) {
      notifyListeners();
      return;
    }
    _selectedMinutes = minutes;
    _remaining = minutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _remaining -= 1;
      if (_remaining <= 0) {
        _fire();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// Annule la minuterie en cours.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _remaining = 0;
    _selectedMinutes = 0;
    notifyListeners();
  }

  void _fire() {
    _timer?.cancel();
    _timer = null;
    _remaining = 0;
    _selectedMinutes = 0;
    notifyListeners();
    // Ferme proprement l'app (retour à l'écran d'accueil de la TV) → le flux
    // s'arrête. C'est le comportement attendu d'une minuterie de veille.
    SystemNavigator.pop();
  }

  /// Format « mm:ss » du temps restant (pour l'affichage).
  String get remainingLabel {
    final int m = _remaining ~/ 60;
    final int s = _remaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
