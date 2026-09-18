// =========================================================
//  profiles_repository.dart — Profils famille (façon Netflix)
// =========================================================
//  Chaque membre de la famille a SON profil : ses « Derniers vus » (films),
//  son historique de recherche et ses collections de favoris. Les données
//  par profil sont obtenues en SUFFIXANT les clés de stockage locales
//  (SharedPreferences) : le profil « Famille » (par défaut) garde les clés
//  HISTORIQUES sans suffixe → zéro migration, zéro perte de données.
//
//  ---------------------------------------------------------
//  VAGUE 2 (30/08) — PROFILS PILOTÉS PAR LE PANEL
//  ---------------------------------------------------------
//  Demande du propriétaire : une seule source M3U collée dans le panel,
//  et le système génère CINQ profils indépendants (papa, maman, trois
//  enfants), chacun avec son PIN, sa liste de chaînes, son historique,
//  activable ou désactivable à distance, avec contrôle parental par
//  profil.
//
//  Ce que ça change ici :
//
//   • un profil porte désormais un PIN, un interrupteur `enabled`, un
//     mode enfant et une liste de catégories bloquées ;
//   • les profils peuvent venir du SERVEUR (`managed: true`). Ceux-là
//     ne sont ni modifiables ni supprimables depuis l'appareil : c'est
//     le panel qui décide, et un client ne doit pas pouvoir contourner
//     le contrôle parental en supprimant le profil qui le porte ;
//   • les profils créés À LA MAIN sur l'appareil continuent d'exister
//     et restent modifiables. Les deux mondes cohabitent.
//
//  LE PIN N'EST PAS STOCKÉ EN CLAIR ICI. Le serveur envoie une empreinte
//  salée (voir `ProfilePin`), jamais le code lui-même. Un vidage des
//  préférences de l'app ne révèle donc aucun code.
//
//  STABILITÉ : aucune interaction avec le lecteur vidéo ni l'écran
//  Direct. Un profil qui n'a ni PIN ni restriction se comporte
//  exactement comme avant.
// =========================================================
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../observability/structured_logger.dart';

/// Empreinte d'un PIN de profil.
///
///  POURQUOI UNE EMPREINTE ET PAS LE CODE. Le panel envoie les profils à
///  l'appareil ; si le PIN voyageait et se stockait en clair, il suffirait
///  de lire les préférences de l'app (ou d'intercepter la réponse) pour
///  contourner le contrôle parental. On transporte donc un HMAC salé :
///  vérifiable, mais non réversible.
///
///  20 000 itérations : assez pour rendre une attaque par dictionnaire sur
///  10 000 combinaisons à 4 chiffres coûteuse, assez peu pour rester
///  instantané sur une box lente. Même réglage que le PIN de l'app, pour
///  n'avoir qu'une seule mécanique à raisonner dans le projet.
@immutable
class ProfilePin {
  const ProfilePin({required this.salt, required this.hash});

  final String salt;
  final String hash;

  static const int _iterations = 20000;

  /// Calcule l'empreinte de [pin] avec [salt]. Utilisée à la vérification
  /// ET par le panel : les deux côtés DOIVENT utiliser la même formule,
  /// sinon aucun PIN ne serait jamais accepté.
  static String derive(String pin, String salt) {
    List<int> acc = utf8.encode('$salt|$pin');
    final Hmac hmac = Hmac(sha256, utf8.encode(salt));
    for (int i = 0; i < _iterations; i++) {
      acc = hmac.convert(acc).bytes;
    }
    return base64Url.encode(acc);
  }

  /// Comparaison à TEMPS CONSTANT. Une comparaison ordinaire s'arrête au
  /// premier caractère différent : le temps de réponse trahirait alors le
  /// nombre de caractères corrects. Sur un PIN à 4 chiffres, c'est
  /// suffisant pour le retrouver bien plus vite qu'en devinant.
  bool matches(String pin) {
    final String candidate = derive(pin, salt);
    if (candidate.length != hash.length) return false;
    int diff = 0;
    for (int i = 0; i < candidate.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ hash.codeUnitAt(i);
    }
    return diff == 0;
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{'salt': salt, 'hash': hash};

  static ProfilePin? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String salt = '${raw['salt'] ?? ''}';
    final String hash = '${raw['hash'] ?? ''}';
    if (salt.isEmpty || hash.isEmpty) return null;
    return ProfilePin(salt: salt, hash: hash);
  }
}

/// Un profil : identité, avatar, et — depuis la vague 2 — ses règles.
@immutable
class TvProfile {
  const TvProfile({
    required this.id,
    required this.name,
    required this.emoji,
    this.pin,
    this.enabled = true,
    this.kids = false,
    this.blockedCategories = const <String>[],
    this.managed = false,
  });

  final String id;
  final String name;
  final String emoji;

  /// Empreinte du PIN. `null` = profil libre d'accès.
  final ProfilePin? pin;

  /// Profil DÉSACTIVÉ à distance par le panel : il reste visible dans la
  /// liste (grisé), mais on ne peut plus le choisir.
  ///
  /// Volontairement visible plutôt que caché : un enfant dont le profil
  /// disparaît croit à une panne et vient réclamer ; un profil grisé dit
  /// clairement « c'est fermé », ce qui est le message voulu.
  final bool enabled;

