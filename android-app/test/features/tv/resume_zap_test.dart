// =========================================================
//  resume_zap_test.dart — reprise au démarrage dans toute la liste
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/core/resume_zap.dart';

Channel _ch(String id, {bool live = true, int? playlist}) => Channel(
      id: id,
      name: id,
      category: 'Test',
      streamUrl: 'http://flux.example.invalid/$id',
      isLive: live,
      playlistId: playlist,
    );

void main() {
  test('la dernière chaîne est ouverte à sa place dans la liste complète', () {
    final List<Channel> all = <Channel>[
      _ch('a'),
      _ch('b'),
      _ch('film', live: false),
      _ch('c'),
      _ch('d'),
    ];
    final ResumeZap? plan = resumeZapList(all, <Channel>[_ch('c'), _ch('a')]);
    expect(plan, isNotNull);
    expect(
        plan!.channels.map((Channel c) => c.id), <String>['a', 'b', 'c', 'd']);
    expect(plan.startIndex, 2);
  });

  test('chaîne retirée : historique périmé ne permet aucune reprise', () {
    final ResumeZap? plan =
        resumeZapList(<Channel>[_ch('a')], <Channel>[_ch('zz'), _ch('a')]);
    expect(plan, isNull);
  });

  test('reprise manuelle conserve la carte choisie dans le catalogue complet',
      () {
    final all = [_ch('a'), _ch('b'), _ch('film', live: false), _ch('c')];
    final plan = resumeZapList(all, [_ch('c'), _ch('b')], selectedIndex: 1)!;
    expect(plan.channels.map((c) => c.id), ['a', 'b', 'c']);
    expect(plan.startIndex, 1);
  });

  test('filtre parental appliqué au pool et à la cible', () {
    final all = [_ch('a'), _ch('adult'), _ch('c')];
    bool hide(Channel c) => c.id == 'adult';
    final plan = resumeZapList(all, [_ch('c')], hide: hide)!;
    expect(plan.channels.map((c) => c.id), ['a', 'c']);
    expect(plan.startIndex, 1);
    expect(resumeZapList(all, [_ch('adult')], hide: hide), isNull);
  });

  test('identifiant partagé entre listes : aucune substitution de source', () {
    final all = [_ch('same', playlist: 1), _ch('same', playlist: 2)];
    final plan = resumeZapList(all, [_ch('same', playlist: 2)])!;
    expect(plan.startIndex, 1);
    expect(resumeZapList(all, [_ch('same', playlist: 3)]), isNull);
  });

  test('rien à reprendre', () {
    expect(resumeZapList(<Channel>[_ch('a')], <Channel>[]), isNull);
  });
}
