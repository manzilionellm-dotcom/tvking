// =========================================================
//  tv_epg_preview_screen.dart — Guide avec un petit direct
// =========================================================
//  L'accueil a déjà les rangées (reprise, favoris). La liste
//  Direct a déjà un aperçu vidéo. Ce qui manquait : le guide,
//  avec le programme en cours ET l'image de la chaîne focalisée.
//
//  On réutilise [TvLivePreview] : pas de second lecteur, le
//  décodeur n'existe qu'après 1,5 s d'immobilité, et il est
//  détruit dès qu'on change de ligne. Sur une box lente, le
//  défilement ne voit que le logo.
//
//  Le guide n'est lu que pour la chaîne focalisée. On ne
//  demande pas 50 000 programmes d'un coup.
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../security/data/parental_controls.dart';
import '../core/tv_app_tokens.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../data/home_shelves.dart';
import 'tv_live_preview.dart';
import 'tv_player_screen.dart';
import 'tv_shell.dart';

/// Programme en cours et le suivant, pour une seule chaîne.
class TvEpgWindow {
  const TvEpgWindow({this.now, this.next});

  final EpgProgram? now;
  final EpgProgram? next;
}

/// Charge le créneau d'une chaîne. Les tests en passent un faux :
/// l'écran ne touche alors ni la base ni le réseau.
typedef TvEpgWindowLoader = Future<TvEpgWindow> Function(String channelId);

class TvEpgPreviewScreen extends StatefulWidget {
  const TvEpgPreviewScreen({
    super.key,
    this.channels,
    this.loadWindow,
    this.preview,
  });

  /// Null : les chaînes déjà en mémoire. Une liste fournie (test)
  /// ne s'abonne pas au dépôt.
  final List<Channel>? channels;

  final TvEpgWindowLoader? loadWindow;

  /// Null : l'aperçu vidéo existant. Un test peut dessiner autre chose.
  final Widget Function(Channel channel)? preview;

  @override
  State<TvEpgPreviewScreen> createState() => _TvEpgPreviewScreenState();
}

class _TvEpgPreviewScreenState extends State<TvEpgPreviewScreen> {
  static const double _rowExtent = 72;

  List<Channel> _source = const <Channel>[];
  List<Channel> _rows = const <Channel>[];
  int _index = 0;
  Future<TvEpgWindow> _window = Future<TvEpgWindow>.value(const TvEpgWindow());
  StreamSubscription<List<Channel>>? _sub;

  @override
  void initState() {
    super.initState();
    if (widget.channels != null) {
      _source = widget.channels!;
    } else {
      _source = PlaylistRepository.instance.currentChannels;
      _sub = PlaylistRepository.instance.channelsStream.listen((
        List<Channel> list,
      ) {
        _source = list;
        _apply();
      });
    }
    _rows = _filter(_source);
    _window = _loadCurrent();
    ParentalControls.instance.kidsMode.addListener(_apply);
  }

  @override
  void dispose() {
    _sub?.cancel();
    ParentalControls.instance.kidsMode.removeListener(_apply);
    // Le plein écran a besoin du décodeur. On le rend tout de suite.
    unawaited(TvLivePreview.releaseActive());
    super.dispose();
  }

  List<Channel> _filter(List<Channel> all) {
    final bool kids = ParentalControls.instance.kidsMode.value;
    final List<Channel> out = <Channel>[];
    for (final Channel c in all) {
      if (!c.isLive) continue;
      if (kids && (roughLooksAdult(c.name) || roughLooksAdult(c.category))) {
        continue;
      }
      out.add(c);
    }
    return out;
  }

  void _apply() {
    if (!mounted) return;
    final String? previous = _rows.isEmpty ? null : _rows[_index].id;
    final List<Channel> rows = _filter(_source);
    var index = _index;
    if (rows.isEmpty) {
      index = 0;
    } else if (index >= rows.length) {
      index = rows.length - 1;
    }
    final String? nextId = rows.isEmpty ? null : rows[index].id;
    setState(() {
      _rows = rows;
      _index = index;
      if (nextId != previous) _window = _loadCurrent();
    });
  }

  Future<TvEpgWindow> _loadCurrent() {
    if (_rows.isEmpty) return Future<TvEpgWindow>.value(const TvEpgWindow());
    final String id = _rows[_index].id;
    final TvEpgWindowLoader? custom = widget.loadWindow;
    if (custom != null) return custom(id);
    return _fromRepository(id);
  }

  Future<TvEpgWindow> _fromRepository(String id) async {
    try {
      final EpgProgram? now = await EpgRepository.instance.currentProgram(id);
      final EpgProgram? next = await EpgRepository.instance.nextProgram(id);
      return TvEpgWindow(now: now, next: next);
    } catch (_) {
      return const TvEpgWindow();
    }
  }

  void _onFocus(int i, bool focused) {
    if (!focused || i == _index || i < 0 || i >= _rows.length) return;
    setState(() {
      _index = i;
      _window = _loadCurrent();
    });
  }

  void _open(int i) {
    if (i < 0 || i >= _rows.length) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvShell(
          applySafeArea: false,
          child: TvPlayerScreen(channels: _rows, startIndex: i),
        ),
      ),
    );
  }

  Widget _previewOf(Channel channel) {
    final Widget Function(Channel channel)? custom = widget.preview;
    if (custom != null) return custom(channel);
    return TvLivePreview(channel: channel);
  }

  @override
  Widget build(BuildContext context) {
    final TvAppTokens tokens = TvAppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TvDimens.safeH,
            TvDimens.safeV,
            TvDimens.safeH,
            TvDimens.gutter,
          ),
          child: Text(
            context.l10n.tvNavGuide,
            style: tokens.ui(TvDimens.headline, weight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: _rows.isEmpty
              ? Center(
                  child: Text(
                    context.l10n.tvNoChannels,
                    style: tokens.ui(TvDimens.title, color: tokens.muted),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: _list(tokens)),
                    SizedBox(
                      width: TvDimens.columnWidth * 8,
                      child: _side(tokens, _rows[_index]),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _list(TvAppTokens tokens) {
    return ListView.builder(
      itemCount: _rows.length,
      itemExtent: _rowExtent,
      itemBuilder: (BuildContext context, int i) {
        final Channel channel = _rows[i];
        return TvFocusable(
          key: ValueKey<String>(channel.id),
          autofocus: i == 0,
          scale: TvFocusScale.none,
          onFocusChange: (bool focused) => _onFocus(i, focused),
          onSelect: () => _open(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: TvDimens.gutter),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                channel.cleanName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.ui(
                  TvDimens.titleS,
                  weight: i == _index ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _side(TvAppTokens tokens, Channel channel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TvDimens.gutter,
        0,
        TvDimens.safeH,
        TvDimens.safeV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              child: _previewOf(channel),
            ),
          ),
          const SizedBox(height: TvDimens.gutter),
          FutureBuilder<TvEpgWindow>(
            future: _window,
            builder: (BuildContext context, AsyncSnapshot<TvEpgWindow> snap) {
              final EpgProgram? now = snap.data?.now;
              final EpgProgram? next = snap.data?.next;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (now != null)
                    Text(
                      now.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.ui(
                        TvDimens.title,
                        weight: FontWeight.w600,
                      ),
                    ),
                  if (now != null)
                    Text(
                      now.timeRangeShort,
                      style: tokens.ui(TvDimens.label, color: tokens.muted),
                    ),
                  if (next != null) ...<Widget>[
                    const SizedBox(height: TvDimens.rowGap),
                    Text(
                      next.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.ui(TvDimens.body, color: tokens.muted),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
