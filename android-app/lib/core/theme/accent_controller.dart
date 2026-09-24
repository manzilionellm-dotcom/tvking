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
  final String id;

  /// Libellé affiché dans le sélecteur.
  final String label;

  /// Couleur d'accent principale (boutons, onglet actif, liserés…).
  final Color accent;

  /// Variante claire — glows, focus, survol.
  final Color bright;

  /// Variante profonde — bordures actives, dégradés premium.
  final Color muted;
}

/// Catalogue des thèmes proposés au client. Le 1er (ember) est le
/// défaut historique The Few — valeurs IDENTIQUES à l'ancienne
/// façade `AppColors` pour ne rien changer tant que le client n'a pas
/// choisi.
const List<AccentTheme> kAccentThemes = <AccentTheme>[
  // Défaut « The Few » — Maison Noir : or champagne sur noir profond.
  // (1er du catalogue = appliqué tant que le client/panel n'a rien choisi.)
  AccentTheme(
    id: 'champagne',
    label: 'Champagne',
    accent: Color(0xFFC6A664),
    bright: Color(0xFFE2C982),
    muted: Color(0xFF8A7038),
  ),
  AccentTheme(
    id: 'ember',
    label: 'Braise',
    accent: Color(0xFFD63A30),
    bright: Color(0xFFFF5A4A),
    muted: Color(0xFF8E1F1D),
  ),
  AccentTheme(
    id: 'ocean',
    label: 'Océan',
    accent: Color(0xFF2E7DD6),
    bright: Color(0xFF5AA8FF),
    muted: Color(0xFF1D4E8E),
  ),
  AccentTheme(
    id: 'emerald',
    label: 'Émeraude',
    accent: Color(0xFF2FA96A),
    bright: Color(0xFF4ADB8E),
    muted: Color(0xFF1D6E47),
  ),
  AccentTheme(
    id: 'violet',
    label: 'Améthyste',
    accent: Color(0xFF8E5AD6),
    bright: Color(0xFFB58AFF),
    muted: Color(0xFF5E1D8E),
  ),
  AccentTheme(
    id: 'gold',
    label: 'Or',
    accent: Color(0xFFD6A030),
    bright: Color(0xFFFFC94A),
    muted: Color(0xFF8E6A1D),
  ),
  AccentTheme(
    id: 'turquoise',
    label: 'Turquoise',
    accent: Color(0xFF2EC4C6),
    bright: Color(0xFF5AF0F2),
    muted: Color(0xFF1D8E8E),
  ),
  AccentTheme(
    id: 'rose',
    label: 'Rose',
    accent: Color(0xFFD63A8E),
    bright: Color(0xFFFF5AB0),
    muted: Color(0xFF8E1D5E),
  ),
  AccentTheme(
    id: 'coral',
    label: 'Corail',
    accent: Color(0xFFE8703A),
    bright: Color(0xFFFF9A5A),
    muted: Color(0xFFA8431D),
  ),
  AccentTheme(
    id: 'indigo',
    label: 'Indigo',
    accent: Color(0xFF4A5AD6),
    bright: Color(0xFF7A8AFF),
    muted: Color(0xFF2A2F8E),
  ),
  AccentTheme(
    id: 'lime',
    label: 'Citron vert',
    accent: Color(0xFF8AC62E),
    bright: Color(0xFFB5F05A),
    muted: Color(0xFF5E8E1D),
  ),
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
