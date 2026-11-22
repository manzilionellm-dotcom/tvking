// =========================================================
//  tv_legal_screen.dart — Mentions légales & Conditions d'utilisation
// =========================================================
//  POSITIONNEMENT JURIDIQUE (comme les lecteurs sérieux : TiviMate, OTT
//  Navigator…) : l'app est un LECTEUR multimédia neutre. Elle NE VEND, NE
//  FOURNIT, N'HÉBERGE AUCUNE chaîne ni lien M3U. L'abonnement éventuel rémunère
//  le LOGICIEL, pas le contenu. Affiché en clair pour limiter le risque de
//  retrait/bannissement et clarifier les responsabilités.
//
//  Les conditions génériques restent celles du worker historique. L'édition
//  NOVATUBE MAX possède sa propre politique de confidentialité publiée : son
//  résumé et son lien remplacent uniquement la section Données personnelles.
//
//  Défilement à la télécommande : Haut/Bas font défiler le texte (D-pad), Retour
//  quitte l'écran.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app/novatube_privacy.dart';
import '../../../core/app/novatube_tv_edition.dart';
import '../../../core/i18n/l10n_extension.dart';

import '../core/tv_dimens.dart';
import '../core/tv_app_tokens.dart';

class TvLegalScreen extends StatefulWidget {
  const TvLegalScreen({super.key});

  @override
  State<TvLegalScreen> createState() => _TvLegalScreenState();
}

class _TvLegalScreenState extends State<TvLegalScreen> {
  final ScrollController _sc = ScrollController();
  final FocusNode _focus = FocusNode();
  final FocusNode _privacyFocus = FocusNode();
  bool _openingPrivacy = false;
  bool _privacyUnavailable = false;

  String get _languageCode => Localizations.localeOf(context).languageCode;
  Uri get _privacyUri => novatubePrivacyUri(_languageCode);

  // (titre, corps) — conditions génériques traduites au rendu. Seule la
  // confidentialité MAX utilise le résumé de sa propre politique publiée.
  List<(String, String)> get _sections => <(String, String)>[
    (context.l10n.tvLegalSection1Title, context.l10n.tvLegalSection1Body),
    (context.l10n.tvLegalSection2Title, context.l10n.tvLegalSection2Body),
    (context.l10n.tvLegalSection3Title, context.l10n.tvLegalSection3Body),
    (context.l10n.tvLegalSection4Title, context.l10n.tvLegalSection4Body),
    (context.l10n.tvLegalSection5Title, context.l10n.tvLegalSection5Body),
    (context.l10n.tvLegalSection6Title, context.l10n.tvLegalSection6Body),
    (context.l10n.tvLegalSection7Title, context.l10n.tvLegalSection7Body),
    (
      context.l10n.tvLegalSection8Title,
      kNovatubeTv
          ? novatubePrivacySummary(_languageCode)
          : context.l10n.tvLegalSection8Body,
    ),
    (context.l10n.tvLegalSection9Title, context.l10n.tvLegalSection9Body),
  ];

  @override
  void dispose() {
    _sc.dispose();
    _focus.dispose();
    _privacyFocus.dispose();
    super.dispose();
  }

  Future<void> _openPrivacy() async {
    if (_openingPrivacy) return;
    setState(() {
      _openingPrivacy = true;
      _privacyUnavailable = false;
    });
    bool opened = false;
    try {
      opened = await launchUrl(
        _privacyUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Une TV sans navigateur conserve le résumé et l'adresse à l'écran.
    }
    if (!mounted) return;
    setState(() {
      _openingPrivacy = false;
      _privacyUnavailable = !opened;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_sc.hasClients) return KeyEventResult.ignored;
    const double step = 140;
    final LogicalKeyboardKey k = event.logicalKey;
    if (kNovatubeTv) {
      // Le lien est le premier contrôle au D-pad. Bas rend le focus au texte
      // pour conserver le défilement existant ; Haut, en début de page, revient
      // au lien. Entrée/OK reste géré normalement par le bouton Material.
      if (k == LogicalKeyboardKey.arrowDown && _privacyFocus.hasFocus) {
        _focus.requestFocus();
      } else if (k == LogicalKeyboardKey.arrowUp && _sc.offset <= 0) {
        _privacyFocus.requestFocus();
        return KeyEventResult.handled;
      }
    }
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
      autofocus: !kNovatubeTv,
      onKeyEvent: _onKey,
      child: SingleChildScrollView(
        controller: _sc,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.tvLegalTitle,
              style: TextStyle(
                fontSize: TvDimens.displayM,
                fontWeight: FontWeight.w800,
                color: TvAppTokens.of(context).text,
              ),
            ),
            const SizedBox(height: 8),
            if (kNovatubeTv) ...<Widget>[
              TextButton.icon(
                key: const ValueKey<String>('novatube-privacy-link'),
                focusNode: _privacyFocus,
                autofocus: true,
                onPressed: _openingPrivacy ? null : _openPrivacy,
                icon: const Icon(Icons.open_in_new),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(context.l10n.aboutPrivacyPolicy),
                    Text(
                      _privacyUri.toString(),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
                style:
                    TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor: TvAppTokens.of(context).accentBright,
                      textStyle: TextStyle(fontSize: TvDimens.body),
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith(
                        (Set<WidgetState> states) =>
                            states.contains(WidgetState.focused)
                            ? BorderSide(
                                color: TvAppTokens.of(context).accent,
                                width: TvDimens.focusOutline,
                              )
                            : null,
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (Set<WidgetState> states) =>
                            states.contains(WidgetState.focused)
                            ? TvAppTokens.of(context).sel
                            : null,
                      ),
                    ),
              ),
              if (_privacyUnavailable)
                Text(
                  context.l10n.subCantOpenUrl(_privacyUri.toString()),
                  style: TextStyle(
                    fontSize: TvDimens.body,
                    color: TvAppTokens.of(context).muted,
                  ),
                ),
              const SizedBox(height: 8),
            ],
            Text(
              context.l10n.tvLegalLead,
              style: TextStyle(
                fontSize: TvDimens.body,
                color: TvAppTokens.of(context).mutedDim,
              ),
            ),
            const SizedBox(height: 24),
            for (final (String title, String body) in _sections) ...<Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: TvDimens.title,
                  fontWeight: FontWeight.w800,
                  color: TvAppTokens.of(context).accentBright,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Text(
                  body,
                  style: TextStyle(
                    fontSize: TvDimens.body,
                    height: 1.5,
                    color: TvAppTokens.of(context).muted,
                  ),
                ),
              ),
              const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}
