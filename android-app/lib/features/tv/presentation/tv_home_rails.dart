// =========================================================
//  tv_home_rails.dart — Rangées de l'accueil (10-foot)
// =========================================================
//  Sous le bonjour, avant les tuiles Direct / Films / Séries :
//    • Vos rappels     — émissions que VOUS avez cochées
//    • Reprendre       — dernières chaînes en direct
//    • Continuer       — films et épisodes entamés
//    • Favoris
//    • Populaire       — les plus regardées en ce moment, parmi
//                        les vôtres (jamais une chaîne hors playlist)
//
//  OK lance. Rien ne se lance tout seul depuis ces cartes.
//  Une rangée vide n'est pas dessinée : pas de case « vide » qui
//  fait culpabiliser, pas de contenu inventé.
//
//  Navigation : chaque carte est focusable. Quand elle prend le
//  focus, on la fait défiler dans le cadre (horizontal ET vertical)
//  pour que la télécommande ne « perde » pas une carte hors écran.
// =========================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../cinema/data/watch_progress.dart';
import '../../epg/domain/program_reminder.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../data/home_shelves.dart';

class TvHomeRails extends StatelessWidget {
  const TvHomeRails({
    super.key,
    required this.model,
    required this.nowMs,
    required this.onPlayChannel,
    required this.onPlayContinue,
    required this.onPlayReminder,
    this.initialShelf,
  });

  final HomeShelfModel model;
  final int nowMs;
  final void Function(List<Channel> shelf, int index) onPlayChannel;
  final void Function(WatchEntry entry) onPlayContinue;
  final void Function(ProgramReminder reminder) onPlayReminder;

  /// Rangée qui reçoit le focus au premier affichage (une seule fois).
  final HomeShelfKind? initialShelf;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rails = <Widget>[];

    if (model.reminders.isNotEmpty) {
      rails.add(_Rail(
        label: context.l10n.tvHomeReminders,
        count: model.reminders.length,
        itemBuilder: (BuildContext context, int i) {
          final ProgramReminder r = model.reminders[i];
          return _TextCard(
            autofocus: initialShelf == HomeShelfKind.reminders && i == 0,
            icon: Icons.alarm_rounded,
            title: r.title,
            subtitle: _reminderSubtitle(context, r),
            onSelect: () => onPlayReminder(r),
          );
        },
      ));
    }
    if (model.resume.isNotEmpty) {
      rails.add(_Rail(
        label: context.l10n.tvHomeResume,
        count: model.resume.length,
        itemBuilder: (BuildContext context, int i) => _ChannelCard(
          channel: model.resume[i],
          autofocus: initialShelf == HomeShelfKind.resume && i == 0,
          onSelect: () => onPlayChannel(model.resume, i),
        ),
      ));
    }
    if (model.continueWatching.isNotEmpty) {
      rails.add(_Rail(
        label: context.l10n.tvHomeContinue,
        count: model.continueWatching.length,
        itemBuilder: (BuildContext context, int i) {
          final WatchEntry e = model.continueWatching[i];
          return _ContinueCard(
            entry: e,
            autofocus: initialShelf == HomeShelfKind.continueWatching && i == 0,
            upNextLabel: context.l10n.tvEpgNext,
            onSelect: () => onPlayContinue(e),
          );
        },
      ));
    }
    if (model.favorites.isNotEmpty) {
      rails.add(_Rail(
        label: context.l10n.tvHomeFavorites,
        count: model.favorites.length,
        itemBuilder: (BuildContext context, int i) => _ChannelCard(
          channel: model.favorites[i],
          autofocus: initialShelf == HomeShelfKind.favorites && i == 0,
          onSelect: () => onPlayChannel(model.favorites, i),
        ),
      ));
    }
    if (model.popular.isNotEmpty) {
      rails.add(_Rail(
        label: context.l10n.tvHomePopular,
        count: model.popular.length,
        itemBuilder: (BuildContext context, int i) => _ChannelCard(
          channel: model.popular[i],
          autofocus: initialShelf == HomeShelfKind.popular && i == 0,
          onSelect: () => onPlayChannel(model.popular, i),
        ),
      ));
    }

    if (rails.isEmpty) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: <Widget>[
        for (int i = 0; i < rails.length; i++) ...<Widget>[
          rails[i],
          if (i != rails.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  String _reminderSubtitle(BuildContext context, ProgramReminder r) {
    final String when = _whenLabel(context, r.startMs, nowMs);
    final String name = r.channelName.trim();
    if (name.isEmpty) return when;
    return '$when · $name';
  }
}

/// « Dans 12 min », « Dans 2 h 05 » ou « C'est commencé ».
String _whenLabel(BuildContext context, int startMs, int nowMs) {
  final int delta = startMs - nowMs;
  if (delta <= 0) return context.l10n.tvReminderStarted;
  final int minutes = (delta / 60000).ceil();
  if (minutes < 60) return context.l10n.tvReminderInMinutes(minutes);
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  if (rest == 0) return context.l10n.tvReminderInHours(hours);
  return context.l10n.tvReminderInHoursMinutes(hours, rest);
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.label,
    required this.count,
    required this.itemBuilder,
  });

  final String label;
  final int count;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: TvTokens.ui(
            TvDimens.caption,
            weight: FontWeight.w800,
            color: TvTokens.mutedDim,
            spacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: TvDimens.railCardH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    );
  }
}

