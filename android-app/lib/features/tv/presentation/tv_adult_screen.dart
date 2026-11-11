import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../cinema/domain/cinema_models.dart';
import '../../security/data/adult_access.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_cinema_screen.dart';
import 'tv_live_screen.dart';
import 'tv_parental_screen.dart';
import 'tv_shell.dart';
import 'tv_touch_components.dart';

/// Entrée séparée : rien de ce catalogue ne rejoint les rangées d'accueil.
class TvAdultScreen extends StatefulWidget {
  const TvAdultScreen({super.key});

  @override
  State<TvAdultScreen> createState() => _TvAdultScreenState();
}

class _TvAdultScreenState extends State<TvAdultScreen> {
  @override
  void dispose() {
    AdultAccess.instance.lock();
    super.dispose();
  }

  void _open(Widget page) {
    if (!AdultAccess.instance.canAccess) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => TvShell(child: page)));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AdultAccess.instance.unlocked,
        builder: (BuildContext context, bool unlocked, Widget? child) =>
            ListView(
          key: const ValueKey<String>('novatube-adult-area'),
          padding: const EdgeInsets.all(TvDimens.touchSafeH),
          children: <Widget>[
            TvTouchPageHeader(title: context.l10n.tvAdultTitle),
            const SizedBox(height: TvDimens.touchGap),
            Text(
              context.l10n.tvAdultIntro,
              style: TvTokens.ui(TvDimens.label, color: TvTokens.muted),
            ),
            const SizedBox(height: TvDimens.touchSafeV),
            if (AdultAccess.instance.canAccess) ...<Widget>[
              _entry(
                Icons.live_tv_rounded,
                context.l10n.tvNavLive,
                () => _open(const TvLiveScreen(adultOnly: true)),
              ),
              _entry(
                Icons.movie_rounded,
                context.l10n.tvNavFilms,
                () => _open(
                  const TvCinemaScreen(kind: CinemaKind.movie, adultOnly: true),
                ),
              ),
              _entry(
                Icons.video_library_rounded,
                context.l10n.tvNavSeries,
                () => _open(
                  const TvCinemaScreen(
                      kind: CinemaKind.series, adultOnly: true),
                ),
              ),
              const SizedBox(height: TvDimens.touchSafeV),
              OutlinedButton.icon(
                onPressed: AdultAccess.instance.lock,
                icon: const Icon(Icons.lock_rounded),
                label: Text(context.l10n.tvAdultLock),
              ),
            ] else ...<Widget>[
              Text(context.l10n.tvAdultLocked),
              const SizedBox(height: TvDimens.touchGap),
              FilledButton.icon(
                onPressed: AdultAccess.instance.blockedForKids
                    ? null
                    : () => authorizeAdultAccess(context),
                icon: const Icon(Icons.lock_open_rounded),
                label: Text(context.l10n.tvAdultOpen),
              ),
            ],
          ],
        ),
      );

  Widget _entry(IconData icon, String label, VoidCallback onPressed) => Padding(
        padding: const EdgeInsets.only(bottom: TvDimens.touchGap),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(TvDimens.touchTarget),
            padding: const EdgeInsets.all(TvDimens.touchSafeH),
          ),
          icon: Icon(icon),
          label: Text(label),
        ),
      );
}
