// =========================================================
//  playback_session_stats_test.dart — S3 : taxonomie + agrégats
// =========================================================
//  USINE v2 run 002. Deux briques pures du lecteur mobile :
//    1. PlaybackErrorTaxonomy : chaque famille S3 reconnaît ses
//       messages réels (libmpv/HTTP) et le 403 sort en `token`
//       (jamais en `source`) — c'est ce qui interdit les boucles
//       de retry aveugles sur un compte expiré.
//    2. PlaybackSessionStats : TTFF, stalls, ratio de rebuffering
//       et taux de démarrage, à l'horloge INJECTÉE (zéro flakiness).
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/playback_error_taxonomy.dart';
import 'package:tv_king/features/player/domain/playback_session_stats.dart';

void main() {
  group('PlaybackErrorTaxonomy.classify', () {
    test('réseau : timeout / DNS / TLS / connexion coupée', () {
      expect(PlaybackErrorTaxonomy.classify('Connection timed out'),
          PlaybackErrorCategory.network);
      expect(PlaybackErrorTaxonomy.classify('Failed to resolve hostname'),
          PlaybackErrorCategory.network);
      expect(PlaybackErrorTaxonomy.classify('TLS handshake failed'),
          PlaybackErrorCategory.network);
      expect(PlaybackErrorTaxonomy.classify('Connection reset by peer'),
          PlaybackErrorCategory.network);
    });

    test('token : 401/403 prioritaires sur la famille source', () {
      expect(PlaybackErrorTaxonomy.classify('HTTP error 403 Forbidden'),
          PlaybackErrorCategory.tokenExpired);
      expect(PlaybackErrorTaxonomy.classify('401 Unauthorized'),
          PlaybackErrorCategory.tokenExpired);
      expect(PlaybackErrorTaxonomy.classify('token expired, please renew'),
          PlaybackErrorCategory.tokenExpired);
    });

    test('source : 404/5xx, manifeste, EOF immédiat', () {
      expect(PlaybackErrorTaxonomy.classify('HTTP error 404 Not Found'),
          PlaybackErrorCategory.source);
      expect(PlaybackErrorTaxonomy.classify('Invalid data found'),
          PlaybackErrorCategory.source);
      expect(
          PlaybackErrorTaxonomy.classify(
              'Error when loading first segment of playlist'),
          PlaybackErrorCategory.source);
      expect(PlaybackErrorTaxonomy.classify('HTTP error 503'),
          PlaybackErrorCategory.source);
    });

    test('décodeur : codec non supporté / échec décodeur', () {
      expect(
          PlaybackErrorTaxonomy.classify(
              'Failed to initialize a video decoder'),
          PlaybackErrorCategory.decoder);
      expect(PlaybackErrorTaxonomy.classify('unsupported format hevc'),
          PlaybackErrorCategory.decoder);
    });

    test('inconnu : vide ou exotique, jamais d\'exception', () {
      expect(PlaybackErrorTaxonomy.classify(''),
          PlaybackErrorCategory.unknown);
      expect(PlaybackErrorTaxonomy.classify('   '),
          PlaybackErrorCategory.unknown);
      expect(PlaybackErrorTaxonomy.classify('quelque chose de bizarre'),
          PlaybackErrorCategory.unknown);
    });
  });

  group('PlaybackSessionStats', () {
    // Horloge pilotée : chaque test avance `now` à la main.
    late DateTime now;
    DateTime clock() => now;

    setUp(() => now = DateTime(2026, 1, 1, 12));

    void advance(int ms) => now = now.add(Duration(milliseconds: ms));

    test('session jamais démarrée : started=false, ratio=0', () {
      final PlaybackSessionStats s =
          PlaybackSessionStats(isLive: true, clock: clock);
      advance(5000);
      final PlaybackSessionSummary sum = s.summarize();
      expect(sum.started, isFalse);
      expect(sum.ttffMs, isNull);
      expect(sum.sessionMs, 5000);
      expect(sum.rebufferRatio, 0);
      expect(sum.healthy, isFalse);
      expect(sum.toLogLine(), contains('JAMAIS DEMARREE'));
    });

    test('TTFF = ouverture → première frame, premières frames suivantes ignorées',
        () {
      final PlaybackSessionStats s =
          PlaybackSessionStats(isLive: true, clock: clock);
      advance(800);
      s.onFirstFrame();
      advance(10000);
      s.onFirstFrame(); // reprise interne → ne change pas le TTFF
      final PlaybackSessionSummary sum = s.summarize();
      expect(sum.ttffMs, 800);
      expect(sum.started, isTrue);
    });

    test('buffering AVANT la première frame = chargement, pas un stall', () {
      final PlaybackSessionStats s =
          PlaybackSessionStats(isLive: true, clock: clock);
      s.onBuffering(true); // chargement initial
      advance(700);
      s.onBuffering(false);
      s.onFirstFrame();
      advance(1000);
      final PlaybackSessionSummary sum = s.summarize();
      expect(sum.stallCount, 0);
      expect(sum.bufferingMs, 0);
    });

    test('stalls et ratio : 2 gels de 500 ms sur 10 s de lecture', () {
      final PlaybackSessionStats s =
          PlaybackSessionStats(isLive: true, clock: clock);
      s.onFirstFrame();
      advance(4000);
      s.onBuffering(true);
      advance(500);
      s.onBuffering(false);
      advance(4000);
      s.onBuffering(true);
      s.onBuffering(true); // double émission → ignorée
      advance(500);
      s.onBuffering(false);
      s.onBuffering(false); // double émission → ignorée
      advance(1000);
      final PlaybackSessionSummary sum = s.summarize();
      expect(sum.stallCount, 2);
      expect(sum.bufferingMs, 1000);
      expect(sum.rebufferRatio, closeTo(0.1, 0.001)); // 1000/10000
      expect(sum.healthy, isFalse); // 10 % > seuil 5 %
    });

    test('gel encore ouvert à la fermeture : temps compté quand même', () {
      final PlaybackSessionStats s =
          PlaybackSessionStats(isLive: false, clock: clock);
      s.onFirstFrame();
      advance(9000);
      s.onBuffering(true);
      advance(1000);
      final PlaybackSessionSummary sum = s.summarize(); // gel jamais refermé
      expect(sum.bufferingMs, 1000);
      expect(sum.stallCount, 1);
    });

    test('erreurs par famille + reconnexions agrégées', () {
      final PlaybackSessionStats s =
          PlaybackSessionStats(isLive: true, clock: clock);
      s.onFirstFrame();
      s.onError(PlaybackErrorCategory.network);
      s.onError(PlaybackErrorCategory.network);
      s.onError(PlaybackErrorCategory.tokenExpired);
      s.onRecovery();
      advance(1000);
      final PlaybackSessionSummary sum = s.summarize();
      expect(sum.errorCounts, <String, int>{'reseau': 2, 'token': 1});
      expect(sum.recoveryCount, 1);
      expect(sum.healthy, isFalse);
      expect(sum.toLogLine(), contains('erreurs=reseau:2,token:1'));
    });

    test('session parfaite : healthy=true', () {
      final PlaybackSessionStats s =
          PlaybackSessionStats(isLive: true, clock: clock);
      advance(600);
      s.onFirstFrame();
      advance(60000);
      final PlaybackSessionSummary sum = s.summarize();
      expect(sum.healthy, isTrue);
      expect(sum.toLogLine(), contains('rebuffer=0.0%'));
    });
  });
}
