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

import '../../profiles/data/active_profile.dart';
import '../../profiles/domain/family_profile.dart';
import '../domain/program_reminder.dart';

class ProgramReminderRepository extends ChangeNotifier {
  ProgramReminderRepository._();
  static final ProgramReminderRepository instance =
      ProgramReminderRepository._();

  /// Ancienne liste unique, avant les profils. On la copie UNE FOIS
  /// dans le carnet du profil 1, puis on n'y touche plus.
  static const String _kLegacy = 'epg.reminders.v1';
  static const String _kLegacyCopied = 'profiles.migration.epg_reminders.v1';

  List<ProgramReminder> _items = <ProgramReminder>[];
  String _profileId = ProfileIds.origin;
  bool _loaded = false;
  bool _listening = false;

  List<ProgramReminder> get current =>
      List<ProgramReminder>.unmodifiable(_items);
  bool get isLoaded => _loaded;

  String get _key => ProfileKeys.reminders(_profileId);

  void _listen() {
    if (_listening) return;
    _listening = true;
    ActiveProfile.instance.listenable.addListener(() {
      _loaded = false;
      load();
    });
  }

  Future<void> load() async {
    _listen();
    final String id = ActiveProfile.instance.id;
    if (_loaded && _profileId == id) return;
    _profileId = id;
    final String key = ProfileKeys.reminders(id);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (ProfileKeys.isOrigin(id) && prefs.getBool(_kLegacyCopied) != true) {
        final String? book = prefs.getString(key);
        final String? legacy = prefs.getString(_kLegacy);
        if ((book == null || book.isEmpty || book == '[]') &&
            legacy != null &&
            legacy.isNotEmpty &&
            legacy != '[]') {
          await prefs.setString(key, legacy);
        }
        await prefs.setBool(_kLegacyCopied, true);
      }
      if (id != ActiveProfile.instance.id) return;
      final int now = DateTime.now().millisecondsSinceEpoch;
      _items = ProgramReminderLog.prune(
        ProgramReminderLog.decode(prefs.getString(key)),
        now,
      );
      await prefs.setString(key, ProgramReminderLog.encode(_items));
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
      await prefs.setString(_key, ProgramReminderLog.encode(_items));
    } catch (e) {
      if (kDebugMode) debugPrint('[Rappels] écriture: $e');
    }
  }
}
