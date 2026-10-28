import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';

Channel channel(String name, String category, {int playlist = 1}) => Channel(
  id: 'cache-review-id', playlistId: playlist, name: name, category: category,
  streamUrl: 'https://example.invalid/review', isLive: true,
);

void main() {
  setUp(() => ChannelPrecompute.retainSnapshot(const <Channel>[]));
  tearDown(() => ChannelPrecompute.retainSnapshot(const <Channel>[]));

  test('même identifiant renommé : nom, genre adulte et qualité actualisés', () {
    final old = channel('FR | TF1 HD', 'FRANCE');
    final oldName = old.cleanName;
    expect(old.genre, isNot(ChannelGenre.adult));
    final updated = channel('XXX Night 4K', 'ADULT');
    expect(ChannelPrecompute.cachedGenre(updated), isNull);
    expect(updated.genre, ChannelGenre.adult);
    expect(updated.cleanName, isNot(oldName));
    expect(updated.quality, ChannelClassifier.detectQuality(updated.name));
    // Un ancien lecteur qui termine sa fermeture garde ses propres valeurs.
    expect(old.cleanName, oldName);
    expect(old.genre, isNot(ChannelGenre.adult));
  });

  test('catégorie changée à nom constant et listes distinctes ne partagent pas le genre', () {
    final normal = channel('Channel 1', 'GENERAL');
    expect(normal.genre, isNot(ChannelGenre.adult));
    final adult = channel('Channel 1', 'ADULT');
    expect(adult.genre, ChannelGenre.adult);
    final other = channel('Channel 1', 'GENERAL', playlist: 2);
    expect(ChannelPrecompute.cachedGenre(other), isNull);
    expect(other.genre, isNot(ChannelGenre.adult));
  });

  test('snapshot inchangé réutilisé ; anciens résultats libérés après suppression', () {
    final first = channel('Test Sport', 'SPORT');
    first.cleanName;
    first.genre;
    final same = channel('Test Sport', 'SPORT');
    expect(ChannelPrecompute.isDone(same), isTrue);
    final added = channel('Test Film', 'CINEMA', playlist: 2);
    added.cleanName;
    expect(ChannelPrecompute.retainedEntryCount, 2);
    ChannelPrecompute.retainSnapshot(<Channel>[same]);
    expect(ChannelPrecompute.retainedEntryCount, 1);
    expect(ChannelPrecompute.isDone(same), isTrue);
    ChannelPrecompute.retainSnapshot(const <Channel>[]);
    expect(ChannelPrecompute.retainedEntryCount, 0);
  });

  test('annulation pendant le dernier lot : résultat tardif non publié', () async {
    final item = channel('Test Cache Cancelled', 'GENERAL');
    int checks = 0;
    await ChannelPrecompute.run(<Channel>[item], cancelled: () => ++checks > 1);
    expect(checks, greaterThanOrEqualTo(2));
    expect(ChannelPrecompute.cachedCleanName(item), isNull);
    expect(ChannelPrecompute.cachedGenre(item), isNull);
  });
}
