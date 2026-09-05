// =========================================================
//  tv_recordings_screen.dart — « Mes enregistrements » (10-foot)
// =========================================================
//  Trois zones, de haut en bas :
//    1. STOCKAGE : « X utilisés · Y libres » + limite d'espace (5/10/20/50/
//       100 Go ou sans limite). Au-delà, les plus anciens s'effacent seuls
//       (RecordingStoragePolicy). Conseil « alarmes exactes » si Android
//       ne les autorise pas (l'enregistrement en veille serait imprécis).
//    2. PRÉVUS : les enregistrements programmés depuis le guide (statut,
//       horaire, taille qui grossit pendant la capture) — OK = annuler.
//    3. ENREGISTREMENTS : les vidéos captées (RecordingRepository). OK =
//       LIRE EN INTERNE (TvRecordingPlayerScreen, ExoPlayer — le MÊME
//       moteur que le direct), corbeille = SUPPRIMER.
//
//  IMPORTANT : on ne délègue PLUS à un lecteur externe (open_filex/intent
//  VIEW). Sur cette box, le .ts tombait sur la Galerie Android qui CRASHE
//  (FATAL EXCEPTION gallery3d) et tue l'app. La lecture interne supprime
//  ce risque.
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../epg/domain/epg_program.dart';
import '../../epg/presentation/epg_format.dart';
import '../../recordings/data/native_recording_scheduler.dart';
import '../../recordings/data/recording_repository.dart';
import '../../recordings/data/recording_scheduler.dart';
import '../../recordings/data/recording_storage_policy.dart';
import '../../recordings/data/scheduled_recording_repository.dart';
import '../../recordings/domain/recording.dart';
import '../../recordings/domain/scheduled_recording.dart';
import '../../vod/data/vod_download_service.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_recording_player_screen.dart';

class TvRecordingsScreen extends StatefulWidget {
  const TvRecordingsScreen({super.key});

  @override
  State<TvRecordingsScreen> createState() => _TvRecordingsScreenState();
}

