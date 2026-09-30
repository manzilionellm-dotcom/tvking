// =========================================================
//  tv_extras_screen.dart — Les fonctions en plus, une par ligne
// =========================================================
//  Chaque ligne ouvre UNE fonction, ou la coupe. Rien ici
//  n'ouvre un flux. La télécommande, les profils et la voix
//  ont leur propre entrée (Réglages, accueil) : on ne les
//  redouble pas ici.
// =========================================================

import 'package:flutter/material.dart';

import '../../missed_show/data/missed_flag.dart';
import '../../time_picks/data/time_pick_flag.dart';
import '../../player/data/clear_voice_flag.dart';
import '../../subtitles/data/subtitle_flag.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_focusable.dart';
import '../../tv/core/tv_tokens.dart';
import '../box_text.dart';

class TvExtrasScreen extends StatefulWidget {
  const TvExtrasScreen({super.key});

  @override
  State<TvExtrasScreen> createState() => _TvExtrasScreenState();
}

class _TvExtrasScreenState extends State<TvExtrasScreen> {
  @override
  void initState() {
    super.initState();
    missedShowFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    timePicksFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    subtitlesFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    ClearVoiceFlag.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggleMissed() async {
    await missedShowFlag.load();
    await missedShowFlag.set(!missedShowFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleTime() async {
    await timePicksFlag.load();
    await timePicksFlag.set(!timePicksFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSubs() async {
    await subtitlesFlag.load();
    await subtitlesFlag.set(!subtitlesFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoice() async {
    await ClearVoiceFlag.load();
    await ClearVoiceFlag.set(!ClearVoiceFlag.value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool on = missedShowFlag.value;
    final bool timeOn = timePicksFlag.value;
    final bool subsOn = subtitlesFlag.value;
    final bool voiceOn = ClearVoiceFlag.value;
    return ListView(
      children: <Widget>[
        Text(
          boxText(context, 'En plus', 'Extras'),
          style: TextStyle(
            fontSize: TvDimens.displayM,
            fontWeight: FontWeight.w800,
            color: TvTokens.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          boxText(
            context,
            'Chaque fonction se coupe seule. Aucune ne bloque une chaîne.',
            'Each feature turns off on its own. None of them blocks a channel.',
          ),
          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
        ),
        const SizedBox(height: 18),
        ExtrasRow(
          autofocus: true,
          title: boxText(context, 'En retard', 'Running late'),
          subtitle: on
              ? boxText(
                  context,
                  'Le guide dit ce que tu as raté. OK pour couper. Le direct ne recule pas tout seul.',
                  'The guide says what you missed. OK to turn off. Live never rewinds on its own.',
                )
              : boxText(
                  context,
                  'Coupé. OK pour rallumer. Une chaîne ne sera pas rembobinée.',
                  'Off. OK to turn on. A channel will not be rewound.',
                ),
          onSelect: _toggleMissed,
        ),
        const SizedBox(height: 4),
        ExtrasRow(
          title: boxText(context, 'À cette heure', 'At this hour'),
          subtitle: timeOn
              ? boxText(
                  context,
                  'Propose les chaînes que tu ouvres souvent à ce moment. OK pour couper. Rien ne se lance tout seul.',
                  'Suggests channels you often open at this time. OK to turn off. Nothing starts on its own.',
                )
              : boxText(
                  context,
                  'Coupé. OK pour rallumer. On ne compte plus, et la rangée disparaît.',
                  'Off. OK to turn on. We stop counting, and the row goes away.',
                ),
          onSelect: _toggleTime,
        ),
        ExtrasRow(
          title: boxText(context, 'Sous-titres', 'Subtitles'),
          subtitle: subsOn
              ? boxText(
                  context,
                  'Affiche la piste déjà dans le flux, dans ta langue. OK pour couper. Rien n\'est traduit, rien n\'est téléchargé.',
                  'Shows the track already in the stream, in your language. OK to turn off. Nothing is translated or downloaded.',
                )
              : boxText(
                  context,
                  'Coupé. OK pour rallumer. Le direct ne change pas de flux.',
                  'Off. OK to turn on. Live does not switch streams.',
                ),
          onSelect: _toggleSubs,
        ),
        ExtrasRow(
          title: boxText(context, 'Voix claire', 'Clear voice'),
          subtitle: voiceOn
              ? boxText(
                  context,
                  'Allumé. Les voix fortes sont un peu baissées (mode nuit). OK pour couper. Le son cinéma surround n\'est pas modifié.',
                  'On. Loud voices are eased a bit (night mode). OK to turn off. Surround passthrough is left as it is.',
                )
              : boxText(
                  context,
                  'Coupé, c\'est le réglage d\'origine. OK pour adoucir les écarts de volume entre chaînes.',
                  'Off, which is the original setting. OK to soften volume jumps between channels.',
                ),
          onSelect: _toggleVoice,
        ),
      ],
    );
  }
}

class ExtrasRow extends StatelessWidget {
  const ExtrasRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    this.autofocus = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TvFocusable(
        autofocus: autofocus,
        onSelect: onSelect,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: TvDimens.titleS,
                  fontWeight: FontWeight.w700,
                  color: TvTokens.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: TvDimens.label, color: TvTokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
