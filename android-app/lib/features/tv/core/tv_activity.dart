// =========================================================
//  tv_activity.dart — « La box est-elle occupée ? »
// =========================================================
//  Compteur d'écrans LOURDS ouverts (Direct avec son aperçu vidéo, lecteur
//  plein écran). Les tâches de fond gourmandes (re-téléchargement et
//  re-parsing des listes) consultent [isBusy] et ATTENDENT que le client
//  soit revenu à l'accueil : on ne re-parse jamais 30 000 chaînes pendant
//  qu'il zappe (c'était une cause de gel + fermeture de l'app).
// =========================================================
import 'package:flutter/foundation.dart';

abstract final class TvActivity {
  static final ValueNotifier<int> _busy = ValueNotifier<int>(0);

  /// Vrai tant qu'au moins un écran lourd est ouvert.
  static bool get isBusy => _busy.value > 0;

  /// À appeler dans `initState` d'un écran lourd…
  static void enter() => _busy.value = _busy.value + 1;

  /// …et dans son `dispose`.
  static void leave() => _busy.value = _busy.value > 0 ? _busy.value - 1 : 0;
}
