// =========================================================
//  program_reminder_repository.dart — Mémoire locale des rappels
// =========================================================
//  SharedPreferences (JSON). Survit aux redémarrages et aux mises à jour.
//  N'envoie RIEN au serveur : un rappel est un choix privé de la box.
//
//  Les notifications Android sont posées À CÔTÉ, par l'écran qui appelle
//  [NotificationService]. Ici on ne fait que se souvenir de la liste, pour
//  que l'accueil et le guide sachent ce qui est déjà coché (et pour pouvoir
//  annuler d'un second appui).
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/program_reminder.dart';

class ProgramReminderRepository extends ChangeNotifier {
  ProgramReminderRepository._();
  static final ProgramReminderRepository instance =
      ProgramReminderRepository._();

  static const String _kKey = 'epg.reminders.v1';

  List<ProgramReminder> _items = <ProgramReminder>[];
  bool _loaded = false;

  List<ProgramReminder> get current =>
      List<ProgramReminder>.unmodifiable(_items);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int now = DateTime.now().millisecondsSinceEpoch;
      _items = ProgramReminderLog.prune(
        ProgramReminderLog.decode(prefs.getString(_kKey)),
        now,
      );
      // On réécrit tout de suite si le nettoyage a retiré des rappels passés :
      // le fichier ne grossit pas avec des émissions d'hier.
      await prefs.setString(_kKey, ProgramReminderLog.encode(_items));
    } catch (e) {
      if (kDebugMode) debugPrint('[Rappels] lecture: $e');
      _items = <ProgramReminder>[];
    }
    _loaded = true;
    notifyListeners();
  }

  bool contains(String channelId, int startMs) =>
      ProgramReminderLog.contains(_items, channelId, startMs);

  List<ProgramReminder> forHome(
    int nowMs, {
    bool Function(String channelId)? channelStillThere,
  }) =>
      ProgramReminderLog.forHome(
        _items,
        nowMs,
        channelStillThere: channelStillThere,
      );

  Future<void> add(ProgramReminder reminder) async {
    await load();
    final int now = DateTime.now().millisecondsSinceEpoch;
    _items = ProgramReminderLog.upsert(_items, reminder, now);
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String channelId, int startMs) async {
    await load();
    _items = ProgramReminderLog.without(_items, channelId, startMs);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, ProgramReminderLog.encode(_items));
    } catch (e) {
      if (kDebugMode) debugPrint('[Rappels] écriture: $e');
    }
  }
}
