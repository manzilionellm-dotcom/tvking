import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';
import 'package:tv_king/features/tv/data/home_source_label.dart';
import 'package:tv_king/features/tv/data/home_work_queue.dart';

// Compter les visites est reproductible ; chronométrer un runner partagé ne
// permettrait pas d'affirmer combien d'images/s une box physique produira.
class _CountedChannels extends ListBase<Channel> {
  _CountedChannels(this.items);
  final List<Channel> items;
  int reads = 0;
  @override
  int get length => items.length;
  @override
  set length(int value) => throw UnsupportedError('snapshot');
  @override
  Channel operator [](int index) { reads++; return items[index]; }
  @override
  void operator []=(int index, Channel value) => throw UnsupportedError('snapshot');
}

void main() {
  test('50 000 chaînes : 100 usages du même index, une seule traversée', () {
    final channels = _CountedChannels(List<Channel>.generate(50000, (i) => Channel(
      id: '$i', name: 'Chaîne $i', category: 'Test',
      streamUrl: 'https://example.invalid/$i', isLive: true,
    )));
    final snapshot = HomeChannelSnapshot(channels);
    expect(channels.reads, 0, reason: 'construction différée');
    for (int i = 0; i < 100; i++) {
      expect(snapshot.byId['49999']?.name, 'Chaîne 49999');
    }
    expect(channels.reads, 50000, reason: 'pas 5 millions de visites');
  });

  test('nouvelle source, mêmes IDs : aucune ancienne URL dans le nouvel index', () {
    Channel channel(String url) => Channel(id: '1', name: 'Test',
        category: 'Test', streamUrl: url, isLive: true);
    final old = HomeChannelSnapshot(<Channel>[channel('https://example.invalid/old')]);
    expect(old.byId['1']?.streamUrl, endsWith('/old'));
    final updated = HomeChannelSnapshot(<Channel>[channel('https://example.invalid/new')]);
    expect(updated.byId['1']?.streamUrl, endsWith('/new'));
    expect(HomeChannelSnapshot(const <Channel>[]).byId, isEmpty);
  });

  testWidgets('100 notifications coalescées ; pause vidéo et reprise unique', (tester) async {
    final queue = HomeWorkQueue();
    addTearDown(queue.dispose);
    final applied = <int>[];
    for (int i = 0; i < 100; i++) {
      queue.schedule('shelves', () { applied.add(i); }, delay: const Duration(milliseconds: 150));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(applied, isEmpty);
    queue.paused = true;
    await tester.pump(const Duration(minutes: 1));
    expect(applied, isEmpty);
    queue.schedule('shelves', () { applied.add(100); }, delay: const Duration(milliseconds: 150));
    queue.paused = false;
    await tester.pump(const Duration(milliseconds: 151));
    expect(applied, <int>[100]);
  });

  testWidgets('lecture lente du guide : jamais deux lectures en vol, dernier événement conservé', (tester) async {
    final queue = HomeWorkQueue();
    addTearDown(queue.dispose);
    final pending = Completer<void>();
    final steps = <String>[];
    queue.schedule('guide', () async {
      steps.add('start');
      await pending.future;
      steps.add('end');
    });
    await tester.pump(const Duration(milliseconds: 1));
    queue.schedule('guide', () { steps.add('obsolete'); });
    queue.schedule('guide', () { steps.add('latest'); });
    await tester.pump(const Duration(seconds: 60));
    expect(steps, <String>['start']);
    pending.complete();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(steps, <String>['start', 'end', 'latest']);
  });

  testWidgets('quitter pendant une lecture ne relance aucun travail différé', (tester) async {
    final queue = HomeWorkQueue();
    final pending = Completer<void>();
    int repeats = 0;
    queue.schedule('guide', () => pending.future);
    await tester.pump(const Duration(milliseconds: 1));
    queue.schedule('guide', () { repeats++; });
    queue.dispose();
    pending.complete();
    await tester.pump(const Duration(seconds: 60));
    queue.schedule('guide', () { repeats++; });
    expect(repeats, 0);
  });

  testWidgets('une erreur de guide ne bloque pas la prochaine lecture', (tester) async {
    final errors = <Object>[];
    final queue = HomeWorkQueue(onError: (error, _) => errors.add(error));
    addTearDown(queue.dispose);
    queue.schedule('guide', () => throw StateError('base momentanément indisponible'));
    await tester.pump(const Duration(milliseconds: 1));
    int completed = 0;
    queue.schedule('guide', () { completed++; });
    await tester.pump(const Duration(milliseconds: 1));
    expect(errors, hasLength(1));
    expect(completed, 1);
  });

  test('accueil : aucun identifiant fournisseur pour les essais des deux marques', () {
    for (final name in <String>['7 MOTION Essai', 'Zuno TV Essai']) {
      final source = Playlist(id: 1, name: name, type: PlaylistType.xtream,
          createdAt: 1, isActive: true, xtreamUsername: 'private-test-user',
          xtreamPassword: 'private-test-password', xtreamServer: 'https://provider.example.invalid');
      expect(homeSourceLabel(<Playlist>[source]), name);
    }
    const personal = Playlist(id: 2, name: 'Ma liste', type: PlaylistType.xtream,
        createdAt: 1, xtreamUsername: 'mon-compte');
    expect(homeSourceLabel(<Playlist>[personal]), 'mon-compte · Ma liste');
    expect(homeSourceLabel(const <Playlist>[]), isEmpty);
  });
}
