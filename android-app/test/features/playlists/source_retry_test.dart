// =========================================================
//  source_retry_test.dart — Une liste refusée ne bloque plus les autres.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/domain/source_retry.dart';

void main() {
  const int now = 1700000000000;
  const List<String?> fps = <String?>['m3u|mauvaise', 'm3u|bonne', 'm3u|mauvaise-bis'];

  test('jamais refusées : ordre du serveur', () {
    final SourceRetryPlan p = planSourceRetry(
      fingerprints: fps, failures: const <String, SourceFailure>{}, nowMs: now,
    );
    expect(p.tryNow, <int>[0, 1, 2]);
    expect(p.skipped, isEmpty);
  });

  test('une liste refusée il y a 1 min est mise de côté, la bonne passe première', () {
    final Map<String, SourceFailure> f = <String, SourceFailure>{
      'm3u|mauvaise': SourceFailure(at: now - 60000, count: 1),
      'm3u|mauvaise-bis': SourceFailure(at: now - 60000, count: 3),
    };
    final SourceRetryPlan p = planSourceRetry(fingerprints: fps, failures: f, nowMs: now);
    expect(p.tryNow, <int>[1]);
    expect(p.skipped, <int>[0, 2]);
  });

  test('délai passé : on réessaie, mais après les listes saines', () {
    final Map<String, SourceFailure> f = <String, SourceFailure>{
      'm3u|mauvaise': SourceFailure(at: now - 6 * 60000, count: 1), // 5 min passées
    };
    final SourceRetryPlan p = planSourceRetry(fingerprints: fps, failures: f, nowMs: now);
    expect(p.tryNow, <int>[1, 2, 0]);
    expect(p.skipped, isEmpty);
  });

  test('ordre du panel (force) : tout le monde, les refusées en dernier', () {
    final Map<String, SourceFailure> f = <String, SourceFailure>{
      'm3u|mauvaise': SourceFailure(at: now, count: 5),
    };
    final SourceRetryPlan p = planSourceRetry(
      fingerprints: fps, failures: f, nowMs: now, force: true,
    );
    expect(p.tryNow, <int>[1, 2, 0]);
    expect(p.skipped, isEmpty);
  });

  test('délais : 5, 15, 45 min, 2 h, puis 6 h au plus', () {
    expect(sourceRetryDelay(1), const Duration(minutes: 5));
    expect(sourceRetryDelay(2), const Duration(minutes: 15));
    expect(sourceRetryDelay(3), const Duration(minutes: 45));
    expect(sourceRetryDelay(4), const Duration(hours: 2));
    expect(sourceRetryDelay(5), const Duration(hours: 6));
    expect(sourceRetryDelay(50), const Duration(hours: 6));
    expect(sourceRetryDelay(0), Duration.zero);
  });

  test('mémoire : un refus compte, un succès efface', () {
    Map<String, SourceFailure> f = const <String, SourceFailure>{};
    f = noteSourceOutcome(f, fingerprint: 'm3u|x', succeeded: false, nowMs: now);
    expect(f['m3u|x']!.count, 1);
    f = noteSourceOutcome(f, fingerprint: 'm3u|x', succeeded: false, nowMs: now + 1);
    expect(f['m3u|x']!.count, 2);
    expect(f['m3u|x']!.at, now + 1);
    f = noteSourceOutcome(f, fingerprint: 'm3u|x', succeeded: true, nowMs: now + 2);
    expect(f.containsKey('m3u|x'), isFalse);
  });

  test('repli retry_always : ordre du serveur, rien de mis de côté', () {
    final Map<String, SourceFailure> f = <String, SourceFailure>{
      'm3u|mauvaise': SourceFailure(at: now, count: 9),
    };
    final SourceRetryPlan p = planSourceRetry(
      fingerprints: fps, failures: f, nowMs: now, retryAlways: true,
    );
    expect(p.tryNow, <int>[0, 1, 2]);
  });

  test('sans empreinte : toujours tentée', () {
    final SourceRetryPlan p = planSourceRetry(
      fingerprints: const <String?>[null], failures: const <String, SourceFailure>{}, nowMs: now,
    );
    expect(p.tryNow, <int>[0]);
  });

  test('aller-retour JSON', () {
    final SourceFailure f = SourceFailure(at: now, count: 2);
    expect(SourceFailure.fromJson(f.toJson())!.count, 2);
    expect(SourceFailure.fromJson(<String, Object?>{'at': 0, 'n': 1}), isNull);
    expect(SourceFailure.fromJson('x'), isNull);
  });
}