class _TvRecordingsScreenState extends State<TvRecordingsScreen> {
  int? _freeBytes;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    RecordingStoragePolicy.instance.addListener(_onPolicy);
    _loadFree();
    // Les tailles « en cours » bougent : rafraîchissement doux (10 s).
    _refresh = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    RecordingStoragePolicy.instance.removeListener(_onPolicy);
    _refresh?.cancel();
    super.dispose();
  }

  void _onPolicy() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFree() async {
    final int? free = await RecordingStoragePolicy.instance.freeBytes();
    if (mounted && free != _freeBytes) setState(() => _freeBytes = free);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Recording>>(
      stream: RecordingRepository.instance.stream,
      initialData: RecordingRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<List<Recording>> snap) {
        final List<Recording> recs = snap.data ?? const <Recording>[];
        return StreamBuilder<List<ScheduledRecording>>(
          stream: ScheduledRecordingRepository.instance.stream,
          initialData: ScheduledRecordingRepository.instance.current,
          builder: (BuildContext context,
              AsyncSnapshot<List<ScheduledRecording>> ssnap) {
            final List<ScheduledRecording> planned =
                (ssnap.data ?? const <ScheduledRecording>[])
                    .where((ScheduledRecording s) =>
                        s.status != ScheduledRecordingStatus.done)
                    .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
                  child: Text(context.l10n.recordingsTitle,
                      style: TextStyle(
                          fontSize: TvDimens.displayS,
                          fontWeight: FontWeight.w800,
                          color: TvTokens.text)),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(right: 6, bottom: 8),
                    children: <Widget>[
                      _StorageCard(freeBytes: _freeBytes),
                      const SizedBox(height: 18),
                      _SectionHeader(context.l10n.tvRecPlannedHeader),
                      if (planned.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          child: Text(context.l10n.tvRecPlannedEmpty,
                              style: TextStyle(
                                  fontSize: TvDimens.label,
                                  color: TvTokens.mutedDim)),
                        )
                      else
                        for (final ScheduledRecording s in planned) ...<Widget>[
                          _ScheduledRow(entry: s),
                          const SizedBox(height: 10),
                        ],
                      const SizedBox(height: 14),
                      _SectionHeader(context.l10n.recordingsTitle.toUpperCase()),
                      if (recs.isEmpty)
                        SizedBox(
                          height: 260,
                          child: TvEmptyState(
                            icon: Icons.video_library_rounded,
                            title: context.l10n.tvNoRecordings,
                            subtitle: context.l10n.tvRecordingsEmpty,
                          ),
                        )
                      else
                        for (int i = 0; i < recs.length; i++) ...<Widget>[
                          _RecordingRow(rec: recs[i], autofocus: i == 0),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Text(text,
          style: TextStyle(
              fontSize: TvDimens.label,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: TvTokens.mutedDim)),
    );
  }
}

/// Carte STOCKAGE : usage, espace libre, limite (OK = limite suivante),
/// note « purge automatique », conseil alarmes exactes si besoin.
class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.freeBytes});
  final int? freeBytes;

  Future<void> _cycleLimit() async {
    final RecordingStoragePolicy p = RecordingStoragePolicy.instance;
    final List<int> choices = RecordingStoragePolicy.limitChoicesGb;
    final int idx = choices.indexOf(p.limitGb);
    await p.setLimitGb(choices[(idx + 1) % choices.length]);
  }

  @override
  Widget build(BuildContext context) {
    final RecordingStoragePolicy p = RecordingStoragePolicy.instance;
    final String used = VodDownloadService.fmtBytes(p.usedBytes());
    final String free =
        freeBytes == null ? '…' : VodDownloadService.fmtBytes(freeBytes!);
    final String limit = p.limitGb == 0
        ? context.l10n.tvRecStorageUnlimited
        : context.l10n.tvRecStorageLimitGb(p.limitGb);
    final bool exactHint = NativeRecordingScheduler.instance.isSupported &&
        !RecordingScheduler.instance.exactAlarmsOk;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.storage_rounded, color: TvTokens.gold, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.l10n.tvRecStorageUsed(used, free),
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text)),
              ),
              TvFocusBuilder(
                scale: TvFocusScale.small,
                onSelect: _cycleLimit,
                builder: (BuildContext context, bool focused) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: focused ? TvTokens.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(TvTokens.rButton),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.line),
                  ),
                  child: Text(
                    '${context.l10n.tvRecStorageLimit} : $limit',
                    style: TextStyle(
                        fontSize: TvDimens.label,
                        fontWeight: FontWeight.w700,
                        color: focused ? TvTokens.onGold : TvTokens.goldBright),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(context.l10n.tvRecStorageAutoDeleteNote,
              style: TextStyle(fontSize: 13, color: TvTokens.mutedDim)),
          if (exactHint) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(context.l10n.tvRecExactAlarmHint,
                      style: TextStyle(fontSize: 13, color: TvTokens.muted)),
                ),
                const SizedBox(width: 12),
                TvFocusBuilder(
                  scale: TvFocusScale.small,
                  onSelect: () =>
                      NativeRecordingScheduler.instance.openExactAlarmSettings(),
                  builder: (BuildContext context, bool focused) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: focused ? TvTokens.gold : Colors.transparent,
                      borderRadius: BorderRadius.circular(TvTokens.rButton),
                      border: Border.all(
                          color: focused ? TvTokens.gold : TvTokens.line),
                    ),
                    child: Text(context.l10n.tvRecExactAlarmOpen,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: focused
                                ? TvTokens.onGold
                                : TvTokens.goldBright)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Ligne d'un enregistrement PROGRAMMÉ. OK = annuler (confirmation).
