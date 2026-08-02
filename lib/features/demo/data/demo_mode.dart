// =========================================================
//  demo_mode.dart — « Mode démo » : l'app se montre elle-même
// =========================================================
//  Demande du client : « si quelqu'un vient et n'a pas encore mis son
//  M3U, il doit y avoir une option Mode démo. Ça doit avoir des vidéos,
//  une, deux, trois… Même dans le cinéma, tu mets des démonstrations de
//  comment l'application fonctionne. »
//
//  Le problème est réel : une app IPTV vide ne montre RIEN. Le nouvel
//  arrivant ne peut ni juger le lecteur, ni comprendre la navigation, ni
//  voir le cinéma — il doit faire confiance sur parole avant d'avoir
//  quoi que ce soit à regarder. Le mode démo remplit l'app avec un
//  bouquet FICTIF qui traverse tout le parcours : direct, catégories,
//  cinéma, lecteur, cast.
//
//  ─────────────────────────────────────────────────────────────
//  TROIS RÈGLES QUI NE SE NÉGOCIENT PAS
//
//  1. AUCUN NOM DE CHAÎNE OU DE BOUQUET RÉEL. Tout s'appelle
//     « Démo … ». C'est le motif de refus n°1 des lecteurs IPTV sur
//     les stores, et c'est aussi ce qui rend ces écrans utilisables
//     comme captures de fiche Play Store.
//
//  2. AUCUN FLUX QUI NE NOUS APPARTIENNE PAS. On n'utilise QUE des
//     flux de test publics, publiés par leurs éditeurs POUR être
//     testés (Apple HLS reference streams, mux.dev test-streams).
//     Jamais une chaîne réelle, jamais un lien de fournisseur.
//
//  3. LE CLIENT SAIT TOUJOURS QU'IL EST EN DÉMO. L'état est persisté
//     et exposé (`DemoMode.instance.isActive`) pour qu'un bandeau le
//     rappelle. Un client qui croit avoir un abonnement alors qu'il
//     regarde une démo, c'est un litige.
//  ─────────────────────────────────────────────────────────────
//
//  Le bouquet est injecté EN MÉMOIRE, jamais en base : sortir de la
//  démo n'a donc rien à nettoyer dans SQLite, et une vraie source
//  ajoutée par-dessus reprend simplement la main.
// =========================================================
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';

/// Une étape du guide « Comment ça marche », montrée dans le cinéma de
/// démo à côté des films : le client apprend en regardant.
@immutable
class DemoLesson {
  const DemoLesson({
    required this.step,
    required this.title,
    required this.body,
  });

  final int step;
  final String title;
  final String body;
}

class DemoMode extends ChangeNotifier {
  DemoMode._();
  static final DemoMode instance = DemoMode._();

  static const String _kKey = 'demo.mode.active';

  bool _active = false;
  bool get isActive => _active;

