// =========================================================
//  source_calibration_sheet.dart — Feuille « Optimiser la source »
// =========================================================
//  UI de la calibration automatique (cf. source_calibrator.dart),
//  pensée pour un utilisateur NON technique :
//
//    - proposition douce après l'ajout d'une source (« Source
//      ajoutée ! Optimiser maintenant / Plus tard ») ;
//    - progression lisible (étape 1/4 → 4/4), ANNULABLE ;
//    - synthèse finale en ✓ simples (« Compte actif », « Format
//      optimal détecté », « Démarrage moyen : 0,8 s ») ;
//    - échec = UNE phrase claire (compte expiré / serveur
//      injoignable / formats refusés → suggérer un VPN).
//
//  Style Maison Noir : fond mat (surface), accent OR royal
//  (AppColors.royalGold) — l'or est réservé à ce geste premium.
//  Les détails techniques complets partent dans StreamDiagnostics
//  (écran debug caché), jamais ici.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/source_calibrator.dart';
import '../domain/playlist.dart';

/// Ouvre la feuille de calibration pour [playlist].
///
/// [proposal] = `true` juste après l'AJOUT d'une source : la feuille
/// s'ouvre en mode proposition (« Optimiser maintenant / Plus tard »)
/// au lieu de démarrer immédiatement.
Future<void> showSourceCalibrationSheet(
  BuildContext context,
  Playlist playlist, {
  bool proposal = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) =>
        _CalibrationSheet(playlist: playlist, proposal: proposal),
  );
}

enum _Phase { intro, running, done }

class _CalibrationSheet extends StatefulWidget {
  const _CalibrationSheet({required this.playlist, required this.proposal});

  final Playlist playlist;
  final bool proposal;

  @override
  State<_CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<_CalibrationSheet> {
  late _Phase _phase;
  SourceCalibrator? _calibrator;
  CalibrationProgress? _progress;
  CalibrationReport? _report;

  @override
  void initState() {
    super.initState();
    _phase = widget.proposal ? _Phase.intro : _Phase.running;
    if (!widget.proposal) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    // Feuille fermée pendant une calibration → on coupe proprement
    // (les étapes suivantes ne démarrent pas).
    _calibrator?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.running;
      _progress = null;
    });
    final SourceCalibrator calibrator = SourceCalibrator(
      playlist: widget.playlist,
      onProgress: (CalibrationProgress p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    _calibrator = calibrator;
    final CalibrationReport report = await calibrator.run();
    if (!mounted) return;
    if (report.verdict == CalibrationVerdict.cancelled) {
      // Annulé par l'utilisateur : la feuille est déjà (en train
      // d'être) fermée — rien à afficher.
      return;
    }
    setState(() {
      _report = report;
      _phase = _Phase.done;
    });
  }

  void _cancel() {
    _calibrator?.cancel();
    Navigator.of(context).maybePop();
  }

  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.royalGold.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.royalGoldSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_fix_high_rounded,
                    color: AppColors.royalGold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.proposal && _phase == _Phase.intro
                            ? context.l10n.calibrateProposalTitle
                            : (_phase == _Phase.done &&
                                    _report?.verdict ==
                                        CalibrationVerdict.ok)
                                ? context.l10n.calibrateDoneTitle
                                : context.l10n.calibrateSheetTitle,
                        style: AppTextStyles.headlineMedium
                            .copyWith(fontSize: 17),
                      ),
                      Text(
                        widget.playlist.name,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            switch (_phase) {
              _Phase.intro => _buildIntro(context),
              _Phase.running => _buildRunning(context),
              _Phase.done => _buildDone(context),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          context.l10n.calibrateIntroBody,
          style: AppTextStyles.bodyMedium.copyWith(height: 1.4),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _start,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.royalGold,
            foregroundColor: AppColors.voidSurface,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
          label: Text(context.l10n.calibrateStartButton),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style:
              TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: Text(context.l10n.calibrateLaterButton),
        ),
      ],
    );
  }

  Widget _buildRunning(BuildContext context) {
    final int current = _progress?.step ?? 1;
    final List<String> labels = <String>[
      context.l10n.calibrateStepAccount,
      context.l10n.calibrateStepFormat,
      context.l10n.calibrateStepSignature,
      context.l10n.calibrateStepStartup,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          context.l10n.calibrateStepLabel(current, 4),
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.royalGold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 22,
                  height: 22,
                  child: i + 1 < current
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.royalGold, size: 20)
                      : i + 1 == current
                          ? const CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.royalGold,
                            )
                          : const Icon(Icons.circle_outlined,
                              color: AppColors.textMuted, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    labels[i],
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: i + 1 <= current
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: _cancel,
          style:
              TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: Text(context.l10n.buttonCancel),
        ),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    final CalibrationReport r = _report!;
    final List<Widget> rows = <Widget>[];

    if (r.verdict == CalibrationVerdict.ok) {
      // ----- Synthèse « tout va bien » : ✓ lisibles -----
      if (r.accountChecked && r.account != null) {
        final DateTime? exp = r.account!.expDate;
        rows.add(_check(
          ok: true,
          text: exp == null
              ? context.l10n.calibrateCheckAccountOk
              : context.l10n.calibrateCheckAccountOkUntil(
                  '${exp.day}/${exp.month}/${exp.year}'),
        ));
      }
      if (r.formatChecked) {
        rows.add(_check(
          ok: true,
          text: r.winningFormat != null
              ? context.l10n.calibrateCheckFormatOk
              : context.l10n.calibrateCheckFormatKept,
        ));
      }
      if (r.signatureChecked) {
        rows.add(_check(
          ok: true,
          text: r.winningUserAgent != null
              ? context.l10n.calibrateCheckSignatureOk
              : context.l10n.calibrateCheckSignatureKept,
        ));
      }
      if (r.avgStartupMs != null) {
        final String seconds =
            (r.avgStartupMs! / 1000).toStringAsFixed(1).replaceAll('.', ',');
        rows.add(_check(
          ok: true,
          text: context.l10n.calibrateCheckStartup(seconds),
        ));
      }
    } else {
      // ----- Échec : UNE phrase claire -----
      final String msg = switch (r.verdict) {
        CalibrationVerdict.accountExpired =>
          context.l10n.calibrateFailExpired,
        CalibrationVerdict.serverUnreachable =>
          context.l10n.calibrateFailUnreachable,
        CalibrationVerdict.allFormatsRefused =>
          context.l10n.calibrateFailRefused,
        CalibrationVerdict.noChannels =>
          context.l10n.calibrateFailNoChannels,
        _ => context.l10n.calibrateCancelledMsg,
      };
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_rounded, color: AppColors.live, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: AppTextStyles.bodyMedium.copyWith(height: 1.4),
            ),
          ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...rows.map((Widget w) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: w,
            )),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.royalGold,
            foregroundColor: AppColors.voidSurface,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(context.l10n.calibrateClose),
        ),
      ],
    );
  }

  Widget _check({required bool ok, required String text}) {
    return Row(
      children: <Widget>[
        Icon(
          ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: ok ? AppColors.royalGold : AppColors.live,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: AppTextStyles.bodyMedium),
        ),
      ],
    );
  }
}
