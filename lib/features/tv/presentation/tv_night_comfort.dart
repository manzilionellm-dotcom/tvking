// =========================================================
//  tv_night_comfort.dart — Voile « NUIT ROYALE » (confort des yeux)
// =========================================================
//  Le soir, l'écran TV agresse : trop de bleu, trop de luminance dans un
//  salon sombre. Ce voile pose PAR-DESSUS TOUTE l'app (racine, au-dessus
//  du lecteur inclus) :
//    • une teinte AMBRE très légère  → moins de lumière bleue (type f.lux),
//    • une pointe de tamisage        → luminance adoucie.
//
//  Il APPARAÎT/DISPARAÎT en fondu long (2 s) — imperceptible, comme une
//  pièce qui passe en éclairage du soir. IgnorePointer : aucun impact sur
//  le focus, la télécommande, le tactile. Aucun contact avec le décodage
//  vidéo (simple couche de couleur composée par le GPU).
//
//  Modes (Réglages → Affichage) : Désactivé / Auto le soir (défaut) /
//  Toujours. En Auto, une horloge (1 min) vérifie l'heure : actif de
//  21 h à 7 h.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/display_settings.dart';

class TvNightComfortOverlay extends StatefulWidget {
  const TvNightComfortOverlay({super.key});

  /// Heures d'activation du mode Auto : [eveningStart] h → [morningEnd] h.
  static const int eveningStart = 21;
  static const int morningEnd = 7;

  @override
  State<TvNightComfortOverlay> createState() => _TvNightComfortOverlayState();
}

class _TvNightComfortOverlayState extends State<TvNightComfortOverlay> {
  Timer? _clock;
  bool _isEvening = false;

  @override
  void initState() {
    super.initState();
    _isEvening = _eveningNow();
    // Horloge légère : on ne vérifie l'heure qu'une fois par minute, et on
    // ne rebuild QUE si le statut soir/jour change réellement.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      final bool e = _eveningNow();
      if (e != _isEvening && mounted) setState(() => _isEvening = e);
    });
    DisplaySettings.instance.addListener(_onSettings);
  }

  @override
  void dispose() {
    _clock?.cancel();
    DisplaySettings.instance.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  static bool _eveningNow() {
    final int h = DateTime.now().hour;
    return h >= TvNightComfortOverlay.eveningStart ||
        h < TvNightComfortOverlay.morningEnd;
  }

  bool get _active {
    switch (DisplaySettings.instance.nightComfort) {
      case NightComfortMode.off:
        return false;
      case NightComfortMode.always:
        return true;
      case NightComfortMode.auto:
        return _isEvening;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ambre sombre translucide (~8-11 %) : une seule couche qui COUPE le
    // bleu (teinte chaude) ET tamise (la teinte est plus sombre que
    // l'ambre pur). Valeurs volontairement DISCRÈTES : l'œil ne « voit »
    // pas le filtre, il sent juste que l'image est plus douce.
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _active ? 1.0 : 0.0,
        duration: const Duration(seconds: 2),
        curve: Curves.easeInOut,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x15D9924E), Color(0x1FC97F38)],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}
