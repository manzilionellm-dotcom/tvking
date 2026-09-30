// =========================================================
//  voice_query_test.dart — phrases du micro
// =========================================================
//  Aucun micro, aucun réseau : on vérifie seulement que la phrase
//  est rangée au bon endroit (guide du soir, ou recherche).
// =========================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/voice/data/voice_remote_assist.dart';
import 'package:tv_king/features/voice/domain/voice_keys.dart';
import 'package:tv_king/features/voice/domain/voice_query.dart';

void main() {
  test('question du soir, dans plusieurs langues', () {
    const List<String> phrases = <String>[
      "Qu'est-ce qu'il y a ce soir ?",
      'ce soir',
      "what's on tonight",
      'what is on tonight',
      'esta noche',
      'un film ce soir',
    ];
    for (final String p in phrases) {
      expect(interpretVoice(p).kind, VoiceIntentKind.tonight, reason: p);
    }
  });

  test('un titre reste une recherche, même avec « ce soir »', () {
    final VoiceIntent tf1 = interpretVoice('cherche TF1');
    expect(tf1.kind, VoiceIntentKind.catalog);
    expect(tf1.catalogQuery, 'tf1');

    final VoiceIntent marked = interpretVoice('TF1 ce soir');
    expect(marked.kind, VoiceIntentKind.catalog);
    expect(marked.catalogQuery, 'tf1');

    expect(interpretVoice('Amélie').catalogQuery, 'amelie');
    expect(interpretVoice('mets le grand journal').catalogQuery, 'grand journal');
  });

  test('vide, emoji, phrase très longue : pas d\'exception', () {
    expect(interpretVoice('   ').kind, VoiceIntentKind.empty);
    expect(interpretVoice('???').kind, VoiceIntentKind.empty);
    expect(interpretVoice('🎬').kind, VoiceIntentKind.empty);
    final VoiceIntent huge = interpretVoice('a' * 5000);
    expect(huge.kind, VoiceIntentKind.catalog);
    expect(huge.catalogQuery.length, lessThan(400));
  });

  test('touches micro de la télécommande', () {
    expect(VoiceKeys.isMicLogical(LogicalKeyboardKey.browserSearch), isTrue);
    expect(VoiceKeys.isMicLogical(LogicalKeyboardKey.launchAssistant), isTrue);
    expect(VoiceKeys.isMicLogical(LogicalKeyboardKey.keyA), isFalse);
    expect(
      VoiceKeys.isMicLogical(
        LogicalKeyboardKey(VoiceKeys.androidPlane | VoiceKeys.keyVoiceAssist),
      ),
      isTrue,
    );
    expect(
      VoiceKeys.isMicLogical(
        LogicalKeyboardKey(VoiceKeys.androidPlane | VoiceKeys.keySearch),
      ),
      isTrue,
    );
    expect(
      VoiceKeys.isMicLogical(LogicalKeyboardKey(VoiceKeys.androidPlane | 20)),
      isFalse,
    );
  });

  test('aide distante désactivée tant qu\'on ne l\'a pas demandée', () {
    expect(VoiceRemoteAssist.enabledFromStored(null), isFalse);
    expect(VoiceRemoteAssist.enabledFromStored(false), isFalse);
    expect(VoiceRemoteAssist.enabledFromStored(true), isTrue);
  });
}
