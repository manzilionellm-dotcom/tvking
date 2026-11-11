import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/domain/live_open_selection.dart';

Channel _channel(String id, {int playlistId = 1}) => Channel(
  id: id,
  name: id,
  category: 'Info',
  streamUrl: 'https://fixture.invalid/$id.ts',
  isLive: true,
  playlistId: playlistId,
);

LiveOpenContext _context({
  int generation = 1,
  String profile = 'p1',
  int scope = 1,
  bool kids = false,
}) => (
  catalogGeneration: generation,
  profileId: profile,
  profileScope: scope,
  kidsMode: kids,
);

/// Compte les lectures du catalogue, sans transformer un temps x86 en mesure
/// de fluidité sur appareil. Les résultats attendus sont déterministes.
class _CountedList extends ListBase<Channel> {
  _CountedList(this._values);

  final List<Channel> _values;
  int reads = 0;

  @override
  int get length => _values.length;

  @override
  set length(int _) => throw UnsupportedError('fixture en lecture seule');

  @override
  Channel operator [](int index) {
    reads++;
    return _values[index];
  }

  @override
  void operator []=(int index, Channel value) =>
      throw UnsupportedError('fixture en lecture seule');
}

void main() {
  for (final legacy in [false, true]) {
    group('L1-05 ${legacy ? "repli" : "index"}', () {
      final one = _channel('one');
      final denied = _channel('denied', playlistId: 2);
      final two = _channel('two');
      final catalog = [one, denied, two];
      final byId = {for (final c in catalog) c.id: c};
      bool allows(Channel channel) => channel.playlistId == 1;

      LiveOpenSelection? select({List<Channel>? list, int index = 2}) =>
          LiveOpenSelection.capture(
            list: list ?? catalog,
            index: index,
            byId: byId,
            context: _context(),
            catalogSnapshot: catalog,
            allowsChannel: allows,
            legacy: legacy,
          );

      test('chaîne autorisée et ordre de zap conservés', () {
        final selection = select()!;
        expect(selection.selected, same(two));
        expect(selection.channels, [one, two]);
        expect(selection.startIndex, 1);
        expect(
          selection.isCurrent(
            context: _context(),
            catalogSnapshot: catalog,
            byId: byId,
            allowsChannel: allows,
          ),
          isTrue,
        );
        expect(() => selection.channels.clear(), throwsUnsupportedError);
      });

      test('chaîne absente et index hors bornes refusés', () {
        expect(select(list: [_channel('missing')], index: 0), isNull);
        expect(select(index: -1), isNull);
        expect(select(index: catalog.length), isNull);
      });

      test('présence dans byId ne vaut jamais autorisation', () {
        expect(byId[denied.id], same(denied));
        expect(select(index: 1), isNull);
      });

      test('objet remplacé sous le même identifiant refusé', () {
        expect(select(list: [_channel(one.id)], index: 0), isNull);
      });

      test('changement de profil entre sélection et ouverture refusé', () {
        final selection = select()!;
        for (final context in [
          _context(profile: 'p2'),
          _context(scope: 2),
          _context(kids: true),
          _context(generation: 2),
        ]) {
          expect(
            selection.isCurrent(
              context: context,
              catalogSnapshot: catalog,
              byId: byId,
              allowsChannel: allows,
            ),
            isFalse,
          );
        }
      });

      test('remplacement du snapshot avant livraison du stream refusé', () {
        final selection = select()!;
        expect(
          selection.isCurrent(
            context: _context(),
            catalogSnapshot: List<Channel>.of(catalog),
            byId: byId,
            allowsChannel: allows,
          ),
          isFalse,
        );
      });

      test('index remplacé même sans changement de génération refusé', () {
        final selection = select()!;
        expect(
          selection.isCurrent(
            context: _context(),
            catalogSnapshot: catalog,
            byId: Map<String, Channel>.of(byId),
            allowsChannel: allows,
          ),
          isFalse,
        );
      });

      test('permission relue après attente, même avec un index inchangé', () {
        final selection = select()!;
        expect(
          selection.isCurrent(
            context: _context(),
            catalogSnapshot: catalog,
            byId: byId,
            allowsChannel: (_) => false,
          ),
          isFalse,
        );
      });
    });
  }

  test('50 000 chaînes : aucun parcours du catalogue après sélection', () {
    final values = List<Channel>.generate(50000, (i) => _channel('count-$i'));
    final catalog = _CountedList(values);
    final byId = {for (final channel in catalog) channel.id: channel};
    final shown = [values[20], values[40], values[60]];

    // Témoin négatif : l'opération exacte du 116 (currentChannels.toSet())
    // visite tout le catalogue, y compris pour ces trois chaînes affichées.
    // Ce témoin ne prétend pas exécuter à lui seul l'ancien widget complet.
    catalog.reads = 0;
    final previousCurrent = catalog.toSet();
    expect(shown.every(previousCurrent.contains), isTrue);
    expect(catalog.reads, 50000);

    catalog.reads = 0;
    var permissionChecks = 0;
    final selection = LiveOpenSelection.capture(
      list: shown,
      index: 1,
      byId: byId,
      context: _context(),
      catalogSnapshot: catalog,
      allowsChannel: (_) {
        permissionChecks++;
        return true;
      },
    )!;
    expect(selection.selected, same(values[40]));
    for (var i = 0; i < 20; i++) {
      expect(
        selection.isCurrent(
          context: _context(),
          catalogSnapshot: catalog,
          byId: byId,
          allowsChannel: (_) {
            permissionChecks++;
            return true;
          },
        ),
        isTrue,
      );
    }
    expect(catalog.reads, 0);
    expect(permissionChecks, shown.length + 1 + 20);
  });
}
