// =========================================================
//  one_connection_zapping_test.dart — Client 1-connexion parfait
// =========================================================
//  Bug terrain (journal du 2026-07-08 17:07) : sur un compte
//  1 connexion, le zapping rapide ouvrait 5 lectures en 10 s sans
//  fermeture attendue → « connexions 2/1 » côté panel → « Error when
//  loading first segment » + « End of file » sur les chaînes suivantes.
//
//  Ce test d'INTÉGRATION reproduit le panel 1-connexion :
//    - 403 dès qu'une 2e connexion arrive (slot occupé OU pas encore
//      libéré) ;
//    - le slot n'est LIBÉRÉ qu'1 s après la fermeture de la connexion
//      précédente (comportement réel des panels Xtream).
//
//  Scénario (objets de PRODUCTION : LocalStreamRelay réel +
//  StreamBlockedFallback réel, abonné par son attach() de prod) :
//    1. lecture de la chaîne 1 (octets TS qui coulent) ;
//    2. zap RAPIDE 2 → 3 → 4 → 5 (80 ms entre chaque) : le debounce
//       n'ouvre QUE la chaîne finale — les intermédiaires n'émettent
//       AUCUNE requête (vérifié sur le journal du panel) ;
//    3. la chaîne 5 se connecte pendant la fenêtre de libération →
//       403 → fail-fast du relais → BACKOFF (attente + UN retry
//       silencieux) → la lecture repart et des octets TS coulent.
//
//  ASSERTIONS (Definition of Done de la mission) :
//    - la chaîne finale reçoit des octets TS (0x47) ;
//    - zéro 403 non récupéré (aucune erreur montrée à l'utilisateur) ;
//    - JAMAIS 2 connexions simultanées côté panel ;
//    - chaînes intermédiaires : zéro requête.
//  Preuve : extrait du journal imprimé (livrable du rapport).
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';
import 'package:tv_king/features/player/data/player_settings.dart';
import 'package:tv_king/features/player/data/stream_blocked_fallback.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

/// Panel Xtream 1-connexion : sert les flux `.ts` en continu, refuse en
/// 403 toute connexion pendant qu'une autre est active OU pendant la
/// fenêtre de libération (1 s après une fermeture — comportement réel).
class _OneConnectionPanel {
  _OneConnectionPanel(this.server) {
    server.listen(_handle);
  }

  final HttpServer server;

  /// Journal du panel : tous les chemins demandés (la preuve que les
  /// zaps absorbés n'émettent RIEN).
  final List<String> requestedPaths = <String>[];

  /// Chemins qui ont réellement DIFFUSÉ des octets.
  final List<String> streamedPaths = <String>[];

  /// Nombre de requêtes arrivées pendant qu'une AUTRE diffusait encore
  /// (= vraies « 2 connexions simultanées » — doit rester 0).
  int simultaneousAttempts = 0;

  /// Total de 403 servis (chacun doit être récupéré par le backoff).
  int rejected403 = 0;

  int _activeStreams = 0;
  bool _coolingDown = false;
  Timer? _coolTimer;
  final List<Timer> _feeds = <Timer>[];

  int get port => server.port;

  Future<void> _handle(HttpRequest req) async {
    requestedPaths.add(req.uri.path);
    if (!req.uri.path.endsWith('.ts')) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    if (_activeStreams >= 1 || _coolingDown) {
      if (_activeStreams >= 1) simultaneousAttempts++;
      rejected403++;
      req.response.statusCode = 403;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<html>max connections reached</html>');
      await req.response.close();
      return;
    }
    _activeStreams++;
    streamedPaths.add(req.uri.path);
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType('video', 'mp2t');
    req.response.bufferOutput = false;
    final List<int> packet = List<int>.filled(188, 0x47);
    bool closed = false;
    late final Timer feed;
    void onClosed() {
      if (closed) return;
      closed = true;
      feed.cancel();
      _activeStreams--;
      // Le slot n'est PAS libéré tout de suite : 1 s de « libération »
      // comme les vrais panels.
      _coolingDown = true;
      _coolTimer?.cancel();
      _coolTimer = Timer(const Duration(seconds: 1), () {
        _coolingDown = false;
      });
    }

    feed = Timer.periodic(const Duration(milliseconds: 20), (_) {
      try {
        req.response.add(packet);
      } catch (_) {
        onClosed();
      }
    });
    _feeds.add(feed);
    unawaited(req.response.done
        .then((_) => onClosed(), onError: (Object _) => onClosed()));
  }

