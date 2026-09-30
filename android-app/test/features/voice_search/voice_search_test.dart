import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/voice_search/data/voice_search.dart';

void main() {
  test('une réponse vide ou cassée ne donne pas de texte', () {
    expect(VoiceOutcome.fromChannel(null).hasText, isFalse);
    expect(VoiceOutcome.fromChannel(<String, Object>{'ok': false, 'reason': 'unavailable'}).reason,
        'unavailable');
    expect(VoiceOutcome.fromChannel(<String, Object>{'ok': true, 'text': '  TF1  '}).text, 'TF1');
    expect(VoiceOutcome.fromChannel(<String, Object>{'ok': true, 'text': ''}).hasText, isFalse);
  });
}
