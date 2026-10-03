// =========================================================
//  voice_capture.dart — Micro de la télécommande (côté Dart)
// =========================================================
//  Le vrai travail (SpeechRecognizer / intent de recherche) est dans le
//  plugin `zuno_voice`, pour survivre au `flutter create` du build TV.
//  Ici on ne fait qu'appeler, et on RATTRAPE tout :
//    • pas Android (PC) ;
//    • plugin absent ;
//    • box sans micro ou sans application de reconnaissance.
//  Dans tous ces cas on renvoie « indisponible ». Le clavier à l'écran
//  continue. On ne lance jamais d'exception vers l'écran, et on n'appelle
//  pas ceci pendant qu'une chaîne est ouverte (VoiceHotkey).
// =========================================================

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:zuno_voice/zuno_voice.dart';

import '../../player/domain/audio_sources.dart';

/// Pourquoi la reconnaissance s'est arrêtée.
enum VoiceListenStatus {
  ok,
  empty,
  unavailable,
  cancelled,
  failed,
  busy,
}

class VoiceListenResult {
  const VoiceListenResult(this.status, [this.text]);

  final VoiceListenStatus status;
  final String? text;

  static const VoiceListenResult unavailable =
      VoiceListenResult(VoiceListenStatus.unavailable);

  bool get isOk => status == VoiceListenStatus.ok && (text ?? '').isNotEmpty;
}

abstract final class VoiceCapture {
  static const MethodChannel _channel = MethodChannel(kZunoVoiceChannel);

  static bool _handlerInstalled = false;

  /// Dialogue encore compté : le système n'a pas répondu dans le délai.
  /// La prochaine écoute le solde. On ne ferme pas le dialogue nous-mêmes.
  static int? _stuckMic;

  /// Vrai sur Android. Ailleurs (Windows, test) : pas de micro natif.
  static bool get platformHasVoice {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Branche le retour « la box a déjà reconnu une phrase »
  /// (bouton micro qui envoie ACTION_SEARCH). À appeler une fois
  /// au démarrage de l'UI TV. N'échoue jamais.
  static void install(void Function(String query) onQuery) {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    if (!platformHasVoice) return;
    try {
      _channel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'onVoiceQuery' && call.arguments is String) {
          final String q = (call.arguments as String).trim();
          if (q.isNotEmpty) onQuery(q);
        }
        return null;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Voix] handler non branché : $e');
    }
  }

  /// Phrase déjà reconnue par le système (micro télécommande) et pas
  /// encore lue. `null` si rien, ou si le plugin n'est pas là.
  static Future<String?> takePending() async {
    if (!platformHasVoice) return null;
    try {
      final String? q = await _channel
          .invokeMethod<String>('takePending')
          .timeout(const Duration(seconds: 2));
      final String trimmed = (q ?? '').trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (e) {
      if (kDebugMode) debugPrint('[Voix] pas de phrase en attente : $e');
      return null;
    }
  }

  /// Ouvre la reconnaissance du système. Ne lève jamais.
  static Future<VoiceListenResult> listen() async {
    if (!platformHasVoice) return VoiceListenResult.unavailable;
    // Le dialogue du système peut passer l'appareil en mode
    // communication. On le compte, on ne le ferme pas nous-mêmes
    // avant la réponse : le fermer changerait le comportement.
    final int? stuck = _stuckMic;
    _stuckMic = null;
    if (stuck != null) AudioSources.release(stuck);
    final int mic = AudioSources.acquire(AudioSources.voix);
    AudioSources.setPresence(mic, AudioPresence.mic);
    try {
      final Object? raw = await _channel
          .invokeMethod<Object?>('listen')
          .timeout(const Duration(seconds: 25));
      return _parse(raw);
    } on TimeoutException {
      // Le dialogue système n'est pas revenu. On lâche l'écran ;
      // la réponse tardive, si elle arrive, est ignorée côté Kotlin
      // seulement si un nouvel appel a pris la place. Ici on dégrade.
      // Le compteur RESTE : le micro peut encore tenir le mode audio.
      _stuckMic = mic;
      return const VoiceListenResult(VoiceListenStatus.failed);
    } catch (e) {
      if (kDebugMode) debugPrint('[Voix] écoute impossible : $e');
      return VoiceListenResult.unavailable;
    } finally {
      if (_stuckMic != mic) AudioSources.release(mic);
    }
  }

  static VoiceListenResult _parse(Object? raw) {
    if (raw is! Map) return VoiceListenResult.unavailable;
    final String status = (raw['status'] as String?) ?? 'failed';
    final String text = ((raw['text'] as String?) ?? '').trim();
    switch (status) {
      case 'ok':
        if (text.isEmpty) {
          return const VoiceListenResult(VoiceListenStatus.empty);
        }
        return VoiceListenResult(VoiceListenStatus.ok, text);
      case 'empty':
        return const VoiceListenResult(VoiceListenStatus.empty);
      case 'cancelled':
        return const VoiceListenResult(VoiceListenStatus.cancelled);
      case 'busy':
        return const VoiceListenResult(VoiceListenStatus.busy);
      case 'unavailable':
        return VoiceListenResult.unavailable;
      default:
        return const VoiceListenResult(VoiceListenStatus.failed);
    }
  }
}
