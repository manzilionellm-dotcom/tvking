// =========================================================
//  tv_search_screen.dart — Recherche 10-foot + voix
// =========================================================
//  Gauche : clavier télécommande, et un bouton micro.
//  Droite : chaînes, films et séries de la playlist, ou le
//  guide du soir si la phrase est « qu'est-ce qu'il y a ce soir ? ».
//
//  Le micro est optionnel. Pas de micro, reconnaissance absente,
//  phrase incomprise : un message s'affiche et le clavier reste.
//  Rien de tout ça n'est appelé pendant qu'une chaîne est ouverte
//  (VoiceHotkey vérifie TvActivity). Ici, ouvrir un résultat est
//  un choix de la personne (OK), comme avant.
// =========================================================
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/data/ai_search_service.dart';
import '../../channels/domain/channel.dart';
import '../../cinema/data/cinema_repository.dart';
import '../../cinema/domain/cinema_models.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../remote/domain/remote_typing_hub.dart';
import '../../security/data/parental_controls.dart';
import '../../voice/data/voice_capture.dart';
import '../../voice/data/voice_remote_assist.dart';
import '../../voice/domain/tonight_plan.dart';
import '../../voice/domain/voice_catalog.dart';
import '../../voice/domain/voice_query.dart';
import '../../voice/presentation/voice_navigation.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_cinema_detail_screen.dart';
import 'tv_player_screen.dart';
import 'tv_shell.dart';

class TvSearchScreen extends StatefulWidget {
  const TvSearchScreen({
    super.key,
    this.initialQuery = '',
    this.autoListen = false,
  });

  /// Phrase déjà reconnue (micro système) à chercher tout de suite.
  final String initialQuery;

  /// Ouvre le micro dès l'affichage (touche de la télécommande).
  final bool autoListen;

