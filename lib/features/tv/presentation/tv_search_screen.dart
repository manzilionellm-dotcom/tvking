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
import '../../channels/data/search_history_repository.dart';
import '../../vod/data/recent_vod_repository.dart';
import '../../vod/data/series_repository.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/domain/vod_movie.dart';
import '../../vod/domain/vod_series.dart';
import 'tv_series_screen.dart';
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
  String _q = '';
  List<Channel> _results = const <Channel>[];
  // Résultats VOD (façon Netflix : la recherche couvre AUSSI films/séries).
  List<VodMovie> _films = const <VodMovie>[];
  List<VodSeries> _series = const <VodSeries>[];
  Timer? _debounce;
  // Jeton anti-désordre : chaque recherche asynchrone porte un numéro. Un
  // résultat qui revient APRÈS qu'une frappe plus récente soit partie est
  // ignoré (sinon une vieille requête lente écraserait la nouvelle).
  int _epoch = 0;

  // Borne anti-surcharge : 60 résultats max (largement assez pour trouver une
  // chaîne). C'est AUSSI la LIMIT SQL → la base ne renvoie jamais plus que ça,
  // donc on ne matérialise jamais des centaines de chaînes en RAM.
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
    // Charge l'historique des recherches (best-effort) pour proposer les
    // dernières recherches d'un clic quand la requête est vide.
    SearchHistoryRepository.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // Relance une recherche depuis une pastille d'historique (sans re-taper).
  void _searchFrom(String query) {
    _debounce?.cancel();
    setState(() => _q = query);
    _runSearch();
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
    _epoch++; // annule toute recherche en vol
    setState(() {
      _q = '';
      _results = const <Channel>[];
      _films = const <VodMovie>[];
      _series = const <VodSeries>[];
    });
  }

  // Debounce : on ne relance la recherche (et le rendu des logos) qu'après une
  // courte pause → frappe fluide et pas de tempête de requêtes/chargements.
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  // Recherche EN BASE (SQL LIKE + LIMIT, cf. PlaylistRepository.searchLiveChannels)
  // : on ne garde JAMAIS toute la liste de chaînes en RAM. La base renvoie au
  // plus _maxResults lignes correspondantes — c'est le principe anti-OOM
  // « façon TiviMate » appliqué à la recherche (tient 100 000 chaînes).
  Future<void> _runSearch() async {
    final String t = _q.trim();
    final int epoch = ++_epoch;
    if (t.isEmpty) {
      if (mounted) {
        setState(() {
          _results = const <Channel>[];
          _films = const <VodMovie>[];
          _series = const <VodSeries>[];
        });
      }
      return;
    }
    final List<Channel> r = await PlaylistRepository.instance
        .searchLiveChannels(t, limit: _maxResults);
    // Une frappe plus récente est partie entre-temps → on jette ce résultat.
    if (!mounted || epoch != _epoch) return;
    setState(() => _results = r);

    // ----- FILMS & SÉRIES (façon Netflix) -----
    // Les catalogues VOD sont en CACHE MÉMOIRE (déjà plafonné RAM). Le tout
    // est best-effort : les sections apparaissent quand elles sont prêtes,
    // et le jeton `epoch` jette tout résultat périmé. Une erreur réseau ne
    // casse jamais la recherche des chaînes.
    final String q = t.toLowerCase();
    try {
      final List<VodMovie> movies = await VodRepository.instance.fetchMovies();
      if (!mounted || epoch != _epoch) return;
      setState(() => _films = movies
          .where((VodMovie m) => m.name.toLowerCase().contains(q))
          .take(20)
          .toList(growable: false));
    } catch (_) {/* pas de VOD → section absente */}
    try {
      final List<VodSeries> series =
          await SeriesRepository.instance.fetchSeries();
      if (!mounted || epoch != _epoch) return;
      setState(() => _series = series
          .where((VodSeries s) => s.name.toLowerCase().contains(q))
          .take(20)
          .toList(growable: false));
    } catch (_) {/* idem */}
  }

  @override
  Widget build(BuildContext context) {
    final List<Channel> res = _results;
    // Material (transparent) au SOMMET de l'écran : cet écran est poussé depuis
    // PLUSIEURS endroits (boutons « Recherche » de tous les templates), parfois
    // sans ancêtre Material → Flutter dessinait alors des DOUBLES SOULIGNEMENTS
    // JAUNES sous chaque lettre du clavier. En s'enveloppant lui-même, l'écran
    // est TOUJOURS propre, quel que soit l'appelant (clavier net, « VIP »).
    return Material(
      type: MaterialType.transparency,
      child: Row(
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
                child: (res.isEmpty && _films.isEmpty && _series.isEmpty)
                    ? _buildEmptyState(context)
                    // RÉSULTATS EN SECTIONS (façon Netflix) : Chaînes, Films,
                    // Séries — chaque section est une rangée HORIZONTALE
                    // paresseuse (seules les vignettes visibles existent).
                    : ListView(
                        children: <Widget>[
                          if (res.isNotEmpty) ...<Widget>[
                            _sectionTitle(context.l10n.tvTabChannels),
                            SizedBox(
                              height: 132,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                addAutomaticKeepAlives: false,
                                itemExtent: 210,
                                itemCount: res.length,
                                itemBuilder: (BuildContext c, int i) =>
                                    Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _channelTile(res, i),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_films.isNotEmpty) ...<Widget>[
                            _sectionTitle(context.l10n.tvNavFilms),
                            SizedBox(
                              height: 214,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                addAutomaticKeepAlives: false,
                                itemExtent: 140,
                                itemCount: _films.length,
                                itemBuilder: (BuildContext c, int i) =>
                                    Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _filmCard(_films[i]),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_series.isNotEmpty) ...<Widget>[
                            _sectionTitle(context.l10n.tvNavSeries),
                            SizedBox(
                              height: 214,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                addAutomaticKeepAlives: false,
                                itemExtent: 140,
                                itemCount: _series.length,
                                itemBuilder: (BuildContext c, int i) =>
                                    Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _seriesCard(_series[i]),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TvTokens.mutedDim,
            letterSpacing: 1.6,
          ),
        ),
      );

  /// Vignette CHAÎNE (logo + nom). OK = lecture dans la liste des résultats.
  Widget _channelTile(List<Channel> list, int i) {
    final Channel ch = list[i];
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: () {
        // La recherche a servi (on ouvre un résultat) → on la mémorise.
        SearchHistoryRepository.instance.add(_q);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TvPlayerScreen(channels: list, startIndex: i),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: (ch.logoUrl != null && ch.logoUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: ch.logoUrl!,
                      fit: BoxFit.contain,
                      memCacheWidth: 200,
                      // Le DISQUE aussi est borné : sans ça, la box stocke l'affiche
                      // en taille d'origine (2000 px) alors qu'on ne l'affiche jamais
                      // au-delà de 200 px — sur un catalogue de 100 000 titres, c'est
                      // des gigaoctets pour rien.
                      maxWidthDiskCache: 200,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) =>
                          Opacity(opacity: 0.35, child: _ini(ch)),
                      errorWidget: (_, __, ___) => _ini(ch))
                  : _ini(ch),
            ),
            const SizedBox(height: 6),
            Text(ch.cleanName,
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
    );
  }

  /// Affiche FILM (poster 2:3 + titre). OK = lecture + mémorise la recherche.
  Widget _filmCard(VodMovie m) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: () {
        SearchHistoryRepository.instance.add(_q);
        RecentVodRepository.instance.add(m); // alimente « Derniers vus »
        final Channel ch = Channel(
          id: m.id,
          name: m.name,
          category: m.category,
          streamUrl: m.streamUrl,
          isLive: false,
          logoUrl: m.posterUrl,
        );
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                TvPlayerScreen(channels: <Channel>[ch], startIndex: 0),
          ),
        );
      },
      child: _posterAndTitle(m.posterUrl, m.name, Icons.movie_rounded),
    );
  }

  /// Affiche SÉRIE (poster + titre). OK = fiche de la série (saisons/épisodes).
  Widget _seriesCard(VodSeries s) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: () {
        SearchHistoryRepository.instance.add(_q);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TvSeriesDetailScreen(series: s),
          ),
        );
      },
      child: _posterAndTitle(s.posterUrl, s.name, Icons.live_tv_rounded),
    );
  }

  Widget _posterAndTitle(String? url, String name, IconData fallbackIcon) {
    final Widget fallback = Container(
      color: TvTokens.tile,
      child: Center(
          child: Icon(fallbackIcon, size: 30, color: TvTokens.mutedDim)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (url == null || url.isEmpty)
                ? fallback
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: 300,
                    // Le DISQUE aussi est borné : sans ça, la box stocke l'affiche
                    // en taille d'origine (2000 px) alors qu'on ne l'affiche jamais
                    // au-delà de 300 px — sur un catalogue de 100 000 titres, c'est
                    // des gigaoctets pour rien.
                    maxWidthDiskCache: 300,
                    placeholder: (_, __) => fallback,
                    errorWidget: (_, __, ___) => fallback,
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: TvDimens.caption,
                  fontWeight: FontWeight.w600,
                  color: TvTokens.text)),
        ),
      ],
    );
  }

  // État « pas de grille » : soit « aucun résultat » (requête en cours), soit
  // les RECHERCHES RÉCENTES cliquables (requête vide) — confort D-pad.
  Widget _buildEmptyState(BuildContext context) {
    if (_q.trim().isNotEmpty) {
      return Center(
        child: Text(
          context.l10n.tvNoResult,
          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim),
        ),
      );
    }
    final List<String> hist = SearchHistoryRepository.instance.items;
    if (hist.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.tvRecentSearches,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: TvTokens.mutedDim,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final String h in hist)
                TvFocusable(
                  scale: TvFocusScale.small,
                  onSelect: () => _searchFrom(h),
                  child: _chip(icon: Icons.history_rounded, label: h),
                ),
              TvFocusable(
                scale: TvFocusScale.small,
                onSelect: () async {
                  await SearchHistoryRepository.instance.clear();
                  if (mounted) setState(() {});
                },
                child: _chip(
                    icon: Icons.close_rounded,
                    label: context.l10n.buttonClear,
                    muted: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, bool muted = false}) {
    final Color fg = muted ? TvTokens.muted : TvTokens.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: TvTokens.muted),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

  Widget _ini(Channel c) => Center(
        child: Text(c.initials,
            style: TextStyle(fontSize: TvDimens.title, fontWeight: FontWeight.w800, color: TvTokens.muted)),
      );
}

