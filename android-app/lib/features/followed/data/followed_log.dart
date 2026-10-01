// =========================================================
//  followed_log.dart — Carnet local, un par profil
// =========================================================
//  Temps regardé, habitude jour/heure, épingle « Suivre »,
//  et les rappels déjà montrés. SharedPreferences, clé du
//  profil en cours. Aucun envoi.
//
//  Une erreur de disque ne remonte pas : la chaîne continue.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/flavor/flavor.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/domain/family_profile.dart';
import '../domain/show_taste.dart';
import '../domain/show_title.dart';
import 'followed_flag.dart';

class FollowedLog {
  FollowedLog._();
  static final FollowedLog instance = FollowedLog._();

  ShowBook _book = ShowBook.empty;
  String _profile = '';
  bool _ready = false;
  bool _listening = false;
  int _gen = 0;

  /// Change quand le carnet du profil en cours change.
  final ValueNotifier<int> listenable = ValueNotifier<int>(0);

  ShowBook get book => _book;

  Set<String> get seen => _book.seen.toSet();

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
    ShowBook book = ShowBook.empty;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      book = decodeShowBook(prefs.getString(ProfileKeys.followed(id)));
    } catch (e) {
      if (kDebugMode) debugPrint('[Suivi] lecture : $e');
    }
    if (gen != _gen || id != ActiveProfile.instance.id) return;
    _profile = id;
    _book = book;
    _ready = true;
    listenable.value++;
  }

  bool isFollowing(String title, Set<String> favoriteIds) {
    if (!_ready) return false;
    final String key = showKey(title);
    final ShowTaste? taste = _book.shows[key];
    if (taste == null) return false;
    return isFollowed(taste, favoriteIds);
  }

  /// Note une minute d'image. N'attend pas l'écran : l'appelant
  /// peut ignorer le Future. Coupé, ou édition adulte : on
  /// n'écrit rien.
  Future<void> note({
    required String title,
    required String channelId,
    required int addMs,
    required bool channelFavorite,
    DateTime? wall,
    int? nowMs,
  }) async {
    try {
      await followedFlag.load();
      if (!followedFlag.value) return;
      if (_adultOnly) return;
      await _readyBook();
      if (!_ready || ActiveProfile.instance.id != _profile) return;
      final DateTime when = wall ?? DateTime.now();
      final int now = nowMs ?? when.millisecondsSinceEpoch;
      final ShowBook next = addWatch(
        _book,
        title: title,
        channelId: channelId,
        addMs: addMs,
        wall: when,
        nowMs: now,
        channelFavorite: channelFavorite,
      );
      if (identical(next, _book)) return;
      await _save(next);
    } catch (e) {
      if (kDebugMode) debugPrint('[Suivi] note : $e');
    }
  }

  /// Bascule l'épingle. Renvoie vrai si l'émission est épinglée
  /// APRÈS le geste. Faux si le titre est vide ou si c'est coupé.
  Future<bool> togglePin({
    required String title,
    required String channelId,
    int? nowMs,
  }) async {
    try {
      await followedFlag.load();
      if (!followedFlag.value) return false;
      await _readyBook();
      if (!_ready || ActiveProfile.instance.id != _profile) return false;
      final String key = showKey(title);
      final bool was = _book.shows[key]?.pinned ?? false;
      final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      final ShowBook next = setPinned(
        _book,
        title: title,
        channelId: channelId,
        nowMs: now,
        pinned: !was,
      );
      await _save(next);
      return _book.shows[key]?.pinned ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('[Suivi] épingle : $e');
      return false;
    }
  }

  /// Le bandeau a été montré. On ne le remontera pas pour
  /// ce moment-là de cette diffusion.
  Future<void> markSeen(String alertKey, {int? nowMs}) async {
    try {
      if (alertKey.isEmpty || _book.seen.contains(alertKey)) return;
      await _readyBook();
      if (!_ready || ActiveProfile.instance.id != _profile) return;
      final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      final ShowBook next = rememberAlert(_book, alertKey, now);
      if (identical(next, _book)) return;
      await _save(next);
    } catch (e) {
      if (kDebugMode) debugPrint('[Suivi] rappel : $e');
    }
  }

  Future<void> _readyBook() async {
    if (!_ready || _profile != ActiveProfile.instance.id) {
      await reload();
    }
  }

  Future<void> _save(ShowBook next) async {
    _book = next;
    listenable.value++;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (ActiveProfile.instance.id != _profile) return;
    await prefs.setString(
        ProfileKeys.followed(_profile), encodeShowBook(_book));
  }

  bool get _adultOnly {
    try {
      return FlavorConfig.current.adultOnly;
    } catch (_) {
      return false;
    }
  }
}
