// =========================================================
//  tonight_plan_test.dart — « qu'est-ce qu'il y a ce soir ? »
// =========================================================
//  Pas de base, pas de réseau : la soirée et le tri sont purs.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/voice/domain/tonight_plan.dart';

TonightProgram _p({
  required String id,
  required String title,
  required DateTime start,
  required DateTime end,
  String? category,
}) {
  return TonightProgram(
    channelId: id,
    title: title,
    startMs: start.millisecondsSinceEpoch,
    stopMs: end.millisecondsSinceEpoch,
    category: category,
  );
}

void main() {
  final DateTime evening = DateTime(2026, 9, 30, 21, 15);
  final DateTime late = DateTime(2026, 9, 30, 0, 30);
  final DateTime morning = DateTime(2026, 9, 30, 6);

  test('la soirée va de 18 h à 1 h, et après minuit on reste sur la veille', () {
    final EveningWindow w = eveningWindow(evening);
    expect(w.start, DateTime(2026, 9, 30, 18));
    expect(w.end, DateTime(2026, 10, 1, 1));

    final EveningWindow before = eveningWindow(morning);
    expect(before.start, DateTime(2026, 9, 30, 18));

    final EveningWindow afterMidnight = eveningWindow(late);
    expect(afterMidnight.start, DateTime(2026, 9, 29, 18));
    expect(afterMidnight.end, DateTime(2026, 9, 30, 1));
  });

  test('on garde ce qui passe ce soir, du plus tôt au plus tard', () {
    final TonightLineup lineup = planTonight(
      now: evening,
      knownChannelIds: <String>{'tf1', 'm6'},
      channelNames: <String, String>{'tf1': 'TF1', 'm6': 'M6'},
      programs: <TonightProgram>[
        _p(
          id: 'tf1',
          title: 'Journal',
          start: DateTime(2026, 9, 30, 20),
          end: DateTime(2026, 9, 30, 20, 40),
        ),
        // Trop tôt : fini avant 18 h.
        _p(
          id: 'm6',
          title: 'Matin',
          start: DateTime(2026, 9, 30, 8),
          end: DateTime(2026, 9, 30, 9),
        ),
        // Commence avant 18 h mais finit pendant la soirée.
        _p(
          id: 'm6',
          title: 'Feuilleton',
          start: DateTime(2026, 9, 30, 17, 30),
          end: DateTime(2026, 9, 30, 19),
        ),
        // Après 1 h.
        _p(
          id: 'tf1',
          title: 'Nuit',
          start: DateTime(2026, 10, 1, 2),
          end: DateTime(2026, 10, 1, 3),
        ),
        _p(
          id: 'tf1',
          title: '',
          start: DateTime(2026, 9, 30, 21),
          end: DateTime(2026, 9, 30, 22),
        ),
        _p(
          id: 'tf1',
          title: 'Cassé',
          start: DateTime(2026, 9, 30, 21),
          end: DateTime(2026, 9, 30, 21),
        ),
      ],
    );
    expect(lineup.slots.map((TonightSlot s) => s.title), <String>[
      'Feuilleton',
      'Journal',
    ]);
    expect(lineup.slots.first.channelName, 'M6');
    expect(lineup.slots.every((TonightSlot s) => s.canPlay), isTrue);
  });

  test('même émission sur deux chaînes : une seule ligne, la plus tôt', () {
    final TonightLineup lineup = planTonight(
      now: evening,
      knownChannelIds: <String>{'a', 'b'},
      channelNames: <String, String>{'a': 'A', 'b': 'B'},
      programs: <TonightProgram>[
        _p(
          id: 'b',
          title: 'Match',
          start: DateTime(2026, 9, 30, 21),
          end: DateTime(2026, 9, 30, 23),
        ),
        _p(
          id: 'a',
          title: 'Match',
          start: DateTime(2026, 9, 30, 20),
          end: DateTime(2026, 9, 30, 22),
        ),
      ],
    );
    expect(lineup.slots, hasLength(1));
    expect(lineup.slots.single.channelName, 'A');
  });

  test('chaîne absente de la playlist : on montre le titre, on ne le joue pas', () {
    final TonightLineup lineup = planTonight(
      now: evening,
      knownChannelIds: <String>{'tf1'},
      channelNames: <String, String>{'tf1': 'TF1'},
      programs: <TonightProgram>[
        _p(
          id: 'inconnu',
          title: 'Documentaire',
          start: DateTime(2026, 9, 30, 20),
          end: DateTime(2026, 9, 30, 21),
        ),
      ],
    );
    expect(lineup.slots.single.canPlay, isFalse);
    expect(lineup.slots.single.channelName, 'inconnu');
    expect(lineup.slots.single.title, 'Documentaire');
  });

  test('guide vide : liste vide, pas d\'exception', () {
    final TonightLineup lineup = planTonight(
      now: evening,
      programs: const <TonightProgram>[],
      channelNames: const <String, String>{},
    );
    expect(lineup.isEmpty, isTrue);
  });

  test('au plus 12 lignes', () {
    final List<TonightProgram> many = <TonightProgram>[
      for (int i = 0; i < 30; i++)
        _p(
          id: 'c$i',
          title: 'Émission $i',
          start: DateTime(2026, 9, 30, 18).add(Duration(minutes: i)),
          end: DateTime(2026, 9, 30, 18, 30).add(Duration(minutes: i)),
        ),
    ];
    final TonightLineup lineup = planTonight(
      now: evening,
      programs: many,
      channelNames: <String, String>{for (int i = 0; i < 30; i++) 'c$i': 'C$i'},
      knownChannelIds: <String>{for (int i = 0; i < 30; i++) 'c$i'},
    );
    expect(lineup.slots, hasLength(12));
  });
}
