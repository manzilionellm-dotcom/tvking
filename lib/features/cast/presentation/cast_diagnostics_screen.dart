// =========================================================
//  cast_diagnostics_screen.dart — Banc de test cast
// =========================================================
//  Écran de diagnostic accessible depuis Réglages → "Diagnostic
//  cast". Permet à un testeur (toi-même, beta tester) de :
//
//    1. Sélectionner une TV/récepteur déjà découvert
//    2. Choisir un preset (3 / 8 / 15 chaînes)
//    3. Lancer la série de tests → voit en live le verdict de
//       chaque chaîne et la stratégie qui a gagné
//    4. Copier le rapport JSON dans le presse-papier → coller
//       dans une issue GitHub ou dans `COMPATIBILITY.md`
//
//  Le code reste linéaire — un seul Scaffold, conditional rendering
//  selon l'état (idle / running / done). Pas de routing complexe,
//  pas de Bloc, pas de Riverpod.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/observability/black_box.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../data/cast_diagnostics.dart';
import '../data/cast_manager.dart';
import '../data/cast_network_diagnostic.dart';
import '../data/cast_session_diagnostic.dart';
import '../domain/cast_device.dart';

class CastDiagnosticsScreen extends StatefulWidget {
  const CastDiagnosticsScreen({super.key});

  @override
  State<CastDiagnosticsScreen> createState() => _CastDiagnosticsScreenState();
}

class _CastDiagnosticsScreenState extends State<CastDiagnosticsScreen> {
  CastDevice? _selectedDevice;
  DiagnosticPreset _preset = DiagnosticPreset.standard;
  DiagnosticBatchRunner? _runner;

  // Diagnostic RÉSEAU (sans caster) — indépendant du batch runner.
  String? _netReport;
  bool _netRunning = false;

  @override
  void initState() {
    super.initState();
    // Auto-lance la discovery si on entre sans devices chauds.
    if (CastManager.instance.discoveredDevices.isEmpty) {
      CastManager.instance.startDiscovery();
    }
  }

  @override
  void dispose() {
    _runner?.removeListener(_onRunnerTick);
    _runner?.cancel();
    super.dispose();
  }

  void _onRunnerTick() => setState(() {});

