// =========================================================
//  tv_cinematic_home.dart — Accueil « Ce soir » (maquette Lionel)
// =========================================================
//  Gauche : une carte verre, le programme ou le film déjà sur la
//  box, bouton lecture. Droite : le Direct, puis deux rangées
//  horizontales. Fond obsidienne (#070708, TvTokens.bg), plus
//  profond que le gris confort #121212 : la maquette gagne sur
//  CE fond seulement. Le texte et le cuivre restent les jetons
//  du thème (lisible le soir, pas un néon).
//
//  Le flou n'est posé que si [blur] est vrai. Sinon le verre est
//  un aplat. Les affiches ne viennent que d'une URL de la liste.
// =========================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_app_tokens.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_glass.dart';
import 'tv_tonight.dart';

class TvCinematicHome extends StatelessWidget {
  const TvCinematicHome({
    super.key,
    required this.board,
    required this.blur,
    required this.onPlay,
    required this.onLive,
    required this.onFilms,
    required this.onSeries,
    required this.onServer,
    required this.onSettings,
  });

  final TonightBoard board;
  final bool blur;
  final ValueChanged<TonightPiece> onPlay;
  final VoidCallback onLive;
  final VoidCallback onFilms;
  final VoidCallback onSeries;
  final VoidCallback onServer;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final bool heroFirst = board.hasHero;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          flex: 5,
          child: _Hero(
            board: board,
            blur: blur,
            autofocus: heroFirst,
            onPlay: board.hero == null ? null : () => onPlay(board.hero!),
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          flex: 6,
          child: _RailColumn(
            board: board,
            blur: blur,
            liveAutofocus: !heroFirst,
            onLive: onLive,
            onFilms: onFilms,
            onSeries: onSeries,
            onServer: onServer,
            onSettings: onSettings,
            onPlay: onPlay,
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.board,
    required this.blur,
    required this.autofocus,
    required this.onPlay,
  });

  final TonightBoard board;
  final bool blur;
  final bool autofocus;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final TonightPiece? hero = board.hero;
    final String title = hero?.title ?? context.l10n.tvHomeInvite;
    final String detail = board.heroDetail;
    return TvGlassPanel(
      blur: blur,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.tvVoiceTonightTitle,
            style: TvAppTokens.of(context).ui(
              TvDimens.label,
              weight: FontWeight.w700,
              color: TvTokens.accentBright,
            ),
          ),
          if (detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvAppTokens.of(context).ui(
                TvDimens.caption,
                color: TvAppTokens.of(context).muted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _Artwork(
                    url: hero?.artworkUrl,
                    title: title,
                  ),
                ),
                if (onPlay != null)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: _PlayButton(autofocus: autofocus, onSelect: onPlay!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TvAppTokens.of(context).display(
              TvDimens.headline,
              color: TvAppTokens.of(context).text,
            ),
          ),
          if (hero != null && hero.meta.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              hero.meta,
              style: TvAppTokens.of(context).ui(
                TvDimens.caption,
                color: TvAppTokens.of(context).muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.autofocus, required this.onSelect});
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      showGlow: false,
      borderRadius: BorderRadius.circular(40),
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: TvTokens.accent.withValues(alpha: focused ? 0.95 : 0.82),
            border: Border.all(
              color: focused ? TvTokens.accentBright : TvTokens.accent,
              width: focused ? 2 : 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: TvTokens.accent.withValues(alpha: focused ? 0.35 : 0.12),
                blurRadius: focused ? 16 : 8,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            size: 36,
            color: TvTokens.onAccent,
          ),
        );
      },
    );
  }
}

class _RailColumn extends StatelessWidget {
  const _RailColumn({
    required this.board,
    required this.blur,
    required this.liveAutofocus,
    required this.onLive,
    required this.onFilms,
    required this.onSeries,
    required this.onServer,
    required this.onSettings,
    required this.onPlay,
  });

  final TonightBoard board;
  final bool blur;
  final bool liveAutofocus;
  final VoidCallback onLive;
  final VoidCallback onFilms;
  final VoidCallback onSeries;
  final VoidCallback onServer;
  final VoidCallback onSettings;
  final ValueChanged<TonightPiece> onPlay;

