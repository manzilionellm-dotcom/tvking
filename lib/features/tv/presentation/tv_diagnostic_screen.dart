// =========================================================
//  tv_diagnostic_screen.dart — Diagnostic réseau ON-DEVICE (DeFew TV)
// =========================================================
//  Écran ISOLÉ, réservé à DeFew TV (cible `main_tv` / Android TV). Sert à
//  TRANCHER, sur place (le Wi-Fi du bar), si le pivot « lecture sur la TV
//  elle-même » est viable — c.-à-d. si la box joue le flux depuis SA propre
//  IP, sans casting ni relais.
//
//  Il ne touche RIEN d'existant : pas de cast, pas de VOD, pas de Direct, pas
//  le lecteur de prod. Il LIT seulement (config, MAC, chaîne courante) et fait
//  des requêtes réseau de LECTURE. Aucune écriture réseau, aucune URL inventée.
//
//  Accès CACHÉ : depuis l'accueil TV, séquence D-pad HAUT-HAUT-BAS-BAS.
//  Sortie : touche RETOUR.
//
//  5 vérifs séquentielles (~8 s de time-out chacune) :
//    1. Portail captif / 204   (connectivitycheck.gstatic.com/generate_204)
//    2. Résolution DNS de l'hôte IPTV (hôte de la chaîne courante)
//    3. Joignabilité du flux / 456 (HEAD puis GET, on montre le code HTTP)
//    4. Lecture de la source poussée (GET /api/device-source/<MAC>)
//    5. Sonde ExoPlayer/Media3 (mini instance native, 1re image ou erreur)
//
//  REFACTOR 2026-07-10 : la LOGIQUE des vérifications vit désormais dans
//  TvDiagnosticsService (partagée avec la Boîte noire des Réglages) — cet
//  écran n'est plus que l'AFFICHAGE. Comportement et textes identiques.
//
//  Chaque ligne est aussi écrite dans logcat (tag DEFEW_DIAG) pour relire le
//  test à froid via `adb logcat -s DEFEW_DIAG`.
// =========================================================
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../data/tv_diagnostics_service.dart';

/// Tag logcat — `adb logcat -s DEFEW_DIAG`.
const String _kLogTag = 'DEFEW_DIAG';

enum _Stat { pending, running, ok, fail, timeout, unknown }

class _Check {
  _Check(this.name);
  final String name;
  _Stat stat = _Stat.pending;
  String detail = '…';
}

/// Verdict global affiché en haut.
enum _Verdict { running, pivotOk, networkBlock, playerBug, partial }

class TvDiagnosticScreen extends StatefulWidget {
  const TvDiagnosticScreen({super.key});

  @override
  State<TvDiagnosticScreen> createState() => _TvDiagnosticScreenState();
}

class _TvDiagnosticScreenState extends State<TvDiagnosticScreen> {
  final FocusNode _focus = FocusNode(debugLabel: 'tvDiag');

  // Ordre = ordre d'exécution.
  final _Check _captive = _Check('1. Portail captif (204)');
  final _Check _dns = _Check('2. Résolution DNS hôte IPTV');
  final _Check _stream = _Check('3. Joignabilité flux (HTTP / 456)');
  final _Check _source = _Check('4. Source poussée (device-source)');
  final _Check _player = _Check('5. Sonde ExoPlayer / Media3');

  late final List<_Check> _checks = <_Check>[
    _captive, _dns, _stream, _source, _player,
  ];

  _Verdict _verdict = _Verdict.running;
  bool _done = false;

  // Mini-vue native montée UNIQUEMENT pendant la sonde lecteur (5).
  NativeVideoController? _probe;

