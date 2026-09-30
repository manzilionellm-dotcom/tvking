// =========================================================
//  voice_mic_button.dart — Bouton micro de la recherche
// =========================================================
//  OK lance l'écoute. Si le micro manque, on l'écrit sous
//  le bouton. Le clavier à côté n'est pas retiré.
// =========================================================

import 'package:flutter/material.dart';

import '../../box_extras/box_text.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_focusable.dart';
import '../../tv/core/tv_tokens.dart';
import '../data/voice_search.dart';

class VoiceMicButton extends StatefulWidget {
  const VoiceMicButton({super.key, required this.onText});

  final ValueChanged<String> onText;

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton> {
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    VoiceSearch.flag.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _listen() async {
    if (_busy) return;
    await VoiceSearch.flag.load();
    if (!VoiceSearch.flag.value) {
      setState(() {
        _note = boxText(
          context,
          'Micro coupé dans « En plus ». Le clavier reste là.',
          'Mic is off in Extras. The keyboard stays.',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _note = boxText(context, 'Parle…', 'Speak…');
    });
    final String lang = Localizations.localeOf(context).languageCode;
    final VoiceOutcome outcome = await VoiceSearch.listen(lang);
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome.hasText) {
      setState(() => _note = null);
      widget.onText(outcome.text!);
      return;
    }
    setState(() => _note = _reason(outcome.reason));
  }

  String _reason(String? reason) {
    switch (reason) {
      case 'permission':
        return boxText(
          context,
          'Autorise le micro, puis réessaie. Le clavier reste là.',
          'Allow the mic, then try again. The keyboard stays.',
        );
      case 'off':
        return boxText(
          context,
          'Micro coupé. Le clavier reste là.',
          'Mic is off. The keyboard stays.',
        );
      default:
        return boxText(
          context,
          'Micro indisponible. Le clavier reste là.',
          'Mic unavailable. The keyboard stays.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TvFocusable(
            onSelect: _listen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    _busy ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: TvTokens.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    boxText(context, 'Micro', 'Mic'),
                    style: TextStyle(
                      fontSize: TvDimens.titleS,
                      fontWeight: FontWeight.w700,
                      color: TvTokens.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 8),
              child: Text(
                _note!,
                style: TextStyle(fontSize: TvDimens.label, color: TvTokens.muted),
              ),
            ),
        ],
      ),
    );
  }
}
