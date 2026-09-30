// =========================================================
//  profile_catalog.dart — La liste des profils (max 4)
// =========================================================
//  Pur Dart : pas de disque, pas d'écran. Le dépôt
//  (profile_repository) se charge d'enregistrer le JSON.
//  Ici on décide seulement ce qui est AUTORISÉ :
//    • 4 profils grand maximum ;
//    • un seul profil Enfants (il doit rester lisible) ;
//    • on ne supprime JAMAIS le profil 1 (ses données sont
//      les anciennes données de la box) ;
//    • on ne supprime pas le dernier profil restant.
// =========================================================

import 'dart:convert';

import 'family_profile.dart';

class ProfileCatalog {
  const ProfileCatalog({
    required this.profiles,
    required this.activeId,
    required this.askOnStartup,
  });

  static const int maxProfiles = 4;

  final List<FamilyProfile> profiles;

  /// Profil affiché en ce moment. Toujours un id de [profiles].
  final String activeId;

  /// `null`  → on demande au démarrage dès qu'il y a 2 profils.
  /// `true`  → pareil (choix explicite).
  /// `false` → on ne demande jamais (démarrage direct).
  final bool? askOnStartup;

  FamilyProfile get active => byId(activeId) ?? profiles.first;

  bool get hasKids => profiles.any((FamilyProfile p) => p.isKids);

  bool get canAdd => profiles.length < maxProfiles;

  FamilyProfile? byId(String id) {
    for (final FamilyProfile p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Boîte neuve, ou catalogue illisible : un seul profil,
  /// celui qui porte déjà les données.
  static ProfileCatalog fresh({int nowMs = 0}) => ProfileCatalog(
        profiles: <FamilyProfile>[FamilyProfile.origin(nowMs: nowMs)],
        activeId: ProfileIds.origin,
        askOnStartup: null,
      );

  /// Ajoute un profil. `null` si c'est refusé (déjà 4, ou un
  /// deuxième profil Enfants, ou un nom vide / trop long).
  ProfileCatalog? add({
    required String name,
    required bool isKids,
    required int nowMs,
  }) {
    if (!canAdd) return null;
    if (isKids && hasKids) return null;
    final String trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 18) return null;
    final FamilyProfile created = FamilyProfile(
      id: _freshId(nowMs),
      name: trimmed,
      avatar: profiles.length % FamilyProfile.avatarCount,
      isKids: isKids,
      createdAtMs: nowMs,
    );
    return ProfileCatalog(
      profiles: <FamilyProfile>[...profiles, created],
      activeId: activeId,
      askOnStartup: askOnStartup,
    );
  }

  ProfileCatalog? rename(String id, String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 18) return null;
    if (byId(id) == null) return null;
    return ProfileCatalog(
      profiles: <FamilyProfile>[
        for (final FamilyProfile p in profiles)
          if (p.id == id) p.copyWith(name: trimmed) else p,
      ],
      activeId: activeId,
      askOnStartup: askOnStartup,
    );
  }

  /// `null` si l'id n'existe pas. Le même catalogue si c'est
  /// déjà le profil actif (rien à changer).
  ProfileCatalog? activate(String id) {
    if (byId(id) == null) return null;
    if (id == activeId) return this;
    return ProfileCatalog(
      profiles: profiles,
      activeId: id,
      askOnStartup: askOnStartup,
    );
  }

  /// Refuse le profil d'origine et le dernier profil.
  /// Si on retire le profil actif, on revient au profil 1.
  ProfileCatalog? remove(String id) {
    if (id == ProfileIds.origin) return null;
    if (profiles.length <= 1) return null;
    if (byId(id) == null) return null;
    final List<FamilyProfile> kept = profiles
        .where((FamilyProfile p) => p.id != id)
        .toList(growable: false);
    final String nextActive =
        kept.any((FamilyProfile p) => p.id == activeId) ? activeId : ProfileIds.origin;
    return ProfileCatalog(
      profiles: kept,
      activeId: kept.any((FamilyProfile p) => p.id == nextActive)
          ? nextActive
          : kept.first.id,
      askOnStartup: askOnStartup,
    );
  }

  ProfileCatalog withAsk(bool? value) => ProfileCatalog(
        profiles: profiles,
        activeId: activeId,
        askOnStartup: value,
      );

  String encode() => jsonEncode(<String, Object?>{
        'activeId': activeId,
        'profiles': profiles.map((FamilyProfile p) => p.toJson()).toList(),
        if (askOnStartup != null) 'askOnStartup': askOnStartup,
      });

  /// Lit le JSON. Si c'est vide, cassé, ou sans profil 1 :
  /// on REPARE sans rien jeter.
  ///
  ///   • pas de profil 1 → on l'ajoute en tête (ses données
  ///     disque existent peut-être déjà) ;
  ///   • plus de 4 lignes → on n'en montre que 4, en gardant
  ///     toujours le profil 1. Les autres restent sur le disque
  ///     (on n'efface pas leurs clés ici) ;
  ///   • id actif inconnu → profil 1.
  static ProfileCatalog decode(String? raw, {int nowMs = 0}) {
    if (raw == null || raw.trim().isEmpty) return fresh(nowMs: nowMs);
    try {
      final Object? json = jsonDecode(raw);
      if (json is! Map) return fresh(nowMs: nowMs);
      final List<FamilyProfile> parsed = <FamilyProfile>[];
      final Object? list = json['profiles'];
      if (list is List) {
        for (final Object? item in list) {
          final FamilyProfile? p = FamilyProfile.fromJson(item);
          if (p == null) continue;
          if (parsed.any((FamilyProfile e) => e.id == p.id)) continue;
          parsed.add(p);
        }
      }
      List<FamilyProfile> kept = parsed;
      if (!kept.any((FamilyProfile p) => p.id == ProfileIds.origin)) {
        kept = <FamilyProfile>[FamilyProfile.origin(nowMs: nowMs), ...kept];
      }
      if (kept.length > maxProfiles) {
        final FamilyProfile origin =
            kept.firstWhere((FamilyProfile p) => p.id == ProfileIds.origin);
        final List<FamilyProfile> others = kept
            .where((FamilyProfile p) => p.id != origin.id)
            .take(maxProfiles - 1)
            .toList(growable: false);
        kept = <FamilyProfile>[origin, ...others];
      }
      if (kept.isEmpty) return fresh(nowMs: nowMs);
      final String wanted = json['activeId']?.toString() ?? ProfileIds.origin;
      final String active =
          kept.any((FamilyProfile p) => p.id == wanted) ? wanted : ProfileIds.origin;
      bool? ask;
      final Object? askRaw = json['askOnStartup'];
      if (askRaw is bool) ask = askRaw;
      return ProfileCatalog(profiles: kept, activeId: active, askOnStartup: ask);
    } catch (_) {
      // JSON cassé : on repart sur Profil 1. Les tiroirs
      // (favoris, reprise…) ne sont PAS dans ce JSON, donc
      // ils restent sur le disque.
      return fresh(nowMs: nowMs);
    }
  }

  String _freshId(int nowMs) {
    final Set<String> taken = profiles.map((FamilyProfile p) => p.id).toSet();
    for (int i = 0; i < 20; i++) {
      final String id = 'p${nowMs}_$i';
      if (id != ProfileIds.origin && !taken.contains(id)) return id;
    }
    return 'p${nowMs}_${profiles.length}';
  }
}
