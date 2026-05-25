// =========================================================
//  device_class_repository.dart — Téléphone ou Télévision ?
// =========================================================
//  À la première ouverture, l'utilisateur choisit s'il est sur
//  son téléphone ou sur sa TV (Android TV / Fire TV / Google TV).
//  Le choix conditionne :
//    - L'écran d'accueil (Phone vs TV : grille XL focus-aware)
//    - La taille des éléments interactifs (zones D-pad)
//    - Les raccourcis clavier (TV uniquement)
//
//  3 valeurs possibles :
//    - phone  : usage tactile sur smartphone
//    - tv     : usage télécommande, focus rings, tailles XL
//    - auto   : on devine via la taille d'écran + plateforme à
//               chaque démarrage. Fallback raisonnable.
// =========================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DeviceClass {
  /// Smartphone tactile.
  phone,

  /// Android TV / Fire TV / Google TV avec télécommande.
  tv,

  /// Détection automatique au runtime.
  auto,
}

class DeviceClassRepository extends ChangeNotifier {
  DeviceClassRepository._();
  static final DeviceClassRepository instance = DeviceClassRepository._();

  static const String _kKey = 'device.class.v1';

  DeviceClass _choice = DeviceClass.auto;

  /// Le choix brut de l'utilisateur — ce qui a été coché à
  /// l'onboarding. `auto` veut dire "laisse l'app décider".
  DeviceClass get choice => _choice;

  /// Le résultat effectif après résolution de `auto`. C'est ce que
  /// les écrans regardent pour décider de leur layout. Toujours
  /// `phone` ou `tv`, jamais `auto`.
  DeviceClass effectiveFor(BuildContext context) {
    if (_choice != DeviceClass.auto) return _choice;
    return _autoDetect(context);
  }

  bool isTvFor(BuildContext context) =>
      effectiveFor(context) == DeviceClass.tv;

  Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_kKey);
    switch (stored) {
      case 'phone':
        _choice = DeviceClass.phone;
      case 'tv':
        _choice = DeviceClass.tv;
      default:
        _choice = DeviceClass.auto;
    }
    notifyListeners();
  }

  Future<void> setChoice(DeviceClass choice) async {
    _choice = choice;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, _serialize(choice));
    notifyListeners();
  }

  String _serialize(DeviceClass c) {
    switch (c) {
      case DeviceClass.phone:
        return 'phone';
      case DeviceClass.tv:
        return 'tv';
      case DeviceClass.auto:
        return 'auto';
    }
  }

  // ============================================================
  //  Heuristique auto-détection
  // ============================================================
  //  Critères combinés (un seul suffit pour considérer "TV") :
  //    1. Diagonale d'écran > 10 pouces (logique : tablette XL ou TV)
  //    2. Densité < 1.6 (typique des TVs, qui sont en dpi natif bas)
  //    3. Plus large que haut + plus de 1280 px de largeur
  //
  //  Pas parfait mais évite de demander à chaque ouverture si
  //  l'utilisateur n'a jamais choisi.
  // ============================================================

  DeviceClass _autoDetect(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final Size size = mq.size;
    final double dpr = mq.devicePixelRatio;
    final double widthDp = size.width;
    final double heightDp = size.height;

    // Largeur en pouces approximative (96 dp = 1 inch sur Flutter logical)
    final double widthInches = widthDp / 96.0;
    final double diagonalInches = (size.shortestSide * 1.41) / 96.0;

    final bool isLandscape = widthDp > heightDp;
    final bool largeScreen =
        isLandscape && widthDp >= 1280 && diagonalInches > 10;
    final bool lowDensity = dpr < 1.6;

    if (largeScreen || (lowDensity && widthInches > 12)) {
      return DeviceClass.tv;
    }
    return DeviceClass.phone;
  }
}
