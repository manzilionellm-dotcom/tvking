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
  }

  Future<void> _toggleMissed() async {
    await missedShowFlag.load();
    await missedShowFlag.set(!missedShowFlag.value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool on = missedShowFlag.value;
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
