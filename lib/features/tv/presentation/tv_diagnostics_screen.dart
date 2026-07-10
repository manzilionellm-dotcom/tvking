// =========================================================
//  tv_diagnostics_screen.dart — Boîte noire (diagnostic TV)
// =========================================================
//  La MÊME boîte noire que sur téléphone (StreamDiagnostics), rendue
//  pour la TÉLÉVISION : navigation D-pad, gros texte 10-foot, journal
//  qui défile. Elle est DÉJÀ alimentée par tout le pipeline TV (le live
//  passe par le relais → statuts HTTP, résolution DoH, reconnexions,
//  erreurs moteur, état du compte Xtream…). On ne fait ici que
//  l'AFFICHER et offrir les actions manuelles (aucune sonde réseau
//  automatique — même règle que sur téléphone).
//
//  Ouvert depuis « À propos » en sélectionnant la ligne Version
//  (équivalent D-pad de l'appui long sur la version côté mobile).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../cast/data/stream_probe.dart';
import '../../player/data/player_settings.dart';
import '../../player/data/stream_diagnostics.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvDiagnosticsScreen extends StatefulWidget {
  const TvDiagnosticsScreen({super.key});

  @override
  State<TvDiagnosticsScreen> createState() => _TvDiagnosticsScreenState();
}

class _TvDiagnosticsScreenState extends State<TvDiagnosticsScreen> {
  bool _busyAccount = false;
  bool _busyProbe = false;
  String _flash = '';

  /// Playlist Xtream à contrôler : celle du flux courant si connue,
  /// sinon la première source Xtream chargée.
  Playlist? _xtreamPlaylist() {
    final List<Playlist> all = PlaylistRepository.instance.currentPlaylists;
    final int? pid = StreamDiagnostics.instance.playlistId;
    if (pid != null) {
      for (final Playlist p in all) {
        if (p.id == pid) {
          return p.type == PlaylistType.xtream ? p : null;
        }
      }
    }
    for (final Playlist p in all) {
      if (p.type == PlaylistType.xtream) return p;
    }
    return null;
  }

  Future<void> _checkAccount() async {
    final Playlist? p = _xtreamPlaylist();
    if (p == null ||
        p.xtreamServer == null ||
        p.xtreamUsername == null ||
        p.xtreamPassword == null ||
        _busyAccount) {
      _setFlash(context.l10n.tvBlackBoxNoXtreamAccount);
      return;
    }
    setState(() => _busyAccount = true);
    final StreamDiagnostics d = StreamDiagnostics.instance;
    d.recordEvent('xtream', 'Contrôle du compte (player_api.php)…');
    try {
      // fetchAccountInfo enregistre lui-même le résultat dans la boîte noire.
      await XtreamClient(
        serverUrl: p.xtreamServer!,
        username: p.xtreamUsername!,
        password: p.xtreamPassword!,
      ).fetchAccountInfo();
      if (mounted) _setFlash(context.l10n.tvBlackBoxAccountChecked);
    } catch (e) {
      d.recordEvent('xtream', 'Contrôle du compte impossible : $e',
          level: 'error');
      if (mounted) _setFlash(context.l10n.tvBlackBoxCheckFailed);
    } finally {
      if (mounted) setState(() => _busyAccount = false);
    }
  }

  Future<void> _probe() async {
    final StreamDiagnostics d = StreamDiagnostics.instance;
    final String? url = d.streamUrl;
    if (url == null || url.isEmpty || _busyProbe) {
      _setFlash(context.l10n.tvBlackBoxNoStream);
      return;
    }
    setState(() => _busyProbe = true);
    final String ua = PlayerSettings.instance.userAgent;
    d.recordEvent('probe', 'Test manuel du flux (UA: $ua)…');
    try {
      final StreamProbeResult r =
          await StreamProbe.instance.probe(url, userAgent: ua);
      d.recordHttp(
        status: r.success ? (r.errorCode ?? 200) : r.errorCode,
        finalUrl: r.finalUrl,
        mime: r.mime,
        error: r.success ? null : (r.errorReason ?? 'échec'),
        source: 'probe',
      );
      d.recordEvent(
        'probe',
        r.success
            ? 'OK en ${r.timeToFirstByte ?? '?'} ms '
                '(${r.redirectCount} redirection(s))'
            : 'ÉCHEC : ${r.errorReason ?? '?'} '
                '${r.errorCode != null ? '(HTTP ${r.errorCode})' : ''}',
        level: r.success ? 'info' : 'error',
      );
      if (mounted) {
        _setFlash(r.success
            ? context.l10n.tvBlackBoxStreamOk
            : context.l10n.tvBlackBoxStreamFailed);
      }
    } catch (e) {
      d.recordEvent('probe', 'Test impossible : $e', level: 'error');
      if (mounted) _setFlash(context.l10n.tvBlackBoxTestFailed);
    } finally {
      if (mounted) setState(() => _busyProbe = false);
    }
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(
      ClipboardData(text: StreamDiagnostics.instance.buildReport()),
    );
    if (mounted) _setFlash(context.l10n.tvBlackBoxReportCopied);
  }

