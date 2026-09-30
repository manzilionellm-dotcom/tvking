import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/domain/panel_source_decision.dart';

void main() {
  const ProvisionKey panel = ProvisionKey.xtream('https://s', 'alice');
  const ProvisionKey hand = ProvisionKey.xtream('https://s', 'bob');

  test('un tableau sources vide, sans objet source, est un effacement', () {
    expect(panelClearedSources(<String, dynamic>{'sources': <Object>[]}), isTrue);
    expect(panelClearedSources(<String, dynamic>{}), isFalse);
    expect(
      panelClearedSources(<String, dynamic>{
        'sources': <Object>[<String, dynamic>{'type': 'xtream'}],
      }),
      isFalse,
    );
    expect(
      panelClearedSources(<String, dynamic>{
        'sources': <Object>[],
        'source': <String, dynamic>{'type': 'm3u'},
      }),
      isFalse,
    );
  });

  test('l\'effacement retire le panel, pas la liste ajoutée à la main', () {
    final Set<ProvisionKey> drop = keysToRemove(
      explicitClear: true,
      provisioned: <ProvisionKey>{panel},
      orders: const <Map<String, dynamic>>[],
    );
    expect(drop, contains(panel));
    expect(drop, isNot(contains(hand)));
  });

  test('un ordre source_remove retire sa cible, rien d\'autre', () {
    final Set<ProvisionKey> drop = keysToRemove(
      explicitClear: false,
      provisioned: <ProvisionKey>{panel},
      orders: <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'source_remove',
          'target': <String, dynamic>{
            'server': 'https://s',
            'username': 'bob',
          },
        },
      ],
    );
    expect(drop, <ProvisionKey>{hand});
  });

  test('un ordre sans identifiant ou d\'un type inconnu est refusé', () {
    expect(
      orderLooksValid(<String, dynamic>{'id': 4, 'kind': 'source_remove'}),
      isTrue,
    );
    expect(
      orderLooksValid(<String, dynamic>{'id': 0, 'kind': 'source_remove'}),
      isFalse,
    );
    expect(
      orderLooksValid(<String, dynamic>{'id': 4, 'kind': 'wipe_phone'}),
      isFalse,
    );
  });
}
