import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/missed_show/domain/missed_summary.dart';

void main() {
  EpgProgram program({int startMin = 0, int stopMin = 60}) {
    final int t0 = DateTime(2026, 9, 30, 20).millisecondsSinceEpoch;
    return EpgProgram(
      channelId: 'c',
      startTime: t0 + startMin * 60000,
      stopTime: t0 + stopMin * 60000,
      title: 'Journal',
      description: 'Le sommaire du soir.',
    );
  }

  test('moins de trois minutes : on ne dit rien', () {
    final EpgProgram p = program();
    final DateTime now = DateTime.fromMillisecondsSinceEpoch(p.startTime + 60000);
    expect(missedFromGuide(program: p, now: now, catchupDeclared: true, rewindUrl: 'http://x'), isNull);
  });

  test('en retard : le texte du guide, sans vidéo si le catch-up n\'est pas déclaré', () {
    final EpgProgram p = program();
    final DateTime now = DateTime.fromMillisecondsSinceEpoch(p.startTime + 12 * 60000);
    final MissedSummary? quiet = missedFromGuide(
      program: p,
      now: now,
      catchupDeclared: false,
      rewindUrl: 'http://x',
    );
    expect(quiet, isNotNull);
    expect(quiet!.missedMinutes, 12);
    expect(quiet.canRewind, isFalse);
    expect(quiet.description, 'Le sommaire du soir.');

    final MissedSummary? rewind = missedFromGuide(
      program: p,
      now: now,
      catchupDeclared: true,
      rewindUrl: 'http://replay',
    );
    expect(rewind!.canRewind, isTrue);
    expect(rewind.rewindUrl, 'http://replay');
  });

  test('programme déjà fini ou pas encore commencé : rien', () {
    final EpgProgram p = program();
    expect(
      missedFromGuide(
        program: p,
        now: DateTime.fromMillisecondsSinceEpoch(p.stopTime + 1000),
        catchupDeclared: true,
        rewindUrl: 'http://x',
      ),
      isNull,
    );
  });
}
