// =========================================================
//  accent_controller.dart — Thème d'accent choisi par le client
// =========================================================
//  Le client peut choisir la COULEUR D'ACCENT de l'app via le bouton
//  « Thème » (écran Profil). Le changement est INSTANTANÉ : ce
//  contrôleur est un ChangeNotifier branché à la racine (main.dart)
//  dans le `Listenable.merge` qui reconstruit tout `MaterialApp`. Comme
//  `AppColors.accent` (et sa famille) sont devenus des getters qui
//  lisent ce contrôleur, toute l'UI se recolore d'un coup.
//
//  Choix persistant (SharedPreferences) → conservé au redémarrage.
//
//  NB : c'est ICI (avec lumiere_tokens.dart) qu'il est légitime
//  d'écrire des `Color(0xFF...)` : c'est la SOURCE des valeurs de
//  palette. Ailleurs dans l'app, on passe toujours par AppColors.
// =========================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une variante d'accent : la couleur principale + ses deux dérivées
/// (claire pour les brillances/focus, profonde pour les bordures).
@immutable
class AccentTheme {
  const AccentTheme({
    required this.id,
    required this.label,
    required this.accent,
    required this.bright,
    required this.muted,
  });

  /// Identifiant stable stocké en préférences (ne pas traduire).
  /// C'est aussi la clé de mappage vers le libellé traduit du
  /// sélecteur (voir `theme_picker_sheet.dart` → `_accentLabel`).
  final String id;

  /// Libellé français de REPLI. L'UI ne l'affiche que si l'`id` n'a
  /// pas (encore) de clé de traduction correspondante : les libellés
  /// visibles passent par AppLocalizations (clés `accentX`), mappés
  /// depuis `id` dans le widget du picker. Ce fichier reste ainsi pur
  /// (pas de BuildContext dans la couche thème).
  final String label;

  /// Couleur d'accent principale (boutons, onglet actif, liserés…).
  final Color accent;

  /// Variante claire — glows, focus, survol.
  final Color bright;

  /// Variante profonde — bordures actives, dégradés premium.
  final Color muted;

  /// Construit une variante premium à partir de la SEULE couleur d'accent :
  /// les tons clair (glow/focus) et profond (bordures) sont dérivés par HSL,
  /// pour garder une famille cohérente. Permet d'étendre le catalogue à des
  /// dizaines de teintes sans tripler les valeurs à la main.
  factory AccentTheme.derive({
    required String id,
    required String label,
    required Color accent,
  }) {
    final HSLColor hsl = HSLColor.fromColor(accent);
    final Color bright = hsl
        .withLightness((hsl.lightness + 0.14).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + 0.06).clamp(0.0, 1.0))
        .toColor();
    final Color muted =
        hsl.withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0)).toColor();
    return AccentTheme(
      id: id,
      label: label,
      accent: accent,
      bright: bright,
      muted: muted,
    );
  }
}