  @override
  State<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends State<TvSearchScreen> {
  StreamSubscription<List<Channel>>? _sub;
  List<Channel> _channels = const <Channel>[];
  String _q = '';
  List<VoiceHit> _hits = const <VoiceHit>[];
  TonightLineup? _tonight;
  String? _banner;
  bool _listening = false;
  int _gen = 0;
  Timer? _debounce;
  late final VoiceSearchHooks _hooks;
  // Une seule fermeture : le hub compare l'identité pour se désinscrire.
  late final bool Function(String text) _remoteTyping = _onRemoteQuery;

  // Le clavier est construit UNE SEULE FOIS. Même instance dans build() →
  // Flutter ne reconstruit pas son sous-arbre à chaque frappe, le focus
  // reste sur la touche.
  late final Widget _keyboard = _Keyboard(
    onType: _type,
    onBackspace: _backspace,
    onClear: _clear,
    onMic: _listen,
  );

  @override
  void initState() {
    super.initState();
    _q = widget.initialQuery;
    _hooks = VoiceSearchHooks(onText: _applySpoken, onListen: _listen);
    VoiceNavigation.attach(_hooks);
    RemoteTypingHub.instance.register(_remoteTyping);
    _channels = List<Channel>.of(PlaylistRepository.instance.currentChannels);
    _sub = PlaylistRepository.instance.channelsStream.listen((List<Channel> ch) {
      if (!mounted) return;
      _channels = List<Channel>.of(ch);
      if (_q.trim().isNotEmpty) _schedule();
    });
    CinemaRepository.instance.indexVersion.addListener(_onIndex);
    if (_q.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
    } else if (widget.autoListen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_listen());
      });
    }
  }

  @override
  void dispose() {
    VoiceNavigation.detach(_hooks);
    RemoteTypingHub.instance.unregister(_remoteTyping);
    _sub?.cancel();
    _debounce?.cancel();
    CinemaRepository.instance.indexVersion.removeListener(_onIndex);
    super.dispose();
  }

  void _onIndex() {
    if (!mounted || _q.trim().isEmpty) return;
    _schedule();
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
    _gen++;
    setState(() {
      _q = '';
      _hits = const <VoiceHit>[];
      _tonight = null;
      _banner = null;
    });
  }

  /// Le téléphone envoie toute la phrase d'un coup. On la cherche
  /// comme si elle avait été dite. On ne touche pas au lecteur.
  bool _onRemoteQuery(String text) {
    if (!mounted) return false;
    _applySpoken(text);
    return true;
  }

  void _applySpoken(String text) {
    _debounce?.cancel();
    setState(() {
      _q = text;
      _banner = null;
    });
    unawaited(_runSearch());
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_runSearch());
    });
  }

  Future<void> _listen() async {
    if (_listening) return;
    setState(() {
      _listening = true;
      _banner = null;
    });
    final VoiceListenResult result = await VoiceCapture.listen();
    if (!mounted) return;
    setState(() => _listening = false);
    switch (result.status) {
      case VoiceListenStatus.ok:
        _applySpoken(result.text ?? '');
      case VoiceListenStatus.unavailable:
        setState(() => _banner = context.l10n.tvVoiceUnavailable);
      case VoiceListenStatus.cancelled:
        setState(() => _banner = context.l10n.tvVoiceCancelled);
      case VoiceListenStatus.busy:
        setState(() => _banner = context.l10n.tvVoiceBusy);
      case VoiceListenStatus.empty:
      case VoiceListenStatus.failed:
        setState(() => _banner = context.l10n.tvVoiceFailed);
    }
  }

  Future<void> _runSearch() async {
    final int gen = ++_gen;
    final String raw = _q;
    final VoiceIntent intent = interpretVoice(raw);
    if (!mounted || gen != _gen) return;
    if (intent.kind == VoiceIntentKind.empty) {
      setState(() {
        _hits = const <VoiceHit>[];
        _tonight = null;
      });
      return;
    }
    if (intent.kind == VoiceIntentKind.tonight) {
      await _loadTonight(gen);
      return;
    }
    List<CinemaTitle> movies = const <CinemaTitle>[];
    List<CinemaTitle> series = const <CinemaTitle>[];
    try {
      movies = CinemaRepository.instance.search(
        CinemaKind.movie,
        intent.catalogQuery,
        max: 24,
      );
      series = CinemaRepository.instance.search(
        CinemaKind.series,
        intent.catalogQuery,
        max: 24,
      );
    } catch (e) {
      // Index cinéma indisponible : on garde les chaînes.
      if (kDebugMode) debugPrint('[Voix] cinéma : $e');
    }
    final bool kids = ParentalControls.instance.kidsMode.value;
    final List<VoiceHit> local = searchCatalog(
      query: intent.catalogQuery,
      channels: _channels,
      movies: movies,
      series: series,
      hideAdult: kids,
    );
    if (!mounted || gen != _gen) return;
    setState(() {
      _hits = local;
      _tonight = null;
    });
    await _maybeRemote(gen, intent.catalogQuery, local);
  }

  /// Aide distante : seulement si le réglage est allumé (défaut : non).
  /// Échec réseau → on garde [local]. Jamais pour « ce soir ».
  Future<void> _maybeRemote(int gen, String query, List<VoiceHit> local) async {
    bool on = false;
    try {
      on = await VoiceRemoteAssist.load();
    } catch (_) {
      on = false;
    }
    if (!on || !mounted || gen != _gen) return;
    try {
      final AiSearchFilter? filter = await AiSearchService.search(query)
          .timeout(const Duration(seconds: 8));
      if (filter == null || !mounted || gen != _gen) return;
      final bool kids = ParentalControls.instance.kidsMode.value;
      final List<VoiceHit> remote = <VoiceHit>[];
      for (final Channel c in _channels) {
        if (remote.length >= 24) break;
        if (kids && c.genre == ChannelGenre.adult) continue;
        if (!filter.matches(c)) continue;
        remote.add(VoiceHit.fromChannel(c));
      }
      final List<VoiceHit> merged = mergeRemoteChannels(
        local: local,
        remoteChannels: remote,
      );
      if (!mounted || gen != _gen) return;
      setState(() => _hits = merged);
    } catch (e) {
      if (kDebugMode) debugPrint('[Voix] aide distante ignorée : $e');
    }
  }

  Future<void> _loadTonight(int gen) async {
    final DateTime now = DateTime.now();
    final EveningWindow window = eveningWindow(now);
    final List<EpgProgram> programs =
        await EpgRepository.instance.programsOverlapping(
      window.start.millisecondsSinceEpoch,
      window.end.millisecondsSinceEpoch,
    );
    if (!mounted || gen != _gen) return;
    // Noms seulement pour les chaînes qui ont un programme ce soir.
    // cleanName lance le curator : on ne le fait pas sur les 50 000
    // chaînes, seulement sur celles du guide (quelques dizaines).
    final Set<String> wanted = <String>{
      for (final EpgProgram p in programs) p.channelId,
    };
    final Map<String, String> names = <String, String>{};
    final Set<String> known = <String>{};
    for (final Channel c in _channels) {
      known.add(c.id);
      if (wanted.contains(c.id)) names[c.id] = c.cleanName;
    }
    final TonightLineup lineup = planTonight(
      now: now,
      programs: <TonightProgram>[
        for (final EpgProgram p in programs)
          TonightProgram(
            channelId: p.channelId,
            title: p.title,
            startMs: p.startTime,
            stopMs: p.stopTime,
            category: p.category,
          ),
      ],
      channelNames: names,
      knownChannelIds: known,
    );
    setState(() {
      _tonight = lineup;
      _hits = const <VoiceHit>[];
    });
  }

  void _openHit(VoiceHit hit) {
    final CinemaTitle? cinema = hit.cinema;
    if (cinema != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => TvShell(
          applySafeArea: false,
          child: cinema.kind == CinemaKind.series
              ? TvSeriesScreen(title: cinema)
              : TvMovieDetailScreen(title: cinema),
        ),
      ));
      return;
    }
    final Channel? channel = hit.channel;
    if (channel == null || channel.streamUrl.trim().isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TvPlayerScreen(
        channels: <Channel>[channel],
        startIndex: 0,
      ),
    ));
  }

  void _openSlot(TonightSlot slot) {
    if (!slot.canPlay) return;
    Channel? channel;
    for (final Channel c in _channels) {
      if (c.id == slot.channelId) {
        channel = c;
        break;
      }
    }
    if (channel == null || channel.streamUrl.trim().isEmpty) return;
    final Channel play = channel;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TvPlayerScreen(channels: <Channel>[play], startIndex: 0),
    ));
  }

  bool get _cinemaCold =>
      !CinemaRepository.instance.indexReady(CinemaKind.movie) &&
      !CinemaRepository.instance.indexReady(CinemaKind.series);

  String _kindLabel(BuildContext context, VoiceHitKind kind) {
    switch (kind) {
      case VoiceHitKind.channel:
        return context.l10n.tvVoiceKindChannel;
      case VoiceHitKind.movie:
        return context.l10n.tvVoiceKindMovie;
      case VoiceHitKind.series:
        return context.l10n.tvVoiceKindSeries;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TonightLineup? tonight = _tonight;
    final bool showCinemaHint = tonight == null &&
        _q.trim().isNotEmpty &&
        _cinemaCold &&
        !_hits.any((VoiceHit h) => h.kind != VoiceHitKind.channel);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 380,
          // Défile si l'écran est petit : un clavier trop haut ne doit pas
          // faire déborder l'écran (bandes jaunes) ni bloquer la recherche.
          child: SingleChildScrollView(child: _keyboard),
        ),
        const SizedBox(width: TvDimens.gutter),
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
                  _listening
                      ? context.l10n.tvVoiceListening
                      : (_q.isEmpty ? context.l10n.tvSearchHint : _q),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TvDimens.title,
                    fontWeight: FontWeight.w700,
                    color: _q.isEmpty && !_listening
                        ? TvTokens.mutedDim
                        : TvTokens.text,
                  ),
                ),
              ),
              if (_banner != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _banner!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(TvDimens.body, color: TvTokens.muted),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(child: _body(context, tonight)),
              if (showCinemaHint)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.l10n.tvVoiceCinemaHint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(TvDimens.caption, color: TvTokens.mutedDim),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, TonightLineup? tonight) {
    if (tonight != null) {
      if (tonight.isEmpty) {
        return Center(
          child: Text(
            context.l10n.tvVoiceTonightEmpty,
            textAlign: TextAlign.center,
            style: TvTokens.ui(TvDimens.body, color: TvTokens.mutedDim),
          ),
        );
      }
      final DateFormat hm =
          DateFormat.Hm(Localizations.localeOf(context).toString());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.tvVoiceTonightTitle,
            style: TvTokens.ui(TvDimens.title, weight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: tonight.slots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int i) {
                final TonightSlot slot = tonight.slots[i];
                final String when =
                    hm.format(DateTime.fromMillisecondsSinceEpoch(slot.startMs));
                return _RowTile(
                  autofocus: i == 0,
                  title: slot.title,
                  badge: when,
                  subtitle: context.l10n.tvVoiceOnChannel(slot.channelName),
                  onSelect: slot.canPlay ? () => _openSlot(slot) : () {},
                );
              },
            ),
          ),
        ],
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: Text(
          _q.trim().isEmpty ? '' : context.l10n.tvNoResult,
          style: TvTokens.ui(TvDimens.body, color: TvTokens.mutedDim),
        ),
      );
    }
    return ListView.separated(
      itemCount: _hits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int i) {
        final VoiceHit hit = _hits[i];
        return _RowTile(
          autofocus: i == 0,
          title: hit.title,
          badge: _kindLabel(context, hit.kind),
          subtitle: hit.subtitle,
          onSelect: () => _openHit(hit),
        );
      },
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.title,
    required this.badge,
    required this.subtitle,
    required this.onSelect,
    this.autofocus = false,
  });

  final String title;
  final String badge;
  final String subtitle;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 120,
              child: Text(
                badge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.ui(TvDimens.label,
                    weight: FontWeight.w700, color: TvTokens.accentBright),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(TvDimens.body, weight: FontWeight.w600),
                  ),
                  if (subtitle.trim().isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(TvDimens.caption, color: TvTokens.muted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Clavier à l'écran réutilisable (recherche du Cinéma). Rendu IDENTIQUE
/// à celui de la recherche du Direct, plus le micro.
class TvKeyboard extends StatelessWidget {
  const TvKeyboard({
    super.key,
    required this.onType,
    required this.onBackspace,
    required this.onClear,
  });

  final ValueChanged<String> onType;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => _Keyboard(
        onType: onType,
        onBackspace: onBackspace,
        onClear: onClear,
      );
}

class _Keyboard extends StatelessWidget {
  const _Keyboard({
    required this.onType,
    required this.onBackspace,
    required this.onClear,
    this.onMic,
  });

  final ValueChanged<String> onType;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback? onMic;

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
    final VoidCallback? mic = onMic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.l10n.tvNavSearch,
            style: const TextStyle(
                fontSize: TvDimens.displayS,
                fontWeight: FontWeight.w800,
                color: TvTokens.text)),
        const SizedBox(height: 12),
        if (mic != null) ...<Widget>[
          _Key(label: context.l10n.tvVoiceMic, wide: true, onTap: mic),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < _keys.length; i++)
              _Key(
                  label: _keys[i],
                  autofocus: i == 0,
                  onTap: () => onType(_keys[i])),
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
  const _Key({
    required this.label,
    required this.onTap,
    this.wide = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool wide;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 180 : 54,
      height: 54,
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onTap,
        builder: (BuildContext context, bool focused) {
          return Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: focused ? TvTokens.accent : TvTokens.sel,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: TvDimens.title,
                    fontWeight: FontWeight.w700,
                    color: focused ? TvTokens.onAccent : TvTokens.text)),
          );
        },
      ),
    );
  }
}
