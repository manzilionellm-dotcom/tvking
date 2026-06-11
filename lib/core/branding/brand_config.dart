// =========================================================
//  brand_config.dart — Nom d'app surchargeable à distance
// =========================================================
//  Le panel « Thème » peut renommer l'app à distance (ex.
//  « WorldCup2026 »). Ce singleton ChangeNotifier porte le nom AFFICHÉ :
//    - surcharge distante si le panel en a posé une ;
//    - sinon le nom du flavor (The Few).
//  Branché à la racine (main.dart) dans le `Listenable.merge` qui
//  reconstruit MaterialApp → le nouveau nom apparaît partout d'un coup.
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/foundation.dart';

import '../flavor/flavor.dart';

class BrandConfig extends ChangeNotifier {
  BrandConfig._();
  static final BrandConfig instance = BrandConfig._();

  String? _override;

  /// Nom affiché de l'app : surcharge distante (panel) si présente et non
  /// vide, sinon le nom du flavor courant (The Few).
  String get appName {
    final String? o = _override;
    if (o != null && o.trim().isNotEmpty) return o.trim();
    return FlavorConfig.current.appName;
  }

  /// Pose (ou retire avec `null`/vide) la surcharge distante du nom.
  void setOverrideName(String? name) {
    final String? next =
        (name == null || name.trim().isEmpty) ? null : name.trim();
    if (next == _override) return;
    _override = next;
    notifyListeners();
  }
}
