// =========================================================
//  hidden_categories_store.dart — Catégories MASQUÉES
// =========================================================
//  Le client peut MASQUER des catégories/groupes qu'il ne veut pas voir
//  (ex. les chaînes d'un pays qui ne l'intéresse pas) SANS contacter son
//  fournisseur. Le choix est PERSISTÉ (SharedPreferences) et appliqué
//  partout où les catégories sont listées (téléphone ET TV).
//
//  On MASQUE seulement l'AFFICHAGE : rien n'est supprimé de la source. Le
//  client peut ré-afficher à tout moment (rien n'est perdu).
//
//  ---------------------------------------------------------
//  VAGUE 2 (30/08) — DEUX LISTES QUI NE SE MÉLANGENT PAS
//  ---------------------------------------------------------
//  Demande du propriétaire : chaque profil a « sa propre liste de chaînes »,
//  avec un contrôle parental piloté depuis le panel. Il y a donc désormais
//  DEUX sources de masquage, et elles n'ont ni les mêmes droits ni la même
//  durée de vie :
//
//   1. LE CHOIX DU CLIENT (`_hidden`) — ce qu'il a masqué lui-même sur cet
//      appareil. Modifiable par lui, et SUFFIXÉ PAR PROFIL : papa peut
//      cacher le sport sans le cacher à maman. Même mécanique `keySuffix`
//      que les autres données par profil du projet.
//
//   2. LE VERROU DU PANEL (`_remoteBlocked`) — les catégories interdites au
//      profil actif, décidées à distance. LECTURE SEULE sur l'appareil.
//
//  POURQUOI DEUX LISTES ET PAS UNE. Si on les fusionnait, `unhide()`
//  laisserait un enfant ré-afficher une catégorie que son parent a
//  interdite depuis le panel — le contrôle parental se contournerait en
//  deux clics. Séparées, `unhide()` ne peut toucher QUE la liste du client :
//  le verrou du panel est hors de sa portée par construction, et pas
//  seulement parce qu'on a pensé à cacher le bouton.
//
//  COMPARAISON TOLÉRANTE pour le verrou du panel : un nom saisi dans le
//  panel ne reproduit jamais exactement la graphie de la source (« Cinéma »
//  vs « CINEMA », « Sport FR » vs « sport fr »). On compare donc sans
//  casse, sans accents et sans ponctuation. Le choix du client, lui, reste
//  en comparaison EXACTE : il vient d'un clic sur la catégorie réelle, il
//  n'y a rien à deviner.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profiles/profiles_repository.dart';

class HiddenCategoriesStore extends ChangeNotifier {
  HiddenCategoriesStore._();
  static final HiddenCategoriesStore instance = HiddenCategoriesStore._();

  static const String _kBaseKey = 'category_hidden_v1';

  /// Clé SUFFIXÉE par profil. « Famille » garde la clé historique (suffixe
  /// vide) → aucune migration, aucun masquage perdu à la mise à jour.
  static String get _key =>
      '$_kBaseKey${ProfilesRepository.instance.keySuffix}';

  final Set<String> _hidden = <String>{};

  /// Verrou du panel pour le profil actif, sous forme NORMALISÉE (voir
  /// [_normalize]). Recalculé à chaque changement de profil.
  Set<String> _remoteBlocked = <String>{};

  bool _loaded = false;

  /// Noms de catégories masquées PAR LE CLIENT (copie non modifiable).
  /// Ne contient pas le verrou du panel : c'est cette liste-là, et elle
  /// seule, que l'écran « Catégories masquées » propose de rouvrir.
  Set<String> get hidden => Set<String>.unmodifiable(_hidden);

  /// Nombre de catégories masquées par le client.
  int get count => _hidden.length;

  /// Nombre de catégories interdites par le panel pour le profil actif.
  /// Affichable pour expliquer « pourquoi je ne vois pas tout » sans
  /// laisser croire qu'on peut les rouvrir.
  int get blockedByPanelCount => _remoteBlocked.length;

