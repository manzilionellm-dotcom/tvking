// =========================================================
//  tv_extras_screen.dart — Les fonctions en plus, une par ligne
// =========================================================
//  Chaque ligne ouvre UNE fonction, ou la coupe. Rien ici
//  n'ouvre un flux. La télécommande, les profils et la voix
//  ont leur propre entrée (Réglages, accueil) : on ne les
//  redouble pas ici.
// =========================================================

import 'package:flutter/material.dart';

import '../../followed/data/followed_flag.dart';
import '../../followed/data/followed_lead.dart';
import '../../followed/domain/show_clock.dart';
import '../../followed/domain/show_lines.dart';
import '../../missed_show/data/missed_flag.dart';
import '../../time_picks/data/time_pick_flag.dart';
import '../../player/data/clear_voice_flag.dart';
import '../../player/data/image_prefs.dart';
import '../../player/domain/image_engine.dart';
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
  int _lead = kLeadDefault;

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
    ImagePrefs.load().then((_) {
      if (mounted) setState(() {});
    });
    followedFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    FollowedLead.load().then((int minutes) {
      if (mounted) setState(() => _lead = minutes);
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

  Future<void> _cycleEngine() async {
    await ImagePrefs.load();
    final EngineStep step = EngineStep.next(
      ImagePrefs.engine,
      ffmpegVideo: false,
    );
    await ImagePrefs.setEngine(step.engine);
    if (mounted) setState(() {});
  }

  Future<void> _toggleFps() async {
    await ImagePrefs.load();
    await ImagePrefs.setFrameRateMatch(!ImagePrefs.frameRateMatch);
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoice() async {
    await ClearVoiceFlag.load();
    await ClearVoiceFlag.set(!ClearVoiceFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleFollowed() async {
    await followedFlag.load();
    await followedFlag.set(!followedFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _cycleLead() async {
    final int next = nextLead(_lead);
    await FollowedLead.set(next);
    if (mounted) setState(() => _lead = FollowedLead.value);
  }

  @override
  Widget build(BuildContext context) {
    final bool on = missedShowFlag.value;
    final bool timeOn = timePicksFlag.value;
    final bool subsOn = subtitlesFlag.value;
    final bool voiceOn = ClearVoiceFlag.value;
    final bool fpsOn = ImagePrefs.frameRateMatch;
    final String engine = switch (ImagePrefs.engine) {
      ImageEngine.software => 'Logiciel',
      ImageEngine.ffmpeg => 'FFmpeg',
      ImageEngine.hardware => 'Matériel',
    };
    final bool followOn = followedFlag.value;
    final String code = Localizations.localeOf(context).languageCode;
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
          title: followedWord(code, 'row'),
          subtitle: followOn
              ? followedWord(code, 'setOn')
              : followedWord(code, 'setOff'),
          onSelect: _toggleFollowed,
        ),
        ExtrasRow(
          title: leadLine(code, _lead),
          subtitle: leadHint(code),
          onSelect: _cycleLead,
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
                  'Coupé, c\'est le réglage d\'origine. OK pour baisser un peu les voix trop fortes. Le son surround envoyé tel quel à la barre de son ne change pas.',
                  'Off, which is the original setting. OK to ease voices that are too loud. Surround sent as-is to a soundbar does not change.',
                ),
          onSelect: _toggleVoice,
        ),
        ExtrasRow(
          title: boxText(context, 'Moteur image', 'Picture engine'),
          subtitle: boxText(
            context,
            'Maintenant : $engine. OK pour changer. Matériel = la box (réglage d\'origine). Logiciel = si l\'image est noire. FFmpeg vidéo n\'est pas dans cette version : OK le saute.',
            'Now: $engine. OK to change. Hardware = the box (original). Software = if the picture stays black. FFmpeg video is not in this version: OK skips it.',
          ),
          onSelect: _cycleEngine,
        ),
        ExtrasRow(
          title: boxText(context, 'Fréquence de l\'écran', 'Screen refresh'),
          subtitle: fpsOn
              ? boxText(
                  context,
                  'Allumé. L\'écran peut passer en 24, 50 ou 60 Hz selon le flux. OK pour couper. Sur certaines box ça coupe l\'image une seconde : si ça arrive, coupe.',
                  'On. The screen may switch to 24, 50 or 60 Hz to match the stream. OK to turn off. On some boxes the picture drops for a second: if it does, turn it off.',
                )
              : boxText(
                  context,
                  'Coupé, c\'est le réglage d\'origine. OK pour caler l\'écran sur 24 / 25 / 30 / 50 / 60 images par seconde. On ne le fait pas tout seul.',
                  'Off, which is the original setting. OK to match the screen to 24 / 25 / 30 / 50 / 60 frames per second. It never turns on by itself.',
                ),
          onSelect: _toggleFps,
        ),
        ExtrasRow(
          title: boxText(context, 'Contraste', 'Contrast'),
          subtitle: boxText(
            context,
            'Pas disponible. Le seul filtre Android quitte l\'image directe et a déjà fait des écrans noirs. On ne l\'allume pas.',
            'Not available. The only Android filter leaves the direct picture path and has made black screens before. It stays off.',
          ),
          onSelect: () {},
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
                style:
                    TextStyle(fontSize: TvDimens.label, color: TvTokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
