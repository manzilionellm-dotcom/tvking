// =========================================================
//  prediction_bar.dart — « 1 · N · 2 » : le pronostic des fans (téléphone)
// =========================================================
//  Une ligne sous chaque duel du coin Sport. Avant le coup d'envoi, trois
//  boutons : domicile, nul, extérieur. Dès qu'on a voté, les pourcentages
//  des autres fans apparaissent. Après le coup d'envoi, la ligne se fige
//  (« Pronostics clos ») et ne s'affiche que si elle a quelque chose à
//  dire — un vote, ou des pourcentages. Un match sans aucun vote ne
//  traîne pas une ligne vide.
//
//  Couleurs et tailles : AppColors / AppTextStyles uniquement (AGENTS.md).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/predictions_service.dart';
import '../domain/sport_models.dart';

class PredictionBar extends StatefulWidget {
  const PredictionBar({super.key, required this.event});
  final SportEvent event;

  @override
  State<PredictionBar> createState() => _PredictionBarState();
}

class _PredictionBarState extends State<PredictionBar> {
  StreamSubscription<void>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sub = PredictionsService.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Les pourcentages viennent du serveur ; on ne les demande que pour un
    // duel (une course n'a pas de « 1 N 2 »).
    if (widget.event.isDuel) {
      unawaited(PredictionsService.instance.load(widget.event.id));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _vote(Pick p) async {
    if (_busy) return;
    setState(() => _busy = true);
    await PredictionsService.instance.vote(widget.event, p);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(context.l10n.sportPredictSaved),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final SportEvent e = widget.event;
    if (!e.isDuel) return const SizedBox.shrink();
    final PredictionsService svc = PredictionsService.instance;
    final bool open = PredictionsService.isOpen(e, DateTime.now());
    final PredictionTally? tally = svc.tallyFor(e.id);
    final Pick? mine = tally?.mine ?? svc.myPick(e.id);
    // Fermé et rien à montrer → pas de ligne.
    if (!open && mine == null && (tally == null || tally.total == 0)) {
      return const SizedBox.shrink();
    }
    // Les pourcentages ne se montrent qu'une fois qu'on a voté, ou quand
    // c'est fermé : voir « 71 % » AVANT de choisir influence le choix, et
    // le sondage ne dirait plus ce que pensent les fans.
    final bool showPct = tally != null && tally.total > 0 && (mine != null || !open);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Text(
            open ? context.l10n.sportPredictTitle : context.l10n.sportPredictClosed,
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(width: 8),
          for (final Pick p in Pick.values) ...<Widget>[
            _PickChip(
              label: p == Pick.draw ? context.l10n.sportPredictDraw : (p == Pick.home ? '1' : '2'),
              pct: showPct ? tally.pct(p) : null,
              selected: mine == p,
              enabled: open && !_busy,
              onTap: () => _vote(p),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.pct,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final int? pct;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = selected
        ? AppColors.accent
        : (enabled ? AppColors.textSecondary : AppColors.textTertiary);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.16)
              : AppColors.surfaceHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.55)
                : AppColors.surfaceHigh,
          ),
        ),
        child: Text(
          pct == null ? label : '$label · $pct %',
          style: AppTextStyles.labelSmall.copyWith(
            color: fg,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
