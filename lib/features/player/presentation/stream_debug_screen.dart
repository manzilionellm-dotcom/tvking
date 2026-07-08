// =========================================================
//  stream_debug_screen.dart — Écran debug flux CACHÉ (mobile)
// =========================================================
//  Accès : écran « À propos » → appui LONG sur la pastille de
//  version. Volontairement absent des menus : c'est un outil de
//  diagnostic terrain, pas une feature grand public.
//
//  Affiche, pour le flux en cours (ou le dernier joué) :
//    - codec vidéo / audio détectés + résolution,
//    - statut HTTP réel + MIME + URL finale après redirections,
//    - User-Agent envoyé au serveur,
//    - la DERNIÈRE ERREUR EXACTE du moteur de lecture,
//    - le journal des derniers événements (ouvertures, erreurs,
//      reconnexions watchdog/relais, sondes multi-signatures).
//
//  + « Tester le flux maintenant » : refait une requête HTTP sur
//    l'URL avec le User-Agent actuel et montre le verdict (statut,
//    MIME, redirections) — pour trancher en 5 s entre « serveur
//    KO / signature refusée » et « souci de décodage local ».
//
//  Les identifiants Xtream sont MASQUÉS partout (URL affichées et
//  rapport copié) : un screenshot ne fuite pas le compte.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/data/cast_black_box.dart';
import '../../cast/data/stream_probe.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../data/player_settings.dart';
import '../data/stream_diagnostics.dart';

class StreamDebugScreen extends StatefulWidget {
  const StreamDebugScreen({super.key});

  @override
  State<StreamDebugScreen> createState() => _StreamDebugScreenState();
}

class _StreamDebugScreenState extends State<StreamDebugScreen> {
  bool _probing = false;
  bool _checkingAccount = false;

  // PAS de contrôle automatique du compte à l'ouverture (mission
  // 2026-07-08 17:07) : sur un abonnement 1-connexion, CHAQUE requête
  // réseau non sollicitée compte — le journal terrain montrait encore
  // « un probe + 2 player_api en 10 s » après la lecture, dont ce
  // contrôle auto. Ici TOUT est manuel : boutons « Vérifier le compte »
  // et « Tester le flux » uniquement.

  /// Playlist Xtream à contrôler : celle du flux courant si connue,
  /// sinon la première source Xtream chargée (cas « rien joué encore »).
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

  /// Interroge player_api.php (user_info) : statut du compte, date
  /// d'expiration, connexions max/actives. But : trancher en un coup
  /// d'œil « code mort » vs « mauvais format d'URL de flux ».
  Future<void> _checkAccountNow() async {
    final Playlist? p = _xtreamPlaylist();
    if (p == null ||
        p.xtreamServer == null ||
        p.xtreamUsername == null ||
        p.xtreamPassword == null ||
        _checkingAccount) {
      return;
    }
    setState(() => _checkingAccount = true);
    final StreamDiagnostics d = StreamDiagnostics.instance;
    d.recordEvent('xtream', 'Contrôle du compte (player_api.php)…');
    try {
      // fetchAccountInfo enregistre lui-même le résultat dans la
      // boîte noire (statut / expiration / connexions).
      await XtreamClient(
        serverUrl: p.xtreamServer!,
        username: p.xtreamUsername!,
        password: p.xtreamPassword!,
      ).fetchAccountInfo();
    } catch (e) {
      d.recordEvent('xtream', 'Contrôle du compte impossible : $e',
          level: 'error');
    } finally {
      if (mounted) setState(() => _checkingAccount = false);
    }
  }

  /// Re-teste l'URL de la session courante avec le User-Agent actif.
  /// Le résultat part dans le journal + l'instantané HTTP.
  Future<void> _probeNow() async {
    final StreamDiagnostics d = StreamDiagnostics.instance;
    final String? url = d.streamUrl;
    if (url == null || url.isEmpty || _probing) return;
    setState(() => _probing = true);
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
    } catch (e) {
      d.recordEvent('probe', 'Test impossible : $e', level: 'error');
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _copyReport() async {
    // Le rapport principal embarque AUSSI la boîte noire cast : les
    // testeurs copient naturellement CE bouton-là — sans la concat, le
    // support recevait le rapport flux et jamais celui du cast.
    final String report = '${StreamDiagnostics.instance.buildReport()}\n\n'
        '=== CAST (boîte noire) ===\n'
        '${CastDiagnostics.instance.exportReport()}';
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rapport copié dans le presse-papiers')),
    );
  }

