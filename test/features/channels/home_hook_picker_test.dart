// =========================================================
//  home_hook_picker_test.dart — Rail « Derniers vus » (Vague 3)
// =========================================================
//  Ce que ces tests protègent, et POURQUOI :
//
//    1. La chaîne d'habitude (slot) passe DEVANT les récents —
//       c'est tout l'accroche qu'on s'autorise : réordonner 8
//       logos DÉJÀ affichés, pas en ajouter.
//    2. On ne dépasse JAMAIS 8. Un 9e logo = pic mémoire en
//       hausse sur Firestick 1 Go — interdit (stabilité > Netflix).
//    3. Une id inconnue est sautée, pas une exception. Playlist
//       changée : l'accueil reste utilisable.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/data/home_hook_picker.dart';
import 'package:tv_king/features/channels/domain/channel.dart';

Channel _ch(String id, String name) => Channel(
      id: id,
      name: name,
      category: 'GENERAL',
      streamUrl: 'http://x/$id',
      isLive: true,
    );

void main() {
  final Channel slot = _ch('slot', 'TF1');
  final Channel recentA = _ch('rec-a', 'France 2');
  final Channel recentB = _ch('rec-b', 'M6');
  final List<Channel> bouquet = <Channel>[recentB, recentA, slot];

  group('continueWatching', () {
    test('la chaîne d\'habitude passe devant les récents', () {
      final List<Channel> out = HomeHookPicker.continueWatching(
        all: bouquet,
        recentIds: <String>['rec-a', 'rec-b'],
        slotChannelId: 'slot',
        limit: 8,
      );
      expect(out.map((Channel c) => c.id).toList(),
          <String>['slot', 'rec-a', 'rec-b']);
    });

    test('plafond 8 : pas un logo de plus que l\'aperçu D d\'avant', () {
      final List<String> ids = <String>[
        for (int i = 0; i < 12; i++) 'id-$i',
      ];
      final List<Channel> many = <Channel>[
        for (int i = 0; i < 12; i++) _ch('id-$i', 'Ch $i'),
      ];
      final List<Channel> out = HomeHookPicker.continueWatching(
        all: many,
        recentIds: ids,
        limit: HomeHookPicker.kMaxRail,
      );
      expect(out, hasLength(HomeHookPicker.kMaxRail));
      expect(HomeHookPicker.kMaxRail, 8);
    });

    test('id inconnue sautée — pas d\'exception, pas de trou', () {
      final List<Channel> out = HomeHookPicker.continueWatching(
        all: bouquet,
        recentIds: <String>['disparue', 'rec-b'],
        slotChannelId: 'plus-la',
      );
      expect(out.map((Channel c) => c.id).toList(), <String>['rec-b']);
    });

    test('slot déjà dans les récents : pas de doublon', () {
      final List<Channel> out = HomeHookPicker.continueWatching(
        all: bouquet,
        recentIds: <String>['slot', 'rec-a'],
        slotChannelId: 'slot',
      );
      expect(out.map((Channel c) => c.id).toList(), <String>['slot', 'rec-a']);
    });

    test('bouquet vide → liste vide', () {
      expect(
        HomeHookPicker.continueWatching(
          all: const <Channel>[],
          recentIds: <String>['slot'],
          slotChannelId: 'slot',
        ),
        isEmpty,
      );
    });
  });
}
