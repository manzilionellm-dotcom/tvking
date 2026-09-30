// =========================================================
//  family_profile.dart — Un membre de la maison
// =========================================================
//  « Maison » est le profil d'origine : ses favoris et son
//  historique sont ceux déjà enregistrés. Les autres profils
//  ont leurs propres listes. Un profil enfant allume le mode
//  enfants. Rien ici n'ouvre une chaîne.
// =========================================================

import 'dart:convert';

class FamilyProfile {
  const FamilyProfile({
    required this.id,
    required this.name,
    required this.child,
  });

  /// Profil d'origine. Son id ne change pas : les données déjà
  /// sur la box (SQLite) restent les siennes.
  static const String homeId = 'maison';

  final String id;
  final String name;
  final bool child;

  bool get isHome => id == homeId;

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'name': name,
        'child': child,
      };

  static FamilyProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'];
    final Object? name = raw['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    if (id == homeId) return null;
    return FamilyProfile(
      id: id,
      name: name.trim(),
      child: raw['child'] == true,
    );
  }
}

const FamilyProfile kHomeProfile = FamilyProfile(
  id: FamilyProfile.homeId,
  name: 'Maison',
  child: false,
);

/// Décode la liste. « Maison » est toujours en premier.
/// Un texte cassé ne donne que Maison : on ne perd pas l'accueil.
List<FamilyProfile> decodeProfiles(String? raw) {
  final List<FamilyProfile> out = <FamilyProfile>[kHomeProfile];
  if (raw == null || raw.isEmpty) return out;
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return out;
    final Set<String> seen = <String>{FamilyProfile.homeId};
    for (final Object? item in decoded) {
      final FamilyProfile? profile = FamilyProfile.fromJson(item);
      if (profile == null || !seen.add(profile.id)) continue;
      out.add(profile);
      if (out.length >= 6) break;
    }
  } catch (_) {
    return <FamilyProfile>[kHomeProfile];
  }
  return out;
}

String encodeProfiles(List<FamilyProfile> profiles) {
  final List<Map<String, Object>> body = <Map<String, Object>>[
    for (final FamilyProfile profile in profiles)
      if (!profile.isHome) profile.toJson(),
  ];
  return jsonEncode(body);
}
