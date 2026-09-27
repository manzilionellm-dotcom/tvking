// =========================================================
//  carousel_controller.dart — Cerveau du carrousel (≈ « useCarousel »)
// =========================================================
//  Équivalent Flutter du hook React `useCarousel` : il possède l'état et
//  la logique, le widget ne fait que dessiner.
//
//  ÉTAT
//    • index      : carte sélectionnée (0..count-1), l'anneau boucle ;
//    • position   : position CONTINUE sur l'anneau (1.5 = entre la carte 1
//                   et la 2) — c'est elle qu'on anime pour un mouvement
//                   fluide ; au repos elle vaut exactement l'index (snap).
//
//  ÉTAPES À VENIR (cahier des charges) :
//    étape 3 → animation du snap, molette, glisser tactile ;
//    étape 4 → zoom de sélection + respiration au repos ;
//    étape 5 → branchement du son (tick / sélection).
// =========================================================
import 'package:flutter/foundation.dart';

class ZunoCarouselController extends ChangeNotifier {
  ZunoCarouselController({required int count, int initialIndex = 0})
      : assert(count > 0),
        _count = count,
        _index = _wrap(initialIndex, count),
        _position = _wrap(initialIndex, count).toDouble();

  final int _count;
  int _index;
  double _position;

  int get count => _count;
  int get index => _index;

  /// Position continue sur l'anneau (animée à l'étape 3).
  double get position => _position;

  /// Écart SIGNÉ le plus court entre la carte [i] et la position courante,
  /// en tenant compte de la boucle (sur 12 cartes, la 11 est à -1 de la 0).
  /// Sert au widget pour placer chaque carte sur l'arc.
  double offsetOf(int i) {
    double d = i - _position;
    final double half = _count / 2;
    while (d > half) {
      d -= _count;
    }
    while (d < -half) {
      d += _count;
    }
    return d;
  }

  /// Carte suivante / précédente (boucle).
  void next() => jumpTo(_index + 1);
  void previous() => jumpTo(_index - 1);

  /// Va à la carte [i] (bornée par la boucle). Sans animation à cette
  /// étape : le snap animé arrive à l'étape 3.
  void jumpTo(int i) {
    final int target = _wrap(i, _count);
    if (target == _index) return;
    _index = target;
    _position = target.toDouble();
    notifyListeners();
  }

  static int _wrap(int i, int n) => ((i % n) + n) % n;
}
