// =========================================================
//  tv_hue_screen.dart — Réglages « Image et lumière » (10-foot)
// =========================================================
//  Guichet TV du mode Hue (cf. hue_service.dart) : trouver le pont,
//  l'associer (appui sur son gros bouton), activer la synchro
//  image↔lumière et la tester. Tout au D-pad.
//
//  POURQUOI la saisie IP est visible MÊME avant une recherche ratée :
//  sur Firestick le multicast SSDP est souvent filtré. Sans ce repli,
//  l'option restait « aucun pont » pour toujours — c'était le bug
//  client « ça ne se connecte pas ».
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../hue/data/hue_service.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvHueScreen extends StatefulWidget {
  const TvHueScreen({super.key});

  @override
  State<TvHueScreen> createState() => _TvHueScreenState();
}

class _TvHueScreenState extends State<TvHueScreen> {
  bool _searching = false;
  bool _searchFailed = false;
  bool _manualBusy = false;
  String? _manualMsg;

  /// Secondes restantes de la fenêtre d'association (0 = pas en cours).
  int _pairCountdown = 0;
  Timer? _pairTimer;

  /// Nombre de lampes joignables (null = inconnu / pas associé).
  int? _lights;

  /// Saisie D-pad de l'IP (chiffres + points). Instance stable = focus OK.
  String _typedIp = '';

  @override
  void initState() {
    super.initState();
    HueService.instance.load().then((_) {
      final String? known = HueService.instance.bridgeIp;
      if (known != null && mounted) {
        setState(() => _typedIp = known);
      }
      return _refreshLights();
    });
  }

