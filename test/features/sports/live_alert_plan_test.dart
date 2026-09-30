import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/sports/domain/live_alert_plan.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

SportEvent ev(String id, String home, String away, {String status = '1H'}) =>
    SportEvent(
      id: id,
      home: 'A',
      away: 'B',
      homeScore: home,
      awayScore: away,
      status: status,
    );

void main() {
  test('la première photo, même pleine, ne crie pas', () {
    final LiveAlertPlan plan = LiveAlertPlan();
    expect(
      plan.consume(<SportEvent>[ev('a', '2', '1'), ev('b', '0', '3')]),
      isEmpty,
    );
  });

  test('une photo vide n\'arme pas la baseline', () {
    final LiveAlertPlan plan = LiveAlertPlan();
    expect(plan.consume(const <SportEvent>[]), isEmpty);
    expect(plan.consume(<SportEvent>[ev('a', '1', '0')]), isEmpty);
  });

  test('deux buts dans la même photo sont tous les deux annoncés', () {
    final LiveAlertPlan plan = LiveAlertPlan();
    plan.consume(<SportEvent>[ev('a', '0', '0'), ev('b', '0', '0')]);
    final List<LiveAlert> out = plan.consume(<SportEvent>[
      ev('a', '1', '0'),
      ev('b', '0', '1'),
    ]);
    expect(
      out.where((LiveAlert a) => a.kind == LiveAlertKind.goal).map((LiveAlert a) => a.event.id),
      <String>['a', 'b'],
    );
  });

  test('le coup d\'envoi n\'est pas répété, la fin attend deux absences', () {
    final LiveAlertPlan plan = LiveAlertPlan();
    plan.consume(<SportEvent>[ev('a', '0', '0', status: 'NS')]);
    final List<LiveAlert> start =
        plan.consume(<SportEvent>[ev('a', '0', '0', status: '1H')]);
    expect(start.map((LiveAlert a) => a.kind), <LiveAlertKind>[LiveAlertKind.started]);
    expect(
      plan.consume(<SportEvent>[ev('a', '0', '0', status: '1H')]),
      isEmpty,
    );
    expect(plan.consume(const <SportEvent>[]), isEmpty);
    final List<LiveAlert> end = plan.consume(const <SportEvent>[]);
    expect(end.single.kind, LiveAlertKind.ended);
    expect(end.single.event.id, 'a');
  });

  test('mille photos se décident en moins de 200 ms sur cette machine', () {
    final LiveAlertPlan plan = LiveAlertPlan();
    final List<SportEvent> photo = <SportEvent>[
      for (int i = 0; i < 40; i++) ev('m$i', '0', '0'),
    ];
    final Stopwatch sw = Stopwatch()..start();
    for (int n = 0; n < 1000; n++) {
      plan.consume(photo);
    }
    sw.stop();
    debugPrint('LiveAlertPlan 1000 photos / 40 matchs : ${sw.elapsedMicroseconds} µs');
    expect(sw.elapsedMilliseconds, lessThan(200));
  });
}
