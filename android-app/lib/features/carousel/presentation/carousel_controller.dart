// =========================================================
//  carousel_controller.dart — Cerveau du carrousel (≈ « useCarousel »)
// =========================================================
//  Équivalent Flutter du hook React `useCarousel` : il possède l'état et
//  la logique, le widget ne fait que dessiner et animer.
//
//  ÉTAT
//    • index      : carte sélectionnée (0..count-1), l'anneau boucle ;
//    • position   : position CONTINUE sur l'anneau (1.5 = entre la carte 1
//                   et la 2). C'est elle que le widget anime (snap, glisser)
//                   pour un mouvement fluide ; au repos elle vaut un entier.
//                   Elle n'est PAS bornée à 0..count-1 : en tournant 3 fois
//                   à droite depuis la dernière carte, elle continue (12, 13…)
//                   et [offsetOf] replie la boucle. Pas de « saut » visuel.
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

  /// Position continue sur l'anneau.
  double get position => _position;

  /// Écart SIGNÉ le plus court entre la carte [i] et la position courante,
  /// en tenant compte de la boucle (sur 12 cartes, la 11 est à -1 de la 0).
  /// Sert au widget pour placer chaque carte sur l'arc.
  double offsetOf(int i) {
    double d = (i - _position) % _count; // 0..count
    if (d > _count / 2) d -= _count;
    return d;
  }

  /// Carte suivante / précédente, SANS animation (tests, sauts directs).
  void next() => jumpTo(_index + 1);
  void previous() => jumpTo(_index - 1);

  /// Va à la carte [i] immédiatement (position = index).
  void jumpTo(int i) {
    final int target = _wrap(i, _count);
    if (target == _index && _position == target.toDouble()) return;
    _index = target;
    _position = target.toDouble();
    notifyListeners();
  }

  /// Utilisé par l'animation (snap, glisser) : déplace la position continue.
  /// L'index suit la carte la plus proche du centre ; renvoie `true` si la
  /// carte sélectionnée a changé (→ tick sonore, texte d'info mis à jour).
  bool setPosition(double p) {
    _position = p;
    final int nearest = _wrap(p.round(), _count);
    final bool changed = nearest != _index;
    _index = nearest;
    notifyListeners();
    return changed;
  }

  static int _wrap(int i, int n) => ((i % n) + n) % n;
}
