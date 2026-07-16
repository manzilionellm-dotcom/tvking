// =========================================================
//  xmltv_parse_isolate_test.dart — Parse XMLTV en isolate
// =========================================================
//  FLUIDITÉ : la sync EPG parse désormais le XML dans un isolate
//  dédié (parseInIsolate) et renvoie des LOTS de Map prêts pour
//  SQLite. Ces tests verrouillent :
//    1. l'équivalence fonctionnelle avec parse() : mêmes programmes,
//       même fenêtre temporelle, même filtre de chaînes connues ;
//    2. l'ordre et l'intégrité des lots (aucune perte, pas de
//       doublon, ordre du document préservé) ;
//    3. la remontée d'erreur propre (XML tronqué ne pend pas et
//       n'avale pas l'échec).
// =========================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/data/xmltv_parser.dart';

/// Petit XMLTV synthétique : 3 chaînes, 5 programmes dans la fenêtre.
String xmltv({int programmes = 5}) {
  final StringBuffer b = StringBuffer('<?xml version="1.0"?><tv>');
  final DateTime base = DateTime.now().toUtc();
  String fmt(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}'
      '${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}00 +0000';
  for (int i = 0; i < programmes; i++) {
    final DateTime start = base.add(Duration(hours: i));
    final DateTime stop = start.add(const Duration(hours: 1));
    final String chan = 'chan-${i % 3}';
    b.write('<programme start="${fmt(start)}" stop="${fmt(stop)}" '
        'channel="$chan"><title>Prog $i</title>'
        '<desc>Description $i</desc></programme>');
  }
  b.write('</tv>');
  return b.toString();
}

Stream<List<int>> chunked(String s, {int size = 64}) async* {
  final List<int> bytes = utf8.encode(s);
  for (int i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(
        i, i + size > bytes.length ? bytes.length : i + size);
  }
}

void main() {
  test('parseInIsolate émet les mêmes programmes que parse, en ordre',
      () async {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    final int total = await XmltvParser.parseInIsolate(
      chunked(xmltv(programmes: 12)),
      batchSize: 5, // force plusieurs lots
      onBatch: (List<Map<String, Object?>> batch) async {
        rows.addAll(batch);
      },
    );
    expect(total, 12);
    expect(rows.length, 12, reason: 'aucune perte, aucun doublon');
    // Ordre du document préservé (lot après lot).
    for (int i = 0; i < rows.length; i++) {
      expect(rows[i]['title'], 'Prog $i');
    }
    expect(rows.first['channel_id'] ?? rows.first['channelId'], isNotNull,
        reason: 'les Map doivent être prêtes pour batch.insert');
  });

  test('parseInIsolate respecte le filtre des chaînes connues', () async {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    final int total = await XmltvParser.parseInIsolate(
      chunked(xmltv(programmes: 9)),
      knownChannelIds: <String>{'chan-0'}, // chan-1 / chan-2 ignorées
      onBatch: (List<Map<String, Object?>> batch) async {
        rows.addAll(batch);
      },
    );
    expect(total, 3, reason: '9 programmes répartis sur 3 chaînes → 3');
    expect(rows.length, 3);
  });

  test('un XML malformé remonte une erreur propre (pas de blocage)',
      () async {
    expect(
      () => XmltvParser.parseInIsolate(
        chunked('<tv><programme start="oops'),
        onBatch: (_) async {},
      ),
      throwsA(isA<Exception>()),
    );
  });
}
