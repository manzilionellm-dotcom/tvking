// =========================================================
//  history_policy_test.dart — une chaîne survolée ne compte pas
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/history_policy.dart';

void main() {
  test('après 20 s : seulement si une image a été vue et qu\'on y est encore', () {
    expect(HistoryPolicy.dwell, const Duration(seconds: 20));
    expect(
      HistoryPolicy.recordAfterDwell(frameShown: true, sameChannel: true, immediate: false),
      isTrue,
    );
    expect(
      HistoryPolicy.recordAfterDwell(frameShown: false, sameChannel: true, immediate: false),
      isFalse,
      reason: 'chaîne qui n\'a jamais donné d\'image : pas une chaîne regardée',
    );
    expect(
      HistoryPolicy.recordAfterDwell(frameShown: true, sameChannel: false, immediate: false),
      isFalse,
      reason: 'on a zappé entre-temps',
    );
  });

  test('en quittant le lecteur : la chaîne laissée à l\'écran compte, une fois', () {
    expect(
      HistoryPolicy.recordOnExit(frameShown: true, alreadyRecorded: false, immediate: false),
      isTrue,
    );
    expect(
      HistoryPolicy.recordOnExit(frameShown: true, alreadyRecorded: true, immediate: false),
      isFalse,
    );
    expect(
      HistoryPolicy.recordOnExit(frameShown: false, alreadyRecorded: false, immediate: false),
      isFalse,
    );
  });

  test('repli « à l\'ouverture » : l\'écriture immédiate reste seule', () {
    expect(
      HistoryPolicy.recordAfterDwell(frameShown: true, sameChannel: true, immediate: true),
      isFalse,
    );
    expect(
      HistoryPolicy.recordOnExit(frameShown: true, alreadyRecorded: false, immediate: true),
      isFalse,
    );
  });
}
