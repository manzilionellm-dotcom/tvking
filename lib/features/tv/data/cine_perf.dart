// =========================================================
//  cine_perf.dart — Chronomètres des budgets de fluidité Cinéma
// =========================================================
//  « Plus fluide que Netflix » ne se DÉCLARE pas, ça se MESURE. Ce module
//  centralise les chronos des parcours critiques du Cinéma TV, chacun
//  comparé à son BUDGET :
//
//    - homeFirstRender  : ouverture accueil Cinéma → 1er rendu utile < 400 ms
//    - detailOpen       : OK sur une affiche → fiche affichée      < 300 ms
//    - playToFirstFrame : « Regarder » → première frame vidéo      < 2500 ms
//
//  Chaque mesure part dans la Boîte noire (StreamDiagnostics, tag « perf »)
//  ET en debugPrint — vérifiable sur box réelle via l'écran Diagnostics.
//  Un dépassement est loggé en WARN avec le chiffre réel : pas de maquillage.
//
//  Usage :
//    CinePerf.start(CinePerf.homeFirstRender);
//    … (premier build utile) …
//    CinePerf.end(CinePerf.homeFirstRender);   // → « 213 ms (budget 400) »
//
//  `end` sur un chrono jamais démarré est un no-op silencieux (les écrans
//  peuvent instrumenter sans se soucier de qui a démarré quoi).
// =========================================================

import 'package:flutter/foundation.dart';

import '../../player/data/stream_diagnostics.dart';

abstract final class CinePerf {
  // ----- Parcours instrumentés (clé = nom stable pour les logs) -----
  static const String homeFirstRender = 'cinema.home_first_render';
  static const String detailOpen = 'cinema.detail_open';
  static const String playToFirstFrame = 'cinema.play_to_first_frame';

  /// Budgets (ms) — les chiffres de la mission, pas des impressions.
  static const Map<String, int> budgets = <String, int>{
    homeFirstRender: 400,
    detailOpen: 300,
    playToFirstFrame: 2500,
  };

  static final Map<String, Stopwatch> _running = <String, Stopwatch>{};

  /// (Re)démarre le chrono [tag]. Redémarrer un chrono en cours le remet à
  /// zéro — utile quand l'utilisateur relance le même parcours.
  static void start(String tag) {
    _running[tag] = Stopwatch()..start();
  }

  /// Vrai si le chrono [tag] court (fenêtre de mesure ouverte).
  static bool isRunning(String tag) => _running.containsKey(tag);

  /// Arrête le chrono [tag], logge « <ms> ms (budget <b>) » et renvoie la
  /// durée mesurée en ms — `null` si le chrono n'avait pas été démarré.
  /// [detail] enrichit le log (nom du film, résolution…).
  static int? end(String tag, {String? detail}) {
    final Stopwatch? sw = _running.remove(tag);
    if (sw == null) return null;
    sw.stop();
    final int ms = sw.elapsedMilliseconds;
    final int? budget = budgets[tag];
    final bool over = budget != null && ms > budget;
    final String msg = '$tag : $ms ms'
        '${budget != null ? ' (budget $budget ms${over ? ' DÉPASSÉ' : ''})' : ''}'
        '${detail != null ? ' — $detail' : ''}';
    StreamDiagnostics.instance
        .recordEvent('perf', msg, level: over ? 'warn' : 'info');
    if (kDebugMode) debugPrint('[CinePerf] $msg');
    return ms;
  }

  /// Abandonne un chrono sans mesurer (parcours interrompu : retour arrière
  /// avant l'affichage, erreur…) — évite de polluer les stats avec des
  /// durées qui n'en sont pas.
  static void cancel(String tag) => _running.remove(tag);
}