  @override
  void dispose() {
    _pairTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLights() async {
    if (!HueService.instance.isPaired) return;
    final int? n = await HueService.instance.lightCount();
    if (mounted) setState(() => _lights = n);
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _searchFailed = false;
      _manualMsg = null;
    });
    final String? ip = await HueService.instance.discoverBridge();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searchFailed = ip == null;
      if (ip != null) _typedIp = ip;
    });
  }

  /// Fenêtre d'association 30 s : tentative IMMÉDIATE puis une par
  /// seconde. POURQUOI immédiat : Timer.periodic n'envoie le 1er tick
  /// qu'à +1 s — on ratait le bouton déjà pressé (fenêtre Hue = 30 s).
  void _startPairing() {
    _pairTimer?.cancel();
    setState(() => _pairCountdown = 30);
    unawaited(_tryPairTick());
    _pairTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_tryPairTick());
    });
  }

  Future<void> _tryPairTick() async {
    if (!mounted || _pairCountdown <= 0) return;
    final HuePairResult r = await HueService.instance.tryPair();
    if (!mounted) return;
    if (r == HuePairResult.success) {
      _pairTimer?.cancel();
      setState(() => _pairCountdown = 0);
      unawaited(_refreshLights());
      return;
    }
    if (_pairCountdown <= 1) {
      _pairTimer?.cancel();
      setState(() => _pairCountdown = 0);
    } else {
      setState(() => _pairCountdown--);
    }
  }

  Future<void> _applyManualIp() async {
    if (_manualBusy) return;
    setState(() {
      _manualBusy = true;
      _manualMsg = null;
    });
    final bool ok =
        await HueService.instance.setBridgeIpManually(_typedIp);
    if (!mounted) return;
    setState(() {
      _manualBusy = false;
      _manualMsg = ok
          ? null
          : context.l10n.tvHueManualInvalid;
      _searchFailed = false;
    });
  }

  Future<void> _forget() async {
    _pairTimer?.cancel();
    await HueService.instance.forgetBridge();
    if (mounted) {
      setState(() {
        _lights = null;
        _pairCountdown = 0;
        _searchFailed = false;
        _manualMsg = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvTokens.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: HueService.instance,
          builder: (BuildContext context, _) {
            final HueService hue = HueService.instance;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(40, 28, 40, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(context.l10n.tvHueTitle,
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: TvTokens.text)),
                  const SizedBox(height: 4),
                  Text(context.l10n.tvHueSubtitle,
                      style: const TextStyle(
                          fontSize: 14, color: TvTokens.muted)),
                  const SizedBox(height: 22),

                  // ----- Carte d'état du pont -----
                  Container(
                    width: 760,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: TvTokens.card,
                      borderRadius:
                          BorderRadius.circular(TvDimens.panelRadius),
                      border: Border.all(color: TvTokens.lineSoft),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          hue.isPaired
                              ? Icons.lightbulb_rounded
                              : Icons.lightbulb_outline_rounded,
                          size: 30,
                          color: hue.isPaired
                              ? TvTokens.ember
                              : TvTokens.mutedDim,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            hue.isPaired
                                ? context.l10n
                                    .tvHueStatusPaired(_lights ?? 0)
                                : hue.bridgeIp != null
                                    ? context.l10n
                                        .tvHueStatusFound(hue.bridgeIp!)
                                    : _searchFailed
                                        ? context.l10n.tvHueSearchFailed
                                        : context.l10n.tvHueStatusNone,
                            style: const TextStyle(
                                fontSize: 16, color: TvTokens.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ----- Rechercher le pont -----
                  _HueButton(
                    icon: Icons.wifi_find_rounded,
                    label: _searching
                        ? context.l10n.tvHueSearching
                        : context.l10n.tvHueSearch,
                    autofocus: true,
                    onSelect: _searching ? null : _search,
                  ),
                  const SizedBox(height: 10),

                  // ----- Associer (fenêtre bouton du pont) -----
                  if (hue.bridgeIp != null && !hue.isPaired) ...<Widget>[
                    _HueButton(
                      icon: Icons.radio_button_checked_rounded,
                      label: _pairCountdown > 0
                          ? context.l10n.tvHuePairing(_pairCountdown)
                          : context.l10n.tvHuePair,
                      onSelect:
                          _pairCountdown > 0 ? null : _startPairing,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // ----- Interrupteur + test (une fois associé) -----
                  if (hue.isPaired) ...<Widget>[
                    _HueButton(
                      icon: hue.enabled
                          ? Icons.movie_filter_rounded
                          : Icons.movie_filter_outlined,
                      label: hue.enabled
                          ? context.l10n.tvHueEnabledOn
                          : context.l10n.tvHueEnabledOff,
                      onSelect: () => hue.setEnabled(!hue.enabled),
                    ),
                    const SizedBox(height: 10),
                    _HueButton(
                      icon: Icons.auto_awesome_rounded,
                      label: context.l10n.tvHueTest,
                      onSelect: () => hue.testScene(),
                    ),
                    const SizedBox(height: 10),
                    _HueButton(
                      icon: Icons.link_off_rounded,
                      label: context.l10n.tvHueForget,
                      onSelect: _forget,
                    ),
                  ],

                  // ----- Saisie IP (repli Firestick) -----
                  if (!hue.isPaired) ...<Widget>[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 760,
                      child: Text(context.l10n.tvHueManualIp,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: TvTokens.text)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 760,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: TvTokens.card,
                        borderRadius:
                            BorderRadius.circular(TvDimens.cardRadius),
                        border: Border.all(color: TvTokens.lineSoft),
                      ),
                      child: Text(
                        _typedIp.isEmpty
                            ? context.l10n.tvHueManualIpHint
                            : _typedIp,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: _typedIp.isEmpty
                              ? TvTokens.mutedDim
                              : TvTokens.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 760,
                      child: _IpKeypad(
                        onDigit: (String d) =>
                            setState(() => _typedIp += d),
                        onBackspace: () {
                          if (_typedIp.isEmpty) return;
                          setState(() => _typedIp =
                              _typedIp.substring(0, _typedIp.length - 1));
                        },
                        onClear: () => setState(() => _typedIp = ''),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _HueButton(
                      icon: Icons.lan_rounded,
                      label: _manualBusy
                          ? context.l10n.tvHueSearching
                          : context.l10n.tvHueManualApply,
                      onSelect: _manualBusy ? null : _applyManualIp,
                    ),
                    if (_manualMsg != null) ...<Widget>[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 760,
                        child: Text(_manualMsg!,
                            style: const TextStyle(
                                fontSize: 14, color: TvTokens.emberBright)),
                      ),
                    ],
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: 760,
                    child: Text(context.l10n.tvHueHelp,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: TvTokens.mutedDim)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Pavé IPv4 10-foot (chiffres + point). Plus fiable sur Firestick
/// qu'un IME système qui n'apparaît pas toujours.
class _IpKeypad extends StatelessWidget {
  const _IpKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const List<String> _keys = <String>[
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String k in _keys)
          _PadKey(label: k, onTap: () => onDigit(k)),
        _PadKey(label: '⌫', onTap: onBackspace),
        _PadKey(label: '✕', wide: true, onTap: onClear),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.label,
    required this.onTap,
    this.wide = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 116 : 54,
      height: 54,
      child: TvFocusBuilder(
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
                    color: focused ? TvTokens.onEmber : TvTokens.text)),
          );
        },
      ),
    );
  }
}

/// Bouton pleine largeur des réglages Hue — carte focusable D-pad, accent
/// rouge braise (le langage du Cinéma). onSelect null = désactivé (grisé).
class _HueButton extends StatelessWidget {
  const _HueButton({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onSelect != null;
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect ?? () {},
      builder: (BuildContext context, bool focused) {
        final Color bg =
            focused && enabled ? TvTokens.ember : TvTokens.sel;
        final Color fg = focused && enabled
            ? TvTokens.onEmber
            : enabled
                ? TvTokens.text
                : TvTokens.mutedDim;
        return Container(
          width: 760,
          padding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
          child: Row(
            children: <Widget>[
              Icon(icon, color: fg, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w700,
                        color: fg)),
              ),
            ],
          ),
        );
      },
    );
  }
}
