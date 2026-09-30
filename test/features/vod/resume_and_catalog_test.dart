import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/vod/data/catalog_disk_cache.dart';
import 'package:tv_king/features/vod/domain/resume_start.dart';

void main() {
  test('moins de 30 secondes, ou « depuis le début » : on repart à zéro', () {
    expect(
      ResumeStart.decide(saved: const Duration(seconds: 29)).at,
      Duration.zero,
    );
    expect(
      ResumeStart.decide(
        saved: const Duration(minutes: 10),
        fromStart: true,
      ).resumes,
      isFalse,
    );
    expect(ResumeStart.decide().at, Duration.zero);
  });

  test('une position mémorisée reprend 5 secondes plus tôt, jamais avant 0', () {
    final ResumeStart r = ResumeStart.decide(
      saved: const Duration(seconds: 60),
    );
    expect(r.resumes, isTrue);
    expect(r.at, const Duration(seconds: 55));
    expect(
      ResumeStart.decide(saved: const Duration(seconds: 3)).at,
      Duration.zero,
    );
  });

  test('une réponse catalogue vide ne remplace pas ce qu\'on a déjà', () {
    expect(
      keepPreviousWhenEmpty<String>(
        incoming: const <String>[],
        previous: const <String>['film'],
        disk: const <String>['disque'],
      ),
      <String>['film'],
    );
    expect(
      keepPreviousWhenEmpty<String>(
        incoming: null,
        previous: const <String>[],
        disk: const <String>['disque'],
      ),
      <String>['disque'],
    );
    expect(
      keepPreviousWhenEmpty<String>(
        incoming: const <String>['neuf'],
        previous: const <String>['film'],
        disk: const <String>['disque'],
      ),
      <String>['neuf'],
    );
  });
}
