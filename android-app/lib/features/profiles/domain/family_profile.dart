// =========================================================
//  family_profile.dart — Un profil de la maison + ses clés
// =========================================================
//  Jusqu'à 4 personnes (parents, enfants, invité). Chacun a SON
//  tiroir : favoris, historique, reprise de lecture, rappels et
//  code parental. Les chaînes IPTV, elles, restent communes :
//  changer de profil ne retire jamais une chaîne, et ne bloque
//  jamais la lecture.
//
//  MIGRATION DOUCE
//  ---------------
//  Le premier profil s'appelle « Profil 1 » et son id est `p1`.
//  Il relit EXACTEMENT les clés d'avant cette fonctionnalité
//  (code PIN, mode enfants, reprise des films). On ne les copie
//  pas, on ne les renomme pas, on ne les efface jamais. Ainsi
//  une mise à jour ne perd rien : les données déjà là SONT le
//  profil 1. Les profils créés ensuite ont des clés à part.
// =========================================================

/// Identifiants stables. `p1` est réservé au profil d'origine.
abstract final class ProfileIds {
  /// Profil qui hérite des données déjà présentes sur la box.
  static const String origin = 'p1';
}

/// Où chaque tiroir est rangé dans SharedPreferences.
///
/// Pour [ProfileIds.origin] on garde le nom HISTORIQUE de la clé.
/// C'est ça, la migration douce : le fichier n'a pas bougé.
abstract final class ProfileKeys {
  static bool isOrigin(String id) => id == ProfileIds.origin;

  /// Reprise de lecture cinéma (films / épisodes).
  static String watchProgress(String id) =>
      isOrigin(id) ? 'cinema.progress.v1' : 'cinema.progress.v1.$id';

  /// Code parental à 4 chiffres.
  static String pin(String id) =>
      isOrigin(id) ? 'security.app_pin_value' : 'security.app_pin_value.$id';

  /// Interrupteur « Mode Enfants » (masque l'adulte).
  static String kidsMode(String id) =>
      isOrigin(id) ? 'security.kids_mode.v1' : 'security.kids_mode.v1.$id';

  /// Carnet des rappels de programmes (EPG).
  static String reminders(String id) =>
      isOrigin(id) ? 'notif.reminders.book.v1' : 'notif.reminders.book.v1.$id';

  /// Liste des profils + lequel est actif + choix au démarrage.
  static const String catalog = 'profiles.catalog.v1';

  /// Passe à vrai UNE FOIS, quand on a copié l'ancienne table
  /// `favorites` vers le tiroir du profil 1. On ne recopie plus
  /// ensuite : sinon un favori retiré reviendrait tout seul.
  static const String favoritesMigrated = 'profiles.migration.favorites.v1';

  /// Même idée pour l'historique « récemment regardées ».
  static const String historyMigrated = 'profiles.migration.history.v1';

  /// Clés qu'on a le DROIT d'effacer en supprimant [id].
  ///
  /// Le profil d'origine n'en a aucune : ses clés sont celles de
  /// l'app d'avant. Les supprimer ferait disparaître les favoris
  /// de reprise, le code et le mode enfants déjà réglés.
  static List<String> disposableKeys(String id) {
    if (isOrigin(id)) return const <String>[];
    return <String>[
      watchProgress(id),
      pin(id),
      kidsMode(id),
      reminders(id),
    ];
  }
}

/// Une personne de la maison. Objet simple, sans Flutter :
/// facile à tester, et il ne sait pas afficher un bouton.
class FamilyProfile {
  const FamilyProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.isKids,
    required this.createdAtMs,
  });

  /// Nombre de pastilles (couleur + icône) côté écran.
  static const int avatarCount = 6;

  final String id;
  final String name;

  /// 0 … [avatarCount] - 1. L'écran choisit l'icône.
  final int avatar;

  /// Vrai pour le profil Enfants : le mode enfants y est forcé,
  /// et le quitter demande le code de CE profil.
  final bool isKids;

  final int createdAtMs;

  /// Le profil qui reçoit les données déjà sur la box.
  factory FamilyProfile.origin({int nowMs = 0}) => FamilyProfile(
        id: ProfileIds.origin,
        name: 'Profil 1',
        avatar: 0,
        isKids: false,
        createdAtMs: nowMs,
      );

  FamilyProfile copyWith({String? name, int? avatar, bool? isKids}) =>
      FamilyProfile(
        id: id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        isKids: isKids ?? this.isKids,
        createdAtMs: createdAtMs,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'avatar': avatar,
        'isKids': isKids,
        'createdAt': createdAtMs,
      };

  /// `null` si la ligne est inutilisable (id vide, caractères
  /// bizarres). Un catalogue abîmé ne doit pas faire planter
  /// le démarrage : on ignore la ligne, on ne jette pas le reste.
  static FamilyProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String id = raw['id']?.toString() ?? '';
    if (!_safeId(id)) return null;
    String name = (raw['name']?.toString() ?? '').trim();
    if (name.isEmpty) {
      name = id == ProfileIds.origin ? 'Profil 1' : 'Profil';
    }
    if (name.length > 18) name = name.substring(0, 18);
    final int avatar = (raw['avatar'] as num?)?.toInt() ?? 0;
    final int created = (raw['createdAt'] as num?)?.toInt() ?? 0;
    return FamilyProfile(
      id: id,
      name: name,
      avatar: avatar < 0 ? 0 : (avatar >= avatarCount ? avatarCount - 1 : avatar),
      isKids: raw['isKids'] == true,
      createdAtMs: created < 0 ? 0 : created,
    );
  }

  static bool _safeId(String id) =>
      id.isNotEmpty && id.length <= 40 && RegExp(r'^[A-Za-z0-9_]+$').hasMatch(id);
}
