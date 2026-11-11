// =========================================================
//  profile_repository.dart — Profils sur le disque
// =========================================================
//  Enregistre le catalogue (qui existe, qui est actif, est-ce
//  qu'on demande au démarrage). Le chargement est court et
//  borné par l'appelant. Sur ZUNO, un profil non confirmé conserve
//  la barrière parentale fermée ; le budget ne valide pas le profil 1.
//
//  Supprimer un profil efface SON tiroir seulement. Le profil 1
//  ne se supprime pas, et ses clés historiques non plus.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/app/app_platform.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../cinema/data/watch_progress.dart';
import '../../playlists/data/favorites_repository.dart';
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
  bool _confirmed = false;
  bool loadFailed = false;

  bool get activeProfileConfirmed => _ready && _confirmed && !loadFailed;

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
      final String? raw = prefs.getString(ProfileKeys.catalog);
      _confirmed = !AppPlatform.isZuno || ProfileCatalog.confirmsActiveProfile(raw);
      loadFailed = !_confirmed;
      _catalog = ProfileCatalog.decode(raw);
    } catch (e) {
      _confirmed = false;
      loadFailed = true;
      if (kDebugMode) debugPrint('[Profils] lecture impossible : $e');
      _catalog = ProfileCatalog.fresh();
    }
    _publishActiveScope();
    _ready = true;
    notifyListeners();
  }

  /// Nouvelle lecture explicite après erreur, sans effacer les préférences.
  Future<void> retryProtectedRead() {
    if (!activeProfileConfirmed) _loading = null;
    return load();
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

  /// Le propriétaire est capturé par le formulaire AVANT ses attentes.
  /// Le résultat ne change pas de profil si l'utilisateur bascule pendant
  /// le téléchargement, et ne ressuscite pas un profil supprimé.
  Future<bool> attachPlaylist(String profileId, int playlistId) async {
    await load();
    final ProfileCatalog? next = _catalog.attachPlaylist(profileId, playlistId);
    return _saveSourceScope(next);
  }

  Future<bool> detachPlaylist(String profileId, int playlistId) async {
    await load();
    final ProfileCatalog? next = _catalog.detachPlaylist(profileId, playlistId);
    return _saveSourceScope(next);
  }

  Future<bool> _saveSourceScope(ProfileCatalog? next) async {
    if (next == null) return false;
    if (identical(next, _catalog)) return true;
    final ProfileCatalog before = _catalog;
    _catalog = next;
    final bool saved = await _persist();
    // Une erreur disque ne doit pas annoncer une association durable. Si
    // un autre geste a eu lieu pendant l'écriture, ne pas l'écraser non plus.
    if (!saved && identical(_catalog, next)) _catalog = before;
    _publishActiveScope();
    notifyListeners();
    return saved;
  }

  void _publishActiveScope() => ActiveProfile.instance.set(
        _catalog.activeId,
        playlistIds: _catalog.active.playlistIds,
      );

  @visibleForTesting
  void resetForTesting(ProfileCatalog catalog, {bool loaded = true}) {
    _catalog = catalog;
    _ready = loaded;
    _confirmed = loaded;
    loadFailed = false;
    _loading = loaded ? Future<void>.value() : null;
    _publishActiveScope();
    notifyListeners();
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
    _publishActiveScope();
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
    _publishActiveScope();
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

  Future<bool> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return await prefs.setString(ProfileKeys.catalog, _catalog.encode());
    } catch (e) {
      if (kDebugMode) debugPrint('[Profils] écriture impossible : $e');
      return false;
    }
  }

  /// Efface le tiroir d'un profil qui n'est PAS le profil 1.
  /// Les chaînes ne sont pas concernées.
  Future<void> _wipe(String id) async {
    if (ProfileKeys.disposableKeys(id).isEmpty) return;
    await FavoritesRepository.instance.dropProfile(id);
    await RecentlyWatchedRepository.instance.dropProfile(id);
    await WatchProgressRepository.instance.dropProfile(id);
    await NotificationService.instance.dropBook(id);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
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
}