/// Catalogue des thèmes proposés au client. Le 1er (ember) est le
/// défaut historique The Few — valeurs IDENTIQUES à l'ancienne
/// façade `AppColors` pour ne rien changer tant que le client n'a pas
/// choisi.
// NB : liste `final` (et non `const`) car les teintes premium ci-dessous
// sont DÉRIVÉES par HSL au chargement (AccentTheme.derive) — calcul runtime.
// Les 11 premières restent réglées à la main (défaut historique inchangé).
final List<AccentTheme> kAccentThemes = <AccentTheme>[
  // Défaut « The Few » — Maison Noir : or champagne sur noir profond.
  // (1er du catalogue = appliqué tant que le client/panel n'a rien choisi.)
  const AccentTheme(
    id: 'champagne',
    label: 'Champagne',
    accent: Color(0xFFC6A664),
    bright: Color(0xFFE2C982),
    muted: Color(0xFF8A7038),
  ),
  const AccentTheme(
    id: 'ember',
    label: 'Braise',
    accent: Color(0xFFD63A30),
    bright: Color(0xFFFF5A4A),
    muted: Color(0xFF8E1F1D),
  ),
  const AccentTheme(
    id: 'ocean',
    label: 'Océan',
    accent: Color(0xFF2E7DD6),
    bright: Color(0xFF5AA8FF),
    muted: Color(0xFF1D4E8E),
  ),
  const AccentTheme(
    id: 'emerald',
    label: 'Émeraude',
    accent: Color(0xFF2FA96A),
    bright: Color(0xFF4ADB8E),
    muted: Color(0xFF1D6E47),
  ),
  const AccentTheme(
    id: 'violet',
    label: 'Améthyste',
    accent: Color(0xFF8E5AD6),
    bright: Color(0xFFB58AFF),
    muted: Color(0xFF5E1D8E),
  ),
  const AccentTheme(
    id: 'gold',
    label: 'Or',
    accent: Color(0xFFD6A030),
    bright: Color(0xFFFFC94A),
    muted: Color(0xFF8E6A1D),
  ),
  const AccentTheme(
    id: 'turquoise',
    label: 'Turquoise',
    accent: Color(0xFF2EC4C6),
    bright: Color(0xFF5AF0F2),
    muted: Color(0xFF1D8E8E),
  ),
  const AccentTheme(
    id: 'rose',
    label: 'Rose',
    accent: Color(0xFFD63A8E),
    bright: Color(0xFFFF5AB0),
    muted: Color(0xFF8E1D5E),
  ),
  const AccentTheme(
    id: 'coral',
    label: 'Corail',
    accent: Color(0xFFE8703A),
    bright: Color(0xFFFF9A5A),
    muted: Color(0xFFA8431D),
  ),
  const AccentTheme(
    id: 'indigo',
    label: 'Indigo',
    accent: Color(0xFF4A5AD6),
    bright: Color(0xFF7A8AFF),
    muted: Color(0xFF2A2F8E),
  ),
  const AccentTheme(
    id: 'lime',
    label: 'Citron vert',
    accent: Color(0xFF8AC62E),
    bright: Color(0xFFB5F05A),
    muted: Color(0xFF5E8E1D),
  ),

  // ===================================================================
  //  COLLECTION PREMIUM — teintes « riches » dérivées par HSL.
  //  Pierres précieuses, métaux nobles, grands crus, épices, laques…
  //  Objectif : une palette « app de riche », addictive, jamais fade.
  //  (libellé français direct — repli assumé du sélecteur, cf.
  //   theme_picker_sheet.dart → _accentLabel default.)
  // ===================================================================

  // — Pierres & minéraux —
  AccentTheme.derive(id: 'saphir', label: 'Saphir', accent: const Color(0xFF0F52BA)),
  AccentTheme.derive(id: 'rubis', label: 'Rubis', accent: const Color(0xFFE0115F)),
  AccentTheme.derive(id: 'topaze', label: 'Topaze', accent: const Color(0xFFFFC12E)),
  AccentTheme.derive(id: 'citrine', label: 'Citrine', accent: const Color(0xFFE4A81C)),
  AccentTheme.derive(id: 'grenat', label: 'Grenat', accent: const Color(0xFF9B2242)),
  AccentTheme.derive(id: 'aiguemarine', label: 'Aigue-marine', accent: const Color(0xFF2FC4B2)),
  AccentTheme.derive(id: 'lapis', label: 'Lapis-lazuli', accent: const Color(0xFF26619C)),
  AccentTheme.derive(id: 'tanzanite', label: 'Tanzanite', accent: const Color(0xFF5A5FB0)),
  AccentTheme.derive(id: 'jade', label: 'Jade', accent: const Color(0xFF00A86B)),
  AccentTheme.derive(id: 'malachite', label: 'Malachite', accent: const Color(0xFF18C56A)),
  AccentTheme.derive(id: 'opale', label: 'Opale', accent: const Color(0xFF7FC7B8)),
  AccentTheme.derive(id: 'quartzrose', label: 'Quartz rose', accent: const Color(0xFFE8A0A6)),
  AccentTheme.derive(id: 'onyx', label: 'Onyx', accent: const Color(0xFF515158)),
  AccentTheme.derive(id: 'obsidienne', label: 'Obsidienne', accent: const Color(0xFF44454F)),
  AccentTheme.derive(id: 'perle', label: 'Perle', accent: const Color(0xFFCDBE9A)),
  AccentTheme.derive(id: 'nacre', label: 'Nacre', accent: const Color(0xFFCBBFA3)),
  AccentTheme.derive(id: 'ambre', label: 'Ambre', accent: const Color(0xFFF0A81E)),
  AccentTheme.derive(id: 'peridot', label: 'Péridot', accent: const Color(0xFF9DBE2E)),

  // — Métaux nobles —
  AccentTheme.derive(id: 'orrose', label: 'Or rose', accent: const Color(0xFFE0A899)),
  AccentTheme.derive(id: 'platine', label: 'Platine', accent: const Color(0xFF9FB0B5)),
  AccentTheme.derive(id: 'argent', label: 'Argent', accent: const Color(0xFFA9B0BA)),
  AccentTheme.derive(id: 'bronze', label: 'Bronze', accent: const Color(0xFFC1803C)),
  AccentTheme.derive(id: 'cuivre', label: 'Cuivre', accent: const Color(0xFFB6642E)),
  AccentTheme.derive(id: 'titane', label: 'Titane', accent: const Color(0xFF8A8D8F)),
  AccentTheme.derive(id: 'acier', label: 'Acier', accent: const Color(0xFF6E7B86)),
  AccentTheme.derive(id: 'laiton', label: 'Laiton', accent: const Color(0xFFB59A3C)),
  AccentTheme.derive(id: 'vermeil', label: 'Vermeil', accent: const Color(0xFFD98A3C)),

  // — Grands crus & rouges profonds —
  AccentTheme.derive(id: 'bordeaux', label: 'Bordeaux', accent: const Color(0xFF7A1128)),
  AccentTheme.derive(id: 'bourgogne', label: 'Bourgogne', accent: const Color(0xFF8C1230)),
  AccentTheme.derive(id: 'merlot', label: 'Merlot', accent: const Color(0xFF8A2C3A)),
  AccentTheme.derive(id: 'cognac', label: 'Cognac', accent: const Color(0xFFA0522D)),
  AccentTheme.derive(id: 'acajou', label: 'Acajou', accent: const Color(0xFF8B3A1E)),
  AccentTheme.derive(id: 'cerise', label: 'Cerise', accent: const Color(0xFFC51E3A)),
  AccentTheme.derive(id: 'framboise', label: 'Framboise', accent: const Color(0xFFCE2C5A)),
  AccentTheme.derive(id: 'grenadine', label: 'Grenadine', accent: const Color(0xFFE23B4E)),
  AccentTheme.derive(id: 'vermillon', label: 'Vermillon', accent: const Color(0xFFE34234)),
  AccentTheme.derive(id: 'carmin', label: 'Carmin', accent: const Color(0xFFB01030)),
  AccentTheme.derive(id: 'cardinal', label: 'Cardinal', accent: const Color(0xFFA51E3C)),
  AccentTheme.derive(id: 'ecarlate', label: 'Écarlate', accent: const Color(0xFFE62030)),

  // — Prunes, pourpres & orchidées —
  AccentTheme.derive(id: 'prune', label: 'Prune', accent: const Color(0xFF9B4E86)),
  AccentTheme.derive(id: 'aubergine', label: 'Aubergine', accent: const Color(0xFF6E4468)),
  AccentTheme.derive(id: 'cassis', label: 'Cassis', accent: const Color(0xFF8A2350)),
  AccentTheme.derive(id: 'pourpre', label: 'Pourpre', accent: const Color(0xFF8A2360)),
  AccentTheme.derive(id: 'byzantin', label: 'Byzantin', accent: const Color(0xFF8A2A72)),
  AccentTheme.derive(id: 'magenta', label: 'Magenta', accent: const Color(0xFFC81E7A)),
  AccentTheme.derive(id: 'fuchsia', label: 'Fuchsia', accent: const Color(0xFFC63FB0)),
  AccentTheme.derive(id: 'orchidee', label: 'Orchidée', accent: const Color(0xFFB65AC8)),
  AccentTheme.derive(id: 'lavande', label: 'Lavande', accent: const Color(0xFF9B8AD0)),
  AccentTheme.derive(id: 'lilas', label: 'Lilas', accent: const Color(0xFFB07EDC)),
  AccentTheme.derive(id: 'glycine', label: 'Glycine', accent: const Color(0xFF9A7BC0)),
  AccentTheme.derive(id: 'mauve', label: 'Mauve', accent: const Color(0xFFB07AA8)),
  AccentTheme.derive(id: 'parme', label: 'Parme', accent: const Color(0xFFC29AE0)),

  // — Roses raffinés —
  AccentTheme.derive(id: 'rosepoudre', label: 'Rose poudré', accent: const Color(0xFFE0A2AC)),
  AccentTheme.derive(id: 'vieuxrose', label: 'Vieux rose', accent: const Color(0xFFC58089)),
  AccentTheme.derive(id: 'flamant', label: 'Flamant', accent: const Color(0xFFF07EA0)),
  AccentTheme.derive(id: 'fraise', label: 'Fraise', accent: const Color(0xFFE23A58)),

  // — Épices, ors chauds & agrumes —
  AccentTheme.derive(id: 'safran', label: 'Safran', accent: const Color(0xFFF4B41A)),
  AccentTheme.derive(id: 'moutarde', label: 'Moutarde', accent: const Color(0xFFD9A400)),
  AccentTheme.derive(id: 'curcuma', label: 'Curcuma', accent: const Color(0xFFE59A0C)),
  AccentTheme.derive(id: 'miel', label: 'Miel', accent: const Color(0xFFD9A02E)),
  AccentTheme.derive(id: 'caramel', label: 'Caramel', accent: const Color(0xFFC57F32)),
  AccentTheme.derive(id: 'terracotta', label: 'Terracotta', accent: const Color(0xFFC4643C)),
  AccentTheme.derive(id: 'rouille', label: 'Rouille', accent: const Color(0xFFB5451E)),
  AccentTheme.derive(id: 'paprika', label: 'Paprika', accent: const Color(0xFFC7392A)),
  AccentTheme.derive(id: 'abricot', label: 'Abricot', accent: const Color(0xFFF0902E)),
  AccentTheme.derive(id: 'mangue', label: 'Mangue', accent: const Color(0xFFF4A02A)),
  AccentTheme.derive(id: 'peche', label: 'Pêche', accent: const Color(0xFFF29A7A)),
  AccentTheme.derive(id: 'papaye', label: 'Papaye', accent: const Color(0xFFEE6C48)),
  AccentTheme.derive(id: 'mandarine', label: 'Mandarine', accent: const Color(0xFFF07E1E)),
  AccentTheme.derive(id: 'potiron', label: 'Potiron', accent: const Color(0xFFE87722)),

  // — Verts précieux —
  AccentTheme.derive(id: 'menthe', label: 'Menthe', accent: const Color(0xFF2FB98A)),
  AccentTheme.derive(id: 'sauge', label: 'Sauge', accent: const Color(0xFF7E9B6E)),
  AccentTheme.derive(id: 'olive', label: 'Olive', accent: const Color(0xFF8A8A2A)),
  AccentTheme.derive(id: 'kaki', label: 'Kaki', accent: const Color(0xFF8C9268)),
  AccentTheme.derive(id: 'foret', label: 'Forêt', accent: const Color(0xFF1E7A52)),
  AccentTheme.derive(id: 'sapin', label: 'Sapin', accent: const Color(0xFF1F6E4C)),
  AccentTheme.derive(id: 'celadon', label: 'Céladon', accent: const Color(0xFF74A98A)),
  AccentTheme.derive(id: 'chartreuse', label: 'Chartreuse', accent: const Color(0xFF9DC81E)),
  AccentTheme.derive(id: 'pistache', label: 'Pistache', accent: const Color(0xFF86C24A)),
  AccentTheme.derive(id: 'absinthe', label: 'Absinthe', accent: const Color(0xFF9CBE1A)),
  AccentTheme.derive(id: 'tilleul', label: 'Tilleul', accent: const Color(0xFFBCCB4E)),
  AccentTheme.derive(id: 'vertimperial', label: 'Vert impérial', accent: const Color(0xFF0E7A44)),
  AccentTheme.derive(id: 'vertbouteille', label: 'Vert bouteille', accent: const Color(0xFF156A4A)),

  // — Bleus & sarcelles nobles —
  AccentTheme.derive(id: 'azur', label: 'Azur', accent: const Color(0xFF1E88E5)),
  AccentTheme.derive(id: 'cobalt', label: 'Cobalt', accent: const Color(0xFF1146C8)),
  AccentTheme.derive(id: 'klein', label: 'Bleu Klein', accent: const Color(0xFF0A34C0)),
  AccentTheme.derive(id: 'marine', label: 'Marine', accent: const Color(0xFF28407A)),
  AccentTheme.derive(id: 'nuit', label: 'Bleu nuit', accent: const Color(0xFF2B2F8E)),
  AccentTheme.derive(id: 'cyan', label: 'Cyan', accent: const Color(0xFF08B7C2)),
  AccentTheme.derive(id: 'petrole', label: 'Bleu pétrole', accent: const Color(0xFF1F7A80)),
  AccentTheme.derive(id: 'lagon', label: 'Lagon', accent: const Color(0xFF1FAAA6)),
  AccentTheme.derive(id: 'ceruleen', label: 'Céruléen', accent: const Color(0xFF2A7FDB)),
  AccentTheme.derive(id: 'bleuroi', label: 'Bleu roi', accent: const Color(0xFF2C46B8)),
  AccentTheme.derive(id: 'bleuglacier', label: 'Bleu glacier', accent: const Color(0xFF6FB0D6)),
  AccentTheme.derive(id: 'paon', label: 'Bleu paon', accent: const Color(0xFF1F8FA0)),
  AccentTheme.derive(id: 'denim', label: 'Denim', accent: const Color(0xFF3B5EA8)),
  AccentTheme.derive(id: 'ardoise', label: 'Ardoise', accent: const Color(0xFF546A7B)),

  // — Neutres sophistiqués & bruns nobles —
  AccentTheme.derive(id: 'sable', label: 'Sable', accent: const Color(0xFFC2A85E)),
  AccentTheme.derive(id: 'ivoire', label: 'Ivoire', accent: const Color(0xFFC9BC8E)),
  AccentTheme.derive(id: 'grege', label: 'Grège', accent: const Color(0xFFAFA48C)),
  AccentTheme.derive(id: 'taupe', label: 'Taupe', accent: const Color(0xFF8E8177)),
  AccentTheme.derive(id: 'camel', label: 'Camel', accent: const Color(0xFFC29A5E)),
  AccentTheme.derive(id: 'noisette', label: 'Noisette', accent: const Color(0xFF9A7A4E)),
  AccentTheme.derive(id: 'moka', label: 'Moka', accent: const Color(0xFF8A5A3C)),
  AccentTheme.derive(id: 'chocolat', label: 'Chocolat', accent: const Color(0xFF6A4028)),
  AccentTheme.derive(id: 'espresso', label: 'Espresso', accent: const Color(0xFF6B4A32)),
  AccentTheme.derive(id: 'anthracite', label: 'Anthracite', accent: const Color(0xFF4A4F57)),
  AccentTheme.derive(id: 'graphite', label: 'Graphite', accent: const Color(0xFF565A62)),
];

