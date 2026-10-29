import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/source_http_input_formatter.dart';

void main() {
  const formatter = SourceHttpInputFormatter();
  TextEditingValue apply(String text, {TextSelection? selection,
      TextRange composing = TextRange.empty}) => formatter.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: text,
      selection: selection ?? TextSelection.collapsed(offset: text.length),
      composing: composing),
  );

  test('seul le s du protocole initial est supprimé, le reste est identique', () {
    const input = 'https://user:pass@server.invalid:8443/list.m3u?next=https://cdn.invalid/master.m3u8&token=A%2bB%2Fc';
    const expected = 'http://user:pass@server.invalid:8443/list.m3u?next=https://cdn.invalid/master.m3u8&token=A%2bB%2Fc';
    final result = apply(input);
    expect(result.text, expected);
    expect(result.selection.baseOffset, expected.length);
    expect(result.selection.extentOffset, expected.length);
    expect(result.composing, TextRange.empty);
    expect(formatter.formatEditUpdate(result, result), result,
        reason: 'la transformation reste idempotente');
  });

  test('espaces et caractères invisibles initiaux conservés, casse conservée', () {
    const prefix = ' \t\n\uFEFF\u200B\u200C\u200D\u2060';
    const input = '${prefix}HtTpS://server.invalid:8080/path?url=https://nested.invalid';
    const expected = '${prefix}HtTp://server.invalid:8080/path?url=https://nested.invalid';
    expect(apply(input).text, expected);
    expect(apply(input).selection.extentOffset, expected.length);
    expect(apply(input, selection: TextSelection.collapsed(
        offset: prefix.length + 2)).selection.extentOffset, prefix.length + 2);
    expect(apply(input, selection: TextSelection.collapsed(
        offset: prefix.length + 6)).selection.extentOffset, prefix.length + 5);
  });

  for (final text in <String>[
    'http://server.invalid/list.m3u',
    'ftp://server.invalid/list.m3u',
    'server.invalid/list.m3u?next=https://nested.invalid',
    'prefix https://server.invalid',
    'https:',
    'https:/',
    '',
  ]) {
    test('saisie sans préfixe HTTPS complet inchangée : $text', () {
      final value = TextEditingValue(text: text,
          selection: TextSelection.collapsed(offset: text.length));
      expect(formatter.formatEditUpdate(TextEditingValue.empty, value), value);
    });
  }

  test('curseur avant, sur et après le caractère supprimé', () {
    const input = 'https://server.invalid/list.m3u';
    for (final entry in <int, int>{0: 0, 3: 3, 4: 4, 5: 4, 8: 7,
      input.length: input.length - 1}.entries) {
      final result = apply(input,
          selection: TextSelection.collapsed(offset: entry.key));
      expect(result.selection.baseOffset, entry.value, reason: 'position ${entry.key}');
      expect(result.selection.extentOffset, entry.value);
    }
    expect(apply(input, selection: const TextSelection.collapsed(offset: -1))
        .selection, const TextSelection.collapsed(offset: -1));
  });

  test('sélection avant/arrière ajustée sans perdre direction ou affinité', () {
    const input = 'https://server.invalid:8080/list.m3u';
    final forward = apply(input, selection: TextSelection(
      baseOffset: 0, extentOffset: input.length,
      affinity: TextAffinity.upstream, isDirectional: true));
    expect(forward.selection.baseOffset, 0);
    expect(forward.selection.extentOffset, input.length - 1);
    expect(forward.selection.affinity, TextAffinity.upstream);
    expect(forward.selection.isDirectional, isTrue);
    final reverse = apply(input, selection: TextSelection(
      baseOffset: input.length, extentOffset: 2,
      affinity: TextAffinity.upstream, isDirectional: true));
    expect(reverse.selection.baseOffset, input.length - 1);
    expect(reverse.selection.extentOffset, 2);
    expect(reverse.selection.affinity, TextAffinity.upstream);
    expect(reverse.selection.isDirectional, isTrue);
    final removedOnly = apply(input,
        selection: const TextSelection(baseOffset: 4, extentOffset: 5));
    expect(removedOnly.selection.isCollapsed, isTrue);
    expect(removedOnly.selection.extentOffset, 4);
  });

  test('composition IME active intacte, conversion seulement après validation', () {
    const composing = TextEditingValue(
      text: 'https://server.invalid/list.m3u',
      selection: TextSelection.collapsed(offset: 12),
      composing: TextRange(start: 8, end: 14),
    );
    expect(formatter.formatEditUpdate(TextEditingValue.empty, composing), composing);
    final committed = composing.copyWith(composing: TextRange.empty);
    final result = formatter.formatEditUpdate(composing, committed);
    expect(result.text, 'http://server.invalid/list.m3u');
    expect(result.selection.extentOffset, 11);
    expect(result.composing, TextRange.empty);
  });
}