/// Langues du clavier à l'écran. Le client peut BASCULER d'une langue à l'autre
/// pour taper des noms de chaînes/films dans leur alphabet (ex. chaînes arabes,
/// chaînes nordiques). Ajouter une langue = ajouter une entrée ici + son tracé.
enum _KbLang { latin, nordic, arabic }

class _Keyboard extends StatefulWidget {
  const _Keyboard(
      {required this.onType, required this.onBackspace, required this.onClear});
  final ValueChanged<String> onType;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  State<_Keyboard> createState() => _KeyboardState();
}

class _KeyboardState extends State<_Keyboard> {
  // Langue de saisie ACTIVE (par défaut l'alphabet latin, qui couvre FR/EN…).
  _KbLang _lang = _KbLang.latin;

  // Tracés par langue. On garde les CHIFFRES sur chaque tracé (utile partout).
  static const List<String> _digits = <String>[
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  ];
  static const List<String> _latin = <String>[
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];
  // Nordique (suédois/danois/norvégien) : latin + Å Ä Ö Æ Ø.
  static const List<String> _nordic = <String>[
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    'Å', 'Ä', 'Ö', 'Æ', 'Ø',
  ];
  // Arabe : les 28 lettres + hamza/ta marbouta/alif maqsoura usuels.
  static const List<String> _arabic = <String>[
    'ا', 'ب', 'ت', 'ث', 'ج', 'ح', 'خ', 'د', 'ذ', 'ر', 'ز', 'س', 'ش', //
    'ص', 'ض', 'ط', 'ظ', 'ع', 'غ', 'ف', 'ق', 'ك', 'ل', 'م', 'ن', 'ه',
    'و', 'ي', 'ء', 'آ', 'ة', 'ى',
  ];

