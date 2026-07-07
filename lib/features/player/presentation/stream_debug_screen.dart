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
import '../../cast/data/stream_probe.dart';
import '../data/player_settings.dart';
import '../data/stream_diagnostics.dart';

class StreamDebugScreen extends StatefulWidget {
  const StreamDebugScreen({super.key});

  @override
  State<StreamDebugScreen> createState() => _StreamDebugScreenState();
}

class _StreamDebugScreenState extends State<StreamDebugScreen> {
  bool _probing = false;

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
    await Clipboard.setData(
      ClipboardData(text: StreamDiagnostics.instance.buildReport()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rapport copié dans le presse-papiers')),
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