/// Contrôleur global du thème d'accent. Singleton + ChangeNotifier.
class AccentController extends ChangeNotifier {
  AccentController._();
  static final AccentController instance = AccentController._();

  static const String _kPrefKey = 'accent_theme_id';

  /// Thème courant. Défaut = ember (1er du catalogue) tant que rien
  /// n'est chargé/choisi → comportement identique à avant.
  AccentTheme _current = kAccentThemes.first;
  AccentTheme get current => _current;

  /// Charge le choix sauvegardé au démarrage. Silencieux si rien.
  Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? id = prefs.getString(_kPrefKey);
      if (id == null) return;
      final AccentTheme match = kAccentThemes.firstWhere(
        (AccentTheme t) => t.id == id,
        orElse: () => kAccentThemes.first,
      );
      if (match.id != _current.id) {
        _current = match;
        notifyListeners();
      }
    } catch (_) {
      // best-effort : en cas d'échec on reste sur ember.
    }
  }

  /// Applique une couleur d'accent ARBITRAIRE, pilotée à distance par le
  /// panel « Thème » (ex. blanc, or, vert Coupe du Monde…). On dérive les
  /// variantes claire (glows/focus) et profonde (bordures) par HSL pour
  /// garder une famille cohérente. NON persistée : le panel est la source
  /// de vérité, relue à chaque démarrage. Sans effet si identique.
  void applyCustom(Color accent) {
    final HSLColor hsl = HSLColor.fromColor(accent);
    final Color bright =
        hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0)).toColor();
    final Color muted =
        hsl.withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0)).toColor();
    if (_current.id == 'remote' && _current.accent == accent) return;
    _current = AccentTheme(
      id: 'remote',
      label: 'Personnalisé',
      accent: accent,
      bright: bright,
      muted: muted,
    );
    notifyListeners();
  }

  /// Applique un thème (instantané) et le persiste.
  Future<void> select(AccentTheme theme) async {
    if (theme.id == _current.id) return;
    _current = theme;
    notifyListeners(); // recolore toute l'app immédiatement
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefKey, theme.id);
    } catch (_) {
      // best-effort
    }
  }
}
