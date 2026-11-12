// Téléchargement du bouquet Xtream en UN bloc (11/11/2026) : seuil selon la
// RAM, délai d'INACTIVITÉ au lieu d'un délai total, repli par catégorie si
// le bloc s'interrompt après le début des données, jamais de rafale de
// requêtes vers un serveur muet. Serveur simulé, données synthétiques.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/core/app/box_memory_budget.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/playlist_import_limits.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

const int _kCats = 6;

String _stream(int id, int cat) => jsonEncode(<String, Object>{
      'num': id,
      'name': 'Chaîne $id',
      'stream_id': id,
      'stream_icon': 'http://logo.invalid/$id.png',
      'epg_channel_id': 'c$id.fr',
      'category_id': '$cat',
      'added': '1700000000',
      'custom_sid': '',
      // Champ inutilisé (sauté par le lecteur) : grossit le JSON comme les
      // vrais fournisseurs, sans dépasser le plafond de 50 000 chaînes.
      'direct_source': 'x' * 120,
    });

List<int> _whole(int count) =>
    utf8.encode('[${List<String>.generate(count, (int i) => _stream(i, i % _kCats)).join(',')}]');

List<int> _category(int cat) => utf8.encode(
    '[${<String>[for (int k = 0; k < 3; k++) _stream(1000 + cat * 10 + k, cat)].join(',')}]');

final List<int> _categories = utf8.encode(jsonEncode(<Map<String, String>>[
  for (int c = 0; c < _kCats; c++) <String, String>{'category_id': '$c', 'category_name': 'Cat $c'},
]));

/// Réponse en morceaux espacés de [gap] ; [failAfter] coupe le flux après
/// ce nombre de morceaux (erreur réseau), [stallAfter] cesse d'envoyer.
Stream<List<int>> _chunked(List<int> body,
    {int chunks = 8, Duration gap = Duration.zero, int? failAfter, int? stallAfter}) {
  // StreamController : comme une vraie connexion, l'annulation est
  // immédiate même quand plus rien n'arrive (blocage simulé).
  final StreamController<List<int>> out = StreamController<List<int>>();
  final int size = (body.length / chunks).ceil();
  bool cancelled = false;
  out.onCancel = () => cancelled = true;
  Future<void>(() async {
    for (int i = 0; i < chunks && !cancelled; i++) {
      if (failAfter != null && i == failAfter) {
        out.addError(http.ClientException('connexion coupée en plein téléchargement'));
        await out.close();
        return;
      }
      if (stallAfter != null && i == stallAfter) return; // plus aucun octet
      if (gap > Duration.zero) await Future<void>.delayed(gap);
      final int start = i * size;
      if (start >= body.length) break;
      out.add(body.sublist(start, start + size > body.length ? body.length : start + size));
    }
    if (!cancelled) await out.close();
  });
  return out.stream;
}

class _Server {
  _Server(this.whole);
  final Stream<List<int>> Function() whole;
  int wholeCalls = 0;
  final Set<String> categoryCalls = <String>{};

  http.Client client() => MockClient.streaming((http.BaseRequest r, _) async {
        final String? action = r.url.queryParameters['action'];
        if (action == 'get_live_categories') {
          return http.StreamedResponse(Stream<List<int>>.value(_categories), 200);
        }
        if (action == 'get_live_streams') {
          final String? cat = r.url.queryParameters['category_id'];
          if (cat == null) {
            wholeCalls++;
            return http.StreamedResponse(whole(), 200);
          }
          categoryCalls.add(cat);
          return http.StreamedResponse(Stream<List<int>>.value(_category(int.parse(cat))), 200);
        }
        return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
      });
}

Future<List<Channel>> _import(_Server server, {Duration timeout = const Duration(seconds: 20)}) =>
    XtreamClient(
      serverUrl: 'http://xtream.invalid',
      username: 'u',
      password: 'p',
      httpClient: server.client(),
      timeout: timeout,
    ).fetchLiveChannels(playlistId: 1);

void main() {
  setUp(() => BoxMemoryBudget.debugTier = BoxRamTier.tight);
  tearDown(() => BoxMemoryBudget.debugTier = null);

  test('seuil du bloc selon la RAM : 24 / 48 / 64 Mo, sous le plafond dur', () {
    expect(xtreamSingleShotBytesFor(BoxRamTier.tight), 24 * 1024 * 1024);
    expect(xtreamSingleShotBytesFor(BoxRamTier.balanced), 48 * 1024 * 1024);
    expect(xtreamSingleShotBytesFor(BoxRamTier.roomy), 64 * 1024 * 1024);
    for (final BoxRamTier t in BoxRamTier.values) {
      expect(xtreamSingleShotBytesFor(t), lessThan(kMaxXtreamJsonBytes));
    }
  });

  test('une liste de 11 Mo arrive en UNE requête (avant : 919 requêtes par catégorie)', () async {
    final List<int> body = _whole(36000); // ~11 Mo de JSON
    expect(body.length, greaterThan(10 * 1024 * 1024));
    expect(body.length, lessThan(kXtreamSingleShotBytes));
    final _Server server = _Server(() => _chunked(body, chunks: 32));
    final List<Channel> channels = await _import(server);
    expect(channels.length, 36000);
    expect(server.wholeCalls, 1);
    expect(server.categoryCalls, isEmpty);
  });

  test('téléchargement lent mais continu : plus d’échec sur délai total', () async {
    // 8 morceaux à 60 ms d'écart = ~480 ms > délai de 200 ms : avant, délai
    // TOTAL dépassé → import en échec. Maintenant, délai d'INACTIVITÉ respecté.
    final _Server server = _Server(() => _chunked(_whole(200), gap: const Duration(milliseconds: 60)));
    final List<Channel> channels =
        await _import(server, timeout: const Duration(milliseconds: 200));
    expect(channels.length, 200);
    expect(server.categoryCalls, isEmpty);
  });

  test('coupure APRÈS le début des données : repli par catégorie, import réussi', () async {
    final _Server server = _Server(() => _chunked(_whole(400), failAfter: 3));
    final List<Channel> channels = await _import(server);
    expect(server.categoryCalls.length, _kCats);
    expect(channels.length, _kCats * 3);
  });

  test('plus aucun octet pendant le délai d’inactivité : repli par catégorie', () async {
    final _Server server = _Server(() => _chunked(_whole(400), stallAfter: 2));
    final List<Channel> channels =
        await _import(server, timeout: const Duration(milliseconds: 150));
    expect(server.categoryCalls.length, _kCats);
    expect(channels.length, _kCats * 3);
  });

  test('serveur muet dès la connexion : erreur, et aucune rafale par catégorie', () async {
    final _Server server = _Server(() => _chunked(_whole(10), failAfter: 0));
    await expectLater(_import(server), throwsA(anything));
    expect(server.categoryCalls, isEmpty);
  });
}
