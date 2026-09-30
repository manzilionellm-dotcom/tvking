import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/followed/domain/show_clock.dart';
import 'package:tv_king/features/followed/domain/show_lines.dart';
import 'package:tv_king/features/followed/domain/show_taste.dart';
import 'package:tv_king/features/followed/domain/show_title.dart';

void main() {
  const String journal = 'Le Journal';

  ShowBook watch(
    ShowBook book, {
    required int minutes,
    required DateTime wall,
    String title = journal,
    String channelId = 'tf1',
    bool favorite = false,
  }) {
    return addWatch(
      book,
      title: title,
      channelId: channelId,
      addMs: minutes * 60000,
      wall: wall,
      nowMs: wall.millisecondsSinceEpoch,
      channelFavorite: favorite,
    );
  }

  GuideSlot slot({
    required int startMin,
    int lengthMin = 60,
    String title = journal,
    String channelId = 'tf1',
    String channelName = 'TF1',
    bool catchup = false,
    int originMs = 0,
  }) {
    final int start = originMs + startMin * 60000;
    return GuideSlot(
      channelId: channelId,
      channelName: channelName,
      title: title,
      startMs: start,
      stopMs: start + lengthMin * 60000,
      catchupDeclared: catchup,
    );
  }

  group('apprendre', () {
    test('un passage court ne suffit pas', () {
      final ShowBook book = watch(
        ShowBook.empty,
        minutes: 5,
        wall: DateTime(2026, 9, 30, 20),
      );
      final ShowTaste taste = book.shows.values.single;
      expect(isFollowed(taste, <String>{}), isFalse);
      expect(isFollowed(taste, <String>{'tf1'}), isFalse);
    });

    test('quinze minutes d\'image : émission suivie', () {
      final ShowBook book = watch(
        ShowBook.empty,
        minutes: 15,
        wall: DateTime(2026, 9, 30, 20),
      );
      expect(isFollowed(book.shows.values.single, <String>{}), isTrue);
    });

    test('le même jour et la même heure, deux fois : une habitude', () {
      final DateTime first = DateTime(2026, 9, 30, 20, 15);
      final DateTime nextWeek = DateTime(2026, 10, 7, 20, 15);
      ShowBook book = watch(ShowBook.empty, minutes: 2, wall: first);
      expect(isFollowed(book.shows.values.single, <String>{}), isFalse);
      book = watch(book, minutes: 2, wall: nextWeek);
      expect(book.shows.values.single.slots['3-20'], 2);
      expect(isFollowed(book.shows.values.single, <String>{}), isTrue);
    });

    test('deux heures différentes ne font pas une habitude', () {
      ShowBook book = watch(
        ShowBook.empty,
        minutes: 2,
        wall: DateTime(2026, 9, 30, 20),
      );
      book = watch(book, minutes: 2, wall: DateTime(2026, 9, 30, 21));
      expect(isFollowed(book.shows.values.single, <String>{}), isFalse);
    });

    test('la même séance ne compte pas deux fois le créneau', () {
      final DateTime start = DateTime(2026, 9, 30, 20);
      ShowBook book = watch(ShowBook.empty, minutes: 2, wall: start);
      book = watch(
        book,
        minutes: 2,
        wall: start.add(const Duration(minutes: 10)),
      );
      expect(book.shows.values.single.sessions, 1);
      expect(book.shows.values.single.slots.values.single, 1);
      expect(book.shows.values.single.watchMs, 4 * 60000);
    });

    test('chaîne favorite : 8 minutes suffisent, et plus si on retire le cœur',
        () {
      final ShowBook book = watch(
        ShowBook.empty,
        minutes: 8,
        wall: DateTime(2026, 9, 30, 20),
        favorite: true,
      );
      final ShowTaste taste = book.shows.values.single;
      expect(isFollowed(taste, <String>{'tf1'}), isTrue);
      expect(isFollowed(taste, <String>{}), isFalse);
    });

    test('épingler suit tout de suite, retirer l\'épingle laisse le temps', () {
      ShowBook book = setPinned(
        ShowBook.empty,
        title: journal,
        channelId: 'tf1',
        nowMs: 10,
        pinned: true,
      );
      expect(isFollowed(book.shows.values.single, <String>{}), isTrue);
      book = watch(book, minutes: 15, wall: DateTime(2026, 9, 30, 20));
      book = setPinned(
        book,
        title: journal,
        channelId: 'tf1',
        nowMs: 20,
        pinned: false,
      );
      expect(book.shows.values.single.pinned, isFalse);
      expect(isFollowed(book.shows.values.single, <String>{}), isTrue);
    });

    test('un titre vide ou un zapping d\'une seconde ne crée rien', () {
      expect(
        addWatch(
          ShowBook.empty,
          title: ' ',
          channelId: 'tf1',
          addMs: 60000,
          wall: DateTime(2026, 9, 30, 20),
          nowMs: 1,
          channelFavorite: false,
        ).shows,
        isEmpty,
      );
      expect(
        addWatch(
          ShowBook.empty,
          title: journal,
          channelId: 'tf1',
          addMs: 500,
          wall: DateTime(2026, 9, 30, 20),
          nowMs: 1,
          channelFavorite: false,
        ).shows,
        isEmpty,
      );
    });

    test('S02E05 et les accents sont la même émission', () {
      expect(showKey('Plus belle la vie S02E05'), showKey('PLUS BELLE LA VIE'));
      expect(showKey('Émission spéciale'), showKey('emission speciale'));
      expect(showKey('a'), isEmpty);
    });

    test('un carnet illisible est vide', () {
      expect(decodeShowBook('pas du json').shows, isEmpty);
      expect(decodeShowBook(null).shows, isEmpty);
      final ShowBook book = decodeShowBook(
        '{"shows":{"le journal":{"t":"Le Journal","c":"tf1","w":1,"p":true,"s":{"3-20":2,"x":0}},"mauvais":1},"seen":["a",""]}',
      );
      expect(book.shows.keys, <String>['le journal']);
      expect(book.shows['le journal']!.pinned, isTrue);
      expect(book.shows['le journal']!.slots, <String, int>{'3-20': 2});
      expect(book.seen, <String>['a']);
    });
  });

  group('l\'heure du guide', () {
    final int t0 = DateTime.utc(2026, 9, 30, 20).millisecondsSinceEpoch;

    ShowPlan at(int deltaMin,
        {int lead = 5, List<GuideSlot>? programs, Set<String>? seen}) {
      return planShows(
        nowMs: t0 + deltaMin * 60000,
        leadMinutes: lead,
        programs: programs ??
            <GuideSlot>[
              slot(originMs: t0, startMin: 0, catchup: true),
            ],
        followed: <String>{showKey(journal)},
        seen: seen ?? <String>{},
      );
    }

    test('commence dans 5 minutes', () {
      final ShowPlan plan = at(-5);
      expect(plan.banner, isNotNull);
      expect(plan.banner!.moment, ShowMoment.soon);
      expect(plan.banner!.minutes, 5);
      expect(
        startsInLine('fr', plan.banner!.title, plan.banner!.minutes),
        'Le Journal commence dans 5 minutes',
      );
      expect(plan.row.single.rowGroup, ShowMoment.soon);
    });

    test('dans 6 minutes : la rangée oui, le bandeau non (délai 5)', () {
      final ShowPlan plan = at(-6);
      expect(plan.row.single.moment, ShowMoment.soon);
      expect(plan.banner, isNull);
    });

    test('à la seconde du début : en cours, pas de bandeau « il y a 0 »', () {
      final ShowPlan plan = at(0);
      expect(plan.row.single.moment, ShowMoment.onAir);
      expect(plan.banner, isNull);
    });

    test(
        'commencé il y a 12 minutes, avec rattrapage seulement s\'il est déclaré',
        () {
      final ShowPlan late = at(12);
      expect(late.banner!.moment, ShowMoment.started);
      expect(late.banner!.minutes, 12);
      expect(late.banner!.canRewind, isTrue);
      expect(late.row.single.rowGroup, ShowMoment.started);
      expect(
        startedAgoLine('fr', late.banner!.title, late.banner!.minutes),
        'Le Journal a commencé il y a 12 minutes',
      );

      final ShowPlan quiet = planShows(
        nowMs: t0 + 12 * 60000,
        leadMinutes: 5,
        programs: <GuideSlot>[slot(originMs: t0, startMin: 0, catchup: false)],
        followed: <String>{showKey(journal)},
        seen: <String>{},
      );
      expect(quiet.banner!.canRewind, isFalse);
    });

    test('une minute après le début : bandeau, rangée encore « en cours »', () {
      final ShowPlan plan = at(1);
      expect(plan.banner!.moment, ShowMoment.started);
      expect(plan.banner!.minutes, 1);
      expect(plan.row.single.rowGroup, ShowMoment.onAir);
      expect(
        startedAgoLine('fr', 'Journal', 1),
        'Journal a commencé il y a 1 minute',
      );
    });

    test('terminée, avec rediffusion si le guide en a une plus tard', () {
      final int now = t0 + 70 * 60000;
      final ShowPlan plan = planShows(
        nowMs: now,
        leadMinutes: 5,
        programs: <GuideSlot>[
          slot(originMs: t0, startMin: 0),
          slot(
            originMs: t0,
            startMin: 180,
            channelId: 'm6',
            channelName: 'M6',
          ),
        ],
        followed: <String>{showKey(journal)},
        seen: <String>{},
      );
      expect(plan.banner!.moment, ShowMoment.finished);
      expect(plan.banner!.hasReplay, isTrue);
      expect(plan.banner!.replayChannelId, 'm6');
      expect(finishedLine('fr', 'Le Journal'), 'Le Journal est terminée');
      expect(plan.row, isEmpty);
    });

    test('terminée sans autre passage : pas de rediffusion', () {
      final ShowPlan plan = at(70);
      expect(plan.banner!.moment, ShowMoment.finished);
      expect(plan.banner!.hasReplay, isFalse);
    });

    test('finie depuis longtemps : on n\'en parle plus', () {
      expect(at(120).banner, isNull);
      expect(at(120).row, isEmpty);
    });

    test('le même rappel ne revient pas, un autre moment si', () {
      final ShowPlan soon = at(-5);
      final String key = soon.banner!.alertKey;
      final ShowPlan again = at(-4, seen: <String>{key});
      expect(again.banner, isNull);
      expect(again.row, isNotEmpty);

      final ShowPlan later = at(12, seen: <String>{key});
      expect(later.banner, isNotNull);
      expect(later.banner!.alertKey, isNot(key));
    });

    test('deux lignes du guide pour la même diffusion : une seule carte', () {
      final GuideSlot one = slot(originMs: t0, startMin: 0);
      final ShowPlan plan = planShows(
        nowMs: t0 + 12 * 60000,
        leadMinutes: 5,
        programs: <GuideSlot>[one, one],
        followed: <String>{showKey(journal)},
        seen: <String>{},
      );
      expect(plan.row, hasLength(1));
    });

    test('guide vide, titre vide, horaire à l\'envers : rien, pas d\'exception',
        () {
      expect(
        planShows(
          nowMs: t0,
          leadMinutes: 5,
          programs: const <GuideSlot>[],
          followed: <String>{showKey(journal)},
          seen: <String>{},
        ),
        ShowPlan.empty,
      );
      expect(
        planShows(
          nowMs: t0,
          leadMinutes: 5,
          programs: <GuideSlot>[
            slot(originMs: t0, startMin: 0, title: '  '),
            GuideSlot(
              channelId: 'tf1',
              channelName: 'TF1',
              title: journal,
              startMs: t0 + 60000,
              stopMs: t0,
              catchupDeclared: false,
            ),
          ],
          followed: <String>{showKey(journal)},
          seen: <String>{},
        ).row,
        isEmpty,
      );
    });

    test('une émission non suivie n\'apparaît pas', () {
      final ShowPlan plan = planShows(
        nowMs: t0 - 5 * 60000,
        leadMinutes: 5,
        programs: <GuideSlot>[slot(originMs: t0, startMin: 0, title: 'Autre')],
        followed: <String>{showKey(journal)},
        seen: <String>{},
      );
      expect(plan.row, isEmpty);
      expect(plan.banner, isNull);
    });

    test('le délai « dans 5 minutes » ne dépend pas du fuseau', () {
      final int start = DateTime.utc(2026, 6, 15, 18).millisecondsSinceEpoch;
      final DateTime utcNow = DateTime.utc(2026, 6, 15, 17, 55);
      final DateTime localNow =
          DateTime.fromMillisecondsSinceEpoch(utcNow.millisecondsSinceEpoch);
      expect(utcNow.millisecondsSinceEpoch, localNow.millisecondsSinceEpoch);
      ShowPlan planAt(int nowMs) => planShows(
            nowMs: nowMs,
            leadMinutes: 5,
            programs: <GuideSlot>[
              GuideSlot(
                channelId: 'c',
                channelName: 'C',
                title: journal,
                startMs: start,
                stopMs: start + 3600000,
                catchupDeclared: false,
              ),
            ],
            followed: <String>{showKey(journal)},
            seen: <String>{},
          );
      expect(planAt(utcNow.millisecondsSinceEpoch).banner!.minutes, 5);
      expect(planAt(localNow.millisecondsSinceEpoch).banner!.minutes, 5);
    });

    test('le créneau jour/heure suit le décalage, minuit compris', () {
      final int epoch =
          DateTime.utc(2026, 9, 30, 22, 30).millisecondsSinceEpoch;
      final DateTime utc = wallTime(epoch, Duration.zero);
      final DateTime plusTwo = wallTime(epoch, const Duration(hours: 2));
      expect(utc.hour, 22);
      expect(plusTwo.hour, 0);
      expect(plusTwo.weekday,
          utc.weekday == DateTime.sunday ? DateTime.monday : utc.weekday + 1);
      expect(habitSlot(utc), isNot(habitSlot(plusTwo)));
    });

    test('délai inconnu → 5, et on tourne 15 → 2', () {
      expect(normalizeLead(7), 5);
      expect(normalizeLead(null), 5);
      expect(normalizeLead(10), 10);
      expect(nextLead(15), 2);
      expect(nextLead(2), 5);
    });

    test('un vieux rappel est oublié', () {
      const int now = 100 * 24 * 3600000;
      final List<String> kept = pruneSeen(
        <String>['c@0@soon', 'c@$now@started', ''],
        now,
      );
      expect(kept, <String>['c@$now@started']);
    });
  });

  group('phrases', () {
    test('les 16 langues ont une phrase, l\'inconnu retombe sur le français',
        () {
      for (final String code in kFollowedLanguages) {
        expect(startsInLine(code, 'Journal', 5), isNotEmpty);
        expect(startedAgoLine(code, 'Journal', 5), isNotEmpty);
        expect(finishedLine(code, 'Journal'), isNotEmpty);
        expect(followedWord(code, 'watch'), isNotEmpty);
        expect(followedWord(code, 'live'), isNotEmpty);
        expect(followedWord(code, 'start'), isNotEmpty);
        expect(followedWord(code, 'replay'), isNotEmpty);
        expect(followedWord(code, 'row'), isNotEmpty);
      }
      expect(
          startsInLine('xx', 'Journal', 5), 'Journal commence dans 5 minutes');
      expect(followedWord('en', 'row'), 'Your shows');
      expect(leadLine('fr', 5), contains('5'));
    });
  });
}
