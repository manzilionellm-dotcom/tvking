// =========================================================
//  tv_comfort_schedule.dart — Moment de la palette, au choix
// =========================================================
//  Par défaut le soir est FIXE : l'écran ne change pas tout seul
//  pendant un film, et les tests ne dépendent pas de l'heure.
//
//  « Selon l'heure » est optionnel. Il ne teinte pas la vidéo : il
//  ne fait que remplacer `TvComfortPeriod` dans `TvAppTokens`.
//  Un seul réveil, à l'heure pile (7 h, 17 h, 22 h), plus un passage
//  au retour de l'app si la box a dormi. Pas de timer à chaque frame.
// =========================================================

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tv_comfort.dart';

/// Ce que la personne a choisi dans Réglages.
enum TvComfortChoice { day, evening, night, auto }

class TvComfortSchedule extends ChangeNotifier with WidgetsBindingObserver {
  TvComfortSchedule._();

  static final TvComfortSchedule instance = TvComfortSchedule._();

  /// Clé locale. Rien n'est envoyé au panel.
  static const String prefKey = 'zuno.tv.comfort_choice.v1';

  TvComfortChoice _choice = TvComfortChoice.evening;
  Timer? _timer;
  bool _observing = false;
  DateTime Function() _clock = DateTime.now;

  TvComfortChoice get choice => _choice;

  /// Moment réellement peint. « auto » lit l'horloge locale.
  TvComfortPeriod get period => _choice == TvComfortChoice.auto
      ? TvComfortPalette.fromHour(_clock().hour)
      : TvComfortPeriod.values.byName(_choice.name);

  /// Préférence déjà lue, ou le soir si rien n'est enregistré.
  Future<void> load() async {
    _observe();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefKey);
      final TvComfortChoice next = TvComfortChoice.values.firstWhere(
        (TvComfortChoice choice) => choice.name == raw,
        orElse: () => TvComfortChoice.evening,
      );
      if (next != _choice) {
        _choice = next;
        notifyListeners();
      }
    } catch (_) {
      // On reste sur le soir. Le thème ne doit pas bloquer le démarrage.
    }
    _arm();
  }

  /// Cycle Réglages : Soir → Jour → Nuit → Selon l'heure → Soir.
  Future<void> cycle() {
    const List<TvComfortChoice> order = <TvComfortChoice>[
      TvComfortChoice.evening,
      TvComfortChoice.day,
      TvComfortChoice.night,
      TvComfortChoice.auto,
    ];
    final int index = order.indexOf(_choice);
    final TvComfortChoice next = order[(index + 1) % order.length];
    return choose(next);
  }

  Future<void> choose(TvComfortChoice choice) async {
    if (_choice != choice) {
      _choice = choice;
      notifyListeners();
    }
    _arm();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, choice.name);
    } catch (_) {
      // Le choix reste en mémoire pour cette session.
    }
  }

  /// Horloge remplaçable dans les tests. Ne persiste rien.
  void debugChoose(TvComfortChoice choice, {DateTime Function()? clock}) {
    if (clock != null) _clock = clock;
    _choice = choice;
    _timer?.cancel();
    notifyListeners();
  }

  void _observe() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void _arm() {
    _timer?.cancel();
    if (_choice != TvComfortChoice.auto) return;
    final DateTime now = _clock();
    final DateTime next = TvComfortPalette.nextBoundary(now);
    final Duration delay = next.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      notifyListeners();
      _arm();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _choice != TvComfortChoice.auto) {
      return;
    }
    notifyListeners();
    _arm();
  }
}