  Future<void> close() async {
    for (final Timer t in _feeds) {
      t.cancel();
    }
    _coolTimer?.cancel();
    await server.close(force: true);
  }
}

/// Liaisons « widget » minimales, à l'identique de VideoPlayerScreen :
/// debounce de zap, ouverture via le relais, lecture des octets (rôle
/// de mpv), fermeture ATTENDUE de la lecture précédente avant chaque
/// nouvelle ouverture. Aucune logique de diagnostic ici — elle vit dans
/// les objets de production.
class _ZapHarness {
  _ZapHarness({required this.channels, required Duration retryBackoff})
      : current = channels.first {
    fallback = StreamBlockedFallback(
      getChannel: () => current,
      getOverrideUrl: () => null,
      getEffectiveUrl: () => current.streamUrl,
      isAlive: () => alive,
      hasDecodedFrames: () => (bytesByChannel[current.id] ?? 0) > 0,
      getAdoptedAltUrl: () => null,
      setAdoptedAltUrl: (_) {},
      resetWatchdogBudget: () {},
      reopen: (String url) => unawaited(open(url)),
      showBlocked: (BlockedVerdict v) => blockedMessages.add(v.message),
      retryBackoff: retryBackoff,
    )..attach(); // le VRAI abonnement de production au relais
  }

  final List<Channel> channels;
  Channel current;
  bool alive = true;
  late final StreamBlockedFallback fallback;
  final List<String> blockedMessages = <String>[];
  final Map<String, int> bytesByChannel = <String, int>{};

  Timer? _debounce;
  HttpClient? _client;
  StreamSubscription<List<int>>? _reading;

  /// « _openMedia » : fermeture ATTENDUE de la lecture précédente puis
  /// ouverture via le relais ; un client HTTP local joue le rôle de mpv.
  Future<void> open(String url) async {
    final Channel target = current;
    // STOP ATTENDU : on ferme le « mpv » précédent avant TOUTE nouvelle
    // connexion (dans le widget : _recyclePlayer, stop/dispose awaités).
    await _reading?.cancel();
    _reading = null;
    _client?.close(force: true);
    _client = null;
    StreamDiagnostics.instance.beginSession(
      url: url,
      userAgent: PlayerSettings.instance.userAgent,
      title: target.cleanName,
      playlistId: target.playlistId,
    );
    final String localUrl = await LocalStreamRelay.instance.playUrlFor(url);
    // Petit délai façon mpv : le demuxer met quelques dizaines de ms à
    // émettre sa requête après l'open.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (!alive || target.id != current.id) return;
    _client = HttpClient();
    try {
      final HttpClientResponse resp =
          await (await _client!.getUrl(Uri.parse(localUrl))).close();
      _reading = resp.listen((List<int> c) {
        bytesByChannel[target.id] =
            (bytesByChannel[target.id] ?? 0) + c.length;
      });
    } catch (_) {
      // Session fermée par le fail-fast du relais : l'événement
      // definitiveFailures a déjà pris la main.
    }
  }

  /// « _applyZap » : l'UI change tout de suite, l'ouverture RÉSEAU est
  /// débouncée 400 ms — les chaînes intermédiaires n'émettent RIEN.
  void zapTo(Channel next) {
    current = next;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!alive || current.id != next.id) return;
      unawaited(open(next.streamUrl));
    });
  }

  Future<void> shutdown() async {
    alive = false;
    _debounce?.cancel();
    await _reading?.cancel();
    _client?.close(force: true);
    fallback.detach();
  }
}

