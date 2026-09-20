// =========================================================
//  tv_display_settings_screen.dart — Réglages d'affichage (TV)
// =========================================================
//  Réglages de CONFORT, appliqués à la racine de l'app (cf.
//  DisplaySettings). Aucun contact avec le lecteur vidéo / le rendu image.
//    • Zoom : agrandit toute l'interface (grand écran, canapé loin).
//    • Overscan : marge autour de l'image (TV qui rognent les bords).
//    • Grand texte : agrandit légèrement le texte (lecture seniors).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
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
                Text(
                  context.l10n.tvDisplayTitle,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text,
                  ),
                ),
                const SizedBox(height: 24),

                // ----- Zoom de l'interface (20/09/2026) -----
                // EN PREMIER : c'est le réglage qu'un client sur un très
                // grand écran, ou assis loin, cherche. Trois crans, et la
                // box s'en souvient. Voir display_settings.dart pour
                // pourquoi ce n'est pas automatique (la box ne connaît pas
                // la taille de la télé).
                _label(context.l10n.tvZoomLabel),
                const SizedBox(height: 4),
                _hint(context.l10n.tvZoomHint),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _choice(
                      label: context.l10n.tvZoomNormal,
                      selected: d.zoomPct == 100,
                      onSelect: () => d.setZoom(100),
                    ),
                    const SizedBox(width: 12),
                    _choice(
                      label: context.l10n.tvZoomLarge,
                      selected: d.zoomPct == 110,
                      onSelect: () => d.setZoom(110),
                    ),
                    const SizedBox(width: 12),
                    _choice(
                      label: context.l10n.tvZoomXLarge,
                      selected: d.zoomPct == 120,
                      onSelect: () => d.setZoom(120),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // ----- Overscan (marge autour de l'image) -----
                _label(context.l10n.tvOverscanLabel),
                const SizedBox(height: 4),
                // Tant que le client n'a rien choisi, on dit d'où vient le
                // chiffre (zone sûre Android TV, 5 % sur une box) — sinon
                // le support croirait que le client l'a réglé lui-même.
                _hint(d.overscanChoisi
                    ? context.l10n.tvOverscanHint
                    : context.l10n.tvOverscanAuto),
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
                        context.l10n.tvPercent(d.overscanPct),
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
                _label(context.l10n.tvTextSizeLabel),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _choice(
                      label: context.l10n.tvTextNormal,
                      selected: !d.bigText,
                      onSelect: () => d.setBigText(false),
                    ),
                    const SizedBox(width: 12),
                    _choice(
                      label: context.l10n.tvTextLarge,
                      selected: d.bigText,
                      onSelect: () => d.setBigText(true),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // ----- Sons de navigation (clic D-pad) -----
                _label(context.l10n.tvNavSoundsLabel),
                const SizedBox(height: 4),
                _hint(context.l10n.tvNavSoundsHint),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _choice(
                      label: context.l10n.tvEnabled,
                      selected: d.navSounds,
                      onSelect: () => d.setNavSounds(true),
                    ),
                    const SizedBox(width: 12),
                    _choice(
                      label: context.l10n.tvDisabled,
                      selected: !d.navSounds,
                      onSelect: () => d.setNavSounds(false),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // ----- Nuit Royale (confort nocturne) -----
                _label(context.l10n.tvNightComfortTitle),
                const SizedBox(height: 4),
                _hint(context.l10n.tvNightComfortHint),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _choice(
                      label: context.l10n.tvNightOff,
                      selected: d.nightComfort == NightComfortMode.off,
                      onSelect: () =>
                          d.setNightComfort(NightComfortMode.off),
                    ),
                    const SizedBox(width: 12),
                    _choice(
                      label: context.l10n.tvNightAuto,
                      selected: d.nightComfort == NightComfortMode.auto,
                      onSelect: () =>
                          d.setNightComfort(NightComfortMode.auto),
                    ),
                    const SizedBox(width: 12),
                    _choice(
                      label: context.l10n.tvNightAlways,
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
