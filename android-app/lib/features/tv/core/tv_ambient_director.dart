// =========================================================
//  tv_ambient_director.dart — Qui allume le halo, et quand
// =========================================================
//  « Auto » : au-dessus de 2 Go (palier large de PR #207,
//  `!lowRam && totalMb > 2048`, le même test que
//  `TvGlassPolicy.capable`) on moyenne l'échantillon et on
//  fond le halo en 480 ms. À 2 Go et moins, version fixe :
//  le genre seul, sans image, sans animation.
//
//  « Arrêt » : le soir confort, quel que soit le programme.
//  Le réglage est local. Rien n'est envoyé.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../channels/domain/channel_genre.dart';
import 'tv_ambient.dart';
import 'tv_comfort.dart';
import 'tv_glass.dart';
import 'tv_tokens.dart';

enum TvAmbientChoice { auto, off }

class TvAmbientDirector extends ChangeNotifier {
  TvAmbientDirector._();
  static final TvAmbientDirector instance = TvAmbientDirector._();

  static const String prefKey = 'zuno.tv.ambient.v1';

  /// Philips interpole entre deux images retenues. 480 ms est un
  /// fondu d'interface, pas un recalcul à chaque frame vidéo.
  static const Duration blend = Duration(milliseconds: 480);

  TvAmbientChoice _choice = TvAmbientChoice.auto;
  ChannelGenre? _genre;
  String? _epgCategory;
  List<int>? _rgb;
  TvAmbientLook? _look;

  TvAmbientChoice get choice => _choice;
  TvAmbientLook? get look => _look;

  /// Faux sur le palier ≤ 2 Go, ou si les animations sont coupées
  /// par l'appelant. Le halo change alors d'un coup, sans courbe.
  bool get animates => _choice == TvAmbientChoice.auto && TvGlassPolicy.capable;

  /// Vrai quand on a le droit de lire des pixels (affiche, logo).
  /// Jamais sur une box ≤ 2 Go : la version fixe ne dépend que du genre.
  bool get samplesImages => animates;

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefKey);
      final TvAmbientChoice next = raw == TvAmbientChoice.off.name
          ? TvAmbientChoice.off
          : TvAmbientChoice.auto;
      if (next != _choice) {
        _choice = next;
        _publish(force: true);
      }
    } catch (_) {
      // On reste sur Auto.
    }
  }

  Future<void> cycle() => choose(
        _choice == TvAmbientChoice.auto
            ? TvAmbientChoice.off
            : TvAmbientChoice.auto,
      );

  Future<void> choose(TvAmbientChoice choice) async {
    final bool changed = _choice != choice;
    _choice = choice;
    // L'accueil écoute aussi le choix lui-même : sans chaîne en cours,
    // le look reste null mais il faut tout de même éteindre son halo.
    _publish(force: changed);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, choice.name);
    } catch (_) {}
  }

  /// Chaîne affichée. [rgb] est ignoré sous 2 Go.
  void show(ChannelGenre genre, {List<int>? rgb}) {
    _genre = genre;
    _rgb = rgb;
    _publish();
  }

  /// Catégorie du guide, si elle dit film ou sport plus nettement
  /// que le groupe de la chaîne.
  void noteEpg(String? category) {
    _epgCategory = category;
    _publish();
  }

  /// On a quitté le contenu : retour au soir.
  void clear() {
    _genre = null;
    _epgCategory = null;
    _rgb = null;
    _publish();
  }

  void debugReset() {
    _choice = TvAmbientChoice.auto;
    clear();
  }

  void _publish({bool force = false}) {
    final TvAmbientLook? next = _resolve();
    if (!force && next == _look) return;
    _look = next;
    notifyListeners();
  }

  TvAmbientLook? _resolve() {
    if (_choice == TvAmbientChoice.off || _genre == null) return null;
    final TvComfortPalette evening =
        TvComfortPalette.of(TvComfortPeriod.evening);
    final TvAmbientMood mood = TvAmbientMath.moodFor(_genre!, _epgCategory);
    final Color seed = (_rgb != null && samplesImages)
        ? TvAmbientMath.averageRgb(_rgb!)
        : TvTokens.accent;
    return TvAmbientMath.look(mood: mood, seed: seed, evening: evening);
  }
}
