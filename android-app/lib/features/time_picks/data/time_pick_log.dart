// =========================================================
//  time_pick_log.dart — Carnet local, un par profil
// =========================================================
//  Séparé de l'historique « récemment regardées » : on ne
//  change pas cette table. Ici on ne garde qu'un compteur
//  par créneau, dans SharedPreferences, sous la clé du
//  profil en cours.
//
//  Une erreur de disque ne remonte pas : la chaîne continue.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/flavor/flavor.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/domain/family_profile.dart';
import '../domain/time_picks.dart';
import 'time_pick_flag.dart';

class TimePickLog {
  TimePickLog._();
  static final TimePickLog instance = TimePickLog._();

  Map<String, Map<String, int>> _book = <String, Map<String, int>>{};
  String _profile = '';
  bool _ready = false;
  bool _listening = false;
  int _gen = 0;

  /// Change quand le carnet du profil en cours change.
  final ValueNotifier<int> listenable = ValueNotifier<int>(0);

  void _listen() {
    if (_listening) return;
    _listening = true;
    ActiveProfile.instance.listenable.addListener(_onProfile);
  }

  void _onProfile() {
    unawaited(reload());
  }

  /// Recharge le tiroir du profil affiché.
  Future<void> reload() async {
    _listen();
    final int gen = ++_gen;
    final String id = ActiveProfile.instance.id;
    Map<String, Map<String, int>> book = <String, Map<String, int>>{};
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      book = decodeTimePicks(prefs.getString(ProfileKeys.timePicks(id)));
    } catch (e) {
      if (kDebugMode) debugPrint('[Heure] lecture : $e');
    }
    if (gen != _gen || id != ActiveProfile.instance.id) return;
    _profile = id;
    _book = book;
    _ready = true;
    listenable.value++;
  }

  /// Ids du créneau actuel, les plus vus d'abord. Vide si le
  /// carnet n'est pas encore lu, ou si ce créneau n'a rien.
  List<String> idsNow({DateTime? now, int max = kTimePickMax}) {
    if (!_ready) return const <String>[];
    return picksForSlot(_book, timeSlotKey(now ?? DateTime.now()), max: max);
  }

  /// Note qu'on a ouvert [channelId]. Ne bloque pas l'image :
  /// l'appelant n'attend pas, et une erreur est avalée ici.
  Future<void> note(String channelId, {DateTime? now}) async {
    try {
      await timePicksFlag.load();
      if (!timePicksFlag.value) return;
      if (_adultOnly) return;
      if (channelId.isEmpty) return;
      if (!_ready || _profile != ActiveProfile.instance.id) {
        await reload();
      }
      if (!_ready || ActiveProfile.instance.id != _profile) return;
      final String slot = timeSlotKey(now ?? DateTime.now());
      _book = noteTimePick(_book, slot, channelId);
      listenable.value++;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (ActiveProfile.instance.id != _profile) return;
      await prefs.setString(ProfileKeys.timePicks(_profile), encodeTimePicks(_book));
    } catch (e) {
      if (kDebugMode) debugPrint('[Heure] note : $e');
    }
  }

  bool get _adultOnly {
    try {
      return FlavorConfig.current.adultOnly;
    } catch (_) {
      return false;
    }
  }
}
