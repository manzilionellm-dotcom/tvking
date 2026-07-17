// =========================================================
//  tv_hue_screen.dart — Réglages « Lumières Philips Hue » (10-foot)
// =========================================================
//  Le guichet du mode SALLE DE CINÉMA (cf. hue_service.dart) : trouver le
//  pont sur le Wi-Fi, l'associer (un appui sur son gros bouton), activer
//  l'ambiance et la tester. Tout au D-pad, langage visuel des réglages.
//
//  L'ASSOCIATION guide l'utilisateur : on lance une fenêtre de 30 s
//  pendant laquelle l'app re-tente chaque seconde — il suffit d'aller
//  appuyer sur le bouton du pont pendant ce temps. Compte à rebours
//  affiché, résultat clair (✓ associé / bouton pas pressé).
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

  /// Secondes restantes de la fenêtre d'association (0 = pas en cours).
  int _pairCountdown = 0;
  Timer? _pairTimer;

  /// Nombre de lampes joignables (null = inconnu / pas associé).
  int? _lights;

  @override
  void initState() {
    super.initState();
    HueService.instance.load().then((_) => _refreshLights());
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
    setState(() => _searching = true);
    await HueService.instance.discoverBridge();
    if (mounted) setState(() => _searching = false);
  }

  /// Fenêtre d'association 30 s : une tentative par seconde, le temps
  /// d'aller appuyer sur le bouton physique du pont.
  void _startPairing() {
    _pairTimer?.cancel();
    setState(() => _pairCountdown = 30);
    _pairTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      final HuePairResult r = await HueService.instance.tryPair();
      if (!mounted) {
        t.cancel();
        return;
      }
      if (r == HuePairResult.success) {
        t.cancel();
        setState(() => _pairCountdown = 0);
        unawaited(_refreshLights());
        return;
      }
      setState(() => _pairCountdown--);
      if (_pairCountdown <= 0) t.cancel();
    });
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
