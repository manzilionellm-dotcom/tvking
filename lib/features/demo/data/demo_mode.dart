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
//     testés : films libres de la Fondation Blender, flux de référence
//     Apple HLS, échantillons mux.dev. Jamais une chaîne réelle,
//     jamais un lien de fournisseur.
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
        await _extractBundledClip();
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
    await _extractBundledClip();
    PlaylistRepository.instance.publishDemoChannels(demoChannels);
    notifyListeners();
    unawaited(_persist(true));
  }

  // ---------------------------------------------------------
  //  LE CLIP EMBARQUÉ — la seule chaîne qui ne peut PAS tomber
  // ---------------------------------------------------------
  //  Tout le reste du bouquet dépend d'un hébergeur tiers. On a vu ce
  //  que ça donne : trois hôtes différents, un écran noir, et personne
  //  ne pouvait dire si le coupable était le lien, le réseau ou le
  //  décodeur. Une démo qui tombe en panne DEVANT un client, c'est la
  //  vente perdue.
  //
  //  Ce clip-ci vit dans l'APK. On le recopie sur le disque au premier
  //  passage en démo (mpv lit un fichier, pas un asset Flutter), puis on
  //  le sert par chemin local : ni HTTPS, ni DNS, ni CDN, ni playlist à
  //  normaliser. S'il ne s'affiche pas, le problème n'est plus nulle
  //  part ailleurs que dans le rendu — ce qui est en soi un diagnostic.
  static const String _kClipAsset = 'assets/demo/7motion_promo.mp4';
  static String? _clipPath;

  /// Chemin du clip une fois recopié, ou `null` s'il n'a pas pu l'être.
  static String? get clipPath => _clipPath;

  Future<void> _extractBundledClip() async {
    if (_clipPath != null) return;
    try {
      final Directory dir = await getApplicationSupportDirectory();
      final File out = File('${dir.path}/7motion_promo.mp4');
      final ByteData data = await rootBundle.load(_kClipAsset);
      // Réécrit si absent ou de taille différente : une mise à jour de
      // l'app qui change le clip doit remplacer l'ancien, pas le garder.
      final int want = data.lengthInBytes;
      if (!out.existsSync() || await out.length() != want) {
        await out.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, want),
          flush: true,
        );
      }
      _clipPath = out.path;
    } catch (_) {
      // Disque plein, asset absent d'une variante de build… La démo
      // marche sans : le clip est un bonus, pas une dépendance.
      _clipPath = null;
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

  // =========================================================
  //  LE BOUQUET DE DÉMONSTRATION
  // =========================================================
  //  Identifiants préfixés `demo-` : impossible de les confondre avec
  //  une chaîne réelle, et ça donne une porte de sortie propre si on
  //  doit un jour les filtrer ailleurs.

  // ---------------------------------------------------------
  //  LES SOURCES — et pourquoi elles sont de DEUX natures
  // ---------------------------------------------------------
  //  Premier jet : trois playlists HLS, et l'écran est resté NOIR chez
  //  le client. Les liens n'étaient pas vérifiables d'ici (le réseau de
  //  build refuse ces hôtes), donc on ne pouvait pas savoir si le
  //  coupable était le lien, le réseau, ou le chemin HLS du lecteur.
  //
  //  D'où le choix ci-dessous, qui n'est pas cosmétique : le DIRECT est
  //  en HLS, le CINÉMA en MP4 progressif. Ce sont DEUX CHEMINS
  //  DIFFÉRENTS dans le lecteur —
  //    • HLS  → playlist normalisée par le relais local, puis mpv ;
  //    • MP4 (isLive: false) → mpv en direct, Range natif, hors relais.
  //  Donc la démo répond toute seule à la question qu'on ne pouvait pas
  //  trancher : si les films partent et que le direct reste noir, c'est
  //  le chemin HLS ; si RIEN ne part, c'est le réseau de l'appareil.
  //  Et dans tous les cas le client a quelque chose à montrer.
  //
  //  Règle inchangée : QUE des flux de test publics, publiés par leurs
  //  éditeurs POUR être testés (films libres de la Fondation Blender,
  //  flux de référence Apple HLS, échantillons mux.dev). Jamais une
  //  chaîne réelle, jamais un lien de fournisseur.

  // — DIRECT : playlists HLS (le format des vraies chaînes) ————
  /// Flux de référence Apple, version **de base** (`bipbop_4x3`) :
  /// H.264 + AAC, une seule famille de codecs.
  ///
  /// PAS la version `img_bipbop_adv_example_*`. Preuve terrain (boîte
  /// noire du 2026-08-03, 07:18) : « Démo Info » a écrit un
  /// enregistrement de **71 Mo**. L'appareil ATTEINT donc le CDN et en
  /// tire du vrai média — le réseau et le lien sont hors de cause — et
  /// l'écran restait noir quand même. Le suspect qui reste est le
  /// contenu : l'exemple « advanced » d'Apple embarque des variantes
  /// HEVC et Dolby Vision à côté du H.264. Le décodage matériel est
  /// activé par défaut (`player.hardware_decode`) : si le décodeur se
  /// voit servir une variante qu'il ne sait pas traiter, on obtient
  /// exactement ça — des octets qui arrivent, et pas d'image.
  ///
  /// Passer de `_ts` à `_fmp4` ne changeait donc rien : c'est le MÊME
  /// jeu de variantes. Ce qu'il fallait retirer, c'est « advanced ».
  static const String _appleBasic =
      'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
      'bipbop_4x3/bipbop_4x3_variant.m3u8';
  static const String _hlsBunny =
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
  static const String _hlsSintel =
      'https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8';
  static const String _hlsTears =
      'https://demo.unified-streaming.com/k8s/features/stable/video/'
      'tears-of-steel/tears-of-steel.ism/.m3u8';

  // — CINÉMA : MP4 progressifs ————————————————————————
  //  Mêmes films (Blender, licence libre), servis en fichier fini : le
  //  lecteur les ouvre par son chemin VOD, avec seek et démarrage
  //  rapide. C'est aussi le chemin le plus dur à casser.
  static const String _mp4 =
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/';
  static const String _mp4Bunny = '${_mp4}BigBuckBunny.mp4';
  static const String _mp4Elephants = '${_mp4}ElephantsDream.mp4';
  static const String _mp4Sintel = '${_mp4}Sintel.mp4';
  static const String _mp4Tears = '${_mp4}TearsOfSteel.mp4';
  // Les trois « Guide » : des clips COURTS (~15 s). Une leçon qui dure
  // dix minutes n'est pas une leçon.
  static const String _mp4Short1 = '${_mp4}ForBiggerBlazes.mp4';
  static const String _mp4Short2 = '${_mp4}ForBiggerEscapes.mp4';
  static const String _mp4Short3 = '${_mp4}ForBiggerFun.mp4';

  static const List<Channel> _live = <Channel>[
    Channel(
      id: 'demo-live-1',
      name: 'Démo Sport',
      category: 'DÉMO || Sport',
      streamUrl: _hlsTears,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-2',
      name: 'Démo Info',
      category: 'DÉMO || Info',
      streamUrl: _appleBasic,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-3',
      name: 'Démo Divertissement',
      category: 'DÉMO || Divertissement',
      streamUrl: _hlsBunny,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-4',
      name: 'Démo Enfants',
      category: 'DÉMO || Enfants',
      streamUrl: _hlsBunny,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-5',
      name: 'Démo Musique',
      category: 'DÉMO || Musique',
      streamUrl: _hlsSintel,
      isLive: true,
    ),
    Channel(
      id: 'demo-live-6',
      name: 'Démo Documentaire',
      category: 'DÉMO || Documentaire',
      streamUrl: _hlsTears,
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
      streamUrl: _mp4Bunny,
      isLive: false,
    ),
    Channel(
      id: 'demo-vod-2',
      name: 'Démo — Film de démonstration 2',
      category: 'DÉMO FILMS || Catalogue',
      streamUrl: _mp4Elephants,
      isLive: false,
    ),
    Channel(
      id: 'demo-vod-3',
      name: 'Démo — Film de démonstration 3',
      category: 'DÉMO FILMS || Catalogue',
      streamUrl: _mp4Sintel,
      isLive: false,
    ),
    Channel(
      id: 'demo-vod-4',
      name: 'Démo — Film de démonstration 4',
      category: 'DÉMO FILMS || Catalogue',
      streamUrl: _mp4Tears,
      isLive: false,
    ),
    Channel(
      id: 'demo-tuto-1',
      name: 'Guide 1 — Ajouter ma source',
      category: 'DÉMO FILMS || Guide',
      streamUrl: _mp4Short1,
      isLive: false,
    ),
    Channel(
      id: 'demo-tuto-2',
      name: 'Guide 2 — Trouver une chaîne',
      category: 'DÉMO FILMS || Guide',
      streamUrl: _mp4Short2,
      isLive: false,
    ),
    Channel(
      id: 'demo-tuto-3',
      name: 'Guide 3 — Envoyer sur ma télé',
      category: 'DÉMO FILMS || Guide',
      streamUrl: _mp4Short3,
      isLive: false,
    ),
  ];

  /// Le bouquet complet : le clip embarqué EN TÊTE, puis direct,
  /// cinéma et guides.
  ///
  /// Le clip d'abord, et pas par vanité de marque : c'est la seule
  /// entrée du bouquet qui ne dépende ni du réseau, ni d'un CDN, ni
  /// d'une playlist à normaliser. Un client qui ouvre la démo tombe
  /// donc sur la vidéo qui a le plus de chances de partir — et si
  /// même celle-là reste noire, on sait immédiatement que le problème
  /// n'est pas dehors.
  ///
  /// Absent tant que `_extractBundledClip()` n'a pas réussi : mieux
  /// vaut une entrée en moins qu'une vignette qui ne s'ouvre pas.
  static List<Channel> get demoChannels => <Channel>[
        if (_clipPath != null)
          Channel(
            id: 'demo-clip-1',
            name: 'Démo — Découvrir 7 MOTION',
            category: 'DÉMO || Présentation',
            streamUrl: _clipPath!,
            isLive: false,
          ),
        ..._live,
        ..._vod,
      ];

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
