// =========================================================
//  search_live_channels_test.dart — Chemin TV de SmartSearch
// =========================================================
//  Vague 1 : la recherche TV ne doit PLUS passer par un
//  `LIKE '%q%'` SQL. [PlaylistRepository.searchLiveChannels] est
//  l'unique porte d'entrée (tv_search_screen l'appelle) et elle
//  délègue à [SmartSearch].
//
//  Ces tests prouvent le contrat que le LIKE cassait :
//    • « bein 1 » trouve « beIN SPORTS 1 » (les mots ne se suivent
//      PAS dans le nom — LIKE '%bein 1%' renvoyait vide) ;
//    • « cine » trouve « Ciné+ » (accents) ;
//    • « sport france » trouve malgré l'ordre inversé ;
//    • « sprot » trouve malgré la faute de frappe.
//
//  Zéro SQLite, zéro réseau : on sème le cache mémoire
//  ([PlaylistRepository.debugSeedChannels]), le même bassin que
//  la box a déjà en RAM après le boot.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/data/smart_search.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';

/// IDs uniques dans TOUT le fichier : SmartSearch mémoïse par id
/// pour la session de test (même cache que channel.dart).
Channel _ch(
  String id,
  String name, {
  bool isLive = true,
  String category = 'GENERAL',
}) =>
    Channel(
      id: id,
      name: name,
      category: category,
      streamUrl: 'http://example.com/$id.ts',
      isLive: isLive,
    );

void main() {
  final PlaylistRepository repo = PlaylistRepository.instance;

  setUp(() {
    // currentChannels applique le filtre flavor : sans ça, StateError.
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
  });

  tearDown(() {
    repo.debugSeedChannels(const <Channel>[]);
    FlavorConfig.resetForTesting();
  });

  group('searchLiveChannels = SmartSearch (chemin TV)', () {
    test('« bein 1 » trouve beIN SPORTS 1 — LIKE aurait échoué', () async {
      // Preuve que le LIKE est le mauvais outil : la sous-chaîne
      // contiguë « bein 1 » N'EST PAS dans le nom (SPORTS s'intercale).
      const String nom = 'beIN SPORTS 1 FR';
      expect(nom.toLowerCase().contains('bein 1'), isFalse);

      repo.debugSeedChannels(<Channel>[
        _ch('slc-bein', nom),
        _ch('slc-tf1', 'TF1'),
      ]);

      final List<Channel> r =
          await repo.searchLiveChannels('bein 1', limit: 20);
      expect(r.map((Channel c) => c.id), contains('slc-bein'));
      expect(r.map((Channel c) => c.id), isNot(contains('slc-tf1')));
    });

    test('« cine » trouve « Ciné+ » (accents ignorés)', () async {
      repo.debugSeedChannels(<Channel>[
        _ch('slc-cine', 'Ciné+ Premier'),
        _ch('slc-m6', 'M6'),
      ]);

      final List<Channel> r =
          await repo.searchLiveChannels('cine', limit: 20);
      expect(r.map((Channel c) => c.id), contains('slc-cine'));
    });

    test('multi-mots, ordre libre : « sport france »', () async {
      repo.debugSeedChannels(<Channel>[
        _ch('slc-frsport', 'France Sport TV'),
        _ch('slc-news', 'France News'),
      ]);

      final List<Channel> r =
          await repo.searchLiveChannels('sport france', limit: 20);
      expect(r.map((Channel c) => c.id), contains('slc-frsport'));
      expect(r.map((Channel c) => c.id), isNot(contains('slc-news')));
    });

    test('faute légère : « sprot » → Sport TV', () async {
      repo.debugSeedChannels(<Channel>[
        _ch('slc-sport', 'Sport TV'),
        _ch('slc-arte', 'Arte'),
      ]);

      final List<Channel> r =
          await repo.searchLiveChannels('sprot', limit: 20);
      expect(r.map((Channel c) => c.id), contains('slc-sport'));
    });

    test('les films (isLive=false) restent hors du bassin LIVE', () async {
      repo.debugSeedChannels(<Channel>[
        _ch('slc-live', 'Ciné+ Live'),
        _ch('slc-vod', 'Ciné+ Le Film', isLive: false),
      ]);

      final List<Channel> r =
          await repo.searchLiveChannels('cine', limit: 20);
      expect(r.map((Channel c) => c.id), contains('slc-live'));
      expect(r.map((Channel c) => c.id), isNot(contains('slc-vod')));
    });

    test('requête vide → aucun résultat (pas de scan)', () async {
      repo.debugSeedChannels(<Channel>[_ch('slc-empty', 'TF1')]);
      expect(await repo.searchLiveChannels('   '), isEmpty);
      expect(await repo.searchLiveChannels(''), isEmpty);
    });

    test('boost historique : le favori remonte', () async {
      repo.debugSeedChannels(<Channel>[
        _ch('slc-dazn1', 'DAZN 1'),
        _ch('slc-dazn2', 'DAZN 2'),
      ]);

      final List<Channel> r = await repo.searchLiveChannels(
        'dazn',
        signals: const SearchSignals(favoriteIds: <String>{'slc-dazn2'}),
      );
      expect(r.first.id, 'slc-dazn2');
    });

    test('limit est respectée', () async {
      repo.debugSeedChannels(<Channel>[
        for (int i = 0; i < 30; i++) _ch('slc-lim$i', 'News Channel $i'),
      ]);
      final List<Channel> r =
          await repo.searchLiveChannels('news', limit: 8);
      expect(r.length, 8);
    });
  });
}
