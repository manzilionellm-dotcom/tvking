// =========================================================
//  resume_start_test.dart — Rangée Reprendre (films / séries)
// =========================================================
//  Adresses factices. On vérifie que la carte lance la minute
//  gardée, pas le début, et qu'un épisode « suivant » part à 0.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/resume_start.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';

WatchEntry _entry(
  String id, {
  int pos = 125000,
  int dur = 6000000,
  bool episode = false,
  String? series,
  int? ep,
  bool upNext = false,
}) {
  return WatchEntry(
    id: id,
    isEpisode: episode || series != null,
    title: series ?? 'Film $id',
    subtitle: series == null ? null : 'S1 · E$ep',
    streamUrl: 'http://example.invalid/$id.mp4',
    posMs: pos,
    durMs: dur,
    updatedAt: 1,
    seriesId: series,
    season: series == null ? null : 1,
    episode: ep,
    upNext: upNext,
  );
}

void main() {
  test('film entamé : reprise 5 s plus tôt, pas au début', () {
    final ResumeStart start = ResumeStart.decide(entry: _entry('film'));
    expect(start.resumes, isTrue);
    expect(start.at, const Duration(seconds: 120));
  });

  test('série : l\'épisode en cours reprend à sa minute', () {
    final ResumeStart start = ResumeStart.decide(
      entry: _entry('e3', series: 'Maison', ep: 3, pos: 600000),
    );
    expect(start.resumes, isTrue);
    expect(start.at, const Duration(seconds: 595));
  });

  test('épisode suivant proposé : on part du début', () {
    final ResumeStart start = ResumeStart.decide(
      entry: _entry('e4', series: 'Maison', ep: 4, pos: 0, upNext: true),
    );
    expect(start.resumes, isFalse);
    expect(start.at, Duration.zero);
  });

  test('moins de 30 s, ou « depuis le début » : pas de reprise', () {
    expect(
      ResumeStart.decide(entry: _entry('court', pos: 10000)).resumes,
      isFalse,
    );
    expect(
      ResumeStart.decide(entry: _entry('film'), fromStart: true).at,
      Duration.zero,
    );
    expect(ResumeStart.decide().at, Duration.zero);
  });

  test('la rangée accueil garde le film et l\'épisode, pas le trop court', () {
    final List<WatchEntry> row = continueForHome(
      <WatchEntry>[
        _entry('film', pos: 125000),
        _entry('e3', series: 'Maison', ep: 3, pos: 600000),
        _entry('court', pos: 10000),
      ],
      kidsMode: false,
    );
    expect(row.map((WatchEntry e) => e.id), <String>['film', 'e3']);
    expect(ResumeStart.decide(entry: row[0]).at, const Duration(seconds: 120));
    expect(ResumeStart.decide(entry: row[1]).at, const Duration(seconds: 595));
  });
}