  List<String> get _letters => switch (_lang) {
        _KbLang.latin => _latin,
        _KbLang.nordic => _nordic,
        _KbLang.arabic => _arabic,
      };

  // Étiquette COURTE de chaque langue (sur le bouton de bascule).
  static String _label(_KbLang l) => switch (l) {
        _KbLang.latin => 'ABC',
        _KbLang.nordic => 'ÅÄÖ',
        _KbLang.arabic => 'عربي',
      };

  // Nom LISIBLE de la langue (pour le libellé « Langue : … »).
  static String _name(_KbLang l) => switch (l) {
        _KbLang.latin => 'ABC (latin)',
        _KbLang.nordic => 'Nordique ÅÄÖ',
        _KbLang.arabic => 'العربية',
      };

  void _cycleLang() {
    setState(() {
      const List<_KbLang> all = _KbLang.values;
      _lang = all[(_lang.index + 1) % all.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<String> letters = _letters;
    final _KbLang next = _KbLang.values[(_lang.index + 1) % _KbLang.values.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.l10n.tvNavSearch,
            style: TextStyle(
                fontSize: TvDimens.displayS,
                fontWeight: FontWeight.w800,
                color: TvTokens.text)),
        const SizedBox(height: 12),
        // BOUTON DE LANGUE — en HAUT, bien visible (pensé personnes âgées).
        // Montre la langue ACTIVE et vers quoi on bascule. OK = langue suivante.
        _LangKey(
          current: _name(_lang),
          next: _label(next),
          onTap: _cycleLang,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < letters.length; i++)
              _Key(
                  label: letters[i],
                  autofocus: i == 0,
                  onTap: () => widget.onType(letters[i])),
            for (final String d in _digits)
              _Key(label: d, onTap: () => widget.onType(d)),
            _Key(label: '␣', wide: true, onTap: () => widget.onType(' ')),
            _Key(label: '⌫', onTap: widget.onBackspace),
            _Key(label: '✕', onTap: widget.onClear),
          ],
        ),
      ],
    );
  }
}

/// Bouton DORÉ de bascule de langue du clavier. Large et lisible : montre la
/// langue active + un chevron vers la suivante. OK = passe à la langue suivante.
class _LangKey extends StatelessWidget {
  const _LangKey(
      {required this.current, required this.next, required this.onTap});
  final String current;
  final String next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 244,
      height: 54,
      child: TvFocusBuilder(
        scale: TvFocusScale.small,
        onSelect: onTap,
        builder: (BuildContext context, bool focused) {
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: focused ? TvTokens.gold : TvTokens.sel,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              border: Border.all(
                  color: focused ? TvTokens.gold : TvTokens.goldBright,
                  width: 1.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.language_rounded,
                    size: 22,
                    color: focused ? const Color(0xFF1A1206) : TvTokens.goldBright),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Langue : $current  →  $next',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.body,
                        fontWeight: FontWeight.w800,
                        color: focused ? const Color(0xFF1A1206) : TvTokens.text),
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
              color: focused ? TvTokens.ember : TvTokens.sel,
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