  /// Mode enfant PROPRE À CE PROFIL : les chaînes classées « adulte »
  /// sont retirées partout. Remplace, pour ce profil, l'interrupteur
  /// global de l'appareil.
  final bool kids;

  /// Catégories masquées pour ce profil, telles que nommées par la
  /// source. Comparaison insensible à la casse et aux accents côté
  /// filtre — un panel ne saisit jamais exactement la même graphie.
  final List<String> blockedCategories;

  /// Profil VENU DU PANEL. Ni modifiable ni supprimable sur l'appareil :
  /// sinon le contrôle parental se contournerait en supprimant le profil
  /// qui le porte.
  final bool managed;

  TvProfile copyWith({
    String? name,
    String? emoji,
    ProfilePin? pin,
    bool? enabled,
    bool? kids,
    List<String>? blockedCategories,
    bool? managed,
  }) =>
      TvProfile(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        pin: pin ?? this.pin,
        enabled: enabled ?? this.enabled,
        kids: kids ?? this.kids,
        blockedCategories: blockedCategories ?? this.blockedCategories,
        managed: managed ?? this.managed,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'emoji': emoji,
        if (pin != null) 'pin': pin!.toJson(),
        'enabled': enabled,
        'kids': kids,
        'blockedCategories': blockedCategories,
        'managed': managed,
      };

  /// Lecture TOLÉRANTE : un champ absent ou d'un type inattendu prend sa
  /// valeur par défaut. Une seule ligne mal formée ne doit jamais faire
  /// disparaître tous les profils — le client se retrouverait sans accès.
  static TvProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String id = '${raw['id'] ?? ''}'.trim();
    final String name = '${raw['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) return null;
    final Object? cats = raw['blockedCategories'];
    return TvProfile(
      id: id,
      name: name,
      emoji: '${raw['emoji'] ?? '👤'}',
      pin: ProfilePin.fromJson(raw['pin']),
      // `!= false` et non `== true` : un champ ABSENT vaut « activé ».
      // Un profil livré sans le champ ne doit pas devenir inaccessible.
      enabled: raw['enabled'] != false,
      kids: raw['kids'] == true,
      blockedCategories: cats is List
          ? cats.map((Object? c) => '$c').where((String c) => c.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      managed: raw['managed'] == true,
    );
  }
}

class ProfilesRepository extends ChangeNotifier {
  ProfilesRepository._();
  static final ProfilesRepository instance = ProfilesRepository._();

  static const String _kList = 'tv_profiles';
  static const String _kActive = 'tv_profile_active';
  static const String _kManaged = 'tv_profiles_managed.v1';

  /// 12 au lieu de 6 : le panel en génère 5 (papa, maman, trois enfants),
  /// et il restait exactement 5 places à côté de « Famille ». Zéro marge
  /// signifiait qu'un profil créé à la main faisait échouer en silence la
  /// génération du panel.
  static const int maxProfiles = 12;

  /// Le profil par défaut : conserve les clés historiques (pas de suffixe).
  static const TvProfile familyProfile =
      TvProfile(id: 'default', name: 'Famille', emoji: '🏠');

  List<TvProfile> _extras = <TvProfile>[];
  List<TvProfile> _managed = <TvProfile>[];
  String _activeId = familyProfile.id;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Tous les profils : « Famille », puis ceux du PANEL, puis les locaux.
  /// Les profils du panel passent devant : ce sont ceux que la famille
  /// utilise au quotidien, ils doivent être les premiers sous le pouce.
  List<TvProfile> get profiles =>
      <TvProfile>[familyProfile, ..._managed, ..._extras];

  /// Ceux qu'on peut réellement choisir. Un profil désactivé par le panel
  /// reste dans [profiles] (affiché grisé) mais sort d'ici.
  List<TvProfile> get selectable =>
      profiles.where((TvProfile p) => p.enabled).toList(growable: false);

  TvProfile get active => profiles.firstWhere(
        (TvProfile p) => p.id == _activeId,
        orElse: () => familyProfile,
      );

  /// Suffixe à AJOUTER aux clés SharedPreferences des données par profil.
  /// Vide pour « Famille » (compatibilité avec les données existantes).
  String get keySuffix =>
      _activeId == familyProfile.id ? '' : '.$_activeId';

  /// Le mode enfant EFFECTIF du moment : celui du profil actif.
  /// L'interrupteur global de l'appareil reste le repli pour « Famille »
  /// et pour les profils créés à la main, qui n'ont pas de règle propre.
  bool get activeIsKids => active.kids;

  /// Catégories masquées pour le profil actif.
  List<String> get activeBlockedCategories => active.blockedCategories;

