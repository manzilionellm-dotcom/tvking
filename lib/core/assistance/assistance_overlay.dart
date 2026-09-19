// =========================================================
//  assistance_overlay.dart — ce que le CLIENT voit
// =========================================================
//  Tout le reste du mode assistance est invisible pour lui : des
//  frames, une machine à états, des accusés. Ce fichier-ci est la
//  seule chose qu'il voit — et c'est donc lui qui décide si le mode
//  est honnête ou pas.
//
//  DEPUIS LE 19/09/2026, ON NE LUI DEMANDE PLUS SON ACCORD à l'écran
//  (« je veux que ça soit automatique » — le client est au téléphone,
//  il dit oui à l'oreille du support, pas à sa télécommande). Ce
//  fichier porte donc TOUT le poids de la franchise du mode. Les
//  règles qui restent ne sont pas décoratives :
//
//   1. LE BANDEAU EST IMMÉDIAT, ET IL PORTE UN NOM. « Lionel vous aide
//      en ce moment » — jamais « assistance à distance ». Le client
//      doit reconnaître la personne qu'il a au téléphone, et repérer
//      tout de suite celle qu'il n'a pas appelée.
//
//   2. LE BANDEAU NE PART JAMAIS pendant la session. Il ne se réduit
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
//
//  ---------------------------------------------------------
//  LE HALO — « OÙ JE TOUCHE, IL VOIT OÙ JE TOUCHE »
//  ---------------------------------------------------------
//  Le support touche une maquette d'écran dans le panel ; un rond
//  lumineux apparaît au même endroit, en proportion, sur l'écran du
//  client. C'est le doigt du support, posé sur sa télé.
//
//  IL NE CAPTE PAS LES APPUIS. Le halo est dessiné par-dessus, en
//  `IgnorePointer` : si le client veut appuyer exactement là où on lui
//  montre, son doigt doit passer à travers. Un guide qui bloque le
//  passage n'est plus un guide.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'assistance_controller.dart';
import 'assistance_miroir.dart';
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

  /// La zone capturée pour le miroir. Elle entoure TOUT — l'app, le
  /// halo et le bandeau — pour que le support voie exactement ce que
  /// le client a sous les yeux, bandeau rouge compris. Voir sur son
  /// image que le bandeau est bien affiché, c'est vérifier d'un coup
  /// d'œil que le client sait qu'on est là.
  final GlobalKey _zone = GlobalKey();

  Timer? _ticMiroir;

  /// Une capture est-elle en cours ? Sur une box lente, encoder un PNG
  /// peut dépasser la période ; sans ce verrou les captures
  /// s'empileraient jusqu'à ce que la mémoire lâche.
  bool _captureEnCours = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_maj);
  }

  @override
  void dispose() {
    _c.removeListener(_maj);
    _tic?.cancel();
    _ticMiroir?.cancel();
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
    _ticMiroir?.cancel();
    _ticMiroir = null;
    if (_c.etat != EtatAssistance.active) return;

    _tic = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      // `etat` rafraîchit la session au passage : c'est ce qui fait
      // disparaître le bandeau tout seul quand le temps est écoulé.
      setState(() {});
    });

    //  LE MIROIR NE TOURNE QUE PENDANT UNE SESSION, et seulement si
    //  quelqu'un peut recevoir les images. Encoder un PNG toutes les
    //  deux secondes sur une box à 1 Go n'est pas gratuit : ça se
    //  mérite, et ça s'arrête avec le bandeau.
    if (!_c.miroirBranche) return;
    _ticMiroir = Timer.periodic(periodeMiroir, (_) => _capturer());
  }

  Future<void> _capturer() async {
    if (!mounted || _captureEnCours) return;
    if (_c.etat != EtatAssistance.active) return;
    _captureEnCours = true;
    try {
      final ImageMiroir? img = await capturerMiroir(_zone);
      if (img == null || !mounted) return;
      // On revérifie la session APRÈS l'attente : le client a pu
      // appuyer sur « Arrêter » pendant l'encodage. Sans ce second
      // contrôle, sa dernière image partirait quand même — une image
      // de plus après qu'il a dit non.
      if (_c.etat != EtatAssistance.active) return;
      _c.publierImageMiroir(
        base64Encode(img.octets),
        img.largeur,
        img.hauteur,
      );
    } finally {
      _captureEnCours = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool active = _c.etat == EtatAssistance.active;
    final Designation? d = _c.designation;
    //  LE `Stack` EST TOUJOURS LÀ, MÊME HORS SESSION — et ce n'est pas
    //  du gaspillage, c'est une protection.
    //
    //  Si on rendait `widget.child` tout seul hors session, alors au
    //  moment où le support prend la main l'application changerait de
    //  place dans l'arbre (enfant direct → premier enfant d'un Stack).
    //  Flutter détruirait et reconstruirait tout ce qui est en dessous :
    //  le lecteur vidéo repartirait de zéro, la liste sauterait en
    //  haut, le client verrait son film s'arrêter pile au moment où on
    //  lui dit « ne bougez pas, je regarde ».
    //
    //  Les surcouches s'ajoutent donc APRÈS l'enfant, et lui ne bouge
    //  jamais de l'index 0.
    return RepaintBoundary(
      key: _zone,
      child: Stack(
        children: <Widget>[
          widget.child,
          if (active && d != null && d.aUnHalo) _Halo(x: d.x!, y: d.y!),
          if (active)
            _Bandeau(
              support: _c.support,
              restant: _c.tempsRestant,
              phrase: d?.phrase ?? '',
              //  ON LE DIT. Le support voit son écran : c'est la seule
              //  chose de ce mode que le client ne peut pas deviner en
              //  regardant sa télé. Le bandeau annonce déjà QUI l'aide
              //  et pour combien de temps ; taire le regard serait
              //  garder la fenêtre la plus importante fermée.
              regarde: _c.miroirBranche,
              onArreter: _c.arreterParClient,
            ),
        ],
      ),
    );
  }
}