/// Décale le défilement pour que la carte focalisée reste dans le cadre.
/// On ne le fait qu'au MOMENT où le focus arrive (pas à chaque rebuild),
/// sinon l'animation recommencerait en boucle.
class _KeepInView extends StatefulWidget {
  const _KeepInView({required this.focused, required this.child});
  final bool focused;
  final Widget child;

  @override
  State<_KeepInView> createState() => _KeepInViewState();
}

class _KeepInViewState extends State<_KeepInView> {
  @override
  void initState() {
    super.initState();
    if (widget.focused) _schedule();
  }

  @override
  void didUpdateWidget(_KeepInView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused && !oldWidget.focused) _schedule();
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: TvDimens.focusAnim,
        curve: TvDimens.focusCurve,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.channel,
    required this.onSelect,
    required this.autofocus,
  });

  final Channel channel;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TvDimens.railCardW,
      height: TvDimens.railCardH,
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
          return _KeepInView(
            focused: focused,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: focused ? TvTokens.accent : TvTokens.card,
                borderRadius: BorderRadius.circular(TvTokens.rCard),
                border: Border.all(
                  color: focused ? TvTokens.accent : TvTokens.line,
                  width: focused ? TvDimens.focusOutline : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  _Logo(channel: channel, focused: focused),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      channel.cleanName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(
                        TvDimens.body,
                        weight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.entry,
    required this.onSelect,
    required this.autofocus,
    required this.upNextLabel,
  });

  final WatchEntry entry;
  final VoidCallback onSelect;
  final bool autofocus;
  final String upNextLabel;

  @override
  Widget build(BuildContext context) {
    final String? sub = entry.subtitle;
    return SizedBox(
      width: TvDimens.posterW + 28,
      height: TvDimens.railCardH,
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
          final Color subFg = focused ? TvTokens.onAccent : TvTokens.muted;
          return _KeepInView(
            focused: focused,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: focused ? TvTokens.accent : TvTokens.card,
                borderRadius: BorderRadius.circular(TvTokens.rCard),
                border: Border.all(
                  color: focused ? TvTokens.accent : TvTokens.line,
                  width: focused ? TvDimens.focusOutline : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  _Poster(url: entry.posterUrl, focused: focused),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TvTokens.ui(
                            TvDimens.label,
                            weight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                        if (sub != null && sub.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            entry.upNext ? '$upNextLabel · $sub' : sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TvTokens.ui(TvDimens.caption, color: subFg),
                          ),
                        ] else if (entry.upNext) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            upNextLabel,
                            style: TvTokens.ui(TvDimens.caption, color: subFg),
                          ),
                        ],
                        if (!entry.upNext && entry.fraction > 0) ...<Widget>[
                          const SizedBox(height: 8),
                          _Progress(fraction: entry.fraction, focused: focused),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    required this.autofocus,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: TvDimens.railCardW + 20,
      height: TvDimens.railCardH,
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
          final Color subFg = focused ? TvTokens.onAccent : TvTokens.muted;
          final Color iconFg = focused ? TvTokens.onAccent : TvTokens.accent;
          return _KeepInView(
            focused: focused,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: focused ? TvTokens.accent : TvTokens.card,
                borderRadius: BorderRadius.circular(TvTokens.rCard),
                border: Border.all(
                  color: focused ? TvTokens.accent : TvTokens.line,
                  width: focused ? TvDimens.focusOutline : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 28, color: iconFg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TvTokens.ui(
                            TvDimens.label,
                            weight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TvTokens.ui(TvDimens.caption, color: subFg),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.fraction, required this.focused});
  final double fraction;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final double f = fraction.clamp(0.04, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: focused
                  ? TvTokens.onAccent.withValues(alpha: 0.25)
                  : TvTokens.line,
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: f,
              child: ColoredBox(
                color: focused ? TvTokens.onAccent : TvTokens.accentBright,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.channel, required this.focused});
  final Channel channel;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final String? url = channel.logoUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(TvTokens.rSmall),
      child: Container(
        width: TvDimens.channelLogo,
        height: TvDimens.channelLogo,
        color: focused ? TvTokens.accentBright : TvTokens.tile,
        padding: const EdgeInsets.all(4),
        child: url != null && url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) =>
                    _Initials(channel: channel, focused: focused),
                errorWidget: (_, __, ___) =>
                    _Initials(channel: channel, focused: focused),
              )
            : _Initials(channel: channel, focused: focused),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.focused});
  final String? url;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final String? u = url?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(TvTokens.rSmall),
      child: Container(
        width: 52,
        height: 78,
        color: focused ? TvTokens.accentBright : TvTokens.tile,
        child: u != null && u.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: u,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(
                  Icons.movie_rounded,
                  color: focused ? TvTokens.onAccent : TvTokens.accent,
                ),
              )
            : Icon(
                Icons.movie_rounded,
                color: focused ? TvTokens.onAccent : TvTokens.accent,
              ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.channel, required this.focused});
  final Channel channel;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        channel.initials,
        style: TvTokens.ui(
          TvDimens.caption,
          weight: FontWeight.w800,
          color: focused ? TvTokens.onAccent : TvTokens.accentBright,
        ),
      ),
    );
  }
}