class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({required this.entry});
  final ScheduledRecording entry;

  String _status(BuildContext context) => switch (entry.status) {
        ScheduledRecordingStatus.planned => context.l10n.tvRecStatusPlanned,
        ScheduledRecordingStatus.recording =>
          context.l10n.tvRecStatusRecording,
        ScheduledRecordingStatus.done => context.l10n.tvRecStatusDone,
        ScheduledRecordingStatus.missed => context.l10n.tvRecStatusMissed,
        ScheduledRecordingStatus.failed => context.l10n.tvRecStatusFailed,
        ScheduledRecordingStatus.cancelled => context.l10n.buttonCancel,
      };

  Color _color() => switch (entry.status) {
        ScheduledRecordingStatus.recording => TvTokens.live,
        ScheduledRecordingStatus.planned => TvTokens.gold,
        ScheduledRecordingStatus.done => TvTokens.muted,
        _ => TvTokens.mutedDim,
      };

  Future<void> _onSelect(BuildContext context) async {
    if (!entry.isActive) {
      // Historique (manqué / échec) : OK retire la ligne.
      await ScheduledRecordingRepository.instance.delete(entry.id);
      return;
    }
    final bool? ok = await showTvConfirm(
      context,
      title: context.l10n.tvRecScheduleCancel,
      message: entry.programTitle ?? entry.channelName,
      confirmLabel: context.l10n.buttonOk,
      danger: true,
    );
    if (ok != true) return;
    await RecordingScheduler.instance.cancel(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    // Réutilise le formatage EPG localisé (plage horaire 12 h/24 h).
    final EpgProgram asProgram = EpgProgram(
      channelId: entry.channelId,
      startTime: entry.startMs,
      stopTime: entry.stopMs,
      title: entry.programTitle ?? entry.channelName,
    );
    final DateTime d = entry.startDateTime;
    String two(int n) => n.toString().padLeft(2, '0');
    final String day = '${two(d.day)}/${two(d.month)}';
    final String size = entry.bytes > 0
        ? '  ·  ${VodDownloadService.fmtBytes(entry.bytes)}'
        : '';
    final Color c = _color();
    return TvFocusable(
      scale: TvFocusScale.medium,
      baseColor: TvTokens.card,
      onSelect: () => _onSelect(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(
              entry.status == ScheduledRecordingStatus.recording
                  ? Icons.fiber_manual_record_rounded
                  : Icons.schedule_rounded,
              color: c,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${entry.channelName} · ${entry.programTitle ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$day  ·  ${epgTimeRange(context, asProgram)}  ·  '
                    '${durationText(context.l10n, entry.duration)}$size',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.label, color: TvTokens.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(TvTokens.rSmall),
                border: Border.all(color: c),
              ),
              child: Text(_status(context),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: c)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({required this.rec, this.autofocus = false});
  final Recording rec;
  final bool autofocus;

  // LECTURE EN INTERNE (plus de lecteur externe qui crashait la box) : on
  // pousse le lecteur d'enregistrement dédié, qui rejoue le .ts via le MÊME
  // moteur natif (ExoPlayer/Media3) que le direct. Voir
  // tv_recording_player_screen.dart pour le « pourquoi » détaillé.
  void _play(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TvRecordingPlayerScreen(recording: rec),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    // Confirmation premium partagée (plus d'AlertDialog Android nu).
    final bool? ok = await showTvConfirm(
      context,
      title: context.l10n.tvRecDeleteTitle,
      message: context.l10n.tvRecDeleteConfirm(rec.channelName),
      confirmLabel: context.l10n.buttonDelete,
      danger: true,
    );
    if (ok != true) return;
    try {
      final File f = File(rec.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    try {
      await RecordingRepository.instance.delete(rec);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final String title =
        (rec.programTitle != null && rec.programTitle!.isNotEmpty)
            ? '${rec.channelName} · ${rec.programTitle}'
            : rec.channelName;
    return Row(
      children: <Widget>[
        Expanded(
          child: TvFocusable(
            autofocus: autofocus,
            scale: TvFocusScale.medium,
            baseColor: TvTokens.card,
            onSelect: () => _play(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.play_circle_fill_rounded,
                      color: TvTokens.gold, size: 38),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: TvDimens.title,
                                fontWeight: FontWeight.w700,
                                color: TvTokens.text)),
                        const SizedBox(height: 4),
                        Text(
                            '${rec.startedLabel}  ·  ${rec.durationLabel}  ·  ${rec.sizeLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: TvDimens.label,
                                color: TvTokens.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        TvFocusable(
          scale: TvFocusScale.small,
          baseColor: TvTokens.card,
          onSelect: () => _delete(context),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Icon(Icons.delete_outline_rounded,
                color: TvTokens.muted, size: 28),
          ),
        ),
      ],
    );
  }
}
