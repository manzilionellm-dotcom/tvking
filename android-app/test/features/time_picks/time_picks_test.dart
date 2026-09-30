import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/time_picks/domain/time_picks.dart';

void main() {
  test('le soir de semaine n\'est pas le matin, ni le week-end', () {
    expect(timeSlotKey(DateTime(2026, 9, 30, 20, 15)), 'wd-evening');
    expect(timeSlotKey(DateTime(2026, 9, 30, 8)), 'wd-morning');
    expect(timeSlotKey(DateTime(2026, 10, 3, 20)), 'we-evening');
    expect(timeSlotKey(DateTime(2026, 9, 30, 23, 30)), 'wd-night');
    expect(timeSlotKey(DateTime(2026, 9, 30, 2)), 'wd-night');
  });

  test('on classe le créneau, pas tout l\'historique', () {
    Map<String, Map<String, int>> book = <String, Map<String, int>>{};
    final DateTime evening = DateTime(2026, 9, 30, 21);
    final DateTime morning = DateTime(2026, 9, 30, 9);
    book = noteTimePick(book, timeSlotKey(evening), 'tf1');
    book = noteTimePick(book, timeSlotKey(evening), 'tf1');
    book = noteTimePick(book, timeSlotKey(evening), 'm6');
    book = noteTimePick(book, timeSlotKey(morning), 'arte');

    expect(picksForSlot(book, timeSlotKey(evening)), <String>['tf1', 'm6']);
    expect(picksForSlot(book, timeSlotKey(morning)), <String>['arte']);
    expect(picksForSlot(book, 'we-evening'), isEmpty);
  });

  test('un créneau vide ne retombe pas sur les autres', () {
    final Map<String, Map<String, int>> book = noteTimePick(
      <String, Map<String, int>>{},
      'wd-morning',
      'tf1',
    );
    expect(picksForSlot(book, 'wd-afternoon'), isEmpty);
  });

  test('un fichier illisible donne un carnet vide', () {
    expect(decodeTimePicks('pas du json'), isEmpty);
    expect(decodeTimePicks(null), isEmpty);
    final Map<String, Map<String, int>> book = decodeTimePicks(
      '{"wd-evening":{"tf1":2,"x":0},"mauvais":[]}',
    );
    expect(book['wd-evening'], <String, int>{'tf1': 2});
    expect(book.containsKey('mauvais'), isFalse);
  });
}
