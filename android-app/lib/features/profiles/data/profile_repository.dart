// =========================================================
//  profile_repository.dart — Profils sur le disque
// =========================================================
//  Enregistre le catalogue (qui existe, qui est actif, est-ce
//  qu'on demande au démarrage). L'identité est chargée avant
//  les sources : l'écran ne reçoit jamais le catalogue d'un
//  autre profil en attendant la lecture du disque.
//
//  Supprimer un profil efface SON tiroir seulement. Le profil 1
//  ne se supprime pas, et ses clés historiques non plus.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_service.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../cinema/data/watch_progress.dart';
import '../../cinema/data/cinema_repository.dart';
import '../../epg/data/epg_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../vod/data/download_repository.dart';
import '../domain/family_profile.dart';
import '../domain/profile_catalog.dart';
import '../domain/profile_policies.dart';
import 'active_profile.dart';

class ProfileRepository extends ChangeNotifier {
  ProfileRepository._();
  static final ProfileRepository instance = ProfileRepository._();

  ProfileCatalog _catalog = ProfileCatalog.fresh();
  Future<void>? _loading;
  bool _ready = false;

  bool get isReady => _ready;
  ProfileCatalog get catalog => _catalog;
  FamilyProfile get active => _catalog.active;
  bool get activeIsKids => active.isKids;

  FamilyProfile? profileById(String id) => _catalog.byId(id);

  /// Idempotent. Plusieurs écrans peuvent l'appeler : un seul
  /// passage disque.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _catalog = ProfileCatalog.decode(prefs.getString(ProfileKeys.catalog));
    } catch (e) {
      if (kDebugMode) debugPrint('[Profils] lecture impossible : $e');
      _catalog = ProfileCatalog.fresh();
    }
    ActiveProfile.instance.set(_catalog.activeId);
    await _reloadScopedData();
    _ready = true;
    notifyListeners();
  }

  Future<FamilyProfile?> addProfile({
    required String name,
    required bool isKids,
  }) async {
    await load();
    final ProfileCatalog? next = _catalog.add(
      name: name,
      isKids: isKids,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (next == null) return null;
    _catalog = next;
    await _persist();
    notifyListeners();
    return next.profiles.last;
  }

  Future<bool> rename(String id, String name) async {
    await load();
    final ProfileCatalog? next = _catalog.rename(id, name);
    if (next == null) return false;
    _catalog = next;
    await _persist();
    notifyListeners();
    return true;
  }

  /// [leaveAllowed] doit être vrai pour QUITTER un profil Enfants.
  /// L'écran le met à vrai seulement après le bon code. Entrer
  /// dans le profil Enfants ne demande rien.
  Future<bool> activate(String id, {required bool leaveAllowed}) async {
    await load();
    final FamilyProfile current = _catalog.active;
    if (KidsProfilePolicy.mustConfirmLeave(
          currentIsKids: current.isKids,
          currentId: current.id,
          nextId: id,
        ) &&
        !leaveAllowed) {
      return false;
    }
    final ProfileCatalog? next = _catalog.activate(id);
    if (next == null) return false;
    _catalog = next;
    ActiveProfile.instance.set(next.activeId);
    await _reloadScopedData();
    await _persist();
    notifyListeners();
    return true;
  }

  /// Refuse le profil 1. Si on supprime le profil Enfants alors
  /// qu'on EST dessus, [leaveAllowed] doit venir d'un code juste.
  Future<bool> remove(String id, {required bool leaveAllowed}) async {
    await load();
    if (id == ProfileIds.origin) return false;
    final bool leavingThis = _catalog.activeId == id && _catalog.active.isKids;
    if (leavingThis && !leaveAllowed) return false;
    final ProfileCatalog? next = _catalog.remove(id);
    if (next == null) return false;
    _catalog = next;
    ActiveProfile.instance.set(next.activeId);
    await _reloadScopedData();
    await _persist();
    await _wipe(id);
    notifyListeners();
    return true;
  }

  /// `false` = ne plus demander au démarrage (ouverture directe).
  Future<void> setAskOnStartup(bool value) async {
    await load();
    _catalog = _catalog.withAsk(value);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(ProfileKeys.catalog, _catalog.encode());
    } catch (e) {
      if (kDebugMode) debugPrint('[Profils] écriture impossible : $e');
    }
  }

  /// Efface uniquement les sources et données du profil supprimé.
  Future<void> _wipe(String id) async {
    if (ProfileKeys.disposableKeys(id).isEmpty) return;
    await PlaylistRepository.instance.dropProfile(id);
    await EpgRepository.instance.dropProfile(id);
    await DownloadsRepository.instance.dropProfile(id);
    await FavoritesRepository.instance.dropProfile(id);
    await RecentlyWatchedRepository.instance.dropProfile(id);
    await WatchProgressRepository.instance.dropProfile(id);
    await NotificationService.instance.dropBook(id);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('novatube.adult.enabled.$id');
      for (final String key in ProfileKeys.disposableKeys(id)) {
        if (key == ProfileKeys.pin(id) ||
            key == ProfileKeys.kidsMode(id) ||
            key == ProfileKeys.timePicks(id) ||
            key == ProfileKeys.followed(id)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Profils] nettoyage : $e');
    }
  }

  /// Les observateurs vident déjà leurs snapshots lors du changement d'id.
  /// On attend les lectures locales utiles avant de rendre la main au picker.
  Future<void> _reloadScopedData() async {
    CinemaRepository.instance.changeProfile();
    EpgRepository.instance.profileChanged();
    await PlaylistRepository.instance.reloadForActiveProfile();
    await Future.wait(<Future<void>>[
      FavoritesRepository.instance.reloadForActiveProfile(),
      RecentlyWatchedRepository.instance.reloadForActiveProfile(),
      WatchProgressRepository.instance.load(),
    ]);
  }

  /// Remet seulement le catalogue en mémoire à zéro ; ne supprime ni source,
  /// ni clé, ni historique. Les tests fournissent leurs SharedPreferences.
  @visibleForTesting
  Future<void> resetForTesting() async {
    if (_loading != null) await _loading;
    _catalog = ProfileCatalog.fresh();
    _loading = null;
    _ready = false;
    ActiveProfile.instance.set(ProfileIds.origin);
    await _reloadScopedData();
  }
}
