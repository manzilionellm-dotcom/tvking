// =========================================================
//  m3u_fetch_timeouts_test.dart — Un fournisseur lent n'est plus
//  « refusé après 90 s » tant qu'il envoie des octets.
// =========================================================
//  Mesuré le 05/10/2026 sur la box de test (boîte noire) :
//  « liste M3U du panel refusée après 90,0 s : Impossible de récupérer
//  la playlist ». Le fournisseur, derrière Cloudflare, dépasse les 90 s.
//  Règles testées sur le vrai M3uFetcher avec un client HTTP simulé :
//    - un corps qui arrive lentement mais régulièrement passe ;
//    - un serveur qui se tait au milieu est coupé après le silence
//      maximal, avec la raison « puis s'est tu » ;
//    - un serveur qui ne répond jamais est coupé après l'attente des
//      en-têtes, avec la raison « n'a pas répondu » ;
//    - le repli rétablit 90 s / 90 s / 90 s.
//  Adresses 127.0.0.1, aucune liste réelle.
// =========================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/features/playlists/data/m3u_fetcher.dart';

/// Client qui rejoue un scénario : délai avant les en-têtes, puis des
/// paquets espacés, puis (option) un silence sans fin.
class _ScenarioClient extends http.BaseClient {
  _ScenarioClient({
    required this.headersDelay,
    required this.chunks,
    required this.gap,
    this.stallAfter = false,
  });

  final Duration headersDelay;
  final List<String> chunks;
  final Duration gap;
  final bool stallAfter;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(headersDelay);
    final StreamController<List<int>> ctrl = StreamController<List<int>>();
    unawaited(() async {
      for (final String c in chunks) {
        await Future<void>.delayed(gap);
        if (ctrl.isClosed) return;
        ctrl.add(Uint8List.fromList(c.codeUnits));
      }
      if (!stallAfter) await ctrl.close();
      // stallAfter : on ne ferme jamais → silence.
    }());
    return http.StreamedResponse(ctrl.stream, 200);
  }
}

const String _head = '#EXTM3U\n';
String _line(int i) => '#EXTINF:-1,Chaîne $i\nhttp://127.0.0.1/t/$i.ts\n';

void main() {
  const FetchTimeouts fast = FetchTimeouts(
    headers: Duration(milliseconds: 400),
    idle: Duration(milliseconds: 300),
    total: Duration(seconds: 5),
  );

  test('délais : 120 s / 60 s de silence / 10 min ; repli 90 s partout', () {
    final FetchTimeouts t = M3uFetcher.fetchTimeouts(legacy: false);
    expect(t.headers, const Duration(seconds: 120));
    expect(t.idle, const Duration(seconds: 60));
    expect(t.total, const Duration(minutes: 10));
    final FetchTimeouts l = M3uFetcher.fetchTimeouts(legacy: true);
    expect(l.headers, const Duration(seconds: 90));
    expect(l.idle, const Duration(seconds: 90));
    expect(l.total, const Duration(seconds: 90));
  });

  test('lent mais régulier : la liste passe (le silence compte, pas la durée)',
      () async {
    // 8 paquets espacés de 100 ms = 800 ms de corps, bien plus que le
    // silence maximal de 300 ms : avec l'ancien délai total, ça coupait.
    final http.Client client = _ScenarioClient(
      headersDelay: const Duration(milliseconds: 50),
      chunks: <String>[_head, for (int i = 0; i < 7; i++) _line(i)],
      gap: const Duration(milliseconds: 100),
    );
    final Uint8List bytes = await M3uFetcher.fetchBytes(
      'http://127.0.0.1/lent.m3u',
      httpClient: client,
      timeouts: fast,
    );
    expect(String.fromCharCodes(bytes), contains('Chaîne 6'));
  });

  test('le serveur commence puis se tait : coupé, raison lisible', () async {
    final http.Client client = _ScenarioClient(
      headersDelay: const Duration(milliseconds: 50),
      chunks: <String>[_head, _line(0)],
      gap: const Duration(milliseconds: 50),
      stallAfter: true,
    );
    final Stopwatch sw = Stopwatch()..start();
    await expectLater(
      M3uFetcher.fetchBytes(
        'http://127.0.0.1/muet.m3u',
        httpClient: client,
        timeouts: fast,
      ),
      throwsA(predicate((Object e) =>
          e.toString().contains('puis s\'est tu') &&
          e.toString().contains('Mo reçus'))),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)),
        reason: 'coupé au silence de 300 ms, pas au plafond de 5 s');
  });

  test('aucune réponse : coupé après l\'attente des en-têtes', () async {
    final http.Client client = _ScenarioClient(
      headersDelay: const Duration(seconds: 3),
      chunks: const <String>[],
      gap: Duration.zero,
    );
    await expectLater(
      M3uFetcher.fetchBytes(
        'http://127.0.0.1/sourd.m3u',
        httpClient: client,
        timeouts: fast,
      ),
      throwsA(predicate((Object e) => e.toString().contains('pas répondu'))),
    );
  });
}