  TvProfile? byId(String id) {
    for (final TvProfile p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  TvProfile? byName(String name) {
    for (final TvProfile p in profiles) {
      if (p.name == name) return p;
    }
    return null;
  }

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _extras = _decode(prefs.getString(_kList) ?? '[]');
      _managed = _decode(prefs.getString(_kManaged) ?? '[]')
          .map((TvProfile p) => p.copyWith(managed: true))
          .toList(growable: true);
      _activeId = prefs.getString(_kActive) ?? familyProfile.id;
      // Le profil mémorisé a pu être DÉSACTIVÉ par le panel entre deux
      // ouvertures. On retombe sur « Famille » plutôt que de démarrer sur
      // un profil qu'on n'a plus le droit d'utiliser.
      final TvProfile? current = byId(_activeId);
      if (current == null || !current.enabled) _activeId = familyProfile.id;
    } catch (e) {
      debugPrint('[Profils] load: $e');
      _extras = <TvProfile>[];
      _managed = <TvProfile>[];
      _activeId = familyProfile.id;
    }
    _loaded = true;
    notifyListeners();
  }

  List<TvProfile> _decode(String raw) {
    try {
      final Object? list = jsonDecode(raw);
      if (list is! List) return <TvProfile>[];
      return list
          .map(TvProfile.fromJson)
          .whereType<TvProfile>()
          .toList(growable: true);
    } catch (_) {
      return <TvProfile>[];
    }
  }

  /// Applique la liste de profils envoyée par le PANEL.
  ///
  /// Renvoie `true` si quelque chose a changé — l'appelant peut alors
  /// recharger les écrans sans le faire à chaque synchronisation.
  ///
  /// ⚠ Ne touche PAS aux profils créés à la main sur l'appareil : les
  /// deux listes vivent séparément. Un panel qui pousse ses cinq profils
  /// n'efface pas celui que le client s'était fait.
  Future<bool> applyRemote(List<TvProfile> remote) async {
    final List<TvProfile> next = remote
        .map((TvProfile p) => p.copyWith(managed: true))
        .toList(growable: true);
    if (_sameProfiles(_managed, next)) return false;
    _managed = next;
    // Si le profil actif vient d'être désactivé ou supprimé à distance,
    // on rend la main à « Famille » IMMÉDIATEMENT : c'est tout l'intérêt
    // de pouvoir couper un profil depuis le panel.
    final TvProfile? current = byId(_activeId);
    if (current == null || !current.enabled) _activeId = familyProfile.id;
    await _save();
    return true;
  }

  bool _sameProfiles(List<TvProfile> a, List<TvProfile> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (jsonEncode(a[i].toJson()) != jsonEncode(b[i].toJson())) return false;
    }
    return true;
  }

  Future<void> create(String name, String emoji) async {
    final String n = name.trim();
    if (n.isEmpty || byName(n) != null) return;
    if (profiles.length >= maxProfiles) return;
    // Id stable dérivé du nom (pas d'horloge/aléa nécessaires ici).
    final String id =
        'p_${n.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
    if (profiles.any((TvProfile p) => p.id == id)) return;
    _extras.add(TvProfile(id: id, name: n, emoji: emoji));
    await _save();
  }

  Future<void> delete(String id) async {
    if (id == familyProfile.id) return; // « Famille » est indestructible
    // Un profil du PANEL ne se supprime pas depuis l'appareil : sinon le
    // contrôle parental se contournerait en supprimant le profil qui le
    // porte. Seul le panel peut le retirer.
    if (_managed.any((TvProfile p) => p.id == id)) return;
    _extras.removeWhere((TvProfile p) => p.id == id);
    if (_activeId == id) _activeId = familyProfile.id;
    await _save();
  }

  /// Bascule sur [id]. Refuse un profil inconnu ou DÉSACTIVÉ.
  ///
  /// ⚠ NE VÉRIFIE PAS LE PIN : c'est à l'écran de le demander avant
  /// d'appeler (voir [verifyPin]). Le faire ici obligerait à passer le
  /// code en clair à travers toutes les couches.
  Future<void> setActive(String id) async {
    final TvProfile? p = byId(id);
    if (p == null || !p.enabled) return;
    _activeId = id;
    await _save();
  }

  /// Le profil [id] demande-t-il un code ?
  bool requiresPin(String id) => byId(id)?.pin != null;

  /// Vérifie le code d'un profil. `false` si le profil n'existe pas —
  /// jamais `true` par défaut.
  bool verifyPin(String id, String pin) {
    final ProfilePin? p = byId(id)?.pin;
    if (p == null) return false;
    return p.matches(pin);
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kList, _encode(_extras));
      await prefs.setString(_kManaged, _encode(_managed));
      await prefs.setString(_kActive, _activeId);
    } catch (e) {
      debugPrint('[Profils] save: $e');
      // Perte de données silencieuse : les profils créés/renommés
      // disparaîtraient au prochain boot sans explication → on trace.
      StructuredLogger.instance.warn(
        domain: 'profiles',
        event: 'save_fail',
        ctx: <String, Object?>{'error': e.toString()},
      );
    }
  }

  String _encode(List<TvProfile> list) => jsonEncode(
      list.map((TvProfile p) => p.toJson()).toList(growable: false));

  @visibleForTesting
  Future<void> debugReset() async {
    _extras = <TvProfile>[];
    _managed = <TvProfile>[];
    _activeId = familyProfile.id;
    _loaded = true;
    notifyListeners();
  }
}