  @override
  Widget build(BuildContext context) {
    final bool vod = board.recommendations.any((TonightPiece p) => p.watch != null);
    final String recLabel =
        vod ? context.l10n.tvHomeContinue : context.l10n.tvHomeFavorites;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _WideAction(
          icon: Icons.live_tv_rounded,
          label: context.l10n.tvNavLive,
          blur: blur,
          autofocus: liveAutofocus,
          onSelect: onLive,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              _Chip(icon: Icons.movie_rounded, label: context.l10n.tvNavFilms, onSelect: onFilms),
              _Chip(icon: Icons.video_library_rounded, label: context.l10n.tvNavSeries, onSelect: onSeries),
              _Chip(icon: Icons.dns_rounded, label: context.l10n.tvNavServer, onSelect: onServer),
              _Chip(icon: Icons.settings_rounded, label: context.l10n.tvNavSettings, onSelect: onSettings),
            ],
          ),
        ),
        if (board.recommendations.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _RowLabel(recLabel),
          const SizedBox(height: 8),
          Expanded(
            child: _CardRow(pieces: board.recommendations, onPlay: onPlay),
          ),
        ],
        if (board.discover.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _RowLabel(context.l10n.tvHomePopular),
          const SizedBox(height: 8),
          Expanded(
            child: _CardRow(pieces: board.discover, onPlay: onPlay),
          ),
        ],
        if (board.recommendations.isEmpty && board.discover.isEmpty)
          const Spacer(),
      ],
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TvAppTokens.of(context).ui(
        TvDimens.label,
        weight: FontWeight.w700,
        color: TvAppTokens.of(context).text,
      ),
    );
  }
}

class _WideAction extends StatelessWidget {
  const _WideAction({
    required this.icon,
    required this.label,
    required this.blur,
    required this.autofocus,
    required this.onSelect,
  });

  final IconData icon;
  final String label;
  final bool blur;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      showGlow: false,
      borderRadius: BorderRadius.circular(18),
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return TvGlassPanel(
          blur: blur,
          focused: focused,
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(icon, color: TvTokens.accentBright, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TvAppTokens.of(context).ui(
                    TvDimens.titleS,
                    weight: FontWeight.w700,
                    color: TvAppTokens.of(context).text,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onSelect});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TvFocusBuilder(
        scale: TvFocusScale.small,
        showGlow: false,
        borderRadius: BorderRadius.circular(14),
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          final Color fg = focused ? TvTokens.onAccent : TvAppTokens.of(context).text;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: focused
                  ? TvTokens.accent
                  : TvTokens.bg.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused
                    ? TvTokens.accentBright
                    : TvTokens.accent.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TvAppTokens.of(context).ui(
                    TvDimens.caption,
                    weight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.pieces, required this.onPlay});
  final List<TonightPiece> pieces;
  final ValueChanged<TonightPiece> onPlay;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: pieces.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (BuildContext context, int i) {
        final TonightPiece piece = pieces[i];
        return _PosterCard(piece: piece, onSelect: () => onPlay(piece));
      },
    );
  }
}

class _PosterCard extends StatefulWidget {
  const _PosterCard({required this.piece, required this.onSelect});
  final TonightPiece piece;
  final VoidCallback onSelect;

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      showGlow: false,
      borderRadius: BorderRadius.circular(14),
      onSelect: widget.piece.canPlay ? widget.onSelect : null,
      onFocusChange: (bool focused) {
        if (!focused) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 140),
          curve: TvDimens.focusCurve,
        );
      },
      builder: (BuildContext context, bool focused) {
        return AnimatedContainer(
          duration: TvDimens.focusAnim,
          curve: TvDimens.focusCurve,
          width: 132,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused
                  ? TvTokens.accentBright
                  : TvTokens.accent.withValues(alpha: 0.22),
              width: focused ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _Artwork(
                  url: widget.piece.artworkUrl,
                  title: widget.piece.title,
                ),
              ),
              Container(
                color: TvTokens.bg.withValues(alpha: 0.88),
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Text(
                  widget.piece.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvAppTokens.of(context).ui(
                    TvDimens.caption,
                    weight: FontWeight.w500,
                    color: TvAppTokens.of(context).text,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Jaquette distante, ou monogramme si la source n'a pas d'image.
/// Jamais une affiche embarquée.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.title});
  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final String? art = url;
    if (art == null) return _Monogram(title: title);
    return CachedNetworkImage(
      imageUrl: art,
      fit: BoxFit.cover,
      memCacheWidth: 360,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => _Monogram(title: title),
      errorWidget: (_, __, ___) => _Monogram(title: title),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final String trimmed = title.trim();
    final String letter = trimmed.isEmpty
        ? ''
        : String.fromCharCodes(<int>[trimmed.runes.first]).toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            TvTokens.accent.withValues(alpha: 0.22),
            TvTokens.bg,
          ],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TvAppTokens.of(context).display(
            42,
            color: TvTokens.accentBright,
          ),
        ),
      ),
    );
  }
}
