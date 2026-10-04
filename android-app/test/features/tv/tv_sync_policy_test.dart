// =========================================================
//  tv_sync_policy_test.dart — pas de ré-import de source sous le lecteur
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_sync_policy.dart';

void main() {
  test('lecteur ouvert : la re-vérification lente attend', () {
    expect(
      TvSyncPolicy.allowSlowSync(playerOpen: true, allowDuringPlayback: false),
      isFalse,
    );
    expect(
      TvSyncPolicy.allowSlowSync(playerOpen: false, allowDuringPlayback: false),
      isTrue,
    );
  });

  test('repli : l\'ancien comportement laisse partir le ré-import', () {
    expect(
      TvSyncPolicy.allowSlowSync(playerOpen: true, allowDuringPlayback: true),
      isTrue,
    );
  });
}
