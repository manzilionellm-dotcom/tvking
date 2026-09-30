// =========================================================
//  home_engagement_test.dart — Accueil : rangées, démarrage, rappels
// =========================================================
//  On ne teste QUE les décisions (pas l'écran). Les adresses de flux
//  sont factices : aucune playlist réelle.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/epg/domain/program_reminder.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';
import 'package:tv_king/features/tv/data/startup_preference.dart';

Channel _ch(String id, String name, {String category = 'FR'}) => Channel(
      id: id,
      name: name,
      category: category,
      streamUrl: 'http://example.invalid/$id',
      isLive: true,
    );

WatchEntry _film(String id, {int pos = 120000, String title = 'Film'}) =>
    WatchEntry(
      id: id,
      isEpisode: false,
      title: title,
      streamUrl: 'http://example.invalid/$id.mp4',
      posMs: pos,
      durMs: 6000000,
      updatedAt: 1,
    );

void main() {
  test('bonjour selon l\'heure', () {
    expect(homeDayPart(8), HomeDayPart.morning);
    expect(homeDayPart(12), HomeDayPart.afternoon);
    expect(homeDayPart(17), HomeDayPart.afternoon);
    expect(homeDayPart(18), HomeDayPart.evening);
    expect(homeDayPart(3), HomeDayPart.evening);
  });

  test(
      'reprise au démarrage : seulement si demandé, une fois, hors mode sans échec',
      () {
    expect(
      shouldResumeLastChannel(
        enabled: false,
        alreadyResumedThisVisit: false,
        hasChannel: true,
        safeMode: false,
      ),
      isFalse,
    );
    expect(
      shouldResumeLastChannel(
        enabled: true,
        alreadyResumedThisVisit: false,
        hasChannel: true,
        safeMode: false,
      ),
      isTrue,
    );
    expect(
      shouldResumeLastChannel(
        enabled: true,
        alreadyResumedThisVisit: true,
        hasChannel: true,
        safeMode: false,
      ),
      isFalse,
      reason: 'Retour ne doit pas relancer la chaîne',
    );
    expect(
      shouldResumeLastChannel(
        enabled: true,
        alreadyResumedThisVisit: false,
        hasChannel: false,
        safeMode: false,
      ),
      isFalse,
    );
    expect(
      shouldResumeLastChannel(
        enabled: true,
        alreadyResumedThisVisit: false,
        hasChannel: true,
        safeMode: true,
      ),
      isFalse,
    );
  });

  test('reprendre suit l\'historique et ignore les chaînes disparues', () {
    final Map<String, Channel> byId = indexChannelsById(<Channel>[
      _ch('a', 'TF1'),
      _ch('b', 'M6'),
    ]);
    final List<Channel> resume =
        channelsInIdOrder(<String>['gone', 'b', 'a'], byId);
    expect(resume.map((Channel c) => c.id), <String>['b', 'a']);
  });

  test('favoris : ordre de la playlist, pas plus de 8', () {
    final List<Channel> all = <Channel>[
      for (int i = 0; i < 20; i++) _ch('c$i', 'Ch $i'),
    ];
    final Set<String> favs = <String>{for (int i = 0; i < 20; i++) 'c$i'};
    final List<Channel> out = favoriteChannels(all, favs);
    expect(out.length, kHomeShelfMax);
    expect(out.first.id, 'c0');
    expect(out.last.id, 'c7');
  });

  test('mode enfants : un favori au nom adulte évident est masqué', () {
    final List<Channel> all = <Channel>[
      _ch('ok', 'TF1'),
      _ch('no', 'FR| XXX HD', category: 'ADULT'),
    ];
    final List<Channel> out = favoriteChannels(
      all,
      <String>{'ok', 'no'},
      hide: hiddenForKids,
    );
    expect(out.map((Channel c) => c.id), <String>['ok']);
  });

  test(
      'continuer : un titre adulte sort en mode enfants, un dessin animé reste',
      () {
    final List<WatchEntry> out = continueForHome(
      <WatchEntry>[
        _film('a', title: 'Kirikou'),
        _film('b', title: 'XXX Club'),
      ],
      kidsMode: true,
    );
    expect(out.map((WatchEntry e) => e.id), <String>['a']);
  });

  test('clé grossière : TF1 et « FR| TF1 HD » se rejoignent', () {
    expect(roughChannelKey('TF1'), roughChannelKey('FR| TF1 HD'));
    expect(roughChannelKey('TF1'), isNot(roughChannelKey('TF10')));
  });

  test('populaire : ordre des tendances, seulement les chaînes de la playlist',
      () {
    final List<String> ids = matchTrendingChannelIds(<String, Object?>{
      'names': <String>['Inconnue', 'M6', 'TF1'],
      'ids': <String>['1', '2'],
      'raws': <String>['FR| TF1 FHD', 'M6 HD'],
      'kids': false,
    });
    expect(ids, <String>['2', '1']);
  });

  test('populaire en mode enfants ignore un nom ou une catégorie adulte', () {
    final List<String> ids = matchTrendingChannelIds(<String, Object?>{
      'names': <String>['XXX Night', 'Sports 1', 'M6'],
      'ids': <String>['x', 's', 'm'],
      'raws': <String>['XXX Night HD', 'Sports 1', 'M6'],
      'cats': <String>['ADULT', 'ADULT', 'FR'],
      'kids': true,
    });
    expect(ids, <String>['m']);
  });

  test('le focus va d\'abord au rappel imminent, sinon à Reprendre', () {
    expect(
      pickInitialShelf(
        hasSoonReminder: true,
        hasResume: true,
        hasContinue: true,
        hasFavorites: true,
        hasPopular: true,
      ),
      HomeShelfKind.reminders,
    );
    expect(
      pickInitialShelf(
        hasSoonReminder: false,
        hasResume: true,
        hasContinue: true,
        hasFavorites: false,
        hasPopular: false,
      ),
      HomeShelfKind.resume,
    );
    expect(
      pickInitialShelf(
        hasSoonReminder: false,
        hasResume: false,
        hasContinue: false,
        hasFavorites: false,
        hasPopular: false,
      ),
      isNull,
    );
  });

  test('rappels : trop tard, nettoyage, accueil, second appui retire', () {
    final int now = 1000000000000;
    expect(ProgramReminderLog.isTooLate(now + 30 * 1000, now), isTrue);
    expect(ProgramReminderLog.isTooLate(now + 10 * 60 * 1000, now), isFalse);
    expect(ProgramReminderLog.isSoon(now + 10 * 60 * 1000, now), isTrue);
    expect(ProgramReminderLog.isSoon(now + 2 * 60 * 60 * 1000, now), isFalse);

    final ProgramReminder soon = ProgramReminder(
      channelId: 'a',
      channelName: 'TF1',
      title: 'Journal',
      startMs: now + 20 * 60 * 1000,
    );
    final ProgramReminder later = ProgramReminder(
      channelId: 'b',
      channelName: 'M6',
      title: 'Film',
      startMs: now + 3 * 60 * 60 * 1000,
    );
    final ProgramReminder old = ProgramReminder(
      channelId: 'c',
      channelName: 'W9',
      title: 'Hier',
      startMs: now - 2 * 60 * 60 * 1000,
    );
    final List<ProgramReminder> kept =
        ProgramReminderLog.prune(<ProgramReminder>[old, later, soon], now);
    expect(kept.map((ProgramReminder r) => r.channelId), <String>['a', 'b']);

    final String raw = ProgramReminderLog.encode(kept);
    final List<ProgramReminder> back = ProgramReminderLog.decode(raw);
    expect(back.first.title, 'Journal');
    expect(ProgramReminderLog.decode('pas du json'), isEmpty);
    expect(ProgramReminderLog.decode(null), isEmpty);

    final List<ProgramReminder> home = ProgramReminderLog.forHome(
      kept,
      now,
      channelStillThere: (String id) => id == 'a',
    );
    expect(home.map((ProgramReminder r) => r.channelId), <String>['a']);

    final List<ProgramReminder> removed =
        ProgramReminderLog.without(kept, 'a', soon.startMs);
    expect(ProgramReminderLog.contains(removed, 'a', soon.startMs), isFalse);
    expect(ProgramReminderLog.contains(kept, 'a', soon.startMs), isTrue);
  });
}
