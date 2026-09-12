// =========================================================
//  time_of_day_service_test.dart — Genre selon l'heure
// =========================================================
//  TimeOfDayService n'avait AUCUN appelant hors de son fichier
//  (Vague 3 : on le branche sur l'accueil D). On verrouille la
//  table, pas l'horloge réelle : un test à 3 h du matin doit
//  dire la même chose qu'à 15 h.
//
//  PUR : aucun I/O, aucune base. Si quelqu'un « améliore » les
//  créneaux en les décalant, ces tests tombent — c'est voulu.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/data/time_of_day_service.dart';
import 'package:tv_king/features/channels/domain/channel_genre.dart';

void main() {
  group('TimeOfDayService.suggestedAt', () {
    test('matin → info (le journal, pas le cinéma)', () {
      expect(TimeOfDayService.suggestedAt(7), ChannelGenre.news);
      expect(TimeOfDayService.suggestedAt(9), ChannelGenre.news);
    });

    test('fin de matinée → jeunesse', () {
      expect(TimeOfDayService.suggestedAt(10), ChannelGenre.kids);
      expect(TimeOfDayService.suggestedAt(11), ChannelGenre.kids);
    });

    test('après-midi → sport (le créneau qui accroche)', () {
      expect(TimeOfDayService.suggestedAt(14), ChannelGenre.sports);
      expect(TimeOfDayService.suggestedAt(16), ChannelGenre.sports);
      expect(TimeOfDayService.suggestedAt(18), ChannelGenre.sports);
    });

    test('soirée → films', () {
      expect(TimeOfDayService.suggestedAt(20), ChannelGenre.movies);
      expect(TimeOfDayService.suggestedAt(22), ChannelGenre.movies);
    });

    test('nuit → musique puis films', () {
      expect(TimeOfDayService.suggestedAt(23), ChannelGenre.music);
      expect(TimeOfDayService.suggestedAt(0), ChannelGenre.music);
      expect(TimeOfDayService.suggestedAt(3), ChannelGenre.movies);
    });

    test('heure hors table (modulo) ne plante pas', () {
      expect(TimeOfDayService.suggestedAt(24), TimeOfDayService.suggestedAt(0));
    });
  });
}
