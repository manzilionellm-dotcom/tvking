// =========================================================
//  voice_search.dart — Recherche parlée, avec repli
// =========================================================
//  Android seulement, via SpeechRecognizer (MainActivity).
//  Le résultat est un texte, ou une raison de repli. On ne
//  lance jamais de chaîne ici : l'écran de recherche décide
//  quoi faire du texte, et le clavier reste en place.
// =========================================================

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../box_extras/box_flag.dart';

class VoiceOutcome {
  const VoiceOutcome._({this.text, this.reason});

  final String? text;
  final String? reason;

  bool get hasText => text != null && text!.isNotEmpty;

  static VoiceOutcome fromChannel(Object? raw) {
    if (raw is! Map) return const VoiceOutcome._(reason: 'unavailable');
    final bool ok = raw['ok'] == true;
    final String text = (raw['text'] as String?)?.trim() ?? '';
    if (ok && text.isNotEmpty) return VoiceOutcome._(text: text);
    final String reason = (raw['reason'] as String?)?.trim() ?? '';
    return VoiceOutcome._(reason: reason.isEmpty ? 'empty' : reason);
  }
}

class VoiceSearch {
  VoiceSearch._();

  static final BoxFlag flag = BoxFlag('zuno.flag.voice_search');
  static const MethodChannel _channel = MethodChannel('zuno/voice_search');

  static Future<VoiceOutcome> listen(String languageCode) async {
    await flag.load();
    if (!flag.value) return const VoiceOutcome._(reason: 'off');
    if (kIsWeb || !Platform.isAndroid) {
      return const VoiceOutcome._(reason: 'unavailable');
    }
    try {
      final Object? raw = await _channel.invokeMethod<Object>(
        'listen',
        <String, Object>{'locale': languageCode},
      );
      return VoiceOutcome.fromChannel(raw);
    } catch (_) {
      return const VoiceOutcome._(reason: 'unavailable');
    }
  }
}
