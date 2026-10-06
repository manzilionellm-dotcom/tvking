// =========================================================
//  panel_getphp_reconcile_test.dart — téléphone : ajouter, retirer, éteindre
// =========================================================
//  Constaté le 06/10/2026 sur le téléphone du propriétaire :
//    • lien get.php du panel téléchargé en fichier M3U complet (> 200 Mo
//      chez son fournisseur) → « Pas encore de chaînes » ;
//    • retirer UNE liste au panel ne l'enlevait pas du téléphone ;
//    • « éteindre » au panel n'avait aucun effet.
//  Vrai RemoteSourceRepository.sync, vrai SQLite (FFI), serveur simulé
//  (MockClient) qui joue le Worker ET le fournisseur. Hôtes *.invalid.
// =========================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/panel_source_decision.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

const String kMac = 'MK:24:2A:D0:0E:F3';
const String kGetPhp = 'http://fournisseur.invalid:8080/get.php?username=u1&password=p1&type=m3u_plus&output=ts';
const String kOther = 'http://autre.invalid/liste.m3u';

class _Fs extends PathProviderPlatform {
  _Fs(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

class _Server {
  List<Map<String, Object?>> sources = <Map<String, Object?>>[];
  int m3uDownloads = 0;
  bool apiDown = false;

  http.Client client() => MockClient((http.Request r) async {
        final String path = r.url.path;
        if (path.startsWith('/api/device-source/')) {
          return http.Response(jsonEncode(<String, Object?>{'mac': kMac, 'sources': sources}), 200);
        }
        if (path.startsWith('/api/')) return http.Response('{}', 404);
        if (r.url.host == 'fournisseur.invalid' && path.endsWith('player_api.php')) {
          if (apiDown) return http.Response('refusé', 403);
          final String action = r.url.queryParameters['action'] ?? '';
          if (action.isEmpty) {
            return http.Response(jsonEncode(<String, Object?>{
              'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
              'server_info': <String, Object?>{'url': 'fournisseur.invalid', 'port': '8080'},
            }), 200);
          }
          if (action == 'get_live_categories') {
            return http.Response(jsonEncode(<Map<String, String>>[
              <String, String>{'category_id': '1', 'category_name': 'Sport'},
            ]), 200);
          }
          if (action == 'get_live_streams') {
            return http.Response(jsonEncode(<Map<String, Object>>[
              for (int i = 1; i <= 5; i++)
                <String, Object>{'stream_id': i, 'name': 'Chaîne $i', 'category_id': '1'},
            ]), 200);
          }
          return http.Response('[]', 200);
        }
        if (r.url.host == 'fournisseur.invalid' && path.endsWith('get.php')) {
          m3uDownloads++;
          return http.Response('#EXTM3U\n#EXTINF:-1 group-title="G",Lourde\nhttp://127.0.0.1/s/1.ts\n', 200);
        }
        if (r.url.host == 'autre.invalid') {
          return http.Response('#EXTM3U\n#EXTINF:-1 group-title="G",Autre\nhttp://127.0.0.1/s/9.ts\n', 200);
        }
        return http.Response('inconnu', 404);
      });
}

Future<void> _sync(_Server s) {
  RemoteSourceRepository.xtreamHttpForTest = s.client;
  return http.runWithClient(() => RemoteSourceRepository.sync(), s.client);
}
Future<List<Playlist>> _lists() => PlaylistRepository.instance.getAllPlaylists();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  PathProviderPlatform.instance = _Fs(Directory.systemTemp.createTempSync('zuno-phone-').path);
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{'device.virtual_mac.v1': kMac});
    RemoteSourceRepository.m3uLinkAsM3u = false;
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('channels');
    await db.delete('playlists');
  });

  test('lien get.php du panel → compte Xtream (API), pas le fichier M3U', () async {
    final _Server s = _Server()..sources = <Map<String, Object?>>[
      <String, Object?>{'type': 'm3u', 'm3u_url': kGetPhp, 'label': 'Mon abonnement'},
    ];
    await _sync(s);
    final List<Playlist> ps = await _lists();
    expect(ps, hasLength(1));
    expect(ps.single.type, PlaylistType.xtream);
    expect(s.m3uDownloads, 0, reason: 'le gros fichier M3U n’est jamais téléchargé');
  });

  test('API refusée → repli sur le fichier M3U', () async {
    final _Server s = _Server()
      ..apiDown = true
      ..sources = <Map<String, Object?>>[
        <String, Object?>{'type': 'm3u', 'm3u_url': kGetPhp},
      ];
    await _sync(s);
    final List<Playlist> ps = await _lists();
    expect(ps.single.type, PlaylistType.m3u);
    expect(s.m3uDownloads, 1);
  });

  test('retirer UNE liste au panel : enlevée du téléphone, l’autre reste ; ajoutée à la main : jamais touchée', () async {
    final _Server s = _Server()..sources = <Map<String, Object?>>[
      <String, Object?>{'type': 'm3u', 'm3u_url': kGetPhp},
      <String, Object?>{'type': 'm3u', 'm3u_url': kOther},
    ];
    await _sync(s);
    expect(await _lists(), hasLength(2));
    // Liste ajoutée à la main par le client (pas posée par le panel).
    await http.runWithClient(
        () => PlaylistRepository.instance.addM3uPlaylist(name: 'Perso', url: 'http://autre.invalid/perso.m3u'),
        s.client);
    expect(await _lists(), hasLength(3));

    s.sources = <Map<String, Object?>>[<String, Object?>{'type': 'm3u', 'm3u_url': kOther}];
    await _sync(s);
    final List<Playlist> ps = await _lists();
    expect(ps.any((Playlist p) => p.type == PlaylistType.xtream), isFalse, reason: 'retirée = retirée');
    expect(ps.any((Playlist p) => p.m3uUrl == kOther), isTrue);
    expect(ps.any((Playlist p) => p.name == 'Perso'), isTrue, reason: 'liste du client intacte');
  });

  test('éteindre au panel : enlevée ; rallumer : revient', () async {
    final _Server s = _Server()..sources = <Map<String, Object?>>[
      <String, Object?>{'type': 'm3u', 'm3u_url': kGetPhp},
      <String, Object?>{'type': 'm3u', 'm3u_url': kOther},
    ];
    await _sync(s);
    s.sources = <Map<String, Object?>>[
      <String, Object?>{'type': 'm3u', 'm3u_url': kGetPhp, 'enabled': false},
      <String, Object?>{'type': 'm3u', 'm3u_url': kOther},
    ];
    await _sync(s);
    expect((await _lists()).any((Playlist p) => p.type == PlaylistType.xtream), isFalse);
    s.sources = <Map<String, Object?>>[
      <String, Object?>{'type': 'm3u', 'm3u_url': kGetPhp},
      <String, Object?>{'type': 'm3u', 'm3u_url': kOther},
    ];
    await _sync(s);
    expect((await _lists()).where((Playlist p) => p.type == PlaylistType.xtream), hasLength(1));
  });

  test('contre-preuve repli zuno.mobile.panel_reconcile_off : la liste retirée RESTE (ancien défaut)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': kMac,
      RemoteSourceRepository.panelReconcileOffKey: true,
    });
    final _Server s = _Server()..sources = <Map<String, Object?>>[
      <String, Object?>{'type': 'm3u', 'm3u_url': kGetPhp},
      <String, Object?>{'type': 'm3u', 'm3u_url': kOther},
    ];
    await _sync(s);
    s.sources = <Map<String, Object?>>[<String, Object?>{'type': 'm3u', 'm3u_url': kOther}];
    await _sync(s);
    expect((await _lists()).any((Playlist p) => p.type == PlaylistType.xtream), isTrue,
        reason: 'le défaut d’avant est bien reproduit');
  });

  test('contre-preuve repli zuno.mobile.getphp_as_m3u : le fichier M3U est téléchargé', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': kMac,
      RemoteSourceRepository.m3uLinkAsM3uKey: true,
    });
    final _Server s = _Server()..sources = <Map<String, Object?>>[
      <String, Object?>{'type': 'm3u', 'm3u_url': kGetPhp},
    ];
    await _sync(s);
    expect((await _lists()).single.type, PlaylistType.m3u);
    expect(s.m3uDownloads, 1);
  });

  test('empreintes servies : un lien get.php vaut aussi pour son compte Xtream', () {
    final Set<ProvisionKey> k = RemoteSourceRepository.keysOfServed(<Map<String, dynamic>>[
      <String, dynamic>{'type': 'm3u', 'm3u_url': kGetPhp},
    ]);
    expect(k.map((ProvisionKey e) => e.kind).toSet(), <String>{'m3u', 'xtream'});
  });
}
