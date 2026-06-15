// =========================================================
//  tv_search_screen.dart — Recherche 10-foot (clavier D-pad)
// =========================================================
//  Gauche : clavier à l'écran navigable à la télécommande (A-Z, 0-9,
//  espace, effacer). Droite : résultats en temps réel (chaînes dont le
//  nom contient la requête). OK sur un résultat → lecteur plein écran.
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_player_screen.dart';

class TvSearchScreen extends StatefulWidget {
  const TvSearchScreen({super.key});

  @override
  State<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends State<TvSearchScreen> {
  StreamSubscription<List<Channel>>? _sub;
  List<Channel> _all = const <Channel>[];
  String _q = '';
  List<Channel> _results = const <Channel>[];
  Timer? _debounce;

  // Borne anti-surcharge : sur un boîtier TV modeste, afficher des centaines de
  // vignettes (et leurs logos réseau) d'un coup peut faire planter l'app. On
  // limite à 60 résultats — largement assez pour trouver une chaîne.
  static const int _maxResults = 60;

  // Le clavier est construit UNE SEULE FOIS. En réutilisant la MÊME instance
  // dans build(), Flutter NE reconstruit PAS son sous-arbre à chaque frappe →
  // la touche focus n'est jamais perdue (corrige « impossible d'écrire d'autres
  // lettres »). Les callbacks sont des méthodes stables de ce State.
  late final Widget _keyboard =
      _Keyboard(onType: _type, onBackspace: _backspace, onClear: _clear);

  @override
  void initState() {
    super.initState();
    _all = PlaylistRepository.instance.currentChannels
        .where((Channel c) => c.isLive)
        .toList(growable: false);
    _sub =
        PlaylistRepository.instance.channelsStream.listen((List<Channel> ch) {
      if (!mounted) return;
      _all = ch.where((Channel c) => c.isLive).toList(growable: false);
      _runSearch();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _type(String ch) {
    setState(() => _q += ch);
    _schedule();
  }

  void _backspace() {
    if (_q.isEmpty) return;
    setState(() => _q = _q.substring(0, _q.length - 1));
    _schedule();
  }

  void _clear() {
    _debounce?.cancel();
    setState(() {
      _q = '';
      _results = const <Channel>[];
    });
  }

  // Debounce : on ne recalcule/réaffiche la grille (et ses logos) qu'après une
  // courte pause → frappe fluide et pas de tempête de chargements d'images.
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  void _runSearch() {
    final String t = _q.trim().toLowerCase();
    final List<Channel> r = t.isEmpty
        ? const <Channel>[]
        : _all
            .where((Channel c) => c.cleanName.toLowerCase().contains(t))
            .take(_maxResults)
            .toList(growable: false);
    if (mounted) setState(() => _results = r);
  }

  @override
  Widget build(BuildContext context) {
    final List<Channel> res = _results;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ----- Clavier (instance STABLE → non reconstruite à chaque frappe) -----
        SizedBox(width: 380, child: _keyboard),
        const SizedBox(width: TvDimens.gutter),
        // ----- Requête + résultats -----
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: TvTokens.card,
                  borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                ),
                child: Text(
                  _q.isEmpty ? context.l10n.tvSearchHint : _q,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TvDimens.title,
                    fontWeight: FontWeight.w700,
                    color: _q.isEmpty ? TvTokens.mutedDim : TvTokens.text,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: res.isEmpty
                    ? Center(
                        child: Text(
                          _q.trim().isEmpty ? '' : context.l10n.tvNoResult,
                          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 230,
                          mainAxisExtent: 120,
                          crossAxisSpacing: TvDimens.gutter,
                          mainAxisSpacing: TvDimens.gutter,
                        ),
                        itemCount: res.length,
                        itemBuilder: (BuildContext context, int i) => TvFocusable(
                          scale: TvFocusScale.small,
                          onSelect: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TvPlayerScreen(channels: res, startIndex: i),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Expanded(
                                  child: (res[i].logoUrl != null && res[i].logoUrl!.isNotEmpty)
                                      ? CachedNetworkImage(
                                          imageUrl: res[i].logoUrl!,
                                          fit: BoxFit.contain,
                                          memCacheWidth: 200,
                                          fadeInDuration: const Duration(milliseconds: 150),
                                          placeholder: (_, __) => Opacity(opacity: 0.35, child: _ini(res[i])),
                                          errorWidget: (_, __, ___) => _ini(res[i]))
                                      : _ini(res[i]),
                                ),
                                const SizedBox(height: 6),
                                Text(res[i].cleanName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: TvDimens.caption,
                                        fontWeight: FontWeight.w600,
                                        color: TvTokens.text)),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ini(Channel c) => Center(
        child: Text(c.initials,
            style: TextStyle(fontSize: TvDimens.title, fontWeight: FontWeight.w800, color: TvTokens.muted)),
      );
}

class _Keyboard extends StatelessWidget {
  const _Keyboard({required this.onType, required this.onBackspace, required this.onClear});
  final ValueChanged<String> onType;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const List<String> _keys = <String>[
    'A', 'B', 'C', 'D', 'E', 'F',
    'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R',
    'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', '0', '1', '2', '3',
    '4', '5', '6', '7', '8', '9',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.l10n.tvNavSearch,
            style: TextStyle(fontSize: TvDimens.displayS, fontWeight: FontWeight.w800, color: TvTokens.text)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < _keys.length; i++)
              _Key(label: _keys[i], autofocus: i == 0, onTap: () => onType(_keys[i])),
            _Key(label: '␣', wide: true, onTap: () => onType(' ')),
            _Key(label: '⌫', onTap: onBackspace),
            _Key(label: '✕', onTap: onClear),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, this.wide = false, this.autofocus = false});
  final String label;
  final VoidCallback onTap;
  final bool wide;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 116 : 54,
      height: 54,
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onTap,
        builder: (BuildContext context, bool focused) {
          return Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: focused ? TvTokens.gold : TvTokens.sel,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: TvDimens.title,
                    fontWeight: FontWeight.w700,
                    color: focused ? const Color(0xFF1A1206) : TvTokens.text)),
          );
        },
      ),
    );
  }
}
