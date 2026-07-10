// =========================================================
//  tv_black_box_screen.dart — LA BOÎTE NOIRE visible (Réglages)
// =========================================================
//  Demande client (2026-07-10) : « une boîte noire tellement puissante,
//  surtout pour les chaînes qui ne s'ouvrent pas : elle doit diagnostiquer
//  POINT PAR POINT le pourquoi, et donner le compte rendu général de
//  l'application. Une boîte noire que je ne veux pas changer, qui peut
//  travailler même dix ans. »
//
//  3 volets navigables au D-pad :
//    (a) COMPTE RENDU — toutes les versions (app, build, commit, Android,
//        RAM, plateforme…), la santé (abonnement, backend, compteurs,
//        dernier boot, mémoire) et un VERDICT global en une phrase.
//    (b) CHAÎNES QUI NE S'OUVRENT PAS — le journal durable des échecs de
//        lecture (playback_failure_log.dart) avec, pour chacun, le POURQUOI
//        en français humain (failure_explainer.dart) + un bouton
//        « Diagnostiquer maintenant » qui rejoue 6 vérifications AFFICHÉES
//        UNE PAR UNE (TvDiagnosticsService — le même service que l'écran
//        caché HAUT-HAUT-BAS-BAS, jamais dupliqué).
//    (c) JOURNAL DE VOL — la queue de la BlackBox (session courante +
//        session précédente post-mortem), l'analyse par signatures en tête,
//        et un « code support » court à lire au téléphone au revendeur.
//
//  CONÇU POUR DIX ANS : cet écran ne fait que LIRE des sources stables
//  (codes ExoPlayer, schéma v1 du journal, BlackBox) et tout est fail-open —
//  une donnée manquante s'affiche « inconnue », jamais un crash.
// =========================================================
import 'dart:convert';
import 'dart:io' show Platform, ProcessInfo;

import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app/app_platform.dart';
import '../../../core/app/boot_guard.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/app/device_memory.dart';
import '../../../core/backend/backend_hosts.dart';
import '../../../core/observability/black_box.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../recordings/data/recording_repository.dart';
import '../../subscription/data/subscription_state.dart';
import '../../vod/data/download_repository.dart';
import '../data/failure_explainer.dart';
import '../data/playback_failure_log.dart';
import '../data/tv_diagnostics_service.dart';

/// Commit injecté au build par la CI (--dart-define=GIT_SHA=…). « local »
/// pour un build de développement — même convention que cast_diagnostics.
const String _kGitSha =
    String.fromEnvironment('GIT_SHA', defaultValue: 'local');

class TvBlackBoxScreen extends StatefulWidget {
  const TvBlackBoxScreen({super.key});

  @override
  State<TvBlackBoxScreen> createState() => _TvBlackBoxScreenState();
}

/// Une étape du « Diagnostiquer maintenant » (affichée ✓/✗ UNE PAR UNE).
class _DiagStep {
  _DiagStep(this.label);
  final String label;
  TvCheckStatus? status; // null = pas encore exécutée
  bool running = false;
  String detail = '…';
}

class _TvBlackBoxScreenState extends State<TvBlackBoxScreen> {
  // ----- Volet actif (0 = compte rendu, 1 = échecs, 2 = journal) -----
  int _tab = 0;

  // ----- Volet (a) : compte rendu -----
  PackageInfo? _pkg;
  int? _epgCount;
  int? _channelCount;
  int _sourceCount = 0;
  int _recordingCount = 0;
  int _downloadCount = 0;
  int? _bootFailCount;
  int _rssMb = 0;
  List<BlackBoxFinding> _findings = const <BlackBoxFinding>[];

