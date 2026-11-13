// =========================================================
//  own_list.dart — Une liste ajoutée à la main appartient au
//  profil qui l'ajoute
// =========================================================
//  « 10 profils = 10 listes de serveurs différents » : quand
//  quelqu'un ajoute une liste depuis SON profil, elle s'allume
//  chez lui et reste éteinte chez les autres. Chacun peut la
//  rallumer dans Réglages → Sources de son propre profil.
//
//  Un seul profil sur la box : rien ne change.
//  Les listes envoyées par le panel ne passent pas par ici :
//  elles restent allumées pour toute la maison.
// =========================================================

import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/playlist.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/domain/family_profile.dart';

/// Attend la fin de l'ajout [adding], puis réserve la liste au
/// profil en cours. Renvoie la liste telle qu'elle a été ajoutée.
Future<Playlist> ownedByActiveProfile(Future<Playlist> adding) async {
  // Le profil est noté AVANT l'attente : un import peut durer, et
  // la liste appartient à celui qui a lancé l'ajout.
  final String owner = ActiveProfile.instance.id;
  final Playlist saved = await adding;
  final int? id = saved.id;
  if (id == null) return saved;
  final List<String> others = <String>[
    for (final FamilyProfile p in ProfileRepository.instance.catalog.profiles)
      if (p.id != owner) p.id,
  ];
  if (others.isEmpty) return saved;
  await PlaylistRepository.instance
      .reserveForProfile(id, owner: owner, others: others);
  return saved;
}
