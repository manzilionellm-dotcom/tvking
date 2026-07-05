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

import '../../../core/i18n/l10n_extension.dart';
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
                Text(context.l10n.tvStatsTitle,
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
                const SizedBox(height: 6),
                Text(context.l10n.tvStatsSubtitle,
                    style: const TextStyle(fontSize: 14, color: TvTokens.muted)),
                const SizedBox(height: 26),

                // ----- Grands chiffres -----
                Row(
                  children: <Widget>[
                    _bigNumber(context.l10n.tvStatsToday,
                        _dur(context, s.todayMinutes)),
                    const SizedBox(width: 16),
                    _bigNumber(context.l10n.tvStatsSevenDays,
                        _dur(context, weekTotal)),
                  ],
                ),
                // ----- Ce que l'app a APPRIS de toi (affiché seulement
                //  quand il y a assez de données — on constate, on ne
                //  devine pas). -----
                if (s.favoriteMomentKey() != null ||
                    s.favoriteWeekday() != null) ...<Widget>[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    children: <Widget>[
                      if (s.favoriteMomentKey() != null)
                        _insight(context.l10n.tvStatsMoment(
                            _momentLabel(context, s.favoriteMomentKey()!))),
                      if (s.favoriteWeekday() != null)
                        _insight(context.l10n.tvStatsFavDay(
                            _weekdayLabel(context, s.favoriteWeekday()!))),
                    ],
                  ),
                ],
                const SizedBox(height: 30),

                // ----- Barres des 7 derniers jours -----
                Text(context.l10n.tvStatsThisWeek,
                    style: const TextStyle(
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
                Text(context.l10n.tvStatsTopChannels,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text)),
                const SizedBox(height: 12),
                if (top.isEmpty)
                  Text(context.l10n.tvStatsEmpty,
                      style: const TextStyle(
                          fontSize: 15, color: TvTokens.mutedDim))
                else
                  for (final ChannelStat c in top) ...<Widget>[
                    _channelRow(context, c, maxTop),
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

  /// Durée traduite : « 2 h 05 » / « 45 min » selon la langue active.
  static String _dur(BuildContext ctx, int minutes) {
    if (minutes < 60) return ctx.l10n.tvDurationMinutes(minutes);
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return m == 0
        ? ctx.l10n.tvDurationHours(h)
        : ctx.l10n.tvDurationHoursMinutes(h, m.toString().padLeft(2, '0'));
  }

  /// Clé de moment ('m'/'a'/'s'/'n') → libellé traduit.
  static String _momentLabel(BuildContext ctx, String key) {
    switch (key) {
      case 'm':
        return ctx.l10n.tvMomentMorning;
      case 'a':
        return ctx.l10n.tvMomentAfternoon;
      case 's':
        return ctx.l10n.tvMomentEvening;
      default:
        return ctx.l10n.tvMomentNight;
    }
  }

  /// Jour 1(lundi)..7(dimanche) → libellé traduit.
  static String _weekdayLabel(BuildContext ctx, int wd) {
    switch (wd) {
      case 1:
        return ctx.l10n.tvWeekdayMonday;
      case 2:
        return ctx.l10n.tvWeekdayTuesday;
      case 3:
        return ctx.l10n.tvWeekdayWednesday;
      case 4:
        return ctx.l10n.tvWeekdayThursday;
      case 5:
        return ctx.l10n.tvWeekdayFriday;
      case 6:
        return ctx.l10n.tvWeekdaySaturday;
      default:
        return ctx.l10n.tvWeekdaySunday;
    }
  }

  Widget _channelRow(BuildContext context, ChannelStat c, int max) {
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
          child: Text(_dur(context, c.minutes),
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
