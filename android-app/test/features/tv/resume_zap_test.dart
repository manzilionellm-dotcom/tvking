// =========================================================
//  resume_zap_test.dart — reprise au démarrage dans toute la liste
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/core/resume_zap.dart';

Channel _ch(String id, {bool live = true}) => Channel(
      id: id,
      name: id,
      category: 'Test',
      streamUrl: 'http://flux.example.invalid/$id',
      isLive: live,
    );

void main() {
  test('la dernière chaîne est ouverte à sa place dans la liste complète', () {
    final List<Channel> all = <Channel>[
      _ch('a'), _ch('b'), _ch('film', live: false), _ch('c'), _ch('d'),
    ];
    final ResumeZap? plan = resumeZapList(all, <Channel>[_ch('c'), _ch('a')]);
    expect(plan, isNotNull);
    expect(plan!.channels.map((Channel c) => c.id), <String>['a', 'b', 'c', 'd']);
    expect(plan.startIndex, 2);
  });

  test('chaîne disparue de la liste : on garde la rangée Reprendre', () {
    final ResumeZap? plan = resumeZapList(<Channel>[_ch('a')], <Channel>[_ch('zz'), _ch('a')]);
    expect(plan!.channels.first.id, 'zz');
    expect(plan.startIndex, 0);
  });

  test('rien à reprendre', () {
    expect(resumeZapList(<Channel>[_ch('a')], <Channel>[]), isNull);
  });

  test('chaîne choisie hors de Direct : toute la liste, placée sur elle', () {
    // Avant : le lecteur recevait la seule chaîne choisie, Haut/Bas bloqués.
    final List<Channel> all = <Channel>[
      _ch('a'), _ch('film', live: false), _ch('b'), _ch('c'),
    ];
    final ResumeZap plan = zapListAround(all, _ch('b'));
    expect(plan.channels.map((Channel c) => c.id), <String>['a', 'b', 'c']);
    expect(plan.startIndex, 1);
  });

  test('mode enfants : les chaînes masquées ne sont pas atteignables au zap', () {
    final List<Channel> all = <Channel>[_ch('a'), _ch('adulte'), _ch('b')];
    final ResumeZap plan =
        zapListAround(all, _ch('b'), hide: (Channel c) => c.id == 'adulte');
    expect(plan.channels.map((Channel c) => c.id), <String>['a', 'b']);
    expect(plan.startIndex, 1);
  });

  test('chaîne absente de la liste : elle seule, comme avant', () {
    final ResumeZap plan = zapListAround(<Channel>[_ch('a')], _ch('zz'));
    expect(plan.channels.single.id, 'zz');
    expect(plan.startIndex, 0);
  });
}
