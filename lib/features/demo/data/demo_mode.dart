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
//  2. AUCUN FLUX QUI NE NOUS APPARTIENNE PAS — et désormais aucun
//     flux TOUT COURT. Les clips sont fabriqués par nous et embarqués
//     dans l'APK (voir plus bas : c'est le fruit d'une journée passée
//     à courir après des hébergeurs qui tombent). Jamais une chaîne
//     réelle, jamais un lien de fournisseur, et plus aucune URL.
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
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
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

/// Code d'accès examinateur (Google Play / stores). Tapé tel quel comme
/// IDENTIFIANT (ou comme lien M3U) dans le formulaire de connexion, il fait
/// entrer l'app en Mode démo : bouquet fictif EMBARQUÉ, zéro réseau, zéro
/// activation revendeur. Répond au motif de refus Play « identifiants
/// restreints par l'authentification de l'appareil » : l'examen ne dépend
/// plus d'aucune action côté panel. Insensible à la casse.
const String kReviewAccessCode = 'GPLAYREVIEW';

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
        await _extractClips();
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
    await _extractClips();
    PlaylistRepository.instance.publishDemoChannels(demoChannels);
    notifyListeners();
    unawaited(_persist(true));
  }

  // =========================================================
  //  TOUT LE BOUQUET EST EMBARQUÉ — et c'est le fond du sujet
  // =========================================================
  //  On a passé une journée entière à courir après des hébergeurs.
  //  L'un renvoie 403. Un autre exigeait un TLS que l'app ne négociait
  //  pas. Un troisième nous a fait accuser le codec, à tort. Pendant
  //  tout ce temps, l'écran restait noir.
  //
  //  Le mode démo se déclenche DEVANT un client qui n'a pas encore
  //  d'abonnement. C'est le moment où l'app doit convaincre, et il n'a
  //  pas droit à l'erreur. Dépendre du serveur de quelqu'un d'autre à
  //  cet instant précis, c'est accepter que la vente se joue sur la
  //  disponibilité d'un CDN qu'on ne contrôle pas.
  //
  //  Donc : plus une seule URL. Les clips sont FABRIQUÉS (voir
  //  `tools/generate_demo_clips.py`), livrés dans l'APK, recopiés sur
  //  le disque au premier passage en démo — mpv lit un fichier, pas un
  //  asset Flutter — et servis par chemin local. Ni HTTPS, ni DNS, ni
  //  CDN, ni playlist à normaliser. Coût : ~4 Mo d'APK. Bénéfice : une
  //  démo qui ne peut pas tomber en panne devant un client.
  //
  //  Effet de bord utile : aucun lien de fournisseur ne peut se glisser
  //  ici, ce qui protège aussi la fiche Play Store.

  static const String _kAssetDir = 'assets/demo';

  /// Un clip du bouquet. `asset` est le nom de fichier dans
  /// [_kAssetDir] ; `id` sert aussi de clé de chemin extrait.
  static const List<({
    String id,
    String name,
    String category,
    String asset,
    bool isLive,
  })> _catalogue = <({
    String id,
    String name,
    String category,
    String asset,
    bool isLive,
  })>[
    // La vidéo du client EN TÊTE : c'est la sienne, elle porte sa
    // marque, et c'est la meilleure des démonstrations.
    (
      id: 'demo-clip-1',
      name: 'Démo — Découvrir 7 MOTION',
      category: 'DÉMO || Présentation',
      asset: '7motion_promo.mp4',
      isLive: false
    ),
    (
      id: 'demo-live-1',
      name: 'Démo Sport',
      category: 'DÉMO || Sport',
      asset: 'sport.mp4',
      isLive: true
    ),
    (
      id: 'demo-live-2',
      name: 'Démo Info',
      category: 'DÉMO || Info',
      asset: 'info.mp4',
      isLive: true
    ),
    (
      id: 'demo-live-3',
      name: 'Démo Divertissement',
      category: 'DÉMO || Divertissement',
      asset: 'divertissement.mp4',
      isLive: true
    ),
    (
      id: 'demo-live-4',
      name: 'Démo Enfants',
      category: 'DÉMO || Enfants',
      asset: 'enfants.mp4',
      isLive: true
    ),
    (
      id: 'demo-live-5',
      name: 'Démo Musique',
      category: 'DÉMO || Musique',
      asset: 'musique.mp4',
      isLive: true
    ),
    (
      id: 'demo-live-6',
      name: 'Démo Documentaire',
      category: 'DÉMO || Documentaire',
      asset: 'documentaire.mp4',
      isLive: true
    ),
    // Le CINÉMA : `isLive: false` suffit à les faire apparaître dans la
    // section Films — le même chemin que pour une vraie source, donc le
    // client voit le vrai écran, pas une maquette.
    (
      id: 'demo-vod-1',
      name: 'Démo — Film de démonstration 1',
      category: 'DÉMO FILMS || Catalogue',
      asset: 'film1.mp4',
      isLive: false
    ),
    (
      id: 'demo-vod-2',
      name: 'Démo — Film de démonstration 2',
      category: 'DÉMO FILMS || Catalogue',
      asset: 'film2.mp4',
      isLive: false
    ),
    (
      id: 'demo-vod-3',
      name: 'Démo — Film de démonstration 3',
      category: 'DÉMO FILMS || Catalogue',
      asset: 'film3.mp4',
      isLive: false
    ),
    (
      id: 'demo-vod-4',
      name: 'Démo — Film de démonstration 4',
      category: 'DÉMO FILMS || Catalogue',
      asset: 'film4.mp4',
      isLive: false
    ),
    // Les GUIDES : le client apprend en ouvrant une fiche, exactement
    // comme il ouvrira un film plus tard.
    (
      id: 'demo-tuto-1',
      name: 'Guide 1 — Ajouter ma source',
      category: 'DÉMO FILMS || Guide',
      asset: 'guide1.mp4',
      isLive: false
    ),
    (
      id: 'demo-tuto-2',
      name: 'Guide 2 — Trouver une chaîne',
      category: 'DÉMO FILMS || Guide',
      asset: 'guide2.mp4',
      isLive: false
    ),
    (
      id: 'demo-tuto-3',
      name: 'Guide 3 — Envoyer sur ma télé',
      category: 'DÉMO FILMS || Guide',
      asset: 'guide3.mp4',
      isLive: false
    ),
  ];

  /// Chemins des clips une fois recopiés sur le disque, par identifiant.
  static final Map<String, String> _paths = <String, String>{};

  Future<void> _extractClips() async {
    if (_paths.length == _catalogue.length) return;
    final Directory dir;
    try {
      dir = Directory('${(await getApplicationSupportDirectory()).path}/demo');
      await dir.create(recursive: true);
    } catch (_) {
      return; // Pas de disque : la démo s'ouvrira vide plutôt que cassée.
    }
    for (final ({
      String id,
      String name,
      String category,
      String asset,
      bool isLive
    }) c in _catalogue) {
      try {
        final File out = File('${dir.path}/${c.asset}');
        final ByteData data = await rootBundle.load('$_kAssetDir/${c.asset}');
        final int want = data.lengthInBytes;
        // Réécrit si absent OU de taille différente : une mise à jour de
        // l'app qui change un clip doit remplacer l'ancien, pas le garder.
        if (!out.existsSync() || await out.length() != want) {
          await out.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, want),
            flush: true,
          );
        }
        _paths[c.id] = out.path;
      } catch (_) {
        // Un clip manquant fait UNE entrée en moins, pas une vignette
        // qui ne s'ouvre pas. Le reste du bouquet tient debout.
      }
    }
  }

  /// Le bouquet complet, dans l'ordre : présentation, direct, cinéma,
  /// guides. Vide tant que [_extractClips] n'a rien pu recopier.
  static List<Channel> get demoChannels => <Channel>[
        for (final ({
          String id,
          String name,
          String category,
          String asset,
          bool isLive
        }) c in _catalogue)
          if (_paths[c.id] != null)
            Channel(
              id: c.id,
              name: c.name,
              category: c.category,
              streamUrl: _paths[c.id]!,
              isLive: c.isLive,
            ),
      ];

  /// Renseigne des chemins FACTICES pour que les tests voient le bouquet
  /// complet sans toucher au disque ni au bundle d'assets.
  @visibleForTesting
  static void debugFakeClipPaths() {
    for (final ({
      String id,
      String name,
      String category,
      String asset,
      bool isLive
    }) c in _catalogue) {
      _paths[c.id] = '/data/demo/${c.asset}';
    }
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
