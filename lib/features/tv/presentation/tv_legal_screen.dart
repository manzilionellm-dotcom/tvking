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
  static const List<(String, String)> _sections = <(String, String)>[
    (
      '1. Nature de l\'application — un LECTEUR, rien d\'autre',
      'Cette application est un LECTEUR multimédia (player) permettant de lire '
          'des flux audio/vidéo fournis par l\'utilisateur. Elle NE FOURNIT PAS, '
          'NE VEND PAS, N\'HÉBERGE PAS, NE DIFFUSE PAS et N\'INDEXE AUCUNE chaîne '
          'de télévision, flux, contenu audiovisuel, ni liste de lecture (M3U) ou '
          'identifiants de portail (Xtream). Aucun contenu n\'est inclus, '
          'préchargé ou commercialisé avec l\'application.',
    ),
    (
      '2. Contenu fourni par l\'utilisateur',
      'L\'utilisateur fournit lui-même ses propres sources (lien M3U / '
          'identifiants Xtream), obtenues auprès de son propre fournisseur. '
          'L\'utilisateur est SEUL responsable des contenus qu\'il ajoute, lit ou '
          'diffuse, ainsi que de la détention des droits, licences et abonnements '
          'nécessaires.',
    ),
    (
      '3. Abonnement = le LOGICIEL, pas le contenu',
      'Tout paiement ou abonnement éventuel rémunère UNIQUEMENT l\'utilisation de '
          'l\'application (le lecteur et ses fonctionnalités : interface, favoris, '
          'enregistrement local, EPG…). Il ne constitue EN AUCUN CAS l\'achat, la '
          'vente, la location ou la fourniture de chaînes, de flux ou de contenus.',
    ),
    (
      '4. Usage licite',
      'L\'utilisateur s\'engage à utiliser l\'application conformément aux lois en '
          'vigueur dans son pays et à ne pas l\'utiliser pour accéder à des '
          'contenus illégaux ou portant atteinte aux droits d\'auteur. Toute '
          'utilisation illicite est strictement interdite et relève de la seule '
          'responsabilité de l\'utilisateur.',
    ),
    (
      '5. Contenus tiers — absence de responsabilité',
      'L\'éditeur n\'a aucun contrôle sur les contenus tiers accessibles via les '
          'sources fournies par l\'utilisateur et ne saurait en être tenu '
          'responsable. Il ne garantit ni la disponibilité, ni la légalité, ni la '
          'qualité de ces contenus.',
    ),
    (
      '6. Propriété intellectuelle & réclamations',
      'Toutes les marques, logos et contenus appartiennent à leurs propriétaires '
          'respectifs. L\'application n\'hébergeant aucun contenu, toute '
          'réclamation relative à des droits d\'auteur doit être adressée au '
          'fournisseur de la source concernée.',
    ),
    (
      '7. Fourniture « en l\'état »',
      'L\'application est fournie « telle quelle », sans garantie de '
          'disponibilité continue ni d\'absence d\'erreurs. L\'éditeur peut faire '
          'évoluer ou suspendre tout ou partie des fonctionnalités.',
    ),
    (
      '8. Données personnelles',
      'Un identifiant technique d\'appareil est utilisé pour la gestion de la '
          'licence/essai et le support. Détails : app.7themotion.com/privacy.',
    ),
    (
      '9. Acceptation',
      'En installant ou en utilisant cette application, l\'utilisateur reconnaît '
          'avoir lu et accepté les présentes conditions. Version complète en '
          'ligne : app.7themotion.com/terms',
    ),
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
            for (final (String title, String body) in _sections) ...<Widget>[
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
