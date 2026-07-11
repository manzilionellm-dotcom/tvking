// =========================================================
//  tv_legal_screen.dart — Mentions légales & Conditions d'utilisation
// =========================================================
//  POSITIONNEMENT JURIDIQUE (comme les lecteurs sérieux : TiviMate, OTT
//  Navigator…) : l'app est un LECTEUR multimédia neutre. Elle NE VEND, NE
//  FOURNIT, N'HÉBERGE AUCUNE chaîne ni lien M3U. L'abonnement éventuel rémunère
//  le LOGICIEL, pas le contenu. Affiché en clair pour limiter le risque de
//  retrait/bannissement et clarifier les responsabilités.
//
//  Le MÊME texte est servi en ligne par le worker sur app.7themotion.com/terms
//  (à coller dans la fiche des stores).
//
//  Défilement à la télécommande : Haut/Bas font défiler le texte (D-pad), Retour
//  quitte l'écran.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';

class TvLegalScreen extends StatefulWidget {
  const TvLegalScreen({super.key});

  @override
  State<TvLegalScreen> createState() => _TvLegalScreenState();
}

class _TvLegalScreenState extends State<TvLegalScreen> {
  final ScrollController _sc = ScrollController();
  final FocusNode _focus = FocusNode();

  // (titre, corps) — texte identique à la page /terms du worker.
  List<(String, String)> _sections(AppLocalizations l10n) => <(String, String)>[
        (l10n.tvLegalSection1Title, l10n.tvLegalSection1Body),
        (l10n.tvLegalSection2Title, l10n.tvLegalSection2Body),
        (l10n.tvLegalSection3Title, l10n.tvLegalSection3Body),
        (l10n.tvLegalSection4Title, l10n.tvLegalSection4Body),
        (l10n.tvLegalSection5Title, l10n.tvLegalSection5Body),
        (l10n.tvLegalSection6Title, l10n.tvLegalSection6Body),
        (l10n.tvLegalSection7Title, l10n.tvLegalSection7Body),
        (l10n.tvLegalSection8Title, l10n.tvLegalSection8Body),
        (l10n.tvLegalSection9Title, l10n.tvLegalSection9Body),
      ];

  @override
  void dispose() {
    _sc.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_sc.hasClients) return KeyEventResult.ignored;
    const double step = 140;
    final LogicalKeyboardKey k = event.logicalKey;
    double? target;
    if (k == LogicalKeyboardKey.arrowDown) {
      target = _sc.offset + step;
    } else if (k == LogicalKeyboardKey.arrowUp) {
      target = _sc.offset - step;
    }
    if (target == null) return KeyEventResult.ignored;
    _sc.animateTo(
      target.clamp(0, _sc.position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: SingleChildScrollView(
        controller: _sc,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.l10n.tvLegalTitle,
                style: TextStyle(
                    fontSize: TvDimens.displayM,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
            const SizedBox(height: 8),
            Text(
              context.l10n.tvLegalIntro,
              style: TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim),
            ),
            const SizedBox(height: 24),
            for (final (String title, String body)
                in _sections(context.l10n)) ...<Widget>[
              Text(title,
                  style: TextStyle(
                      fontSize: TvDimens.title,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.goldBright)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Text(body,
                    style: TextStyle(
                        fontSize: TvDimens.body,
                        height: 1.5,
                        color: TvTokens.muted)),
              ),
              const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}
