// =========================================================
//  repair_flags_test.dart — Les interrupteurs de repli sont
//  coupés par défaut, et leur clé est celle qu'on pose en adb.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(RepairFlags.debugReset);

  test('ordre du panel : import immédiat par défaut, repli par la clé',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await RepairFlags.load();
    expect(RepairFlags.sourceOrderWaitsIdle, isFalse,
        reason: 'défaut = la liste du panel arrive même pendant la lecture');
    expect(RepairFlags.sourceOrderWaitsIdleKey, 'zuno.source.order_waits_idle');

    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.sourceOrderWaitsIdleKey: true,
    });
    await RepairFlags.load();
    expect(RepairFlags.sourceOrderWaitsIdle, isTrue,
        reason: 'le repli rétablit l\'attente du retour à l\'accueil');

    RepairFlags.debugReset();
    expect(RepairFlags.sourceOrderWaitsIdle, isFalse);
  });

  test('passe automatique 6 h et premier lot affiché : replis coupés par défaut',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await RepairFlags.load();
    expect(RepairFlags.autoRefreshFull, isFalse);
    expect(RepairFlags.importFirstBatchOff, isFalse);
    expect(RepairFlags.autoRefreshFullKey, 'zuno.refresh.auto_full');
    expect(RepairFlags.importFirstBatchOffKey, 'zuno.import.first_batch_off');
    expect(RepairFlags.heartbeatAfterImportOff, isFalse);
    expect(RepairFlags.heartbeatAfterImportOffKey, 'zuno.heartbeat.after_import_off');
    // Pastille cachée et installation automatique : défauts du 05/10/2026.
    expect(RepairFlags.updatingPillShown, isFalse);
    expect(RepairFlags.updatingPillShownKey, 'zuno.sync.pill_show');
    expect(RepairFlags.autoInstallOff, isFalse);
    expect(RepairFlags.autoInstallOffKey, 'zuno.update.auto_install_off');
    expect(RepairFlags.m3uTimeoutLegacy, isFalse);
    expect(RepairFlags.m3uTimeoutLegacyKey, 'zuno.m3u.timeout_legacy');
    expect(RepairFlags.m3uLinkAsM3u, isFalse);
    expect(RepairFlags.m3uLinkAsM3uKey, 'zuno.source.m3u_link_as_m3u');
    expect(RepairFlags.sourceRetryAlways, isFalse);
    expect(RepairFlags.sourceRetryAlwaysKey, 'zuno.source.retry_always');
    // Ligne de liste disparue pendant l'import, passe de 2 min : défauts du 06/10/2026.
    expect(RepairFlags.importReinsertOff, isFalse);
    expect(RepairFlags.importReinsertOffKey, 'zuno.import.reinsert_off');
    expect(RepairFlags.refreshPendingLegacy, isFalse);
    expect(RepairFlags.refreshPendingLegacyKey, 'zuno.refresh.pending_legacy');
    // Remise à neuf depuis le panel et vérification de mise à jour de la box de test.
    expect(RepairFlags.remoteResetOff, isFalse);
    expect(RepairFlags.remoteResetOffKey, 'zuno.reset.off');
    expect(RepairFlags.testUpdatePollLegacy, isFalse);
    expect(RepairFlags.testUpdatePollLegacyKey, 'zuno.update.test_poll_legacy');
    expect(RepairFlags.sourceDropFirstLegacy, isFalse);
    expect(RepairFlags.sourceDropFirstLegacyKey, 'zuno.source.drop_first_legacy');
    expect(RepairFlags.orderAckOff, isFalse);
    expect(RepairFlags.orderAckOffKey, 'zuno.ack.off');
    expect(RepairFlags.tvDeleteLegacy, isFalse);
    expect(RepairFlags.tvDeleteLegacyKey, 'zuno.source.tv_delete_legacy');
    expect(RepairFlags.liveShelvesLegacy, isFalse);
    expect(RepairFlags.liveShelvesLegacyKey, 'zuno.direct.shelves_legacy');
    expect(RepairFlags.wsReplayLegacy, isFalse);
    expect(RepairFlags.wsReplayLegacyKey, 'zuno.realtime.ws_replay_legacy');

    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.autoRefreshFullKey: true,
      RepairFlags.importFirstBatchOffKey: true,
    });
    await RepairFlags.load();
    expect(RepairFlags.autoRefreshFull, isTrue);
    expect(RepairFlags.importFirstBatchOff, isTrue);
    RepairFlags.debugReset();
    expect(RepairFlags.autoRefreshFull, isFalse);
    expect(RepairFlags.importFirstBatchOff, isFalse);
  });
}