/// Le doigt du support, posé sur l'écran du client.
///
///  Deux ronds concentriques qui respirent : un point plein qui dit
///  « exactement ici », et une onde qui s'ouvre pour attirer l'œil
///  depuis l'autre bout d'une télé de 55 pouces. Un simple point fixe
///  se perd dans une grille de logos de chaînes.
class _Halo extends StatefulWidget {
  const _Halo({required this.x, required this.y});

  /// Fractions de l'écran (0 → 1). Voir [Designation.x].
  final double x;
  final double y;

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //  `IgnorePointer` : le halo MONTRE, il ne bloque pas. Si le client
    //  appuie pile là où on lui indique, son doigt doit atteindre le
    //  bouton qui est dessous.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          const double taille = 132;
          return Stack(
            children: <Widget>[
              Positioned(
                left: widget.x * c.maxWidth - taille / 2,
                top: widget.y * c.maxHeight - taille / 2,
                width: taille,
                height: taille,
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (BuildContext context, _) {
                    final double t = _anim.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        // L'onde qui s'ouvre et s'efface.
                        Opacity(
                          opacity: (1 - t).clamp(0.0, 1.0) * 0.75,
                          child: Container(
                            width: taille * (0.35 + 0.65 * t),
                            height: taille * (0.35 + 0.65 * t),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE84A3E),
                                width: 4,
                              ),
                            ),
                          ),
                        ),
                        // Le point plein : « exactement ici ».
                        Container(
                          width: taille * 0.3,
                          height: taille * 0.3,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFE84A3E),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Color(0x88000000),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
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
    required this.regarde,
    required this.onArreter,
  });

  final String support;
  final Duration? restant;
  final String phrase;

  /// Le support reçoit-il des images de cet écran ?
  final bool regarde;

  final VoidCallback onArreter;

  @override
  Widget build(BuildContext context) {
    final int min = restant == null ? 0 : restant!.inMinutes;
    final String duree =
        min > 0 ? 'se termine dans $min min' : 'se termine dans un instant';
    //  LE REGARD PASSE AVANT LA DURÉE. Si une seule ligne doit être
    //  lue, c'est celle-là : savoir que quelqu'un voit son écran change
    //  ce qu'on fait devant, savoir qu'il reste 12 minutes ne change
    //  rien. La phrase du support, elle, reste prioritaire : c'est
    //  l'instruction qu'il est en train de lui donner.
    final String sousTitre = phrase.isNotEmpty
        ? phrase
        : (regarde ? 'Il voit cet écran · $duree' : 'Ça $duree');
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
                        sousTitre,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                //  LA SORTIE, TOUJOURS LÀ, TOUJOURS AU MÊME ENDROIT.
                _Bouton(texte: 'Arrêter', onTap: onArreter),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  const _Bouton({required this.texte, required this.onTap});

  final String texte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(
        builder: (BuildContext context) {
          final bool focus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
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
