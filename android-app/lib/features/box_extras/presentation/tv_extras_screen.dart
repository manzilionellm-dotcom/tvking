// =========================================================
//  tv_extras_screen.dart — Les fonctions en plus, une par ligne
// =========================================================
//  Chaque ligne ouvre UNE fonction, ou la coupe. Rien ici
//  n'ouvre un flux.
// =========================================================

import 'package:flutter/material.dart';

import '../../phone_remote/presentation/phone_remote_screen.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_focusable.dart';
import '../../tv/core/tv_tokens.dart';
import '../../tv/presentation/tv_shell.dart';
import '../box_text.dart';

class TvExtrasScreen extends StatelessWidget {
  const TvExtrasScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
        _Row(
          autofocus: true,
          title: boxText(context, 'Téléphone', 'Phone'),
          subtitle: boxText(
            context,
            'QR code : le téléphone devient la télécommande.',
            'QR code: the phone becomes the remote.',
          ),
          onSelect: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: PhoneRemoteScreen()),
              ),
            );
          },
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

class _Row extends ExtrasRow {
  const _Row({
    required super.title,
    required super.subtitle,
    required super.onSelect,
    super.autofocus,
  });
}
