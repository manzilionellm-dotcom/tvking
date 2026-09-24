// =========================================================
//  text_scale_repository.dart — Réglage "Texte plus grand"
// =========================================================
//  Accessibilité seniors : un interrupteur qui agrandit typographie ET
//  cibles tactiles de ×1.15. Persisté localement, lu instantanément.
//  ChangeNotifier → l'écran se reconstruit au changement.
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TextScaleRepository extends ChangeNotifier {
  TextScaleRepository._();
  static final TextScaleRepository instance = TextScaleRepository._();

  static const String _kKey = 'a11y.bigText.v1';
  static const double _kBig = 1.15;

  bool _big = false;
  bool _initialized = false;

  /// `true` si le mode "texte plus grand" est actif.
  bool get isBig => _big;

  /// Facteur à appliquer aux tailles de police ET aux cibles tactiles.
  double get factor => _big ? _kBig : 1.0;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _big = p.getBool(_kKey) ?? false;
      notifyListeners();
    } catch (_) {/* défaut = normal */}
  }

  Future<void> toggle() async {
    _big = !_big;
    notifyListeners();
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setBool(_kKey, _big);
    } catch (_) {/* best-effort */}
  }
}
