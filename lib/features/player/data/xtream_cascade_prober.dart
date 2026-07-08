// =========================================================
//  xtream_cascade_prober.dart — Exécution de la cascade de variantes
// =========================================================
//  Le CODE UNIQUE qui sonde les variantes d'URL Xtream après un échec
//  (« la chaîne marche sur IBO mais 404 chez nous »). Utilisé par le
//  chemin de lecture réel (VideoPlayerScreen._declareChannelBlocked)
//  ET par le test d'intégration bout-en-bout — c'est le même code qui
//  tourne en prod et sous test, pas une copie.
//
//  CONTRAT DE JOURNAL (bug terrain du 2026-07-08 11:37 : « la cascade
//  annoncée ne s'exécute jamais » — impossible à diagnostiquer sans
//  trace) : CHAQUE variante essayée écrit UNE ligne
//
//      [cascade] essai 2/4 : http://host/•••/•••/ID.m3u8 → HTTP 404
//
//  puis soit la lecture reprend (variante gagnante), soit on passe à
//  la suivante. Les identifiants sont masqués À L'AFFICHAGE seulement :
//  la sonde reçoit toujours l'URL BRUTE.
// =========================================================

import '../../cast/data/stream_probe.dart';
import 'stream_diagnostics.dart';
import 'xtream_url_variants.dart';

/// Variante gagnante trouvée par la cascade.
class CascadeWin {
  const CascadeWin({
    required this.url,
    required this.formatCode,
    required this.userAgent,
  });

  /// URL BRUTE à ouvrir dans le lecteur.
  final String url;

  /// Code de format à mémoriser pour la source (`live:m3u8`…).
  final String formatCode;

  /// Signature qui a obtenu la réponse média sur cette variante.
  final String userAgent;
}

/// Sonde les variantes d'URL d'un contenu Xtream, dans l'ordre de la
/// cascade, et s'arrête à la première qui répond.
class XtreamCascadeProber {
  XtreamCascadeProber._();

  /// Sonde toutes les variantes de [rawUrl] (SAUF l'originale, index 0,
  /// que l'appelant a déjà sondée) avec les signatures [uaCandidates].
  /// Renvoie la gagnante ou `null` si aucune ne répond.
  ///
  /// [isCancelled] est consulté entre chaque sonde (zap pendant le
  /// diagnostic → on abandonne sans bruit).
  /// [probe] est injectable pour les tests unitaires ; par défaut c'est
  /// la vraie sonde réseau (StreamProbe).
  static Future<CascadeWin?> findWorkingVariant(
    String rawUrl,
    XtreamContentType type, {
    required List<String> uaCandidates,
    bool Function()? isCancelled,
    Future<UserAgentProbeResult> Function(
      String url, {
      required List<String> candidates,
    })? probe,
  }) async {
    final List<XtreamUrlCandidate> variants =
        XtreamUrlVariants.cascadeFor(rawUrl, type);
    if (variants.length <= 1) {
      StreamDiagnostics.instance.recordEvent(
        'cascade',
        '[cascade] URL sans variante possible '
            '(${StreamDiagnostics.maskCredentials(rawUrl)}) — rien à essayer',
        level: 'warn',
      );
      return null;
    }
    StreamDiagnostics.instance.recordEvent(
      'cascade',
      '[cascade] ${variants.length - 1} variante(s) à essayer pour '
          '${type.name} (original : '
          '${StreamDiagnostics.maskCredentials(rawUrl)})',
    );

    for (int i = 1; i < variants.length; i++) {
      if (isCancelled?.call() ?? false) {
        StreamDiagnostics.instance.recordEvent(
            'cascade', '[cascade] annulée (zap) avant l\'essai ${i + 1}');
        return null;
      }
      final XtreamUrlCandidate candidate = variants[i];
      final UserAgentProbeResult result = probe != null
          ? await probe(candidate.url, candidates: uaCandidates)
          : await StreamProbe.instance
              .probeUserAgents(candidate.url, candidates: uaCandidates);

      // LA ligne contractuelle du journal : essai numéroté → statut.
      final StreamProbeResult? first =
          result.attempts.isEmpty ? null : result.attempts.values.first;
      final String statut = result.workingUserAgent != null
          ? 'OK (UA "${result.workingUserAgent}")'
          : (first?.errorCode != null
              ? 'HTTP ${first!.errorCode}'
              : (first?.errorReason ?? 'échec'));
      StreamDiagnostics.instance.recordEvent(
        'cascade',
        '[cascade] essai ${i + 1}/${variants.length} : '
            '${StreamDiagnostics.maskCredentials(candidate.url)} → $statut',
        level: result.workingUserAgent != null ? 'info' : 'warn',
      );

      if (result.workingUserAgent != null) {
        return CascadeWin(
          url: candidate.url,
          formatCode: candidate.formatCode,
          userAgent: result.workingUserAgent!,
        );
      }
    }
    StreamDiagnostics.instance.recordEvent(
      'cascade',
      '[cascade] aucune variante ne répond',
      level: 'error',
    );
    return null;
  }
}
