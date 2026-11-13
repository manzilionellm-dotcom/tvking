import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/source_http_input_formatter.dart';

void main() {
  const formatter = SourceHttpInputFormatter();
  TextEditingValue apply(String text,
          {TextSelection? selection, TextRange composing = TextRange.empty}) =>
      formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
            text: text,
            selection:
                selection ?? TextSelection.collapsed(offset: text.length),
            composing: composing),
      );

  TextEditingValue valueOf(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

  test('http:// collé reste http://, y compris l’URL imbriquée', () {
    const input =
        'http://user:pass@server.invalid:8080/list.m3u?next=https://cdn.invalid/master.m3u8&token=A%2bB%2Fc';
    final result = apply(input);
    expect(result.text, input);
    expect(result.text.startsWith('http://'), isTrue);
    expect(result.text.contains('https://cdn.invalid'), isTrue);
    expect(result.selection.extentOffset, input.length);
  });

  test('https:// collé reste https://, le s n’est ni ajouté ni retiré', () {
    const input =
        'https://user:pass@server.invalid:8443/list.m3u?next=http://cdn.invalid/master.m3u8&token=A%2bB%2Fc';
    final result = apply(input);
    expect(result.text, input);
    expect(result.text.startsWith('https://'), isTrue);
    expect(formatter.formatEditUpdate(result, result), result);
  });

  test('la casse du schéma est conservée', () {
    const prefix = ' \t\n\uFEFF\u200B';
    for (final scheme in <String>[
      'HtTp://',
      'HtTpS://',
      'HTTP://',
      'HTTPS://'
    ]) {
      final String input = '$prefix${scheme}server.invalid:8080/path';
      expect(apply(input).text, input);
    }
  });

  test('taper http:// lettre par lettre n’insère jamais de s', () {
    const target = 'http://panel.invalid:8080';
    var previous = TextEditingValue.empty;
    final buffer = StringBuffer();
    for (final int code in target.codeUnits) {
      buffer.writeCharCode(code);
      final String soFar = buffer.toString();
      final next = formatter.formatEditUpdate(previous, valueOf(soFar));
      expect(next.text, soFar, reason: 'après « $soFar »');
      expect(next.text.contains('https'), isFalse);
      previous = next;
    }
  });

  test('taper https:// lettre par lettre garde le s déjà saisi', () {
    const target = 'https://panel.invalid';
    var previous = TextEditingValue.empty;
    final buffer = StringBuffer();
    for (final int code in target.codeUnits) {
      buffer.writeCharCode(code);
      final String soFar = buffer.toString();
      final next = formatter.formatEditUpdate(previous, valueOf(soFar));
      expect(next.text, soFar, reason: 'après « $soFar »');
      previous = next;
    }
    expect(previous.text, target);
  });

  for (final text in <String>[
    'http://server.invalid/list.m3u',
    'https://server.invalid/list.m3u',
    'ftp://server.invalid/list.m3u',
    'server.invalid/list.m3u?next=https://nested.invalid',
    'prefix https://server.invalid',
    'http:',
    'https:',
    'https:/',
    '',
  ]) {
    test('aucun schéma n’est réécrit : $text', () {
      final value = valueOf(text);
      expect(formatter.formatEditUpdate(TextEditingValue.empty, value), value);
    });
  }

  test('curseur, sélection et composition IME restent en place', () {
    const input = 'https://server.invalid/list.m3u';
    final selection = apply(input,
        selection: const TextSelection(
            baseOffset: 4,
            extentOffset: 8,
            affinity: TextAffinity.upstream,
            isDirectional: true));
    expect(selection.text, input);
    expect(selection.selection.baseOffset, 4);
    expect(selection.selection.extentOffset, 8);
    expect(selection.selection.affinity, TextAffinity.upstream);
    expect(selection.selection.isDirectional, isTrue);

    const composing = TextEditingValue(
      text: 'http://server.invalid/list.m3u',
      selection: TextSelection.collapsed(offset: 12),
      composing: TextRange(start: 7, end: 13),
    );
    expect(formatter.formatEditUpdate(TextEditingValue.empty, composing),
        composing);
  });

  test('HTTP clair autorisé pour la lecture et la connexion, HTTPS inchangé',
      () {
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final String config = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();
    expect(
        manifest,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ));
    expect(manifest, contains('android:usesCleartextTraffic="true"'));
    expect(config, contains('cleartextTrafficPermitted="true"'));
    expect(config.contains('cleartextTrafficPermitted="false"'), isFalse);
  });
}