  Future<void> _copyCastReport() async {
    await Clipboard.setData(
      ClipboardData(text: CastDiagnostics.instance.exportReport()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rapport cast copié dans le presse-papiers'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Diagnostic flux (debug)'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.copy_all_rounded),
            tooltip: 'Copier le rapport',
            onPressed: _copyReport,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: StreamDiagnostics.instance,
        builder: (BuildContext context, _) {
          final StreamDiagnostics d = StreamDiagnostics.instance;
          final bool hasSession = d.streamUrl != null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              if (!hasSession)
                _card(
                  child: Text(
                    'Aucun flux ouvert pour le moment.\n\n'
                    'Lance une chaîne ou un film, puis reviens ici : '
                    'cet écran capture tout ce que le lecteur sait '
                    '(codecs, statut HTTP, signature envoyée, erreur '
                    'exacte du moteur).',
                    style: AppTextStyles.bodyMedium,
                  ),
                )
              else ...<Widget>[
                // ----- Flux -----
                _sectionTitle('Flux'),
                _card(
                  child: Column(
                    children: <Widget>[
                      _row('Titre', d.title ?? '—'),
                      _row(
                        'URL',
                        StreamDiagnostics.maskCredentials(d.streamUrl!),
                      ),
                      _row(
                        'Ouvert à',
                        d.sessionStart == null
                            ? '—'
                            : d.sessionStart
                                .toString()
                                .split('.')
                                .first,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ----- HTTP -----
                _sectionTitle('Serveur (HTTP)'),
                _card(
                  child: Column(
                    children: <Widget>[
                      _row(
                        'Statut',
                        d.httpStatus?.toString() ??
                            '— (pas encore observé)',
                        valueColor: d.httpStatus == null
                            ? null
                            : (d.httpStatus! < 400
                                ? AppColors.success
                                : AppColors.live),
                      ),
                      _row('MIME', d.httpMime ?? '—'),
                      _row(
                        'URL finale',
                        d.httpFinalUrl == null
                            ? '— (aucune redirection observée)'
                            : StreamDiagnostics.maskCredentials(
                                d.httpFinalUrl!),
                      ),
                      _row('User-Agent envoyé', d.userAgent ?? '—'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _probing ? null : _probeNow,
                  icon: _probing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: Text(
                    _probing
                        ? 'Test en cours…'
                        : 'Tester le flux maintenant',
                  ),
                ),
                const SizedBox(height: 14),

                // ----- Décodage -----
                _sectionTitle('Décodage'),
                _card(
                  child: Column(
                    children: <Widget>[
                      _row('Codec vidéo',
                          d.videoCodec?.toUpperCase() ?? '— (pas décodé)'),
                      _row('Codec audio',
                          d.audioCodec?.toUpperCase() ?? '— (pas décodé)'),
                      _row('Résolution', d.resolution ?? '—'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ----- Erreur exacte -----
                _sectionTitle('Dernière erreur du moteur'),
                _card(
                  child: Text(
                    d.lastPlayerError ?? 'Aucune erreur fatale enregistrée.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: d.lastPlayerError == null
                          ? AppColors.textMuted
                          : AppColors.live,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ----- Compte Xtream (affiché dès qu'une source Xtream
              //       existe, même sans flux ouvert) -----
              if (_xtreamPlaylist() != null) ...<Widget>[
                _sectionTitle('Compte Xtream'),
                _card(
                  child: Column(
                    children: <Widget>[
                      _row(
                        'Statut',
                        d.xtreamStatus ?? '— (pas encore contrôlé)',
                        valueColor: d.xtreamStatus == null
                            ? null
                            : (d.xtreamStatus!.trim().toLowerCase() ==
                                    'active'
                                ? AppColors.success
                                : AppColors.live),
                      ),
                      _row(
                        'Expire le',
                        d.xtreamExpDate == null
                            ? '—'
                            : d.xtreamExpDate
                                .toString()
                                .split('.')
                                .first,
                        valueColor: d.xtreamExpDate == null
                            ? null
                            : (d.xtreamExpDate!.isAfter(DateTime.now())
                                ? AppColors.success
                                : AppColors.live),
                      ),
                      _row(
                        'Connexions',
                        d.xtreamMaxConnections == null &&
                                d.xtreamActiveCons == null
                            ? '—'
                            : '${d.xtreamActiveCons ?? '?'} active(s) / '
                                '${d.xtreamMaxConnections ?? '?'} max',
                      ),
                      _row(
                        'Contrôlé à',
                        d.xtreamCheckedAt == null
                            ? '—'
                            : d.xtreamCheckedAt
                                .toString()
                                .split('.')
                                .first,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _checkingAccount ? null : _checkAccountNow,
                  icon: _checkingAccount
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined, size: 18),
                  label: Text(
                    _checkingAccount
                        ? 'Contrôle en cours…'
                        : 'Vérifier le compte maintenant',
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ----- Cast (boîte noire du pipeline Google Cast / DLNA) -----
              //  Même philosophie que le reste de l'écran : données
              //  RÉELLES de la dernière tentative de cast (routage,
              //  statuts Worker, App ID, erreurs natives avec code).
              //  Alimentée par CastManager/GoogleCastTransport via le
              //  singleton CastDiagnostics (cast_black_box.dart).
              _sectionTitle('Cast (dernière tentative)'),
              ListenableBuilder(
                listenable: CastDiagnostics.instance,
                builder: (BuildContext context, _) {
                  final CastDiagnostics box = CastDiagnostics.instance;
                  final CastAttemptSnapshot? snap = box.latest;
                  final List<CastBlackBoxEvent> castTail =
                      box.events.length > 8
                          ? box.events.sublist(box.events.length - 8)
                          : box.events;
                  return _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _row(
                          'Découverte',
                          box.lastDiscoveryEndedAt == null
                              ? '— (aucun scan encore)'
                              : '${box.devicesSeenTotal} appareil(s), dont '
                                  '${box.devicesSeenChromecast} Google Cast',
                        ),
                        if (snap == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Aucune tentative de cast enregistrée — '
                              'caste une chaîne puis reviens ici.',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          )
                        else ...<Widget>[
                          _row('Cible',
                              '${snap.deviceName} (${snap.deviceKind})'),
                          _row(
                            'Étape',
                            snap.stage,
                            valueColor: snap.stage == 'failed'
                                ? AppColors.live
                                : (snap.stage == 'playing'
                                    ? AppColors.success
                                    : null),
                          ),
                          if (snap.castPath != null)
                            _row('Chemin', snap.castPath!),
                          if (snap.contentType != null)
                            _row('contentType', snap.contentType!),
                          if (snap.requestedAppId != null)
                            _row(
                              'App ID',
                              '${snap.requestedAppId}'
                                  '${snap.connectedAppId != null ? ' → ${snap.connectedAppId}' : ''}',
                              valueColor: snap.connectedAppId != null &&
                                      snap.connectedAppId !=
                                          snap.requestedAppId
                                  ? const Color(0xFFFFB74D)
                                  : null,
                            ),
                          if (snap.castSignStatus != null)
                            _row(
                              '/cast-sign',
                              'HTTP ${snap.castSignStatus}',
                              valueColor: snap.castSignStatus == 200
                                  ? null
                                  : const Color(0xFFFFB74D),
                            ),
                          if (snap.proxyVerifyStatus != null)
                            _row(
                              '/cast-proxy',
                              'HTTP ${snap.proxyVerifyStatus}'
                                  '${snap.proxyUpstreamStatus != null ? ' · upstream=${snap.proxyUpstreamStatus}' : ''}',
                              valueColor: snap.proxyVerifyStatus! >= 200 &&
                                      snap.proxyVerifyStatus! < 300
                                  ? AppColors.success
                                  : AppColors.live,
                            ),
                          if (snap.mediaUrlRedacted != null)
                            _row('URL média', snap.mediaUrlRedacted!),
                          if (snap.frameworkErrorCode != null)
                            _row(
                              'Erreur framework',
                              '${snap.frameworkErrorKind} '
                                  'code=${snap.frameworkErrorCode}',
                              valueColor: AppColors.live,
                            ),
                          if (snap.finalError != null)
                            _row('Erreur finale', snap.finalError!,
                                valueColor: AppColors.live),
                        ],
                        if (castTail.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          ...castTail.map(
                            (CastBlackBoxEvent e) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '${e.at.toIso8601String().substring(11, 19)} '
                                '[${e.kind}] ${e.message}',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  height: 1.3,
                                  color: switch (e.level) {
                                    CastBlackBoxLevel.error => AppColors.live,
                                    CastBlackBoxLevel.warn =>
                                      const Color(0xFFFFB74D),
                                    CastBlackBoxLevel.info =>
                                      AppColors.textSecondary,
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _copyCastReport,
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copier le rapport cast'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),

              // ----- Journal -----
              _sectionTitle('Journal (récent → ancien)'),
              _card(
                child: d.events.isEmpty
                    ? Text('Journal vide.', style: AppTextStyles.bodyMedium)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: d.events
                            .map((StreamDiagEvent e) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 3),
                                  child: Text(
                                    e.toString(),
                                    style:
                                        AppTextStyles.bodyMedium.copyWith(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      height: 1.3,
                                      color: switch (e.level) {
                                        'error' => AppColors.live,
                                        'warn' => const Color(0xFFFFB74D),
                                        _ => AppColors.textSecondary,
                                      },
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: AppTextStyles.headlineMedium.copyWith(fontSize: 14),
        ),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: valueColor,
                ),
              ),
            ),
          ],
        ),
      );
}
