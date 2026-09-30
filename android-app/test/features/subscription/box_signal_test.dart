import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/domain/activation_pace.dart';
import 'package:tv_king/features/subscription/domain/box_signal.dart';

void main() {
  test('canal ouvert : filet 25 s ; coupé : rythme 103', () {
    expect(
      signalPace(channelUp: true, waiting: false, failures: 0),
      ActivationPace.parked,
    );
    expect(
      signalPace(channelUp: false, waiting: true, failures: 0),
      const Duration(seconds: 3),
    );
    expect(
      signalPace(channelUp: false, waiting: false, failures: 0),
      const Duration(seconds: 4),
    );
    expect(
      signalPace(channelUp: true, waiting: false, failures: 2),
      const Duration(seconds: 16),
    );
  });

  test('le même numéro ne s\'applique qu\'une fois', () {
    final Set<int> seen = <int>{2};
    final List<Map<String, Object?>> fresh = freshCommands(
      <Map<String, Object?>>[
        <String, Object?>{'id': 2, 'kind': 'activate'},
        <String, Object?>{'id': 4, 'kind': 'suspend'},
        <String, Object?>{'id': 4, 'kind': 'suspend'},
      ],
      seen,
    );
    expect(fresh, hasLength(1));
    expect(fresh.single['kind'], 'suspend');
  });

  test('chaque action du panel a une relecture, sans secret', () {
    expect(refreshesFor('activate'), {SignalRefresh.status});
    expect(refreshesFor('suspend'), {SignalRefresh.status});
    expect(refreshesFor('expire'), {SignalRefresh.status});
    expect(refreshesFor('renew'), {SignalRefresh.status});
    expect(refreshesFor('block'), {SignalRefresh.status});
    expect(
      refreshesFor('source_clear'),
      {SignalRefresh.status, SignalRefresh.source},
    );
    expect(refreshesFor('message'), {SignalRefresh.announcement});
    expect(refreshesFor('force_update'), {SignalRefresh.forceUpdate});
    expect(refreshesFor('theme'), {SignalRefresh.theme});
    expect(kindNeedsStatus('message'), isFalse);
    expect(kindNeedsStatus('activate'), isTrue);
  });
}
