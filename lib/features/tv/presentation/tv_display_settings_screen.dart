// =========================================================
//  tv_display_settings_screen.dart — Réglages d'affichage (TV)
// =========================================================
//  Deux réglages de CONFORT, appliqués à la racine de l'app (cf.
//  DisplaySettings). Aucun contact avec le lecteur vidéo / le rendu image.
//    • Overscan : marge autour de l'image (TV qui rognent les bords).
//    • Grand texte : agrandit légèrement le texte (lecture seniors).
// =========================================================
import 'package:flutter/material.dart';

import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../data/display_settings.dart';

class TvDisplaySettingsScreen extends StatelessWidget {
  const TvDisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final DisplaySettings d = DisplaySettings.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: d,
        builder: (BuildContext context, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Affichage',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text,
                  ),
                ),
                const SizedBox(height: 24),

                // ----- Overscan (marge autour de l'image) -----
                _label('Marge de l\'écran (overscan)'),
                const SizedBox(height: 4),
                _hint('Augmente si les bords de l\'image sont coupés par ta TV.'),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _squareBtn(
                      icon: Icons.remove_rounded,
                      onSelect: () => d.setOverscan(d.overscanPct - 1),
                    ),
                    Container(
                      width: 120,
                      alignment: Alignment.center,
                      child: Text(
                        '${d.overscanPct} %',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: TvTokens.gold,
                        ),
                      ),
                    ),
                    _squareBtn(
                      icon: Icons.add_rounded,
                      onSelect: () => d.setOverscan(d.overscanPct + 1),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // ----- Taille du texte -----
                _label('Taille du texte'),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _choice(
                      label: 'Normale',
                      selected: !d.bigText,
                      onSelect: () => d.setBigText(false),
                    ),
                    const SizedBox(width: 12),
                    _choice(
                      label: 'Grande',
                      selected: d.bigText,
                      onSelect: () => d.setBigText(true),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // ----- Nuit Royale (confort nocturne) -----
                _label('Nuit Royale — confort nocturne'),
                const SizedBox(height: 4),
                _hint(
                    'Voile chaud très léger le soir : moins de lumière bleue, '
                    'image plus douce pour les yeux.'),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _choice(
                      label: 'Désactivé',
                      selected: d.nightComfort == NightComfortMode.off,
                      onSelect: () =>
                          d.setNightComfort(NightComfortMode.off),
                    ),
                    const SizedBox(width: 12),
                    _choice(
                      label: 'Auto le soir',
                      selected: d.nightComfort == NightComfortMode.auto,
                      onSelect: () =>
                          d.setNightComfort(NightComfortMode.auto),
                    ),
                    const SizedBox(width: 12),
                    _choice(
                      label: 'Toujours',
                      selected: d.nightComfort == NightComfortMode.always,
                      onSelect: () =>
                          d.setNightComfort(NightComfortMode.always),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _label(String t) => Text(
        t,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: TvTokens.text,
        ),
      );

  Widget _hint(String t) => Text(
        t,
        style: const TextStyle(fontSize: 14, color: TvTokens.muted),
      );

  Widget _squareBtn({required IconData icon, required VoidCallback onSelect}) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          width: 64,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          ),
          child: Icon(icon,
              size: 28,
              color: focused ? const Color(0xFF1A1206) : TvTokens.goldBright),
        );
      },
    );
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? TvTokens.gold
            : (selected ? TvTokens.badgeBg : TvTokens.sel);
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: selected ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.check_rounded, size: 20, color: fg),
                ),
              Text(
                label,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        );
      },
    );
  }
}
