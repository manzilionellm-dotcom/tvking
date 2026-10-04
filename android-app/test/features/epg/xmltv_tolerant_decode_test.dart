// =========================================================
//  xmltv_tolerant_decode_test.dart — un guide ISO-8859-1 n'est plus jeté
// =========================================================
//  Avant : le décodeur UTF-8 strict levait sur le premier octet non
//  UTF-8 (« é » en Latin-1 = 0xE9) et TOUT l'import était abandonné en
//  silence. Maintenant le titre fautif prend un caractère de
//  remplacement, les autres programmes passent.
// =========================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/data/xmltv_parser.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';

String _stamp(DateTime t) {
  final DateTime u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
}

void main() {
  test('un octet Latin-1 dans un titre ne fait pas échouer le fichier', () async {
    final DateTime now = DateTime(2026, 10, 4, 12);
    final String a = _stamp(now.add(const Duration(hours: 1)));
    final String b = _stamp(now.add(const Duration(hours: 2)));
    final String c = _stamp(now.add(const Duration(hours: 3)));
    final List<int> head = utf8.encode(
      '<?xml version="1.0"?><tv>'
      '<programme start="$a" stop="$b" channel="tf1"><title>Téléfoot</title></programme>'
      '<programme start="$b" stop="$c" channel="tf1"><title>Journal ',
    );
    // 0xE9 = « é » en ISO-8859-1, invalide en UTF-8.
    final List<int> latin = <int>[0xE9];
    final List<int> tail = utf8.encode('té</title></programme></tv>');
    final List<EpgProgram> out = <EpgProgram>[];
    final int n = await XmltvParser.parse(
      Stream<List<int>>.fromIterable(<List<int>>[head, latin, tail]),
      now: now,
      onProgram: (EpgProgram p) async => out.add(p),
    );
    expect(n, 2);
    expect(out.first.title, 'Téléfoot');
    expect(out.last.title, contains('Journal'));
    expect(out.last.title, contains('té'));
  });
}
