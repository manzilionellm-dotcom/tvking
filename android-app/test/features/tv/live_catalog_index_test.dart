import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/domain/live_catalog_index.dart';
import 'package:tv_king/features/tv/domain/live_shelves.dart';
import 'package:tv_king/features/tv/domain/vip_channel_groups.dart';

Channel _channel(String id, String name, String category, {bool live = true}) =>
    Channel(
      id: id,
      name: name,
      category: category,
      streamUrl: 'https://example.invalid/$id.ts',
      isLive: live,
    );

/// Compter les visites prouve l'absence de scans répétés sans dépendre de la
/// vitesse du runner CI. Le chronomètre fournit seulement une mesure indicative.
class _CountedChannels extends Iterable<Channel> {
  _CountedChannels(this.channels);

  final List<Channel> channels;
  int visits = 0;

  Iterable<Channel> _read() sync* {
    for (final channel in channels) {
      visits++;
      yield channel;
    }
  }

  @override
  Iterator<Channel> get iterator => _read().iterator;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cache froid : aucun calcul, puis index complété après le pré-calcul',
      () async {
    final channel = _channel('index-cold', 'FR | France 24 HD', 'FR');
    final index = LiveCatalogIndex([channel]);
    expect(index.byId[channel.id], same(channel));
    expect(index.byCountry, isEmpty);
    expect(index.trending(['France 24']), isEmpty);

    // Une fin best-effort du pré-calcul peut laisser des valeurs absentes.
    // La lecture de l'index ne doit ni calculer, ni figer ce cache incomplet.
    index.completeCuration();
    expect(ChannelPrecompute.cachedCleanName(channel), isNull);
    expect(ChannelPrecompute.cachedCountry(channel).known, isFalse);
    expect(index.byCountry, isEmpty);

    await ChannelPrecompute.run([channel]);
    index.completeCuration();
    final name = ChannelPrecompute.cachedCleanName(channel)!;
    expect(index.trending([name]), [channel]);
    expect(index.byCountry['fr'], [channel]);
  });

  test('tendances et pays gardent ordre, déduplication et règles existantes',
      () async {
    final all = [
      _channel('index-first', 'TV Shared', 'FR'),
      _channel('index-second', 'TV Shared', 'FR'),
      _channel('index-serbia', 'TV Serbia', 'SRB'),
      _channel('index-unknown', 'TV Unknown', 'Divers'),
      _channel('index-film', 'Film', 'FR', live: false),
    ];
    await ChannelPrecompute.run(all);
    final names = [
      '  ${ChannelPrecompute.cachedCleanName(all[2])!.toUpperCase()} ',
      ChannelPrecompute.cachedCleanName(all[0])!,
      ChannelPrecompute.cachedCleanName(all[0])!,
      'introuvable',
    ];
    final index = LiveCatalogIndex(all)..completeCuration();
    expect(index.trending(names), trendingFromCache(all, names));
    expect(index.trending(names), [all[2], all[0]]);
    expect(index.byCountry, vipChannelGroups(all));
    expect(index.byCountry['fr'], [all[0], all[1]]);
    expect(index.byCountry['rs'], [all[2]]);

    final duplicateId = _channel(all[0].id, 'Replacement', 'FR');
    final duplicateIndex = LiveCatalogIndex([all[0], duplicateId]);
    expect(duplicateIndex.byId[all[0].id], same(duplicateId),
        reason: 'la résolution des identifiants garde le dernier reçu');
  });

  test('nouveau lot filtré : aucun ancien favori, pays ou nom ne reste indexé',
      () async {
    final removed = _channel('index-removed', 'Removed channel', 'FR');
    final retained = _channel('index-retained', 'Retained channel', 'SE');
    await ChannelPrecompute.run([removed, retained]);
    final previous = LiveCatalogIndex([removed, retained])..completeCuration();
    expect(previous.byId, hasLength(2));

    // Un import ou le filtre Mode Enfants produit un nouvel index, comme
    // _ingest. Il ne partage aucune table mutable avec le lot précédent.
    final current = LiveCatalogIndex([retained])..completeCuration();
    expect(current.byId.keys, [retained.id]);
    expect(current.byCountry.keys, ['se']);
    expect(current.trending([ChannelPrecompute.cachedCleanName(removed)!]),
        isEmpty);
    expect(previous.byId, hasLength(2));
  });

  test('50 000 chaînes : actualiser les rayons ne rescane plus les index',
      () async {
    final all = List<Channel>.generate(
      50000,
      (i) => _channel('index-large-$i', 'Channel $i', i.isEven ? 'FR' : 'SE'),
      growable: false,
    );
    await ChannelPrecompute.run(all);
    final names = [ChannelPrecompute.cachedCleanName(all[15])!];
    final counted = _CountedChannels(all);
    final index = LiveCatalogIndex(counted);
    final originalIds = index.byId;
    index.completeCuration();
    expect(counted.visits, all.length * 2,
        reason: 'une passe identifiants, une passe noms et pays pour le lot');

    const refreshes = 20;
    final cachedTime = Stopwatch()..start();
    for (var i = 0; i < refreshes; i++) {
      expect(index.byId, same(originalIds));
      index.completeCuration();
      expect(index.trending(names), [all[15]]);
      expect(index.byCountry['fr'], hasLength(25000));
    }
    cachedTime.stop();
    expect(counted.visits, all.length * 2,
        reason: 'les favoris/récents/tendances réutilisent les tables du lot');

    // Même travail de résultat qu'avant, mesuré sans imposer un seuil fragile.
    final previousTime = Stopwatch()..start();
    for (var i = 0; i < refreshes; i++) {
      final byId = {for (final channel in all) channel.id: channel};
      expect(byId[all[15].id], all[15]);
      expect(trendingFromCache(all, names), [all[15]]);
      expect(vipChannelGroups(all)['fr'], hasLength(25000));
    }
    previousTime.stop();
    debugPrint('[mesure] index Direct, $refreshes actualisations × 50 000 : '
        'avant ${previousTime.elapsedMilliseconds} ms, '
        'réutilisés ${cachedTime.elapsedMilliseconds} ms ; '
        'aucune visite supplémentaire du catalogue après initialisation');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
