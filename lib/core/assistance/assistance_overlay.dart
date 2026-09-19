// =========================================================
//  assistance_overlay.dart — ce que le CLIENT voit
// =========================================================
//  Tout le reste du mode assistance est invisible pour lui : des
//  frames, une machine à états, des accusés. Ce fichier-ci est la
//  seule chose qu'il voit — et c'est donc lui qui décide si le mode
//  est honnête ou pas.
//
//  TROIS RÈGLES, ET ELLES SE VOIENT À L'ŒIL NU :
//
//   1. ON LUI DEMANDE, AVEC UN NOM. « Lionel (7 MOTION) veut vous
//      aider » — jamais « une demande d'assistance ». Il doit savoir
//      qui, sinon il ne peut pas répondre.
//
//   2. PENDANT TOUTE LA SESSION, UN BANDEAU RESTE. Il ne se réduit
//      pas, il ne se cache pas au bout de cinq secondes, il ne se
//      range pas dans un coin. Quelqu'un est dans son appareil : ça
//      doit se voir en permanence, sans avoir à y penser.
//
//   3. LE BOUTON « ARRÊTER » EST DANS LE BANDEAU. Pas dans un menu,
//      pas derrière trois écrans de réglages. À portée de pouce, tout
//      le temps. Une sortie qu'il faut chercher n'est pas une sortie.
//
//  Le bandeau annonce aussi le temps qui reste. C'est rassurant ET
//  c'est vrai : la session s'arrête toute seule, même si tout le monde
//  oublie.
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';

import 'assistance_controller.dart';
import 'assistance_session.dart';

/// Enveloppe l'application. À poser une fois, au-dessus de tout.
///
///  L'ENFANT PASSE TOUJOURS. Un surveillant qui, dans un cas tordu,
///  cesserait de rendre l'app en ferait un écran noir — on a déjà vu
///  ce piège avec l'écran de veille. Ici l'enfant est rendu d'abord,
///  et la surcouche vient PAR-DESSUS.
class AssistanceOverlay extends StatefulWidget {
  const AssistanceOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<AssistanceOverlay> createState() => _AssistanceOverlayState();
}

class _AssistanceOverlayState extends State<AssistanceOverlay> {
  final AssistanceController _c = AssistanceController.instance;
  Timer? _tic;

  @override
  void initState() {
    super.initState();
    _c.addListener(_maj);
  }

  @override
  void dispose() {
    _c.removeListener(_maj);
    _tic?.cancel();
    super.dispose();
  }

  void _maj() {
    if (!mounted) return;
    setState(() {});
    _reglerTic();
  }

  /// Le compte à rebours du bandeau ne tourne QUE pendant une session.
  /// Hors session, aucune minuterie : ce fichier ne coûte alors pas un
  /// seul réveil — même règle que l'écran de veille et l'aperçu vidéo.
  void _reglerTic() {
    _tic?.cancel();
    _tic = null;
    if (_c.etat != EtatAssistance.active) return;
    _tic = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      // `etat` rafraîchit la session au passage : c'est ce qui fait
      // disparaître le bandeau tout seul quand le temps est écoulé.
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final EtatAssistance etat = _c.etat;
    return Stack(
      children: <Widget>[
        widget.child,
        if (etat == EtatAssistance.demandee)
          _Demande(
            support: _c.support,
            onOui: _c.accepter,
            onNon: _c.refuser,
          ),
        if (etat == EtatAssistance.active)
          _Bandeau(
            support: _c.support,
            restant: _c.tempsRestant,
            phrase: _c.designation?.phrase ?? '',
            onArreter: _c.arreterParClient,
          ),
      ],
    );
  }
}

/// « Lionel veut vous aider » — la question, en grand, au milieu.
class _Demande extends StatelessWidget {
  const _Demande({
    required this.support,
    required this.onOui,
    required this.onNon,
  });

  final String support;
  final VoidCallback onOui;
  final VoidCallback onNon;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '$support veut vous aider',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFF0EDE9),
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  //  ON DIT CE QUI VA SE PASSER, sans enjoliver. « Il va
                  //  toucher à votre application » est la vérité ; la
                  //  cacher derrière « assistance à distance » ferait
                  //  accepter quelque chose qu'on n'a pas compris.
                  const Text(
                    'Il pourra ouvrir des écrans et changer des réglages '
                    'sur cet appareil, pendant que vous regardez. Vous '
                    'voyez tout ce qu’il fait, et vous pouvez arrêter '
                    'à tout moment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFB6B0A8), fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Il ne peut ni payer, ni changer votre mot de passe, '
                    'ni votre code parental.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF7E7872), fontSize: 14),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      //  « NON » EN PREMIER ET AUSSI VISIBLE QUE « OUI ».
                      //  Mettre le refus en petit, en gris, sur le côté,
                      //  c'est fabriquer un oui.
                      _Bouton(
                        texte: 'Non merci',
                        onTap: onNon,
                        principal: false,
                      ),
                      const SizedBox(width: 16),
                      _Bouton(
                        texte: 'Oui, aidez-moi',
                        onTap: onOui,
                        principal: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sans réponse, la demande s’efface toute seule.',
                    style: TextStyle(color: Color(0xFF4E4A45), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le bandeau permanent. Il ne se cache jamais.
class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.support,
    required this.restant,
    required this.phrase,
    required this.onArreter,
  });

  final String support;
  final Duration? restant;
  final String phrase;
  final VoidCallback onArreter;

  @override
  Widget build(BuildContext context) {
    final int min = restant == null ? 0 : restant!.inMinutes;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: const Color(0xFFE84A3E),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                const Icon(Icons.support_agent, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '$support vous aide en ce moment',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        phrase.isNotEmpty
                            ? phrase
                            : (min > 0
                                ? 'Se termine tout seul dans $min min'
                                : 'Se termine dans un instant'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                //  LA SORTIE, TOUJOURS LÀ, TOUJOURS AU MÊME ENDROIT.
                _Bouton(texte: 'Arrêter', onTap: onArreter, principal: false),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  const _Bouton({
    required this.texte,
    required this.onTap,
    required this.principal,
  });

  final String texte;
  final VoidCallback onTap;
  final bool principal;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: principal,
      child: Builder(
        builder: (BuildContext context) {
          final bool focus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: principal
                    ? const Color(0xFFE84A3E)
                    : Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focus ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Text(
                texte,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
