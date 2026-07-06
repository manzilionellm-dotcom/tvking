// =========================================================
//  tv_city_screen.dart — Choisir SA ville pour la météo (10-foot)
// =========================================================
//  Sur une TV il n'y a pas de GPS : la météo était devinée par l'IP
//  (souvent une ville voisine, ex. « Kista »). Ici l'utilisateur tape
//  le nom de SA ville (clavier D-pad, instance STABLE = focus préservé),
//  choisit dans les résultats (géocodage Open-Meteo) → on la mémorise et
//  la météo devient EXACTE. Une option « Automatique » revient à l'IP.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../tv/data/greeting_repository.dart';
import '../../tv/data/place_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvCityScreen extends StatefulWidget {
  const TvCityScreen({super.key});

  @override
  State<TvCityScreen> createState() => _TvCityScreenState();
}

class _TvCityScreenState extends State<TvCityScreen> {
  String _q = '';
  List<SavedPlace> _results = const <SavedPlace>[];
  bool _loading = false;
  String? _msg;
  Timer? _debounce;
  Timer? _msgTimer;

  // Instance STABLE → non reconstruite à chaque frappe (focus préservé).
  late final Widget _keyboard =
      _CityKeyboard(onType: _type, onBackspace: _backspace, onClear: _clear);

  @override
  void dispose() {
    _debounce?.cancel();
    _msgTimer?.cancel();
    super.dispose();
  }

  void _flash(String m) {
    setState(() => _msg = m);
    _msgTimer?.cancel();
    _msgTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _msg = null);
    });
  }

  void _type(String c) {
    setState(() => _q += c);
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
      _results = const <SavedPlace>[];
    });
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _run);
  }

  Future<void> _run() async {
    final String q = _q.trim();
    if (q.length < 2) {
      if (mounted) setState(() => _results = const <SavedPlace>[]);
      return;
    }
    if (mounted) setState(() => _loading = true);
    final String lang = Localizations.localeOf(context).languageCode;
    final List<SavedPlace> r =
        await PlaceRepository.instance.search(q, language: lang);
    if (mounted) {
      setState(() {
        _results = r;
        _loading = false;
      });
    }
  }

  Future<void> _choose(SavedPlace? place) async {
    await PlaceRepository.instance.setPlace(place);
    // On rafraîchit tout de suite la météo pour la nouvelle ville.
    await GreetingRepository.instance.fetch();
    if (!mounted) return;
    _flash(place == null
        ? context.l10n.tvWeatherAutoSet
        : context.l10n.tvWeatherSaved(place.name));
    // Petit délai pour laisser voir la confirmation, puis on revient.
    Timer(const Duration(milliseconds: 700), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final SavedPlace? cur = PlaceRepository.instance.current;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: 380, child: _keyboard),
        const SizedBox(width: TvDimens.gutter),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Réglage actuel (ville mémorisée ou « automatique »).
              Text(
                cur == null
                    ? context.l10n.tvWeatherCurrentAuto
                    : context.l10n.tvWeatherCurrent(cur.label),
                style: TextStyle(
                    fontSize: TvDimens.label,
                    fontWeight: FontWeight.w600,
                    color: TvTokens.muted),
              ),
              const SizedBox(height: 12),
              // Ce qu'on est en train de taper.
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: TvTokens.card,
                  borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                ),
                child: Text(
                  _q.isEmpty ? context.l10n.tvWeatherHint : _q,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: TvDimens.title,
                      fontWeight: FontWeight.w700,
                      color: _q.isEmpty ? TvTokens.mutedDim : TvTokens.text),
                ),
              ),
              const SizedBox(height: 14),
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_msg!,
                      style: TextStyle(
                          fontSize: TvDimens.label,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.goldBright)),
                ),
              Expanded(child: _resultsView()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultsView() {
    // Requête vide → on propose le retour à l'automatique (IP).
    if (_q.trim().isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(right: 6, bottom: 12),
        children: <Widget>[
          _autoTile(autofocus: true),
        ],
      );
    }
    if (_loading && _results.isEmpty) {
      return const Center(
        child: SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: TvTokens.gold)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(context.l10n.tvWeatherNoResult,
            style:
                TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(right: 6, bottom: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int i) {
        final SavedPlace p = _results[i];
        return TvFocusable(
          autofocus: i == 0,
          scale: TvFocusScale.medium,
          baseColor: TvTokens.card,
          onSelect: () => _choose(p),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                const Icon(Icons.place_rounded, color: TvTokens.gold, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: TvDimens.title,
                              fontWeight: FontWeight.w700,
                              color: TvTokens.text)),
                      if (p.country.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(p.country,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: TvDimens.label,
                                color: TvTokens.muted)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _autoTile({bool autofocus = false}) {
    return TvFocusable(
      autofocus: autofocus,
      scale: TvFocusScale.medium,
      baseColor: TvTokens.card,
      onSelect: () => _choose(null),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            const Icon(Icons.my_location_rounded,
                color: TvTokens.gold, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(context.l10n.tvWeatherAuto,
                      style: TextStyle(
                          fontSize: TvDimens.title,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.text)),
                  const SizedBox(height: 2),
                  Text(context.l10n.tvWeatherAutoDesc,
                      maxLines: 2,
                      style: TextStyle(
                          fontSize: TvDimens.label, color: TvTokens.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CityKeyboard extends StatelessWidget {
  const _CityKeyboard(
      {required this.onType, required this.onBackspace, required this.onClear});
  final ValueChanged<String> onType;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const List<String> _keys = <String>[
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.l10n.tvWeatherTitle,
            style: TextStyle(
                fontSize: TvDimens.displayS,
                fontWeight: FontWeight.w800,
                color: TvTokens.text)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < _keys.length; i++)
              _Key(label: _keys[i], onTap: () => onType(_keys[i])),
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
  const _Key(
      {required this.label,
      required this.onTap,
      this.wide = false,
      this.autofocus = false});
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
