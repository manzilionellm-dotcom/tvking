// =========================================================
//  tv_care_nudge.dart — « Pense à toi » (le mot doux de la maison)
// =========================================================
//  Après 3 HEURES de visionnage d'affilée, un petit mot passe en bas de
//  l'écran pendant 12 secondes, puis s'efface — comme une main posée sur
//  l'épaule, jamais comme une interruption :
// • en journée : « 3 heures déjà — pense à t'étirer, boire un peu d'eau »
// • tard le soir : « Il est tard… la télé sera encore là demain »
//
//  RÈGLES : IgnorePointer (aucun impact focus/lecture), au plus UNE fois
//  toutes les 6 h, s'appuie sur le compteur de minutes consécutives du
//  module Stats (zéro contact lecteur). Ce n'est pas une fonctionnalité,
//  c'est une attention.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../stats/data/watch_stats_service.dart';
import '../core/tv_tokens.dart';

class TvCareNudge extends StatefulWidget {
  const TvCareNudge({super.key});

  /// Seuil de la longue séance (minutes consécutives).
  static const int thresholdMinutes = 180;

  @override
  State<TvCareNudge> createState() => _TvCareNudgeState();
}

class _TvCareNudgeState extends State<TvCareNudge> {
  bool _visible = false;
  DateTime? _lastShown;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    WatchStatsService.instance.addListener(_onStats);
  }

  @override
  void dispose() {
    _hide?.cancel();
    WatchStatsService.instance.removeListener(_onStats);
    super.dispose();
  }

  void _onStats() {
    if (_visible) return;
    final int m = WatchStatsService.instance.continuousMinutes;
    if (m < TvCareNudge.thresholdMinutes) return;
    final DateTime now = DateTime.now();
    if (_lastShown != null &&
        now.difference(_lastShown!) < const Duration(hours: 6)) {
      return;
    }
    _lastShown = now;
    setState(() => _visible = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  String _message(BuildContext context) {
    final int h = DateTime.now().hour;
    if (h >= 22 || h < 5) return context.l10n.tvCareLate;
    return context.l10n.tvCareStretch;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
        child: Align(
          alignment: const Alignment(0, 0.86),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            decoration: BoxDecoration(
              color: TvTokens.surface3.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: TvTokens.hairline),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              _message(context),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: TvTokens.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