  /// `true` si [cat] est masquée — par le client OU par le panel.
  bool isHidden(String cat) =>
      _hidden.contains(cat) ||
      (_remoteBlocked.isNotEmpty && _remoteBlocked.contains(_normalize(cat)));

  /// Charge l'ensemble persisté UNE fois (idempotent, best-effort).
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _read();
    // On suit le dépôt de profils : bascule de profil, ou nouvelle liste
    // poussée par le panel, doivent re-filtrer les écrans tout seuls.
    ProfilesRepository.instance.addListener(_onProfileChanged);
  }

  /// Relit tout pour le profil ACTIF. Appelée à la bascule de profil.
  Future<void> reload() async {
    _loaded = false;
    await _read();
  }

  Future<void> _read() async {
    if (_loaded) return;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _hidden
        ..clear()
        ..addAll(p.getStringList(_key) ?? const <String>[]);
    } catch (_) {
      _hidden.clear();
    }
    _refreshRemote();
    _loaded = true;
    notifyListeners();
  }

  /// Recharge en arrière-plan quand le profil actif change.
  void _onProfileChanged() {
    // ignore: discarded_futures
    reload();
  }

  void _refreshRemote() {
    _remoteBlocked = ProfilesRepository.instance.activeBlockedCategories
        .map(_normalize)
        .where((String s) => s.isNotEmpty)
        .toSet();
  }

  /// Masque [cat] (idempotent) et persiste.
  Future<void> hide(String cat) async {
    if (!_hidden.add(cat)) return;
    _loaded = true;
    notifyListeners();
    await _persist();
  }

  /// Ré-affiche [cat] (idempotent) et persiste.
  ///
  /// ⚠ Ne touche QUE la liste du client. Une catégorie interdite par le
  /// panel reste masquée : c'est exactement ce qu'on attend d'un contrôle
  /// parental — l'enfant a le bouton, il n'a pas le droit.
  Future<void> unhide(String cat) async {
    if (!_hidden.remove(cat)) return;
    notifyListeners();
    await _persist();
  }

  /// Ré-affiche TOUT ce que le client avait masqué. Le verrou du panel,
  /// lui, ne bouge pas.
  Future<void> clear() async {
    if (_hidden.isEmpty) return;
    _hidden.clear();
    notifyListeners();
    await _persist();
  }

  /// Retire de [items] les catégories masquées (filtre l'affichage).
  List<T> applyFilter<T>(List<T> items, String Function(T) nameOf) {
    if (_hidden.isEmpty && _remoteBlocked.isEmpty) return items;
    return items.where((T it) => !isHidden(nameOf(it))).toList();
  }

  /// Rabote un nom de catégorie pour pouvoir comparer ce que le panel a
  /// SAISI avec ce que la source ÉCRIT : minuscules, accents retirés, tout
  /// ce qui n'est ni lettre ni chiffre supprimé.
  ///
  /// « Cinéma & Séries » et « CINEMA SERIES » donnent tous deux
  /// « cinemaseries » — sinon le parent croirait avoir bloqué une catégorie
  /// qui, elle, resterait visible.
  static String _normalize(String raw) {
    const String from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
    const String to = 'aaaaaaceeeeiiiinooooouuuuyy';
    final StringBuffer out = StringBuffer();
    for (final int rune in raw.toLowerCase().runes) {
      final String ch = String.fromCharCode(rune);
      final int idx = from.indexOf(ch);
      final String plain = idx >= 0 ? to[idx] : ch;
      final int c = plain.codeUnitAt(0);
      final bool isAlnum = (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7A);
      if (isAlnum) out.write(plain);
    }
    return out.toString();
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setStringList(_key, _hidden.toList());
    } catch (_) {
      // best-effort : le masquage reste appliqué en mémoire cette session.
    }
  }

  @visibleForTesting
  void debugReset() {
    _hidden.clear();
    _remoteBlocked = <String>{};
    _loaded = false;
  }
}