  void _start() {
    if (_selectedDevice == null) return;
    final List<Channel> all =
        PlaylistRepository.instance.currentChannels;
    final List<Channel> sample =
        pickDiagnosticChannels(all, _preset.sampleSize);
    if (sample.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune chaîne chargée — ajoute d\'abord une playlist.',
          ),
        ),
      );
      return;
    }
    final DiagnosticBatchRunner runner = DiagnosticBatchRunner(
      device: _selectedDevice!,
      channels: sample,
    )..addListener(_onRunnerTick);
    setState(() => _runner = runner);
    runner.run();
  }

  Future<void> _copyReport() async {
    if (_runner == null) return;
    final String report = _runner!.exportReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rapport copié dans le presse-papier')),
    );
  }

  void _reset() {
    _runner?.removeListener(_onRunnerTick);
    setState(() => _runner = null);
  }

  /// Diagnostic RÉSEAU du cast : 6 checks HTTP en séquence, SANS caster
  /// (aucune interaction TV). Produit un rapport JSON copiable.
  Future<void> _runNetworkDiag() async {
    setState(() => _netRunning = true);
    String report;
    try {
      report = await CastNetworkDiagnostic.run();
    } catch (e, st) {
      report = 'Erreur diagnostic réseau: $e\n$st';
    }
    if (!mounted) return;
    setState(() {
      _netRunning = false;
      _netReport = report;
    });
  }

  Future<void> _copyNetReport() async {
    final String? r = _netReport;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: r));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rapport réseau copié dans le presse-papier')),
    );
  }

  /// BOÎTE NOIRE : rapport complet (constats automatiques + journal
  /// persistant + post-mortem de la session précédente si crash).
  Future<void> _copyBlackBox() async {
    final String report = BlackBox.instance.buildReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Boîte noire copiée dans le presse-papier')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Diagnostic cast',
          style: AppTextStyles.headlineMedium,
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: CastManager.instance,
          builder: (BuildContext context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _IntroCard(),
                  const SizedBox(height: 20),
                  _DevicePicker(
                    selected: _selectedDevice,
                    onPick: (CastDevice d) =>
                        setState(() => _selectedDevice = d),
                    locked: _runner?.isRunning ?? false,
                  ),
                  const SizedBox(height: 16),
                  _PresetPicker(
                    selected: _preset,
                    onPick: (DiagnosticPreset p) =>
                        setState(() => _preset = p),
                    locked: _runner?.isRunning ?? false,
                  ),
                  const SizedBox(height: 20),
                  if (_runner == null) ...<Widget>[
                    _StartButton(
                      enabled: _selectedDevice != null,
                      onPressed: _start,
                    ),
                    const SizedBox(height: 12),
                    // Diagnostic RÉSEAU : ne caste pas, ne touche pas la TV.
                    // Sert à voir POURQUOI le cast retombe en relais
                    // (/cast-sign 503 = secret Worker manquant, DNS, etc.).
                    _NetworkDiagButton(
                      running: _netRunning,
                      onPressed: _netRunning ? null : _runNetworkDiag,
                    ),
                    if (_netReport != null) ...<Widget>[
                      const SizedBox(height: 16),
                      _NetworkReportCard(
                        report: _netReport!,
                        onCopy: _copyNetReport,
                      ),
                    ],
                    const SizedBox(height: 12),
                    // BOÎTE NOIRE — tout l'historique persistant de
                    // l'app (erreurs, cast, lecteur, crashs) + les
                    // constats automatiques, en un seul bloc collable.
                    OutlinedButton.icon(
                      onPressed: _copyBlackBox,
                      icon: const Icon(Icons.flight_takeoff_rounded),
                      label: const Text('Copier la boîte noire (A→Z)'),
                    ),
                  ] else ...<Widget>[
                    _RunHeader(runner: _runner!),
                    const SizedBox(height: 12),
                    _ResultsTable(results: _runner!.results),
                    if (!_runner!.isRunning) ...<Widget>[
                      const SizedBox(height: 16),
                      _SummaryCard(runner: _runner!),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _reset,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Refaire'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _copyReport,
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text('Copier le rapport'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...<Widget>[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _runner!.cancel,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Arrêter'),
                      ),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
//  Composants internes
// ============================================================

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.science_outlined, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Teste la compatibilité cast de ta TV en lançant '
              'plusieurs chaînes à la suite. Le rapport copiable '
              'sert à remplir la matrice de compat.',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({
    required this.selected,
    required this.onPick,
    required this.locked,
  });

  final CastDevice? selected;
  final ValueChanged<CastDevice> onPick;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final List<CastDevice> devices =
        CastManager.instance.discoveredDevices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Récepteur', style: AppTextStyles.labelSmall),
        const SizedBox(height: 8),
        if (devices.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recherche en cours… Vérifie que ta TV est sur le même WiFi.',
                    style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else
          ...devices.map(
            (CastDevice d) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _DeviceRow(
                device: d,
                selected: selected?.id == d.id,
                onTap: locked ? null : () => onPick(d),
              ),
            ),
          ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final CastDevice device;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      device.name,
                      style: AppTextStyles.bodyMedium
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${device.kind.name.toUpperCase()} · ${device.host}'
                      '${device.model != null ? " · ${device.model}" : ""}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({
    required this.selected,
    required this.onPick,
    required this.locked,
  });

  final DiagnosticPreset selected;
  final ValueChanged<DiagnosticPreset> onPick;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Taille du test', style: AppTextStyles.labelSmall),
        const SizedBox(height: 8),
        Row(
          children: DiagnosticPreset.values
              .map(
                (DiagnosticPreset p) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: p == DiagnosticPreset.values.last ? 0 : 8,
                    ),
                    child: _PresetChip(
                      preset: p,
                      selected: selected == p,
                      onTap: locked ? null : () => onPick(p),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final DiagnosticPreset preset;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: <Widget>[
              Text(
                preset.label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.accent
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                preset.description,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(
          enabled
              ? 'Lancer le diagnostic'
              : 'Sélectionne un récepteur',
        ),
      ),
    );
  }
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({required this.runner});

  final DiagnosticBatchRunner runner;

  @override
  Widget build(BuildContext context) {
    final int done = runner.results.length;
    final int total = runner.totalCount;
    final double progress = total == 0 ? 0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                runner.isRunning
                    ? 'Test $done/$total — ${runner.currentChannelName ?? "…"}'
                    : runner.isCancelled
                        ? 'Annulé après $done/$total tests'
                        : 'Terminé — $done/$total tests',
                style: AppTextStyles.bodyMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (runner.isRunning)
              Text(
                '${(progress * 100).toInt()}%',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.accent),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: runner.isRunning ? progress : 1,
            minHeight: 4,
            backgroundColor: AppColors.surface,
            valueColor: AlwaysStoppedAnimation<Color>(
              runner.isRunning
                  ? AppColors.accent
                  : AppColors.success,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.results});

  final List<CastSessionDiagnostic> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'En attente du premier résultat…',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < results.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, color: AppColors.border),
            _ResultRow(diag: results[i]),
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.diag});

  final CastSessionDiagnostic diag;

  @override
  Widget build(BuildContext context) {
    final AttemptResult? win = diag.winningAttempt;
    final Color statusColor =
        diag.success ? AppColors.success : AppColors.live;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            diag.success
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            size: 18,
            color: statusColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  diag.channelName ?? 'Chaîne',
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  diag.success
                      ? '${win?.strategyName ?? "ok"} · '
                          '${diag.totalDurationMs ?? "—"}ms'
                          '${diag.channelGenre != null ? " · ${diag.channelGenre}" : ""}'
                      : (diag.finalUserMessage?.isNotEmpty ?? false)
                          ? diag.finalUserMessage!
                          : 'Échec',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.runner});

  final DiagnosticBatchRunner runner;

  @override
  Widget build(BuildContext context) {
    final int total = runner.results.length;
    final int ok = runner.successCount;
    final int rate = total == 0 ? 0 : (ok * 100 ~/ total);
    final int? avg = runner.averageSuccessLatencyMs;
    final Map<String, int> strategies = runner.winningStrategyCounts;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Taux de succès : $rate% ($ok / $total)',
            style: AppTextStyles.bodyMedium
                .copyWith(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Latence moyenne au succès : ${avg != null ? "${avg}ms" : "—"}',
            style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
          ),
          if (strategies.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Stratégies gagnantes : ${strategies.entries.map((MapEntry<String, int> e) => "${e.key} ×${e.value}").join(", ")}',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NetworkDiagButton extends StatelessWidget {
  const _NetworkDiagButton({required this.running, required this.onPressed});

  final bool running;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: running
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.wifi_find_rounded),
        label: Text(
          running ? 'Diagnostic réseau en cours…' : 'Diagnostic réseau cast',
        ),
      ),
    );
  }
}

class _NetworkReportCard extends StatelessWidget {
  const _NetworkReportCard({required this.report, required this.onCopy});

  final String report;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.lan_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rapport réseau cast',
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copier'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 340),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                report,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
