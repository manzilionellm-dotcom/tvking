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
//  Chaque ligne est aussi écrite dans logcat (tag DEFEW_DIAG) pour relire le
//  test à froid via `adb logcat -s DEFEW_DIAG`.
// =========================================================
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:native_video_player/native_video_player.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../channels/domain/channel.dart';
import '../../device/data/device_identity.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;

/// Tag logcat — `adb logcat -s DEFEW_DIAG`.
const String _kLogTag = 'DEFEW_DIAG';

/// Time-out commun à chaque vérif.
const Duration _kCheckTimeout = Duration(seconds: 8);

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
    // Capturé AVANT les await : utilisable même si l'écran est démonté.
    final AppLocalizations l10n = context.l10n;
    // Chaîne courante : sert d'hôte IPTV (DNS) + d'URL de flux (3 et 5).
    final List<Channel> chans = PlaylistRepository.instance.currentChannels;
    final Channel? chan = chans.isEmpty
        ? null
        : chans.firstWhere((Channel c) => c.isLive, orElse: () => chans.first);
    final String? streamUrl = chan?.streamUrl;
    final String? iptvHost =
        (streamUrl != null) ? Uri.tryParse(streamUrl)?.host : null;

    await _runCaptive(l10n);
    await _runDns(l10n, iptvHost);
    await _runStream(l10n, streamUrl);
    await _runSource(l10n);
    await _runPlayer(l10n, streamUrl);

    _computeVerdict();
    _done = true;
    if (mounted) setState(() {});
    _log('===== FIN DIAGNOSTIC — VERDICT: ${_verdict.name} =====');
  }

  // 1. Portail captif : un 204 « nu » = sortie Internet libre. Un 200 avec
  // corps, un 302 ou un autre code = portail captif / interception.
  Future<void> _runCaptive(AppLocalizations l10n) async {
    _set(_captive, _Stat.running, l10n.tvDiagCaptiveRunning);
    try {
      final http.Response r = await http
          .get(Uri.parse('http://connectivitycheck.gstatic.com/generate_204'))
          .timeout(_kCheckTimeout);
      if (r.statusCode == 204 && r.body.isEmpty) {
        _set(_captive, _Stat.ok, l10n.tvDiagCaptiveOk);
      } else {
        _set(_captive, _Stat.fail,
            l10n.tvDiagCaptiveFail(r.statusCode, r.body.length));
      }
    } on TimeoutException {
      _set(_captive, _Stat.timeout, l10n.tvDiagNoReply);
    } catch (e) {
      _set(_captive, _Stat.fail, _err(e));
    }
  }

  // 2. DNS : on résout l'hôte de la chaîne courante. Pas de chaîne = INCONNU.
  Future<void> _runDns(AppLocalizations l10n, String? host) async {
    if (host == null || host.isEmpty) {
      _set(_dns, _Stat.unknown, l10n.tvDiagNoChannelHost);
      return;
    }
    _set(_dns, _Stat.running, l10n.tvDiagDnsLookup(host));
    try {
      final List<InternetAddress> ips = await InternetAddress.lookup(host)
          .timeout(_kCheckTimeout);
      if (ips.isEmpty) {
        _set(_dns, _Stat.fail, l10n.tvDiagDnsNoIp(host));
      } else {
        _set(_dns, _Stat.ok,
            '$host → ${ips.map((InternetAddress a) => a.address).join(', ')}');
      }
    } on TimeoutException {
      _set(_dns, _Stat.timeout, l10n.tvDiagDnsTimeout(host));
    } catch (e) {
      _set(_dns, _Stat.fail, '$host : ${_err(e)}');
    }
  }

  // 3. Joignabilité du flux : HEAD (léger) puis repli GET. On AFFICHE le code.
  // 456 = blocage fournisseur (IP datacenter/cloud) — ici on est sur l'IP de
  // la box, donc un 456 prouverait que le fournisseur bloque même le LAN.
  Future<void> _runStream(AppLocalizations l10n, String? streamUrl) async {
    if (streamUrl == null || streamUrl.isEmpty) {
      _set(_stream, _Stat.unknown, l10n.tvDiagNoChannelUrl);
      return;
    }
    _set(_stream, _Stat.running, l10n.tvDiagStreamHead);
    final Uri uri = Uri.parse(streamUrl);
    try {
      int code;
      try {
        final http.Response h = await http.head(uri).timeout(_kCheckTimeout);
        code = h.statusCode;
      } catch (_) {
        // Beaucoup de serveurs IPTV refusent HEAD → on retente en GET (sans
        // lire tout le flux : le code de statut arrive avec les en-têtes). On
        // ANNULE aussitôt le corps : sinon la connexion live resterait ouverte
        // et pourrait bloquer la sonde lecteur (5) sur un abonnement 1 connexion.
        final http.Request req = http.Request('GET', uri);
        final http.StreamedResponse g =
            await req.send().timeout(_kCheckTimeout);
        code = g.statusCode;
        await g.stream.listen((_) {}).cancel();
      }
      if (code == 456) {
        // Les traductions gardent toutes « HTTP 456 » littéral (le verdict
        // s'appuie sur detail.contains('456')).
        _set(_stream, _Stat.fail, l10n.tvDiagStream456);
      } else if (code >= 200 && code < 400) {
        _set(_stream, _Stat.ok, l10n.tvDiagStreamOk(code));
      } else {
        _set(_stream, _Stat.fail, 'HTTP $code');
      }
    } on TimeoutException {
      _set(_stream, _Stat.timeout, l10n.tvDiagNoReply);
    } catch (e) {
      _set(_stream, _Stat.fail, _err(e));
    }
  }

  // 4. Source poussée : GET /api/device-source/<MAC>. Lecture seule. On montre
  // le code + si une source est assignée à cette box.
  Future<void> _runSource(AppLocalizations l10n) async {
    _set(_source, _Stat.running, l10n.tvDiagSourceReadingMac);
    String mac;
    try {
      mac = await DeviceIdentity.instance.mac;
    } catch (_) {
      mac = DeviceIdentity.instance.macSync;
    }
    if (!mac.startsWith('MK:')) {
      _set(_source, _Stat.unknown, l10n.tvDiagSourceMacUnknown(mac));
      return;
    }
    _set(_source, _Stat.running, 'GET device-source ($mac)…');
    try {
      final http.Response r = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/device-source/$mac'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(_kCheckTimeout);
      if (r.statusCode != 200) {
        _set(_source, _Stat.fail, 'HTTP ${r.statusCode}');
        return;
      }
      // On ne fait que CONSTATER la présence d'une source (pas de parsing
      // métier ni de chargement : c'est un diagnostic, lecture seule).
      final String b = r.body;
      final bool hasSource =
          (b.contains('"source"') && !b.contains('"source":null')) ||
              (b.contains('"sources"') && b.contains('{'));
      _set(_source, hasSource ? _Stat.ok : _Stat.fail,
          hasSource ? l10n.tvDiagSourceAssigned : l10n.tvDiagSourceNone);
    } on TimeoutException {
      _set(_source, _Stat.timeout, l10n.tvDiagNoReply);
    } catch (e) {
      _set(_source, _Stat.fail, _err(e));
    }
  }

  // 5. Sonde lecteur : on monte une MINI NativeVideoView (Media3/ExoPlayer,
  // même moteur que le lecteur de prod) sur l'URL de la chaîne courante et on
  // attend la 1re image (OK) ou une erreur (FAIL). On détruit tout après.
  Future<void> _runPlayer(AppLocalizations l10n, String? streamUrl) async {
    if (streamUrl == null || streamUrl.isEmpty) {
      _set(_player, _Stat.unknown, l10n.tvDiagNoChannelUrl);
      return;
    }
    _set(_player, _Stat.running, l10n.tvDiagPlayerOpening);
    final Completer<_Stat> c = Completer<_Stat>();
    final NativeVideoController ctrl =
        NativeVideoController(initialUrl: streamUrl);
    void listener() {
      if (c.isCompleted) return;
      if (ctrl.firstFrame) {
        c.complete(_Stat.ok);
      } else if (ctrl.hasError) {
        c.complete(_Stat.fail);
      }
    }

    ctrl.addListener(listener);
    if (mounted) setState(() => _probe = ctrl); // monte la vue → attach → play
    try {
      final _Stat s = await c.future.timeout(_kCheckTimeout);
      _set(_player, s,
          s == _Stat.ok ? l10n.tvDiagPlayerFirstFrame : l10n.tvDiagPlayerError);
    } on TimeoutException {
      _set(_player, _Stat.timeout, l10n.tvDiagPlayerNoFrame);
    } catch (e) {
      _set(_player, _Stat.fail, _err(e));
    } finally {
      ctrl.removeListener(listener);
      ctrl.dispose();
      if (mounted) setState(() => _probe = null);
    }
  }

  String _err(Object e) {
    final String s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
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

  String _verdictLabel() {
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

  /// Libellé UI localisé d'une vérif (le `name` du [_Check] reste la
  /// version technique française, écrite telle quelle dans logcat).
  String _checkLabel(_Check c) {
    if (identical(c, _captive)) return context.l10n.tvDiagCheckCaptive;
    if (identical(c, _dns)) return context.l10n.tvDiagCheckDns;
    if (identical(c, _stream)) return context.l10n.tvDiagCheckStream;
    if (identical(c, _source)) return context.l10n.tvDiagCheckSource;
    return context.l10n.tvDiagCheckPlayer;
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
                            _verdictLabel(),
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
                                    _checkLabel(c),
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
                        context.l10n.tvDiagExitHint,
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