  /// Relit l'état au démarrage. Si la démo était active, on la remet —
  /// sinon le client rouvrirait l'app sur un écran vide sans comprendre
  /// pourquoi ce qu'il regardait a disparu.
  Future<void> restore() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      if (p.getBool(_kKey) ?? false) {
        _active = true;
        PlaylistRepository.instance.publishDemoChannels(demoChannels);
        notifyListeners();
      }
    } catch (_) {
      // Préférence illisible : on n'entre simplement pas en démo.
    }
  }

  Future<void> enter() async {
    if (_active) return;
    _active = true;
    PlaylistRepository.instance.publishDemoChannels(demoChannels);
    notifyListeners();
    unawaited(_persist(true));
  }

  Future<void> exit() async {
    if (!_active) return;
    _active = false;
    PlaylistRepository.instance.publishDemoChannels(const <Channel>[]);
    notifyListeners();
    unawaited(_persist(false));
  }

  Future<void> _persist(bool v) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setBool(_kKey, v);
    } catch (_) {}
  }

  // =========================================================
  //  LE BOUQUET DE DÉMONSTRATION
  // =========================================================
  //  Identifiants préfixés `demo-` : impossible de les confondre avec
  //  une chaîne réelle, et ça donne une porte de sortie propre si on
  //  doit un jour les filtrer ailleurs.

  /// Flux de test PUBLICS, publiés pour être testés. Rien d'autre n'a le
  /// droit d'entrer ici.
  static const String _appleAdv =
      'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
      'img_bipbop_adv_example_ts/master.m3u8';
  static const String _muxBasic =
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
  static const String _muxPtsShift =
      'https://test-streams.mux.dev/pts_shift/master.m3u8';

  static const List<Channel> _live = <Channel>[
    Channel(
      id: 'demo-live-1',
      name: 'Démo Sport',
      category: 'DÉMO || Sport',
      streamUrl: _muxBasic,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-2',
      name: 'Démo Info',
      category: 'DÉMO || Info',
      streamUrl: _appleAdv,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-3',
      name: 'Démo Divertissement',
      category: 'DÉMO || Divertissement',
      streamUrl: _muxPtsShift,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-4',
      name: 'Démo Enfants',
      category: 'DÉMO || Enfants',
      streamUrl: _muxBasic,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-5',
      name: 'Démo Musique',
      category: 'DÉMO || Musique',
      streamUrl: _appleAdv,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-6',
      name: 'Démo Documentaire',
      category: 'DÉMO || Documentaire',
      streamUrl: _muxPtsShift,
      isLive: true,
    ),
  ];

  /// Le CINÉMA de démo. `isLive: false` suffit à les faire apparaître
  /// dans la section Films — c'est le même chemin que pour une vraie
  /// source, donc le client voit le vrai écran, pas une maquette.
  ///
  /// Les quatre premiers montrent le catalogue ; les suivants sont des
  /// LEÇONS : « Comment ajouter ma source », « Comment envoyer sur ma
  /// télé »… Le client apprend en ouvrant une fiche, exactement comme
  /// il ouvrira un film plus tard.
  static const List<Channel> _vod = <Channel>[
    Channel(
      id: 'demo-vod-1',
      name: 'Démo — Film de démonstration 1',
      category: 'DÉMO FILMS || Catalogue',
      streamUrl: _muxBasic,
      isLive: false,
    ),
    Channel(
      id: 'demo-vod-2',
      name: 'Démo — Film de démonstration 2',
      category: 'DÉMO FILMS || Catalogue',
      streamUrl: _appleAdv,
      isLive: false,
    ),
    Channel(
      id: 'demo-vod-3',
      name: 'Démo — Film de démonstration 3',
      category: 'DÉMO FILMS || Catalogue',
      streamUrl: _muxPtsShift,
      isLive: false,
    ),
    Channel(
      id: 'demo-vod-4',
      name: 'Démo — Film de démonstration 4',
      category: 'DÉMO FILMS || Catalogue',
      streamUrl: _muxBasic,
      isLive: false,
    ),
    Channel(
      id: 'demo-tuto-1',
      name: 'Guide 1 — Ajouter ma source',
      category: 'DÉMO FILMS || Guide',
      streamUrl: _appleAdv,
      isLive: false,
    ),
    Channel(
      id: 'demo-tuto-2',
      name: 'Guide 2 — Trouver une chaîne',
      category: 'DÉMO FILMS || Guide',
      streamUrl: _muxBasic,
      isLive: false,
    ),
    Channel(
      id: 'demo-tuto-3',
      name: 'Guide 3 — Envoyer sur ma télé',
      category: 'DÉMO FILMS || Guide',
      streamUrl: _muxPtsShift,
      isLive: false,
    ),
  ];

  /// Le bouquet complet : direct + cinéma + guides.
  static List<Channel> get demoChannels => <Channel>[..._live, ..._vod];

  /// Le guide « Comment ça marche », en clair. Volontairement des
  /// PHRASES et non des captures annotées : une flèche dessinée sur une
  /// image se périme au premier changement d'écran, un texte non.
  static const List<DemoLesson> lessons = <DemoLesson>[
    DemoLesson(
      step: 1,
      title: 'Apporte ta source',
      body: 'Réglages → Mes playlists. Colle le lien M3U que ton '
          'fournisseur t\'a donné, ou saisis ton serveur, ton nom '
          'd\'utilisateur et ton mot de passe Xtream. L\'application ne '
          'fournit aucune chaîne : c\'est toi qui apportes la tienne.',
    ),
    DemoLesson(
      step: 2,
      title: 'Trouve ce que tu cherches',
      body: 'Tes chaînes se rangent toutes seules par catégorie. La '
          'recherche répond dès la première lettre, même sur des '
          'dizaines de milliers de lignes. Le cœur met une chaîne en '
          'favori, et elle remonte en haut.',
    ),
    DemoLesson(
      step: 3,
      title: 'Regarde, et reprends où tu t\'es arrêté',
      body: 'Ouvre une chaîne : elle se lit en plein écran. Les pistes '
          'audio et les sous-titres se changent depuis le lecteur, et un '
          'film repris redémarre à la seconde où tu l\'avais laissé.',
    ),
    DemoLesson(
      step: 4,
      title: 'Envoie sur ta télévision',
      body: 'Le bouton Cast, en haut du lecteur, cherche les téléviseurs '
          'du même Wi-Fi. Pas de Chromecast ? Le QR code affiche un lien '
          'à ouvrir dans le navigateur de la télé.',
    ),
    DemoLesson(
      step: 5,
      title: 'Quand tu es prêt',
      body: 'Quitte le mode démo depuis le bandeau en haut de l\'écran. '
          'Les chaînes de démonstration disparaissent, et les tiennes '
          'prennent leur place.',
    ),
  ];
}