  // ----- Volet (b) : échecs + diagnostic point par point -----
  List<PlaybackFailureEntry> _failures = const <PlaybackFailureEntry>[];
  List<_DiagStep>? _diag; // null = aucun diagnostic en cours/affiché
  String _diagTitle = '';
  String _diagVerdict = '';
  String _diagAdvice = '';
  bool _diagRunning = false;
  // Sonde de décodage (étape 6) : mini-vue native montée UNIQUEMENT pendant
  // la sonde — même schéma que l'écran caché (aucune fuite de lecteur).
  NativeVideoController? _probe;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Charge le compte rendu. CHAQUE lecture est best-effort et indépendante :
  /// un compteur qui échoue s'affiche « ? », jamais un écran cassé.
  Future<void> _load() async {
    // Versions.
    try {
      _pkg = await PackageInfo.fromPlatform();
    } catch (_) {}
    // Compteurs (chacun sous son propre try : indépendance totale).
    try {
      _channelCount = await PlaylistRepository.instance.countActiveLiveChannels();
    } catch (_) {}
    try {
      _sourceCount = PlaylistRepository.instance.currentPlaylists.length;
    } catch (_) {}
    try {
      _epgCount = await EpgRepository.instance.totalCount();
    } catch (_) {}
    try {
      _recordingCount = RecordingRepository.instance.current.length;
    } catch (_) {}
    try {
      _downloadCount = DownloadsRepository.instance.current.length;
    } catch (_) {}
    // Compteur de démarrages non réussis — MIROIR LECTURE SEULE de la clé
    // persistée par BootGuard (_kFailCount) : on n'expose pas la clé côté
    // BootGuard pour ne pas élargir son API, et on n'écrit JAMAIS ici.
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _bootFailCount = prefs.getInt('bootguard.fail_count');
    } catch (_) {}
    // Mémoire réellement occupée par le process (RSS) — pur Dart.
    try {
      _rssMb = (ProcessInfo.currentRss / (1024 * 1024)).round();
    } catch (_) {}
    // Analyse par signatures de la boîte de vol (réutilisée telle quelle).
    try {
      _findings = BlackBox.instance.analyze();
    } catch (_) {}
    // Journal durable des échecs de lecture.
    try {
      await PlaybackFailureLog.instance.ensureLoaded();
      _failures = PlaybackFailureLog.instance.entries;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // ==================================================================
  //  VERDICT GLOBAL (une phrase en haut du compte rendu)
  // ==================================================================

  /// Liste des problèmes détectés (analyse BlackBox + états de santé).
  List<String> get _problems {
    final List<String> out = <String>[];
    for (final BlackBoxFinding f in _findings) {
      if (f.severity == 'critique' || f.severity == 'majeur') {
        out.add(f.title);
      }
    }
    switch (SubscriptionState.instance.status) {
      case SubscriptionStatus.banned:
        out.add(context.l10n.tvBlackBoxProblemBanned);
      case SubscriptionStatus.frozen:
        out.add(context.l10n.tvBlackBoxProblemFrozen);
      case SubscriptionStatus.trialExpired:
        out.add(context.l10n.tvBlackBoxProblemTrialExpired);
      case SubscriptionStatus.paid:
      case SubscriptionStatus.trialActive:
      case SubscriptionStatus.unknown:
        break;
    }
    if (BootGuard.instance.isInSafeMode) {
      out.add(context.l10n.tvBlackBoxProblemSafeMode);
    }
    // Échecs de lecture des dernières 24 h : signal fort côté client.
    final DateTime dayAgo = DateTime.now().subtract(const Duration(hours: 24));
    final int recentFails = _failures
        .where((PlaybackFailureEntry e) => e.timestamp.isAfter(dayAgo))
        .length;
    if (recentFails > 0) {
      out.add(context.l10n.tvBlackBoxProblemRecentFails(recentFails));
    }
    return out;
  }

  // ==================================================================
  //  DIAGNOSTIC « POINT PAR POINT » (volet b)
  // ==================================================================

  /// Relance les 6 vérifications, UNE PAR UNE (le client voit chaque étape
  /// passer ✓/✗). [entry] = échec ciblé (on retrouve la chaîne par son nom) ;
  /// null = diagnostic global sur la chaîne courante/première chaîne.
  Future<void> _runDiagnosis({PlaybackFailureEntry? entry}) async {
    if (_diagRunning) return; // une seule campagne à la fois

    // Résolution de la CIBLE. Vie privée : le journal ne stocke que l'HÔTE —
    // on retrouve l'URL réelle via la liste de chaînes si la chaîne existe
    // encore ; sinon on teste ce qu'on peut (internet, DNS, serveur).
    final List<Channel> chans = PlaylistRepository.instance.currentChannels;
    Channel? target;
    if (entry != null && entry.channelName.isNotEmpty) {
      for (final Channel c in chans) {
        if (c.cleanName == entry.channelName || c.name == entry.channelName) {
          target = c;
          break;
        }
      }
    }
    if (target == null && entry == null && chans.isNotEmpty) {
      target = chans.firstWhere((Channel c) => c.isLive,
          orElse: () => chans.first);
    }
    final String? streamUrl = target?.streamUrl;
    final Uri? uri = streamUrl != null ? Uri.tryParse(streamUrl) : null;
    final String? host = uri?.host.isNotEmpty == true
        ? uri!.host
        : (entry != null && entry.streamHost.isNotEmpty
            ? entry.streamHost
            : null);
    final int port = uri != null && uri.hasPort
        ? uri.port
        : (uri?.scheme == 'https' ? 443 : 80);

    final List<_DiagStep> steps = <_DiagStep>[
      _DiagStep(context.l10n.tvBlackBoxStepInternet),
      _DiagStep(context.l10n.tvBlackBoxStepDns),
      _DiagStep(context.l10n.tvBlackBoxStepServer),
      _DiagStep(context.l10n.tvBlackBoxStepHttp),
      _DiagStep(context.l10n.tvBlackBoxStepSignatures),
      _DiagStep(context.l10n.tvBlackBoxStepDecoder),
    ];
    setState(() {
      _diag = steps;
      _diagRunning = true;
      _diagTitle = context.l10n.tvBlackBoxDiagTitleFor(entry != null
          ? entry.channelName
          : (target?.cleanName ?? context.l10n.tvBlackBoxNoChannelLoaded));
      _diagVerdict = '';
      _diagAdvice = '';
    });

    final TvDiagnosticsService svc = TvDiagnosticsService.instance;
    Future<TvCheckResult> stepOf(int i) {
      switch (i) {
        case 0:
          return svc.checkCaptivePortal();
        case 1:
          return svc.checkDns(host);
        case 2:
          return svc.checkServerReachable(host, port: port);
        case 3:
          return svc.checkStreamReachability(streamUrl);
        case 4:
          return svc.checkUserAgentSignatures(streamUrl);
        default:
          return svc.probePlayer(streamUrl, onProbeController:
              (NativeVideoController? ctrl) {
            if (mounted) {
              setState(() => _probe = ctrl);
            } else {
              _probe = ctrl;
            }
          });
      }
    }

    // Exécution SÉQUENTIELLE : chaque ✓/✗ apparaît avant l'étape suivante.
    for (int i = 0; i < steps.length; i++) {
      if (!mounted) return; // l'utilisateur a quitté l'écran → on arrête tout
      setState(() {
        steps[i].running = true;
        steps[i].detail = context.l10n.tvBlackBoxStepChecking;
      });
      TvCheckResult r;
      try {
        r = await stepOf(i);
      } on Object catch (e) {
        r = TvCheckResult(TvCheckStatus.fail, '$e'); // fail-open, jamais de crash
      }
      if (!mounted) return;
      setState(() {
        steps[i].running = false;
        steps[i].status = r.status;
        steps[i].detail = r.detail;
      });
    }

    if (mounted) {
      final (String verdict, String advice) = _concludeDiagnosis(steps, entry);
      setState(() {
        _diagRunning = false;
        _diagVerdict = verdict;
        _diagAdvice = advice;
      });
    }
  }

  /// Verdict final en UNE phrase + conseil actionnable, déduit des 6 étapes.
  /// L'ordre des règles suit la chaîne de causalité : pas d'internet → tout
  /// le reste est forcément KO, inutile d'accuser le fournisseur.
  (String, String) _concludeDiagnosis(
      List<_DiagStep> s, PlaybackFailureEntry? entry) {
    bool ko(int i) =>
        s[i].status == TvCheckStatus.fail || s[i].status == TvCheckStatus.timeout;
    bool ok(int i) => s[i].status == TvCheckStatus.ok;

    if (ko(0)) {
      return (
        context.l10n.tvBlackBoxVerdictNoInternet,
        context.l10n.tvBlackBoxAdviceNoInternet
      );
    }
    if (ko(1)) {
      return (
        context.l10n.tvBlackBoxVerdictDns,
        context.l10n.tvBlackBoxAdviceDns
      );
    }
    if (ko(2)) {
      return (
        context.l10n.tvBlackBoxVerdictServerDown,
        context.l10n.tvBlackBoxAdviceServerDown
      );
    }
    if (ko(3)) {
      // Le détail contient le code HTTP réel (« HTTP 456 — … ») : on le
      // repêche et on réutilise la table du POURQUOI (source unique).
      final int? status = extractHttpStatus(s[3].detail);
      final PlaybackFailureExplanation e = explainPlaybackFailure(
        errorCodeName: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
        httpStatus: status,
      );
      return (e.why, e.advice);
    }
    if (ko(4)) {
      return (
        context.l10n.tvBlackBoxVerdictSignatures,
        context.l10n.tvBlackBoxAdviceSignatures
      );
    }
    if (ko(5)) {
      // Réseau 100 % OK mais pas d'image → décodage. Si l'échec journalisé
      // portait déjà un code DECODER/DECODING, on affiche SON pourquoi.
      final String codeName = entry?.errorCodeName ?? '';
      if (codeName.contains('DECOD')) {
        final PlaybackFailureExplanation e = explainPlaybackFailure(
          errorCodeName: entry!.errorCodeName,
          errorCode: entry.errorCode,
          cause: entry.cause,
        );
        return (e.why, e.advice);
      }
      return (
        context.l10n.tvBlackBoxVerdictDecode,
        context.l10n.tvBlackBoxAdviceDecode
      );
    }
    final bool allKnownOk = ok(0) && ok(1) && ok(2);
    if (allKnownOk && s[3].status == TvCheckStatus.unknown) {
      return (
        context.l10n.tvBlackBoxVerdictChannelGone,
        context.l10n.tvBlackBoxAdviceChannelGone
      );
    }
    return (
      context.l10n.tvBlackBoxVerdictAllOk,
      context.l10n.tvBlackBoxAdviceAllOk
    );
  }

  // ==================================================================
  //  BUILD
  // ==================================================================

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.shield_rounded, color: TvTokens.gold, size: 34),
            const SizedBox(width: 12),
            Text(context.l10n.tvBlackBoxTitle,
                style: const TextStyle(
                    fontSize: TvDimens.displayS,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.tvBlackBoxSubtitle,
          style:
              const TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
        ),
        const SizedBox(height: 18),
        // ----- Volets (D-pad Gauche/Droite entre les onglets) -----
        Row(
          children: <Widget>[
            _tabChip(0, context.l10n.tvBlackBoxTabReport,
                Icons.summarize_rounded,
                autofocus: true),
            const SizedBox(width: 12),
            _tabChip(1, context.l10n.tvBlackBoxTabFailures,
                Icons.report_problem_rounded),
            const SizedBox(width: 12),
            _tabChip(2, context.l10n.tvBlackBoxTabJournal,
                Icons.flight_rounded),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: switch (_tab) {
            0 => _buildReportTab(context),
            1 => _buildFailuresTab(context),
            _ => _buildJournalTab(context),
          },
        ),
      ],
    );
  }

  Widget _tabChip(int index, String label, IconData icon,
      {bool autofocus = false}) {
    final bool selected = _tab == index;
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: () => setState(() => _tab = index),
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? TvTokens.gold
            : (selected ? TvTokens.sel : TvTokens.card);
        final Color fg = focused
            ? const Color(0xFF1A1206)
            : (selected ? TvTokens.goldBright : TvTokens.muted);
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? TvTokens.gold : TvTokens.lineSoft),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: TvDimens.label,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  //  Volet (a) — COMPTE RENDU GÉNÉRAL
  // ------------------------------------------------------------------

  Widget _buildReportTab(BuildContext context) {
    final List<String> problems = _problems;
    final bool healthy = problems.isEmpty;
    final Color vColor =
        healthy ? const Color(0xFF3FBE7C) : const Color(0xFFE8B23A);

    final String version = _pkg == null
        ? '…'
        : '${_pkg!.version} (build ${_pkg!.buildNumber})';
    final String commit =
        _kGitSha.length >= 7 ? _kGitSha.substring(0, 7) : _kGitSha;
    final ({String label, Color color}) sub = _subscriptionLabel();
    final bool backupBackend = BackendHosts.current != BackendHosts.primary;

    String count(int? n) => n == null ? '?' : '$n';

    return ListView(
      children: <Widget>[
        // ----- Verdict global en une phrase -----
        _focusableCard(
          border: vColor,
          child: Row(
            children: <Widget>[
              Icon(healthy ? Icons.check_circle_rounded : Icons.error_rounded,
                  color: vColor, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  healthy
                      ? context.l10n.tvBlackBoxAllGood
                      : context.l10n.tvBlackBoxProblemsDetected(
                          problems.length, problems.join(' · ')),
                  style: TextStyle(
                      fontSize: TvDimens.title,
                      fontWeight: FontWeight.w800,
                      color: vColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle(context.l10n.tvBlackBoxSectionVersions),
        _infoRow(context.l10n.tvBlackBoxRowApp, _pkg?.appName ?? '…'),
        _infoRow(context.l10n.tvBlackBoxRowVersion, version),
        _infoRow(context.l10n.tvBlackBoxRowCommit, commit),
        _infoRow(context.l10n.tvBlackBoxRowPlatform, AppPlatform.id),
        _infoRow(context.l10n.tvBlackBoxRowSystem,
            Platform.operatingSystemVersion),
        _infoRow(context.l10n.tvBlackBoxRowRam, _ramLabel()),
        _infoRow(context.l10n.tvBlackBoxRowLanguage,
            Localizations.localeOf(context).toString()),
        const SizedBox(height: 16),
        _sectionTitle(context.l10n.tvBlackBoxSectionHealth),
        _infoRow(context.l10n.tvBlackBoxRowSubscription, sub.label,
            valueColor: sub.color),
        _infoRow(
            context.l10n.tvBlackBoxRowBackend,
            backupBackend
                ? context.l10n.tvBlackBoxBackendBackup
                : context.l10n.tvBlackBoxBackendPrimary),
        _infoRow(context.l10n.tvBlackBoxRowSources, count(_sourceCount)),
        _infoRow(context.l10n.tvBlackBoxRowChannels, count(_channelCount)),
        _infoRow(context.l10n.tvBlackBoxRowEpg, count(_epgCount)),
        _infoRow(context.l10n.settingsRecordings, count(_recordingCount)),
        _infoRow(context.l10n.tvBlackBoxRowDownloads, count(_downloadCount)),
        _infoRow(
            context.l10n.tvBlackBoxRowRss,
            _rssMb > 0
                ? context.l10n.tvBlackBoxMbValue(_rssMb)
                : context.l10n.tvBlackBoxRamUnknown),
        const SizedBox(height: 16),
        _sectionTitle(context.l10n.tvBlackBoxSectionLastBoot),
        _infoRow(
            context.l10n.tvBlackBoxRowSafeMode,
            BootGuard.instance.isInSafeMode
                ? context.l10n.tvBlackBoxSafeModeYes
                : context.l10n.tvBlackBoxNo),
        _infoRow(context.l10n.tvBlackBoxRowBootPhase,
            _bootPhaseLabel(context, BootGuard.instance.lastFailedPhase)),
        _infoRow(
            context.l10n.tvBlackBoxRowBootFails,
            _bootFailCount == null
                ? context.l10n.tvBlackBoxBootFailsUnknown
                : context.l10n.tvBlackBoxBootFailsValue(
                    _bootFailCount == 0 ? 0 : _bootFailCount! - 1)),
        const SizedBox(height: 24),
      ],
    );
  }

  ({String label, Color color}) _subscriptionLabel() {
    switch (SubscriptionState.instance.status) {
      case SubscriptionStatus.paid:
        return (
          label: context.l10n.tvBlackBoxSubPaid,
          color: const Color(0xFF3FBE7C)
        );
      case SubscriptionStatus.trialActive:
        final int d = SubscriptionState.instance.trialDaysRemaining;
        return (
          label: context.l10n.tvBlackBoxSubTrial(d),
          color: const Color(0xFF5AA0E8)
        );
      case SubscriptionStatus.trialExpired:
        return (
          label: context.l10n.tvBlackBoxSubTrialExpired,
          color: const Color(0xFFE8B23A)
        );
      case SubscriptionStatus.frozen:
        return (
          label: context.l10n.tvBlackBoxSubFrozen,
          color: const Color(0xFFE8B23A)
        );
      case SubscriptionStatus.banned:
        return (
          label: context.l10n.tvBlackBoxSubBanned,
          color: const Color(0xFFFF5A4A)
        );
      case SubscriptionStatus.unknown:
        return (
          label: context.l10n.tvBlackBoxSubUnknown,
          color: TvTokens.mutedDim
        );
    }
  }

  String _ramLabel() {
    if (!DeviceMemory.isLoaded || DeviceMemory.totalMb <= 0) {
      return context.l10n.tvBlackBoxRamUnknown;
    }
    final double gb = DeviceMemory.totalMb / 1024;
    return '${context.l10n.tvBlackBoxRamGb(gb.toStringAsFixed(1))}'
        '${DeviceMemory.lowRam ? ' ${context.l10n.tvBlackBoxRamLowSuffix}' : ''}';
  }

  String _bootPhaseLabel(BuildContext context, BootPhase p) {
    switch (p) {
      case BootPhase.none:
        return context.l10n.tvBlackBoxPhaseNone;
      case BootPhase.flutterUp:
        return context.l10n.tvBlackBoxPhaseFlutterUp;
      case BootPhase.firstFrame:
        return context.l10n.tvBlackBoxPhaseFirstFrame;
      case BootPhase.importStart:
        return context.l10n.tvBlackBoxPhaseImportStart;
      case BootPhase.importDone:
        return context.l10n.tvBlackBoxPhaseImportDone;
      case BootPhase.homeReady:
        return context.l10n.tvBlackBoxPhaseHomeReady;
    }
  }

  // ------------------------------------------------------------------
  //  Volet (b) — CHAÎNES QUI NE S'OUVRENT PAS (le cœur de la demande)
  // ------------------------------------------------------------------

  Widget _buildFailuresTab(BuildContext context) {
    return ListView(
      children: <Widget>[
        // ----- Bouton global « Diagnostiquer maintenant » -----
        TvFocusBuilder(
          scale: TvFocusScale.large,
          onSelect: _diagRunning ? null : () => _runDiagnosis(),
          builder: (BuildContext context, bool focused) {
            final Color bg = focused ? TvTokens.gold : TvTokens.sel;
            final Color fg =
                focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
            return Container(
              decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                children: <Widget>[
                  Icon(Icons.play_circle_fill_rounded, color: fg, size: 26),
                  const SizedBox(width: 12),
                  Text(
                    _diagRunning
                        ? context.l10n.tvBlackBoxDiagRunning
                        : context.l10n.tvBlackBoxDiagNow,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w700,
                        color: fg),
                  ),
                ],
              ),
            );
          },
        ),
        // ----- Panneau du diagnostic point par point -----
        if (_diag != null) ...<Widget>[
          const SizedBox(height: 14),
          _diagnosisPanel(),
        ],
        const SizedBox(height: 18),
        _sectionTitle(context.l10n.tvBlackBoxSectionFailures(_failures.length)),
        if (_failures.isEmpty)
          _focusableCard(
            child: Text(
              context.l10n.tvBlackBoxNoFailures,
              style: const TextStyle(
                  fontSize: TvDimens.body, color: TvTokens.muted),
            ),
          )
        else
          for (final PlaybackFailureEntry e in _failures) _failureCard(e),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _failureCard(PlaybackFailureEntry e) {
    // Le verdict gravé AU MOMENT DES FAITS prime (contexte réel) ; s'il
    // manque (vieille entrée), on retraduit le code — la table est stable.
    final String why = e.verdict.isNotEmpty
        ? e.verdict
        : explainPlaybackFailure(
            errorCodeName: e.errorCodeName,
            errorCode: e.errorCode,
            cause: e.cause,
          ).why;
    final String code = e.errorCodeName ??
        (e.errorCode != null
            ? 'CODE_${e.errorCode}'
            : context.l10n.tvBlackBoxNoCode);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TvFocusBuilder(
        scale: TvFocusScale.large,
        onSelect: _diagRunning ? null : () => _runDiagnosis(entry: e),
        builder: (BuildContext context, bool focused) {
          final Color bg = focused ? TvTokens.sel : TvTokens.card;
          return Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              border: Border.all(
                  color: focused ? TvTokens.gold : TvTokens.lineSoft),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        e.channelName.isEmpty
                            ? context.l10n.tvBlackBoxUnknownChannel
                            : e.channelName,
                        style: const TextStyle(
                            fontSize: TvDimens.titleS,
                            fontWeight: FontWeight.w800,
                            color: TvTokens.text),
                      ),
                    ),
                    Text(_fmtTs(e.timestamp),
                        style: const TextStyle(
                            fontSize: TvDimens.label,
                            color: TvTokens.mutedDim)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(context.l10n.tvBlackBoxWhy(why),
                    style: const TextStyle(
                        fontSize: TvDimens.body,
                        height: 1.3,
                        color: TvTokens.goldBright)),
                const SizedBox(height: 6),
                Text(
                  '$code'
                  '${e.streamHost.isNotEmpty ? ' · ${context.l10n.tvBlackBoxServerLabel(e.streamHost)}' : ''}'
                  '${e.uaTriedCount > 0 ? ' · ${context.l10n.tvBlackBoxSignaturesTested(e.uaTriedCount)}' : ''}'
                  '  —  ${context.l10n.tvBlackBoxOkToDiagnose}',
                  style: const TextStyle(
                      fontSize: TvDimens.label, color: TvTokens.mutedDim),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _diagnosisPanel() {
    final List<_DiagStep> steps = _diag!;
    return Container(
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.panelRadius),
        border: Border.all(color: TvTokens.line),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_diagTitle,
              style: const TextStyle(
                  fontSize: TvDimens.titleS,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.text)),
          const SizedBox(height: 12),
          for (final _DiagStep s in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                      width: 34,
                      child: Text(_stepGlyph(s),
                          style: const TextStyle(fontSize: 20))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(s.label,
                            style: const TextStyle(
                                fontSize: TvDimens.body,
                                fontWeight: FontWeight.w700,
                                color: TvTokens.text)),
                        Text(s.detail,
                            style: TextStyle(
                                fontSize: TvDimens.label,
                                color: _stepColor(s))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Sonde de décodage : mini-vue native (256×144, comme l'écran caché).
          if (_probe != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 256,
                height: 144,
                decoration: BoxDecoration(
                  border: Border.all(color: TvTokens.line),
                  color: Colors.black,
                ),
                child: NativeVideoView(controller: _probe!),
              ),
            ),
          if (_diagVerdict.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TvTokens.sel,
                borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                border: Border.all(color: TvTokens.gold),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(context.l10n.tvBlackBoxVerdictLabel(_diagVerdict),
                      style: const TextStyle(
                          fontSize: TvDimens.body,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          color: TvTokens.goldBright)),
                  const SizedBox(height: 6),
                  Text(context.l10n.tvBlackBoxAdviceLabel(_diagAdvice),
                      style: const TextStyle(
                          fontSize: TvDimens.label,
                          height: 1.3,
                          color: TvTokens.text)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _stepGlyph(_DiagStep s) {
    if (s.running) return '⏳';
    switch (s.status) {
      case null:
        return '·';
      case TvCheckStatus.ok:
        return '✅';
      case TvCheckStatus.fail:
        return '❌';
      case TvCheckStatus.timeout:
        return '⏱️';
      case TvCheckStatus.unknown:
        return '❔';
    }
  }

  static Color _stepColor(_DiagStep s) {
    if (s.running) return Colors.amber;
    switch (s.status) {
      case null:
        return TvTokens.mutedDim;
      case TvCheckStatus.ok:
        return const Color(0xFF3FBE7C);
      case TvCheckStatus.fail:
        return const Color(0xFFFF5A4A);
      case TvCheckStatus.timeout:
        return const Color(0xFFE8B23A);
      case TvCheckStatus.unknown:
        return TvTokens.mutedDim;
    }
  }

  // ------------------------------------------------------------------
  //  Volet (c) — JOURNAL DE VOL (BlackBox) + code support
  // ------------------------------------------------------------------

  Widget _buildJournalTab(BuildContext context) {
    final PlaybackFailureEntry? last =
        _failures.isNotEmpty ? _failures.first : null;
    final String code = supportCode(
      errorCodeName: last?.errorCodeName,
      errorCode: last?.errorCode,
      build: _pkg?.buildNumber ?? '?',
    );
    final List<String> recent = _safeRecent(80);
    final List<String> previous = _safePreviousTail(40);

    return ListView(
      children: <Widget>[
        // ----- Code support (à lire au téléphone au revendeur) -----
        _focusableCard(
          border: TvTokens.gold,
          child: Row(
            children: <Widget>[
              const Icon(Icons.support_agent_rounded,
                  color: TvTokens.gold, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  context.l10n.tvBlackBoxSupportCode,
                  style: const TextStyle(
                      fontSize: TvDimens.body, color: TvTokens.muted),
                ),
              ),
              Text(code,
                  style: TvTokens.mono(TvDimens.headline,
                      color: TvTokens.goldBright, spacing: 4)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionTitle(context.l10n.tvBlackBoxSectionFindings(_findings.length)),
        if (_findings.isEmpty)
          _focusableCard(
            child: Text(
              context.l10n.tvBlackBoxNoFindings,
              style: const TextStyle(
                  fontSize: TvDimens.body, color: TvTokens.muted),
            ),
          )
        else
          for (final BlackBoxFinding f in _findings)
            _focusableCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('[${f.severity}] ${f.title} (×${f.occurrences})',
                      style: TextStyle(
                          fontSize: TvDimens.body,
                          fontWeight: FontWeight.w800,
                          color: f.severity == 'critique'
                              ? const Color(0xFFFF5A4A)
                              : (f.severity == 'majeur'
                                  ? const Color(0xFFE8B23A)
                                  : TvTokens.muted))),
                  const SizedBox(height: 4),
                  Text(f.detail,
                      style: const TextStyle(
                          fontSize: TvDimens.label,
                          height: 1.3,
                          color: TvTokens.muted)),
                ],
              ),
            ),
        const SizedBox(height: 16),
        _sectionTitle(
            context.l10n.tvBlackBoxSectionCurrentSession(recent.length)),
        for (final String line in recent) _journalLine(line),
        if (previous.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _sectionTitle(
              context.l10n.tvBlackBoxSectionPreviousSession(previous.length)),
          for (final String line in previous) _journalLine(line),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  /// Lecture BLINDÉE de la boîte de vol (elle ne doit jamais casser l'écran).
  List<String> _safeRecent(int n) {
    try {
      return BlackBox.instance.recent(n);
    } on Object {
      return const <String>[];
    }
  }

  List<String> _safePreviousTail(int n) {
    try {
      final List<String> tail =
          BlackBox.instance.previousSessionTail.reversed.toList();
      return tail.length <= n ? tail : tail.sublist(0, n);
    } on Object {
      return const <String>[];
    }
  }

  /// Une ligne du journal rendue LISIBLE : « HH:mm:ss  lvl  domaine.évènement
  /// — contexte ». Ligne non-JSON (fallback texte du logger) → brute.
  Widget _journalLine(String raw) {
    String text = raw;
    Color color = TvTokens.muted;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final String ts = '${decoded['ts'] ?? ''}';
        final String hhmmss = ts.length >= 19 ? ts.substring(11, 19) : ts;
        final String lvl = '${decoded['lvl'] ?? '?'}';
        final Object? ctx = decoded['ctx'];
        text = '$hhmmss  ${lvl.toUpperCase().padRight(5)} '
            '${decoded['domain']}.${decoded['event']}'
            '${ctx != null ? '  $ctx' : ''}';
        if (lvl == 'fatal' || lvl == 'err') {
          color = const Color(0xFFFF5A4A);
        } else if (lvl == 'warn') {
          color = const Color(0xFFE8B23A);
        }
      }
    } on Object {
      // ligne brute — affichée telle quelle
    }
    return TvFocusable(
      scale: TvFocusScale.small,
      showGlow: false,
      borderRadius: BorderRadius.circular(TvTokens.rSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: TvDimens.caption,
              fontFamily: 'monospace',
              height: 1.25,
              color: color),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  //  Briques d'UI communes
  // ------------------------------------------------------------------

  Widget _sectionTitle(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: TvDimens.label,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: TvTokens.gold)),
      );

  /// Carte focusable (pour que le D-pad puisse parcourir/scroller le volet).
  Widget _focusableCard({required Widget child, Color? border}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TvFocusable(
          scale: TvFocusScale.small,
          baseColor: TvTokens.card,
          borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              border: Border.all(color: border ?? TvTokens.lineSoft),
            ),
            child: child,
          ),
        ),
      );

  /// Ligne d'information focusable (libellé à gauche, valeur à droite).
  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return TvFocusable(
      scale: TvFocusScale.small,
      showGlow: false,
      borderRadius: BorderRadius.circular(TvTokens.rSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: TvTokens.lineSoft)),
        ),
        child: Row(
          children: <Widget>[
            Text(label,
                style: const TextStyle(
                    fontSize: TvDimens.label,
                    fontWeight: FontWeight.w600,
                    color: TvTokens.muted)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: TvDimens.label,
                      fontWeight: FontWeight.w700,
                      color: valueColor ?? TvTokens.text)),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtTs(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }
}
