// =========================================================
//  line_occupancy_probe.dart — QUI tient la ligne, et combien de temps ?
// =========================================================
//  Terrain 20/08 (exploitant, à bout) : « Limite de connexions (1/1) »
//  persiste ALORS QUE le build installé ferme ses connexions en
//  millisecondes (mesuré), n'ouvre plus d'aperçu sur les lignes
//  1-connexion, et retente 90 s. À ce stade, l'app est hors de cause —
//  la question devient : la ligne est-elle occupée par un AUTRE appareil,
//  ou le panel garde-t-il les sessions mortes plus longtemps que prévu ?
//
//  Cette sonde répond TOUTE SEULE, mesures à l'appui : pendant que CETTE
//  TV n'a AUCUNE connexion ouverte (précondition : l'appelant a tout
//  fermé), elle lit les compteurs réels du compte (player_api — une
//  requête d'API, PAS un flux) toutes les [interval] pendant [total], et
//  rend un verdict :
//    • freed       : la ligne s'est libérée au bout de [freedAfter] —
//                    c'est le « linger » réel du panel ; si > 90 s, il
//                    faut allonger le calendrier de reconnexion ;
//    • neverFreed  : occupée en continu SANS cette TV → un autre
//                    appareil (téléphone, autre box, identifiants
//                    partagés) ou le panel lui-même tient la ligne ;
//    • apiUnavailable : le panel ne fournit pas les compteurs.
//
//  Chaque échantillon est journalisé dans la Boîte noire (horodatage +
//  compteurs) : le verdict est vérifiable ligne à ligne.
// =========================================================

import 'dart:async';

import '../../playlists/data/xtream_client.dart';
import 'stream_diagnostics.dart';

/// Issue d'un test d'occupation de ligne.
enum LineProbeOutcome {
  /// La ligne s'est libérée pendant le test (voir [LineProbeReport.freedAfter]).
  freed,

  /// Occupée en continu pendant TOUT le test, sans aucune connexion de
  /// cette TV : quelqu'un d'autre tient la ligne.
  neverFreed,

  /// Le panel n'a pas répondu (ou ne renvoie pas les compteurs).
  apiUnavailable,
}

/// Résultat complet, verdict + mesures brutes.
class LineProbeReport {
  const LineProbeReport({
    required this.outcome,
    this.freedAfter,
    this.maxConnections,
    this.lastActive,
    this.samples = 0,
  });

  final LineProbeOutcome outcome;

  /// Temps écoulé entre le début du test et le premier échantillon à
  /// 0 connexion active ([LineProbeOutcome.freed] uniquement).
  final Duration? freedAfter;

  /// max_connections du compte (dernier échantillon lisible).
  final int? maxConnections;

  /// active_cons du dernier échantillon lisible.
  final int? lastActive;

  /// Nombre d'échantillons réellement lus.
  final int samples;
}

abstract final class LineOccupancyProbe {
  /// Lance le test. PRÉCONDITION : l'appelant a fermé toutes les
  /// connexions de l'app (lecteur, aperçu, relais, téléchargements) —
  /// le verdict n'a de sens que si cette TV ne compte pour rien.
  ///
  /// [now] injectable pour les tests (horloge par défaut sinon).
  static Future<LineProbeReport> run({
    required XtreamClient client,
    Duration total = const Duration(minutes: 3),
    Duration interval = const Duration(seconds: 5),
    bool Function()? isCancelled,
    void Function(Duration elapsed, int? active, int? max)? onSample,
  }) async {
    final DateTime start = DateTime.now();
    void log(String message, {String level = 'info'}) => StreamDiagnostics
        .instance
        .recordEvent('sonde-ligne', message, level: level);

    log('DÉBUT du test d\'occupation (cette TV : 0 connexion) — '
        'lecture des compteurs toutes les ${interval.inSeconds} s pendant '
        '${total.inMinutes} min');

    int consecutiveFailures = 0;
    int samples = 0;
    int? lastActive;
    int? lastMax;

    while (true) {
      if (isCancelled?.call() ?? false) {
        log('Test annulé par l\'utilisateur après $samples échantillon(s)');
        return LineProbeReport(
          outcome: LineProbeOutcome.apiUnavailable,
          maxConnections: lastMax,
          lastActive: lastActive,
          samples: samples,
        );
      }
      final Duration elapsed = DateTime.now().difference(start);
      if (elapsed >= total) break;

      try {
        final XtreamAccountInfo info = await client.fetchAccountInfo();
        consecutiveFailures = 0;
        samples++;
        lastActive = info.activeCons;
        lastMax = info.maxConnections;
        log('t+${elapsed.inSeconds}s : connexions '
            '${info.activeCons ?? '?'}/${info.maxConnections ?? '?'}'
            '${info.status == null ? '' : ' · ${info.status}'}');
        onSample?.call(elapsed, info.activeCons, info.maxConnections);
        if (info.activeCons == null) {
          // Panel qui ne renvoie pas active_cons : compteurs inutilisables.
          log('Le panel ne renvoie pas active_cons → mesure impossible',
              level: 'warn');
          return LineProbeReport(
            outcome: LineProbeOutcome.apiUnavailable,
            maxConnections: lastMax,
            samples: samples,
          );
        }
        if (info.activeCons == 0) {
          log('LIBÉRÉE après ${elapsed.inSeconds} s — c\'est le temps que '
              'ton fournisseur garde une session fermée');
          return LineProbeReport(
            outcome: LineProbeOutcome.freed,
            freedAfter: elapsed,
            maxConnections: lastMax,
            lastActive: 0,
            samples: samples,
          );
        }
      } catch (e) {
        consecutiveFailures++;
        log('Lecture des compteurs impossible ($e) — '
            'échec $consecutiveFailures/3', level: 'warn');
        if (consecutiveFailures >= 3) {
          return LineProbeReport(
            outcome: LineProbeOutcome.apiUnavailable,
            maxConnections: lastMax,
            lastActive: lastActive,
            samples: samples,
          );
        }
      }
      await Future<void>.delayed(interval);
    }

    log('OCCUPÉE EN CONTINU pendant ${total.inMinutes} min alors que cette '
        'TV n\'avait AUCUNE connexion → un autre appareil (ou le panel) '
        'tient la ligne. Ce n\'est pas cette application.', level: 'error');
    return LineProbeReport(
      outcome: LineProbeOutcome.neverFreed,
      maxConnections: lastMax,
      lastActive: lastActive,
      samples: samples,
    );
  }
}
