// =========================================================
//  order_ack.dart — Accusés réels des ordres du panel (pur, testé)
// =========================================================
//  Avant le 06/10/2026, la box « accusait » un curseur et le serveur
//  répondait `ok` sans rien écrire : personne ne savait si un ordre avait
//  été reçu, ni appliqué. Ici on décide, sans réseau :
//    • ce que la box répond pour un ordre (APPLIED ou FAILED + résultat) ;
//    • le corps exact envoyé à POST /api/box/ack/:mac.
//  La box accuse RECEIVED dès la réception, puis l'issue réelle.
// =========================================================

/// Issue d'une lecture des listes (RemoteSourceRepository.lastReport).
class SourceSyncReport {
  const SourceSyncReport({
    required this.result,
    required this.atMs,
    this.configRev,
    this.error,
    this.keptPrevious = false,
  });

  /// Nom de RemoteSyncResult : loaded, sourceFailed, networkError, noSource.
  final String result;
  final int atMs;

  /// Révision servie par le Worker (`rev`, sinon `updated_at`).
  final int? configRev;

  /// Raison courte (déjà expurgée) du dernier refus.
  final String? error;

  /// Vrai si la nouvelle liste a été refusée et l'ancienne GARDÉE.
  final bool keptPrevious;
}

class OrderOutcome {
  const OrderOutcome({
    required this.applied,
    required this.result,
    this.errorCode,
    this.errorMessage,
    this.configRev,
  });

  final bool applied;
  final String result;
  final String? errorCode;
  final String? errorMessage;
  final int? configRev;

  String get state => applied ? 'applied' : 'failed';
}

const Set<String> _listKinds = <String>{'source', 'source_clear', 'reset'};
const Set<String> _statusKinds = <String>{
  'activate', 'renew', 'expire', 'suspend', 'resume', 'block', 'license', 'transfer', 'device_delete',
};

/// Issue d'un ordre. [receivedAtMs] : quand la box a reçu l'ordre ; un
/// rapport de listes plus ancien ne compte pas (la lecture n'a pas eu lieu
/// pour CET ordre).
OrderOutcome orderOutcome({
  required String kind,
  required int receivedAtMs,
  required bool statusRead,
  required bool sideEffectOk,
  SourceSyncReport? report,
}) {
  if (_listKinds.contains(kind)) {
    if (report == null || report.atMs < receivedAtMs) {
      return const OrderOutcome(
        applied: false,
        result: 'not_run',
        errorCode: 'not_run',
        errorMessage: 'lecture des listes non lancée pour cet ordre',
      );
    }
    switch (report.result) {
      case 'loaded':
        return OrderOutcome(applied: true, result: 'loaded', configRev: report.configRev);
      case 'noSource':
        return OrderOutcome(applied: true, result: 'no_source', configRev: report.configRev);
      case 'sourceFailed':
        return OrderOutcome(
          applied: false,
          result: 'refused',
          errorCode: report.keptPrevious ? 'refused_kept_previous' : 'refused',
          errorMessage: report.error,
          configRev: report.configRev,
        );
      default:
        return OrderOutcome(
          applied: false,
          result: 'network',
          errorCode: 'network',
          errorMessage: report.error,
          configRev: report.configRev,
        );
    }
  }
  if (_statusKinds.contains(kind)) {
    return statusRead
        ? const OrderOutcome(applied: true, result: 'status_ok')
        : const OrderOutcome(
            applied: false,
            result: 'status_unreachable',
            errorCode: 'status_unreachable',
            errorMessage: 'statut illisible après l’ordre',
          );
  }
  return sideEffectOk
      ? const OrderOutcome(applied: true, result: 'refreshed')
      : const OrderOutcome(
          applied: false,
          result: 'side_effect_failed',
          errorCode: 'side_effect_failed',
          errorMessage: 'relecture du réglage impossible',
        );
}

/// Corps d'un accusé, exactement ce que le Worker valide (box_orders.js).
Map<String, Object?> ackPayload({
  required String orderId,
  required String state,
  required String traceId,
  required String appVersion,
  int? receivedAtMs,
  int? appliedAtMs,
  OrderOutcome? outcome,
}) {
  return <String, Object?>{
    'order_id': orderId,
    'state': state,
    if (receivedAtMs != null) 'received_at': receivedAtMs,
    if (appliedAtMs != null) 'applied_at': appliedAtMs,
    if (outcome != null) 'result': outcome.result,
    if (outcome?.errorCode != null) 'error_code': outcome!.errorCode,
    if (outcome?.errorMessage != null) 'error_message': outcome!.errorMessage,
    if (outcome?.configRev != null) 'config_rev': outcome!.configRev,
    if (traceId.isNotEmpty) 'trace_id': traceId,
    if (appVersion.isNotEmpty) 'app_version': appVersion,
  };
}
