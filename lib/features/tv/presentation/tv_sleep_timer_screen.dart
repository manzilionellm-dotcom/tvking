// =========================================================
//  tv_sleep_timer_screen.dart — Minuterie de veille (écran TV)
// =========================================================
//  Choix d'une durée après laquelle l'app se ferme toute seule. N'a AUCUN
//  contact avec le lecteur vidéo (cf. SleepTimer).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';

import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../data/sleep_timer.dart';

class TvSleepTimerScreen extends StatelessWidget {
  const TvSleepTimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SleepTimer t = SleepTimer.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: t,
        builder: (BuildContext context, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.l10n.tvSleepTitle,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.tvSleepHelp,
                  style: const TextStyle(fontSize: 15, color: TvTokens.muted),
                ),
                const SizedBox(height: 24),

                // État actif : décompte + annuler.
                if (t.isActive) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 16),
                    decoration: BoxDecoration(
                      color: TvTokens.badgeBg,
                      borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                      border: Border.all(color: TvTokens.gold),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.bedtime_rounded,
                            color: TvTokens.gold, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          context.l10n.tvSleepCountdown(t.remainingLabel),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: TvTokens.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Choix de durée.
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    for (final int m in SleepTimer.presets)
                      _choice(
                        label: context.l10n.tvDurationMinutes(m),
                        selected: t.isActive && t.selectedMinutes == m,
                        onSelect: () => t.start(m),
                        autofocus: m == SleepTimer.presets.first,
                      ),
                    _choice(
                      label: context.l10n.tvSleepDisable,
                      selected: !t.isActive,
                      onSelect: t.cancel,
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

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onSelect,
    bool autofocus = false,
  }) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? TvTokens.gold
            : (selected ? TvTokens.badgeBg : TvTokens.sel);
        final Color fg = focused ? TvTokens.onGold : TvTokens.text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: selected ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: fg),
          ),
        );
      },
    );
  }
}