void main() {
  test(
      'INTÉGRATION 1-CONNEXION : zap rapide sur 5 chaînes → la finale '
      'affiche des octets TS, zéro 403 non récupéré, jamais 2 connexions '
      'simultanées', () async {
    final _OneConnectionPanel panel = _OneConnectionPanel(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    // Source non-Xtream volontairement : si le backoff échouait, la
    // cascade sortirait en erreur visible → blockedMessages non vide →
    // le test échoue (aucun faux positif possible).
    PlaylistRepository.instance.debugSeedPlaylists(const <Playlist>[]);

    final List<Channel> channels = List<Channel>.generate(5, (int i) {
      final int n = i + 1;
      return Channel(
        id: 'chan-$n',
        name: 'Chaîne $n',
        category: 'TNT',
        streamUrl: 'http://127.0.0.1:${panel.port}/live/USER/PASS/$n.ts',
        isLive: true,
      );
    });

    final _ZapHarness screen = _ZapHarness(
      channels: channels,
      // 1,5 s dans le test (3 s sur le terrain) : doit couvrir la
      // fenêtre de libération d'1 s du panel.
      retryBackoff: const Duration(milliseconds: 1500),
    );

    // ----- 1) Ouverture de la chaîne 1 (comme initState) --------------
    await screen.open(channels.first.streamUrl);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(screen.bytesByChannel['chan-1'] ?? 0, greaterThan(0),
        reason: 'la chaîne 1 doit diffuser avant le test de zapping');

    // ----- 2) ZAP RAPIDE 2 → 3 → 4 → 5 (80 ms entre chaque) -----------
    for (int i = 1; i < channels.length; i++) {
      screen.zapTo(channels[i]);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    // ----- 3) Debounce (400 ms) + 403 attendu + backoff + retry -------
    //  ~400 ms de debounce + ~1,5 s de backoff + connexion : on laisse
    //  3,5 s au pipeline complet pour converger.
    final Stopwatch waited = Stopwatch()..start();
    while ((screen.bytesByChannel['chan-5'] ?? 0) == 0 &&
        waited.elapsed < const Duration(milliseconds: 3500)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // ----- 4) Definition of Done -------------------------------------
    expect(screen.bytesByChannel['chan-5'] ?? 0, greaterThan(0),
        reason: 'la chaîne FINALE doit afficher des octets TS malgré le '
            '403 de libération.\nJournal:\n${_journal()}');
    expect(screen.blockedMessages, isEmpty,
        reason: 'zéro 403 non récupéré : le backoff doit reprendre en '
            'silence, sans erreur utilisateur');
    expect(panel.simultaneousAttempts, 0,
        reason: 'JAMAIS 2 connexions simultanées côté panel');
    // Les chaînes intermédiaires (2, 3, 4) n'ont émis AUCUNE requête.
    for (final int absorbed in <int>[2, 3, 4]) {
      expect(
        panel.requestedPaths.where(
            (String p) => p.contains('/live/USER/PASS/$absorbed.ts')),
        isEmpty,
        reason: 'zap absorbé = zéro requête (chaîne $absorbed)',
      );
    }
    // Seules la chaîne de départ et la chaîne finale ont diffusé.
    expect(panel.streamedPaths,
        <String>['/live/USER/PASS/1.ts', '/live/USER/PASS/5.ts']);
    // Le 403 de la fenêtre de libération a bien eu lieu ET a été
    // récupéré (sinon l'assertion des octets aurait échoué).
    expect(panel.rejected403, greaterThanOrEqualTo(1),
        reason: 'le scénario doit passer par le 403 de libération');

    // ----- 5) Contrats de journal (preuves de la mission) -------------
    final String journal = _journal();
    expect(journal, contains('[backoff]'),
        reason: 'le backoff doit être journalisé');
    expect(journal, contains('retry silencieux'),
        reason: 'le retry unique doit être journalisé');
    expect(journal, isNot(contains('USER/PASS')),
        reason: 'identifiants toujours masqués dans le journal');

    // ----- LIVRABLE : extrait du journal (à coller dans le rapport) ---
    // ignore: avoid_print
    print('===== EXTRAIT JOURNAL (test 1-connexion) =====');
    for (final StreamDiagEvent e
        in StreamDiagnostics.instance.events.toList().reversed) {
      // ignore: avoid_print
      print(e.toString());
    }
    // ignore: avoid_print
    print('===== FIN EXTRAIT =====');

    await screen.shutdown();
    LocalStreamRelay.instance.closeOtherPlaybacks('__aucune__');
    await panel.close();
  });
}

String _journal() => StreamDiagnostics.instance.events
    .map((StreamDiagEvent e) => e.message)
    .join('\n');
