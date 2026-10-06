// =========================================================
//  xtream_category_parallel_test.dart — grosse liste Xtream : catégories en parallèle borné
// =========================================================
//  Mesuré sur la SHIELD le 06/10/2026 : liste > 10 Mo → import par
//  catégorie, 914 appels l'un après l'autre, 136 s. Ici, vrai XtreamClient,
//  serveur simulé (MockClient, hôte *.invalid) qui répond en 40 ms par
//  catégorie et compte les appels simultanés.
//    1. parallèle : jamais plus de 4 appels à la fois, au moins 2 ;
//    2. MÊME résultat qu'en série (ordre, dédoublonnage, catégorie en
//       échec ignorée) ;
//    3. contre-preuve repli `zuno.xtream.per_category_serial` : 1 à la fois.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/playlist_import_limits.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

const int kCats = 40;

class _Server {
  int inFlight = 0;
  int maxInFlight = 0;
  // Catégories demandées (une catégorie en erreur 500 est redemandée avec
  // les autres User-Agent du client : on compte les catégories, pas les appels).
  final Set<String> categoriesAsked = <String>{};

  http.Client client() => MockClient((http.Request r) async {
        final String action = r.url.queryParameters['action'] ?? '';
        if (action == 'get_live_categories') {
          return http.Response(jsonEncode(<Map<String, String>>[
            for (int c = 0; c < kCats; c++) <String, String>{'category_id': '$c', 'category_name': 'Cat $c'},
          ]), 200);
        }
        if (action == 'get_live_streams') {
          final String? cat = r.url.queryParameters['category_id'];
          if (cat == null) {
            // Bouquet entier plus gros que le seuil : force l'import par catégorie.
            return http.Response(' ' * (kXtreamSingleShotBytes + 1024), 200);
          }
          categoriesAsked.add(cat);
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 40));
          inFlight--;
          final int c = int.parse(cat);
          if (c == 5) return http.Response('panne', 500); // catégorie en échec
          return http.Response(jsonEncode(<Map<String, Object>>[
            for (int k = 0; k < 3; k++)
              <String, Object>{'stream_id': c * 10 + k, 'name': 'Chaîne $c-$k', 'category_id': '$c'},
            // La même chaîne rangée dans les catégories 0 et 1 : une seule fois.
            if (c == 1) <String, Object>{'stream_id': 0, 'name': 'Chaîne 0-0', 'category_id': '1'},
          ]), 200);
        }
        return http.Response('{}', 404);
      });
}

Future<List<Channel>> _import(_Server s) => XtreamClient(
      serverUrl: 'http://xtream.invalid:8080',
      username: 'u',
      password: 'p',
      httpClient: s.client(),
    ).fetchLiveChannels(playlistId: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => RepairFlags.xtreamPerCategorySerial = false);

  test('parallèle borné : ≤ 4 appels simultanés, même résultat qu’en série', () async {
    final _Server par = _Server();
    final Stopwatch sw1 = Stopwatch()..start();
    final List<Channel> a = await _import(par);
    sw1.stop();

    RepairFlags.xtreamPerCategorySerial = true;
    final _Server ser = _Server();
    final Stopwatch sw2 = Stopwatch()..start();
    final List<Channel> b = await _import(ser);
    sw2.stop();

    expect(par.categoriesAsked.length, kCats);
    expect(par.maxInFlight, inInclusiveRange(2, kXtreamCategoryConcurrency));
    expect(ser.maxInFlight, 1, reason: 'contre-preuve : le repli lit une catégorie à la fois');
    expect(a.map((Channel c) => c.id).toList(), b.map((Channel c) => c.id).toList(),
        reason: 'même ordre, même dédoublonnage');
    expect(a.length, (kCats - 1) * 3, reason: 'catégorie 5 en échec ignorée, doublon retiré');
    expect(a.first.id, b.first.id);
    debugPrint('[mesure] $kCats catégories à 40 ms : parallèle ${sw1.elapsedMilliseconds} ms, '
        'série ${sw2.elapsedMilliseconds} ms');
  });
}