  void _setFlash(String msg) {
    if (!mounted) return;
    setState(() => _flash = msg);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TvTokens.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
          child: ListenableBuilder(
            listenable: StreamDiagnostics.instance,
            builder: (BuildContext context, _) {
              final StreamDiagnostics d = StreamDiagnostics.instance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.tvBlackBoxTitle,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.tvBlackBoxLastStreamSubtitle,
                    style: const TextStyle(fontSize: 15, color: TvTokens.muted),
                  ),
                  const SizedBox(height: 16),
                  // ----- Actions (D-pad) -----
                  Row(
                    children: <Widget>[
                      _ActionButton(
                        icon: Icons.verified_user_rounded,
                        label: _busyAccount
                            ? context.l10n.tvBlackBoxChecking
                            : context.l10n.tvBlackBoxCheckAccount,
                        autofocus: true,
                        onSelect: _checkAccount,
                      ),
                      const SizedBox(width: 12),
                      _ActionButton(
                        icon: Icons.wifi_tethering_rounded,
                        label: _busyProbe
                            ? context.l10n.tvBlackBoxTesting
                            : context.l10n.tvBlackBoxTestStream,
                        onSelect: _probe,
                      ),
                      const SizedBox(width: 12),
                      _ActionButton(
                        icon: Icons.copy_rounded,
                        label: context.l10n.tvBlackBoxCopyReport,
                        onSelect: _copyReport,
                      ),
                    ],
                  ),
                  if (_flash.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(_flash,
                        style: const TextStyle(
                            fontSize: 15,
                            color: TvTokens.success,
                            fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 16),
                  // ----- Instantané -----
                  _snapshot(d),
                  const SizedBox(height: 14),
                  Text(context.l10n.tvBlackBoxJournalHeader,
                      style: const TextStyle(
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.mutedDim)),
                  const SizedBox(height: 8),
                  // ----- Journal défilant (chaque ligne focusable → D-pad) -----
                  Expanded(child: _journal(d)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _snapshot(StreamDiagnostics d) {
    String mask(String? u) =>
        u == null ? '—' : StreamDiagnostics.maskCredentials(u);
    final List<({String k, String v})> rows = <({String k, String v})>[
      (k: context.l10n.tvBlackBoxRowTitle, v: d.title ?? '—'),
      (k: 'URL', v: mask(d.streamUrl)),
      (k: 'HTTP', v: d.httpStatus?.toString() ?? '—'),
      (k: 'MIME', v: d.httpMime ?? '—'),
      (k: 'Codec', v: '${d.videoCodec ?? '—'} / ${d.audioCodec ?? '—'}'
          '${d.resolution == null ? '' : ' · ${d.resolution}'}'),
      (
        k: context.l10n.tvBlackBoxRowAccount,
        v: '${d.xtreamStatus ?? '—'}'
            '${d.xtreamMaxConnections == null && d.xtreamActiveCons == null ? '' : ' · ${d.xtreamActiveCons ?? '?'}/${d.xtreamMaxConnections ?? '?'}'}'
      ),
      if (d.lastPlayerError != null)
        (k: context.l10n.tvBlackBoxRowError, v: d.lastPlayerError!),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        children: <Widget>[
          for (final ({String k, String v}) r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 120,
                    child: Text(r.k,
                        style: const TextStyle(
                            fontSize: 14,
                            color: TvTokens.muted,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text(r.v,
                        style: const TextStyle(
                            fontSize: 14,
                            color: TvTokens.text,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _journal(StreamDiagnostics d) {
    final List<StreamDiagEvent> events = d.events; // récent → ancien
    if (events.isEmpty) {
      return Text(context.l10n.tvBlackBoxNoEvents,
          style: const TextStyle(fontSize: 15, color: TvTokens.mutedDim));
    }
    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (BuildContext context, int i) {
        final StreamDiagEvent e = events[i];
        final Color c = switch (e.level) {
          'error' => TvTokens.live,
          'warn' => TvTokens.gold,
          _ => TvTokens.text,
        };
        // Chaque ligne est focusable : le D-pad la met en surbrillance et
        // le framework la fait défiler dans la vue.
        return TvFocusBuilder(
          scale: TvFocusScale.small,
          onSelect: () {},
          builder: (BuildContext context, bool focused) {
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: focused ? TvTokens.sel : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: focused ? TvTokens.gold : Colors.transparent),
              ),
              child: Text(
                e.toString(),
                style: TextStyle(
                    fontSize: 14, color: c, fontWeight: FontWeight.w500),
              ),
            );
          },
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.medium,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused ? TvTokens.gold : TvTokens.sel;
        final Color fg =
            focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 16, color: fg, fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
    );
  }
}