  @override
  void initState() {
    super.initState();
    _log('===== DÉBUT DIAGNOSTIC ON-DEVICE =====');
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _probe?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _log(String line) => developer.log(line, name: _kLogTag);

  void _set(_Check c, _Stat s, String detail) {
    c.stat = s;
    c.detail = detail;
    _log('${_glyph(s)} ${c.name} — $detail');
    if (mounted) setState(() {});
  }

  String _glyph(_Stat s) {
    switch (s) {
      case _Stat.ok:
        return '✅';
      case _Stat.fail:
        return '❌';
      case _Stat.timeout:
        return '⏱️';
      case _Stat.unknown:
        return '❔';
      case _Stat.running:
        return '⏳';
      case _Stat.pending:
        return '·';
    }
  }

  // ------------------------------------------------------------------
  //  Déroulé séquentiel
  // ------------------------------------------------------------------
  Future<void> _run() async {
    // Chaîne courante : sert d'hôte IPTV (DNS) + d'URL de flux (3 et 5).
    final List<Channel> chans = PlaylistRepository.instance.currentChannels;
    final Channel? chan = chans.isEmpty
        ? null
        : chans.firstWhere((Channel c) => c.isLive, orElse: () => chans.first);
    final String? streamUrl = chan?.streamUrl;
    final String? iptvHost =
        (streamUrl != null) ? Uri.tryParse(streamUrl)?.host : null;

    await _runCaptive();
    await _runDns(iptvHost);
    await _runStream(streamUrl);
    await _runSource();
    await _runPlayer(streamUrl);

    _computeVerdict();
    _done = true;
    if (mounted) setState(() {});
    _log('===== FIN DIAGNOSTIC — VERDICT: ${_verdictLabel()} =====');
  }

  /// Traduit le statut du service partagé vers l'état d'affichage local.
  _Stat _fromService(TvCheckStatus s) {
    switch (s) {
      case TvCheckStatus.ok:
        return _Stat.ok;
      case TvCheckStatus.fail:
        return _Stat.fail;
      case TvCheckStatus.timeout:
        return _Stat.timeout;
      case TvCheckStatus.unknown:
        return _Stat.unknown;
    }
  }

  void _apply(_Check c, TvCheckResult r) =>
      _set(c, _fromService(r.status), r.detail);

  // 1. Portail captif : un 204 « nu » = sortie Internet libre.
  Future<void> _runCaptive() async {
    if (mounted) {
      _set(_captive, _Stat.running, context.l10n.tvDiagRunningCaptive);
    }
    _apply(_captive, await TvDiagnosticsService.instance.checkCaptivePortal());
  }

  // 2. DNS : on résout l'hôte de la chaîne courante. Pas de chaîne = INCONNU.
  Future<void> _runDns(String? host) async {
    if (host != null && host.isNotEmpty && mounted) {
      _set(_dns, _Stat.running, context.l10n.tvDiagRunningDns(host));
    }
    _apply(_dns, await TvDiagnosticsService.instance.checkDns(host));
  }

  // 3. Joignabilité du flux : HEAD puis repli GET, on AFFICHE le code HTTP.
  // 456 = blocage fournisseur (IP datacenter/cloud) — ici on est sur l'IP de
  // la box, donc un 456 prouverait que le fournisseur bloque même le LAN.
  Future<void> _runStream(String? streamUrl) async {
    if (streamUrl != null && streamUrl.isNotEmpty && mounted) {
      _set(_stream, _Stat.running, context.l10n.tvDiagRunningStream);
    }
    _apply(_stream,
        await TvDiagnosticsService.instance.checkStreamReachability(streamUrl));
  }

  // 4. Source poussée : GET /api/device-source/<MAC>. Lecture seule.
  Future<void> _runSource() async {
    if (mounted) {
      _set(_source, _Stat.running, context.l10n.tvDiagRunningSource);
    }
    _apply(_source, await TvDiagnosticsService.instance.checkPushedSource());
  }

  // 5. Sonde lecteur : le service monte une MINI NativeVideoView
  // (Media3/ExoPlayer, même moteur que la prod) via le callback ci-dessous ;
  // on attend la 1re image (OK) ou une erreur (FAIL). Tout est détruit après.
  Future<void> _runPlayer(String? streamUrl) async {
    if (streamUrl != null && streamUrl.isNotEmpty && mounted) {
      _set(_player, _Stat.running, context.l10n.tvDiagRunningPlayer);
    }
    final TvCheckResult r = await TvDiagnosticsService.instance.probePlayer(
      streamUrl,
      onProbeController: (NativeVideoController? ctrl) {
        if (mounted) {
          setState(() => _probe = ctrl); // monte/démonte la vue native
        } else {
          _probe = ctrl;
        }
      },
    );
    _apply(_player, r);
  }

  // ------------------------------------------------------------------
  //  Verdict
  // ------------------------------------------------------------------
  void _computeVerdict() {
    final bool netBlock = _captive.stat == _Stat.fail ||
        _captive.stat == _Stat.timeout ||
        _dns.stat == _Stat.fail ||
        _dns.stat == _Stat.timeout ||
        (_stream.detail.contains('456'));
    final bool allOk = _checks.every((_Check c) => c.stat == _Stat.ok);
    final bool netOk = _captive.stat == _Stat.ok &&
        _dns.stat == _Stat.ok &&
        _stream.stat == _Stat.ok &&
        _source.stat == _Stat.ok;
    final bool playerKo =
        _player.stat == _Stat.fail || _player.stat == _Stat.timeout;

    if (allOk) {
      _verdict = _Verdict.pivotOk;
    } else if (netBlock) {
      _verdict = _Verdict.networkBlock;
    } else if (netOk && playerKo) {
      _verdict = _Verdict.playerBug;
    } else {
      _verdict = _Verdict.partial;
    }
  }

  /// Libellé TECHNIQUE (français) réservé au journal logcat — le libellé
  /// AFFICHÉ passe par l10n (cf. [_verdictLabelUi]).
  String _verdictLabel() {
    switch (_verdict) {
      case _Verdict.running:
        return 'DIAGNOSTIC EN COURS…';
      case _Verdict.pivotOk:
        return 'PIVOT ON-DEVICE VALIDÉ';
      case _Verdict.networkBlock:
        return 'BLOCAGE CÔTÉ RÉSEAU';
      case _Verdict.playerBug:
        return 'BUG PLAYER';
      case _Verdict.partial:
        return 'DIAGNOSTIC PARTIEL';
    }
  }

  /// Libellé du verdict affiché à l'écran (traduit).
  String _verdictLabelUi(BuildContext context) {
    switch (_verdict) {
      case _Verdict.running:
        return context.l10n.tvDiagVerdictRunning;
      case _Verdict.pivotOk:
        return context.l10n.tvDiagVerdictPivotOk;
      case _Verdict.networkBlock:
        return context.l10n.tvDiagVerdictNetworkBlock;
      case _Verdict.playerBug:
        return context.l10n.tvDiagVerdictPlayerBug;
      case _Verdict.partial:
        return context.l10n.tvDiagVerdictPartial;
    }
  }

  /// Libellé AFFICHÉ d'une ligne de vérif (traduit) — le champ `name` des
  /// [_Check] reste en français pour le journal logcat.
  String _checkLabel(BuildContext context, int index) {
    switch (index) {
      case 0:
        return context.l10n.tvDiagCheckCaptive;
      case 1:
        return context.l10n.tvDiagCheckDns;
      case 2:
        return context.l10n.tvDiagCheckStream;
      case 3:
        return context.l10n.tvDiagCheckSource;
      default:
        return context.l10n.tvDiagCheckPlayer;
    }
  }

  Color _verdictColor() {
    switch (_verdict) {
      case _Verdict.running:
        return Colors.amber;
      case _Verdict.pivotOk:
        return const Color(0xFF4CAF50);
      case _Verdict.networkBlock:
        return const Color(0xFFE53935);
      case _Verdict.playerBug:
        return const Color(0xFFFF9800);
      case _Verdict.partial:
        return const Color(0xFFFFC107);
    }
  }

  Color _statColor(_Stat s) {
    switch (s) {
      case _Stat.ok:
        return const Color(0xFF4CAF50);
      case _Stat.fail:
        return const Color(0xFFE53935);
      case _Stat.timeout:
        return const Color(0xFFFF9800);
      case _Stat.unknown:
        return Colors.white54;
      case _Stat.running:
        return Colors.amber;
      case _Stat.pending:
        return Colors.white30;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.exit) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Back géré dans _onKey (même schéma que tv_player_screen, fiable sur les
    // box où le retour arrive comme KeyEvent et non via le système).
    return Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 36, 48, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.tvDiagTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.tvDiagSubtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  // ----- Verdict -----
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                    decoration: BoxDecoration(
                      color: _verdictColor().withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _verdictColor(), width: 2),
                    ),
                    child: Row(
                      children: <Widget>[
                        if (!_done)
                          const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                                strokeWidth: 3, color: Colors.amber),
                          )
                        else
                          Icon(
                            _verdict == _Verdict.pivotOk
                                ? Icons.check_circle_rounded
                                : Icons.error_rounded,
                            color: _verdictColor(),
                            size: 30,
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            _verdictLabelUi(context),
                            style: TextStyle(
                              color: _verdictColor(),
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // ----- Lignes de vérif -----
                  Expanded(
                    child: ListView.separated(
                      itemCount: _checks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (BuildContext context, int i) {
                        final _Check c = _checks[i];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: 42,
                              child: Text(
                                _glyph(c.stat),
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    _checkLabel(context, i),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c.detail,
                                    style: TextStyle(
                                      color: _statColor(c.stat),
                                      fontSize: 19,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Text(
                        context.l10n.tvDiagBackToQuit,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 16),
                      ),
                      const Spacer(),
                      // Sonde lecteur (5) : mini-vue native montée seulement
                      // pendant la sonde. 256×144 = visible mais discret.
                      if (_probe != null)
                        Container(
                          width: 256,
                          height: 144,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            color: Colors.black,
                          ),
                          child: NativeVideoView(controller: _probe!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
