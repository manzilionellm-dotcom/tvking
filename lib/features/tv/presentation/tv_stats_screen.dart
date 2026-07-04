// =========================================================
//  tv_stats_screen.dart — « Mes statistiques » (10-foot)
// =========================================================
//  Vitrine du module WatchStatsService (fonctionnalité n°15) :
//    • temps regardé AUJOURD'HUI et sur 7 JOURS (grands chiffres),
//    • les 7 derniers jours en barres d'or (simple Containers, zéro lib),
//    • le TOP 5 des chaînes de la semaine avec barres proportionnelles.
//  Tout est LOCAL au profil actif (vie privée) et se met à jour en
//  direct (ListenableBuilder sur le service).
// =========================================================
import 'package:flutter/material.dart';

import '../../stats/data/watch_stats_service.dart';
import '../core/tv_tokens.dart';

class TvStatsScreen extends StatelessWidget {
  const TvStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final WatchStatsService s = WatchStatsService.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: s,
        builder: (BuildContext context, _) {
          final List<int> days = s.last7Daily;
          final int weekTotal = s.minutesLastDays(7);
          final List<ChannelStat> top = s.topChannels(days: 7, limit: 5);
          final int maxDay =
              days.fold<int>(1, (int m, int v) => v > m ? v : m);
          final int maxTop = top.isEmpty ? 1 : top.first.minutes;
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Mes statistiques',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
                const SizedBox(height: 6),
                const Text(
                    'Ton temps d\'écran, rien qu\'à toi — tout reste sur cette box.',
                    style: TextStyle(fontSize: 14, color: TvTokens.muted)),
                const SizedBox(height: 26),

                // ----- Grands chiffres -----
                Row(
                  children: <Widget>[
                    _bigNumber('Aujourd\'hui',
                        WatchStatsService.fmt(s.todayMinutes)),
                    const SizedBox(width: 16),
                    _bigNumber('7 derniers jours',
                        WatchStatsService.fmt(weekTotal)),
                  ],
                ),
                // ----- Ce que l'app a APPRIS de toi (affiché seulement
                //  quand il y a assez de données — on constate, on ne
                //  devine pas). -----
                if (s.favoriteMomentLabel() != null ||
                    s.favoriteWeekdayLabel() != null) ...<Widget>[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    children: <Widget>[
                      if (s.favoriteMomentLabel() != null)
                        _insight(
                            'Ton moment télé : ${s.favoriteMomentLabel()!}'),
                      if (s.favoriteWeekdayLabel() != null)
                        _insight(
                            'Ton jour préféré : ${s.favoriteWeekdayLabel()!}'),
                    ],
                  ),
                ],
                const SizedBox(height: 30),

                // ----- Barres des 7 derniers jours -----
                const Text('Cette semaine',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 90,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      for (int i = 0; i < days.length; i++) ...<Widget>[
                        _dayBar(days[i], maxDay, i == days.length - 1),
                        const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // ----- Top chaînes -----
                const Text('Tes chaînes de la semaine',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text)),
                const SizedBox(height: 12),
                if (top.isEmpty)
                  const Text(
                      'Regarde quelques chaînes et reviens ici : ton palmarès s\'écrira tout seul.',
                      style:
                          TextStyle(fontSize: 15, color: TvTokens.mutedDim))
                else
                  for (final ChannelStat c in top) ...<Widget>[
                    _channelRow(c, maxTop),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bigNumber(String label, String value) {
    return Container(
      width: 300,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(fontSize: 14, color: TvTokens.muted)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.goldBright)),
        ],
      ),
    );
  }

  Widget _insight(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: TvTokens.badgeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TvTokens.hairline),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: TvTokens.goldBright)),
    );
  }

  Widget _dayBar(int minutes, int max, bool isToday) {
    final double h = max <= 0 ? 4 : 4 + (minutes / max) * 70;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Container(
          width: 34,
          height: h,
          decoration: BoxDecoration(
            gradient: isToday ? TvTokens.ctaGradient : null,
            color: isToday ? null : TvTokens.sel,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: isToday ? TvTokens.gold : TvTokens.lineSoft),
          ),
        ),
      ],
    );
  }

  Widget _channelRow(ChannelStat c, int max) {
    final double frac = max <= 0 ? 0 : c.minutes / max;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 260,
          child: Text(c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: TvTokens.text)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Stack(
            children: <Widget>[
              Container(
                height: 14,
                decoration: BoxDecoration(
                  color: TvTokens.sel,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              FractionallySizedBox(
                widthFactor: frac.clamp(0.02, 1.0),
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: TvTokens.ctaGradient,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: Text(WatchStatsService.fmt(c.minutes),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: TvTokens.gold)),
        ),
      ],
    );
  }
}
