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
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tvking_miroir/tvking_miroir.dart';

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

  /// LA CAPTURE SYSTÈME EST-ELLE OUVERTE pour cette session ?
  ///
  ///  `true` = le client a accepté la boîte de dialogue d'Android et la
  ///  projection (MediaProjection) tourne : on voit TOUT, vidéo comprise.
  ///  `false` = on retombe sur la capture Flutter (`toImage`), qui ne
  ///  voit pas la vidéo et gèle sur certaines box — mais qui, elle, DIT
  ///  pourquoi. Voir packages/tvking_miroir.
  bool _natif = false;

  /// On ne pose la question d'Android qu'UNE fois par session. Sans ce
  /// garde-fou, un refus du client ferait réapparaître la boîte de
  /// dialogue à chaque reconstruction du bandeau.
  bool _accordDemande = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_maj);
    //  LE TAPEUR : c'est ICI qu'on peut injecter un vrai appui, parce
    //  que c'est ici qu'on connaît la taille réelle de l'écran et qu'on
    //  peut parler au moteur de gestes. Le contrôleur, lui, ne sait pas
    //  taper.
    _c.installerTapeur(_injecterTap);
  }

  @override
  void dispose() {
    _c.removeListener(_maj);
    _tic?.cancel();
    _ticMiroir?.cancel();
    _fermerNatif();
    super.dispose();
  }

  /// Libère la projection système, sans faute : une projection qui reste
  /// ouverte, c'est une notification « partage d'écran » qui reste
  /// affichée chez le client alors que personne ne regarde plus.
  void _fermerNatif() {
    if (!_natif && !_accordDemande) return;
    _natif = false;
    _accordDemande = false;
    unawaited(TvkingMiroir.arreter());
  }

  /// Ouvre la capture système, si l'appareil le permet et si le client
  /// accepte. Tourne en tâche de fond : le miroir Flutter continue en
  /// attendant, et bascule dès que l'accord arrive.
  Future<void> _ouvrirNatif() async {
    if (_accordDemande) return;
    _accordDemande = true;
    if (!await TvkingMiroir.disponible) return;
    final bool ok = await TvkingMiroir.demander();
    if (!mounted || _c.etat != EtatAssistance.active) {
      // La session s'est fermée pendant que la boîte était à l'écran.
      unawaited(TvkingMiroir.arreter());
      return;
    }
    if (ok) {
      _natif = true;
      return;
    }
    //  LE CLIENT A DIT NON (ou n'a pas répondu). On le DIT au panel,
    //  une fois, avec le bon mot : ce n'est pas une panne, c'est un
    //  refus — et le support doit lui parler, pas redémarrer la box.
    _c.signalerEchecMiroir('accord_refuse', '');
  }

  /// INJECTE UN VRAI APPUI à la position [fx],[fy] (fractions d'écran).
  ///
  ///  On fabrique un couple bas + haut au même endroit et on le donne
  ///  au `GestureBinding` : Flutter fait son hit-test et le widget sous
  ///  ce point reçoit le tap EXACTEMENT comme si le client avait touché
  ///  l'écran. Aucun privilège système — on reste dans notre arbre.
  ///
  ///  ON VISE LA ZONE DE L'APP, PAS LE BANDEAU. Les coordonnées sont
  ///  relatives à la même boîte que la maquette du panel (l'écran
  ///  entier) ; le bandeau rouge est au-dessus mais ne prend qu'une
  ///  bande en haut, et le support ne clique pas dedans.
  void _injecterTap(double fx, double fy) {
    if (!mounted) return;
    final RenderObject? ro = _zone.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final Size s = ro.size;
    if (s.isEmpty) return;
    final Offset local = Offset(fx * s.width, fy * s.height);
    final Offset global = ro.localToGlobal(local);

    //  ON CONSTRUIT LES ÉVÉNEMENTS DIRECTEMENT, avec l'API PUBLIQUE.
    //  La première version passait par `PointerData.toPointerEvent`,
    //  une méthode interne au moteur : elle n'existe pas pour nous, et
    //  la suite de tests entière a refusé de compiler. `PointerDownEvent`
    //  et `PointerUpEvent` sont publics, stables, et présents sur la
    //  3.32 des builds TV. C'est exactement ce que `WidgetTester` fait
    //  pour simuler un tap.
    //
    //  Un identifiant de pointeur À NOUS, hors de la plage des vrais
    //  doigts, pour ne jamais brouiller un appui réel du client s'il
    //  touche en même temps.
    const int idPointeur = 0xA551;
    final GestureBinding gb = GestureBinding.instance;
    gb.handlePointerEvent(PointerDownEvent(
      pointer: idPointeur,
      device: idPointeur,
      kind: PointerDeviceKind.touch,
      position: global,
      buttons: kPrimaryButton,
    ));
    gb.handlePointerEvent(PointerUpEvent(
      pointer: idPointeur,
      device: idPointeur,
      kind: PointerDeviceKind.touch,
      position: global,
    ));
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
    if (_c.etat != EtatAssistance.active) {
      // Fin de session : on rend la projection système avec le bandeau.
      _fermerNatif();
      return;
    }

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
    //  D'ABORD LA VOIE PRO : la capture système, qui voit la vidéo. Elle
    //  demande l'accord du client (boîte d'Android) ; pendant qu'il
    //  répond, le miroir Flutter tourne déjà, et on bascule dès le oui.
    unawaited(_ouvrirNatif());
    _ticMiroir = Timer.periodic(periodeMiroir, (_) => _capturer());
  }

  Future<void> _capturer() async {
    if (!mounted || _captureEnCours) return;
    if (_c.etat != EtatAssistance.active) return;
    _captureEnCours = true;
    try {
      //  VOIE 1 — LA CAPTURE SYSTÈME (MediaProjection), quand le client
      //  a accepté. Elle lit la sortie composée d'Android : menus ET
      //  vidéo, et elle ne gèle pas. Le JPEG est fait en natif.
      if (_natif) {
        final Uint8List? jpeg = await TvkingMiroir.capturer()
            .timeout(const Duration(milliseconds: 2500), onTimeout: () => null);
        if (!mounted || _c.etat != EtatAssistance.active) return;
        // `null` = pas d'image neuve depuis la dernière (écran figé,
        // ou projection pas encore prête) : on ne dit rien, la suivante
        // arrive dans deux secondes. Ce n'est PAS une erreur.
        if (jpeg == null) return;
        if (jpeg.length > poidsMaxMiroir) {
          _c.signalerEchecMiroir(
            EchecMiroir.tropGrosse.name,
            '${(jpeg.length / 1024).round()} Ko (natif)',
          );
          return;
        }
        // Largeur/hauteur : le panel n'en a pas besoin (l'image se cale
        // toute seule dans le cadre) ; 0 signifie « inconnu ».
        _c.publierImageMiroir(base64Encode(jpeg), 0, 0);
        return;
      }

      //  VOIE 2 — LA CAPTURE FLUTTER, en attendant l'accord ou si le
      //  client a refusé. Elle ne voit pas la vidéo et peut geler ; le
      //  délai de garde ci-dessous transforme ce gel en message clair.
      ResultatMiroir r;
      try {
        //  UN DÉLAI DE GARDE, et c'est LE correctif du 19/09 au soir.
        //  Sur cette box (SHIELD, Skia), `capturerMiroir` ne JETAIT pas
        //  — elle RESTAIT SUSPENDUE. `toImage` d'un écran qui contient
        //  la surface vidéo peut ne jamais rendre la main. Résultat : la
        //  toute première capture bloquait `_captureEnCours` pour
        //  toujours, et plus une seule trame ne partait — ni image, ni
        //  erreur. Le support voyait « Pas encore d'image » à l'infini,
        //  session pourtant ouverte. Un `try/catch` n'attrape pas un
        //  gel ; un `timeout`, si.
        r = await capturerMiroir(_zone)
            .timeout(const Duration(milliseconds: 2500));
      } on TimeoutException {
        //  ON LE DIT, ET ON ARRÊTE D'ESSAYER. Si la capture gèle une
        //  fois sur cette box, elle gèlera à chaque fois : réessayer
        //  toutes les 2 s empilerait des captures fantômes en mémoire.
        //  On signale la cause UNE fois, on coupe le miroir pour cette
        //  session — le reste (curseur, clic) continue de marcher.
        _ticMiroir?.cancel();
        _ticMiroir = null;
        if (mounted && _c.etat == EtatAssistance.active) {
          _c.signalerEchecMiroir(
            'capture_bloquee',
            'toImage sans reponse > 2,5 s',
          );
        }
        return;
      }
      if (!mounted) return;
      // On revérifie la session APRÈS l'attente : le client a pu
      // appuyer sur « Arrêter » pendant l'encodage. Sans ce second
      // contrôle, sa dernière image partirait quand même — une image
      // de plus après qu'il a dit non.
      if (_c.etat != EtatAssistance.active) return;
      final ImageMiroir? img = r.image;
      if (img != null) {
        _c.publierImageMiroir(
          base64Encode(img.octets),
          img.largeur,
          img.hauteur,
        );
        return;
      }
      //  ON DIT POURQUOI IL N'Y A PAS D'IMAGE. C'est la correction qui
      //  compte le plus de ce tour : en 198884, chaque capture était
      //  jetée pour dépassement de poids, et le support n'avait devant
      //  lui qu'un cadre vide et une phrase qui parlait d'autre chose.
      //  Une panne muette coûte une session entière.
      _c.signalerEchecMiroir(r.echec!.name, r.detail ?? '');
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
          if (active && d != null && d.aUnHalo) _Curseur(x: d.x!, y: d.y!),
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

/// LE CURSEUR DU SUPPORT, posé sur l'écran du client.
///
///  ---------------------------------------------------------
///  POURQUOI UNE FLÈCHE, ET PLUS UNE BOULE (19/09/2026 au soir)
///  ---------------------------------------------------------
///  La première version dessinait un gros rond rouge qui pulsait. Le
///  propriétaire l'a vu sur sa télé et a tranché :
///
///    « La boule sur TV n'est pas sexy. Fais une petite souris rouge,
///      ou un [curseur] élégant, qui peut pointer partout. »
///
///  Il a raison au-delà du goût. UN ROND NE DÉSIGNE PAS, IL ENTOURE.
///  Posé sur une grille de chaînes, il couvre ce qu'il montre, et le
///  client doit deviner si on lui désigne le logo au centre ou la
///  ligne entière. Une flèche a une POINTE : elle dit « ça », et elle
///  ne cache rien de ce qu'elle indique.
///
///  Et c'est une forme que tout le monde connaît. Personne n'a besoin
///  qu'on lui explique ce qu'est un curseur de souris — pas même
///  quelqu'un qui n'a qu'une télécommande.
///
///  LA POINTE TOMBE EXACTEMENT SUR LE POINT VISÉ. C'est tout l'intérêt
///  d'une flèche : si on centrait le dessin sur la cible comme on
///  centrait la boule, elle désignerait un endroit à côté.
class _Curseur extends StatefulWidget {
  const _Curseur({required this.x, required this.y});

  /// Fractions de l'écran (0 → 1). Voir [Designation.x].
  final double x;
  final double y;

  @override
  State<_Curseur> createState() => _CurseurState();
}

class _CurseurState extends State<_Curseur>
    with TickerProviderStateMixin {
  //  L'ONDE qui respire — un rythme constant, indépendant des
  //  déplacements.
  late final AnimationController _onde = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  //  LE GLISSEMENT — c'est LUI la demande du propriétaire : « ça doit
  //  glisser, pas sauter ». Chaque nouvelle position n'est pas affichée
  //  d'un coup ; on anime de l'ancienne vers la nouvelle, vite mais en
  //  continu, comme une vraie souris.
  late final AnimationController _glisse = AnimationController(
    vsync: this,
    duration: _dureeGlisse,
  );

  //  130 ms : assez court pour coller au doigt du support (le panel
  //  envoie une position toutes les ~70 ms), assez long pour que le
  //  trajet se voie au lieu de clignoter. Le curseur est donc toujours
  //  en train de rattraper la dernière position — c'est exactement ce
  //  qui donne le glissement fluide.
  static const Duration _dureeGlisse = Duration(milliseconds: 130);

  late Offset _depart = Offset(widget.x, widget.y);
  late Offset _cible = Offset(widget.x, widget.y);
  late Animation<Offset> _piste =
      AlwaysStoppedAnimation<Offset>(Offset(widget.x, widget.y));

  @override
  void didUpdateWidget(_Curseur old) {
    super.didUpdateWidget(old);
    final Offset cible = Offset(widget.x, widget.y);
    if (cible == _cible) return;
    //  On repart de LÀ OÙ LE CURSEUR EST VRAIMENT à cet instant (pas de
    //  la dernière cible) : si une nouvelle position arrive avant la
    //  fin du glissement précédent, le mouvement enchaîne sans à-coup.
    _depart = _piste.value;
    _cible = cible;
    _piste = Tween<Offset>(begin: _depart, end: _cible).animate(
      CurvedAnimation(parent: _glisse, curve: Curves.easeOut),
    );
    _glisse
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
    _onde.dispose();
    _glisse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //  `IgnorePointer` : le curseur MONTRE, il ne bloque pas. Si le
    //  client appuie pile là où on lui indique, son doigt doit
    //  atteindre le bouton qui est dessous.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          //  LE DESSIN DÉBORDE LARGEMENT DE LA FLÈCHE : l'onde s'ouvre
          //  autour de la pointe, donc la zone de peinture est centrée
          //  sur elle et doit pouvoir s'étendre dans les QUATRE
          //  directions — y compris vers le haut et la gauche, là où la
          //  flèche, elle, ne va pas.
          const double zone = 220;
          return AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_onde, _glisse]),
            builder: (BuildContext context, _) {
              final Offset p = _piste.value;
              return Stack(
                children: <Widget>[
                  Positioned(
                    left: p.dx * c.maxWidth - zone / 2,
                    top: p.dy * c.maxHeight - zone / 2,
                    width: zone,
                    height: zone,
                    child: CustomPaint(painter: _PeintreCurseur(_onde.value)),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Dessine la flèche et son onde. La POINTE est au centre exact de la
/// zone de peinture — c'est ce qui fait correspondre le geste du
/// support et l'endroit désigné chez le client.
class _PeintreCurseur extends CustomPainter {
  const _PeintreCurseur(this.t);

  /// Avancement de l'animation, 0 → 1.
  final double t;

  /// Le rouge de la maison (`AppColors.accent`). Écrit en dur ICI et
  /// nulle part ailleurs dans ce fichier : cette surcouche est posée
  /// au-dessus de l'application, avant tout thème, et ne peut donc pas
  /// lire les couleurs par le contexte comme un écran normal le ferait.
  static const Color rouge = Color(0xFFE84A3E);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset pointe = Offset(size.width / 2, size.height / 2);

    //  1) L'ONDE, discrète. Elle sert à RETROUVER le curseur sur une
    //  télé de 55 pouces quand le support vient de le déplacer ; elle
    //  ne doit pas devenir le sujet. D'où un seul trait fin, très
    //  transparent, qui s'efface en s'ouvrant — rien à voir avec le
    //  gros rond plein d'avant.
    final double r = 26 + 58 * t;
    canvas.drawCircle(
      pointe,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = rouge.withValues(alpha: (1 - t) * 0.45),
    );

    //  2) LA FLÈCHE. Tracée depuis la pointe (0,0) vers le bas-droite,
    //  comme un curseur de souris : c'est l'orientation que tout le
    //  monde reconnaît sans y penser.
    const double k = 2.6; // échelle : ~62 px de haut, lisible de loin
    final Path fleche = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 24)
      ..lineTo(5.8, 18.2)
      ..lineTo(9.6, 26.4)
      ..lineTo(13.4, 24.6)
      ..lineTo(9.7, 16.7)
      ..lineTo(17.4, 16.4)
      ..close();

    //  ON TRANSFORME LE CANEVAS, PAS LE CHEMIN — et ce n'est pas un
    //  détail de style. La première version passait par
    //  `Matrix4.translateByDouble`, une méthode récente : elle compile
    //  ici (Flutter 3.47) et PAS sur les deux builds TV, épinglés en
    //  3.32. Les deux box sont tombées, et je ne pouvais pas le voir
    //  d'ici — mon conteneur n'a pas la version qu'elles utilisent.
    //
    //  `save` / `translate` / `scale` existent depuis toujours. Quand
    //  une API récente et une API ancienne font la même chose, sur ce
    //  dépôt c'est l'ancienne qui gagne : le parc n'est pas sur la même
    //  version que la machine qui compile.
    canvas.save();
    canvas.translate(pointe.dx, pointe.dy);
    canvas.scale(k);

    //  Les épaisseurs sont divisées par l'échelle pour rester des
    //  tailles À L'ÉCRAN : sans ça, le liseré et le flou grossiraient
    //  avec la flèche et la noieraient.
    //
    //  L'OMBRE PORTÉE N'EST PAS DE LA DÉCORATION. Le curseur passe sur
    //  des fonds clairs comme sur des fonds sombres ; sans elle, il
    //  disparaît sur une affiche de film claire, exactement au moment
    //  où le support croit le montrer.
    canvas.drawPath(
      fleche.shift(const Offset(0, 3 / k)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6 / k),
    );
    canvas.drawPath(fleche, Paint()..color = rouge);
    //  Le liseré blanc fait le reste du travail de contraste : rouge
    //  sur rouge (un logo, un bouton d'alerte) resterait illisible.
    canvas.drawPath(
      fleche,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 / k
        ..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PeintreCurseur old) => old.t != t;
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
