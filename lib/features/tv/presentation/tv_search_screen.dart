// =========================================================
//  tv_search_screen.dart — Recherche 10-foot (clavier D-pad)
// =========================================================
//  Gauche : clavier à l'écran navigable à la télécommande (A-Z, 0-9,
//  espace, effacer). Droite : résultats en temps réel.
//
//  CHAÎNES LIVE : le matching n'est PLUS un `LIKE` SQL sur le nom.
//  On passe par [SmartSearch] (le MÊME moteur que le téléphone) :
//  « bein 1 » trouve « beIN SPORTS 1 », « cine » trouve « Ciné+ »,
//  une faute légère (« sprot ») trouve « Sport ». VOD / sport /
//  EPG restent sur leur propre chemin — ce n'est pas leur vague.
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
// `ValueListenable` n'est PAS réexporté par material.dart (contrairement à
// `ValueNotifier`, qui l'est) : sans cet import, la classe est introuvable.
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
// `KeyEvent` / `KeyDownEvent` : l'écoute des claviers physiques. Ils vivent
// dans `services`, que `material` ne réexporte pas.
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/external_keyboard.dart';
import '../core/tv_tokens.dart';
import '../../channels/domain/channel.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/data/search_history_repository.dart';
import '../../channels/data/smart_search.dart';
import '../../channels/data/watch_history_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/data/now_playing.dart';
import '../../epg/domain/epg_program.dart';
import '../../vod/data/recent_vod_repository.dart';
import '../../vod/data/series_repository.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/domain/vod_movie.dart';
import '../../vod/domain/vod_series.dart';
import 'tv_series_screen.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../sports/data/sport_search.dart';
import '../../sports/domain/sport_models.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_player_screen.dart';

class TvSearchScreen extends StatefulWidget {
  const TvSearchScreen({super.key});

  @override
  State<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends State<TvSearchScreen> {
  String _q = '';
  List<Channel> _results = const <Channel>[];

  /// ÉMISSIONS À L'ANTENNE dont le titre correspond à la requête, avec la
  /// chaîne qui les diffuse. C'est la recherche « inverse » : on part de
  /// l'émission qu'on veut voir et on remonte à la chaîne — pour ceux qui
  /// savent ce qu'ils veulent regarder sans connaître le nom du canal.
  List<({Channel channel, EpgProgram program})> _airing =
      const <({Channel channel, EpgProgram program})>[];
  /// MATCHS trouvés par NOM D'ÉQUIPE, avec la chaîne qui les diffuse.
  ///
  /// LE MANQUE QUE ÇA COMBLE (12/09/2026). Le propriétaire a tapé
  /// « Chelsea » et n'a vu que des films (« Cheaters », « Cheaper by the
  /// Dozen »). Normal, et c'est bien le problème : aucune chaîne ne
  /// s'APPELLE Chelsea, et le guide de son client ne couvre qu'une
  /// douzaine de chaînes sur neuf cents — chercher un titre d'émission ne
  /// pouvait donc pas trouver le match.
  ///
  /// Un nom d'équipe n'est ni un nom de chaîne, ni un titre d'émission :
  /// c'est une quatrième question, et elle a sa propre réponse
  /// (sport_search.dart), qui relie l'équipe au match puis le match à la
  /// chaîne.
  List<SportSearchHit> _matchs = const <SportSearchHit>[];
  // Résultats VOD (façon Netflix : la recherche couvre AUSSI films/séries).
  List<VodMovie> _films = const <VodMovie>[];
  List<VodSeries> _series = const <VodSeries>[];
  Timer? _debounce;
  // Jeton anti-désordre : chaque recherche asynchrone porte un numéro. Un
  // résultat qui revient APRÈS qu'une frappe plus récente soit partie est
  // ignoré (sinon une vieille requête lente écraserait la nouvelle).
  int _epoch = 0;

  // Borne anti-surcharge : 60 résultats max (largement assez pour trouver
  // une chaîne à la télécommande). C'est la [limit] passée à SmartSearch
  // — plus une LIMIT SQL : le moteur classe le bassin déjà en RAM.
  static const int _maxResults = 60;

  /// Signaux de personnalisation (favoris / récemment / temps regardé).
  /// Chargés en arrière-plan : tant qu'ils ne sont pas là, SmartSearch
  /// classe par pertinence textuelle seule (dégradation douce).
  SearchSignals _signals = SearchSignals.none;

  // =========================================================
  //  COMPLÈTEMENT DE SAISIE — « je veux un clavier haut de gamme »
  // =========================================================
  //  Ce qui sépare un clavier de télé ordinaire d'un bon n'est ni son
  //  animation ni ses couleurs : c'est LE NOMBRE D'APPUIS SUR LA
  //  TÉLÉCOMMANDE. Sur ce parc, une chaîne s'appelle « SE - C More Stars
  //  [multi-sub] ». À la télécommande, chaque lettre coûte 3 à 5 appuis
  //  de direction plus un OK. Taper ce nom en entier, c'est une minute.
  //
  //  On propose donc les noms complets dès la 2e lettre : trois lettres,
  //  un « haut », un OK, et la requête est écrite. C'est ce que font
  //  YouTube et les grandes apps, et c'est la seule chose qui change
  //  vraiment la vie de quelqu'un qui cherche avec une télécommande.
  //
  //  GRATUIT EN CALCUL : les noms sortent des résultats DÉJÀ trouvés pour
  //  la requête en cours. Aucune requête de plus, aucun index à tenir.
  //
  //  POURQUOI UN ValueNotifier ET PAS UN PARAMÈTRE. Le clavier est
  //  construit UNE SEULE FOIS (voir juste dessous) : lui passer les
  //  suggestions en paramètre ne les mettrait jamais à jour. Le
  //  reconstruire, lui, ferait perdre le focus à chaque frappe — le bug
  //  « impossible d'écrire d'autres lettres » qu'on a déjà corrigé. Le
  //  notifier traverse donc sans rien reconstruire d'autre que la rangée
  //  de suggestions elle-même.
  final ValueNotifier<List<String>> _suggestions =
      ValueNotifier<List<String>>(const <String>[]);

  // Le clavier est construit UNE SEULE FOIS. En réutilisant la MÊME instance
  // dans build(), Flutter NE reconstruit PAS son sous-arbre à chaque frappe →
  // la touche focus n'est jamais perdue (corrige « impossible d'écrire d'autres
  // lettres »). Les callbacks sont des méthodes stables de ce State.
  late final Widget _keyboard = _Keyboard(
    onType: _type,
    onBackspace: _backspace,
    onClear: _clear,
    suggestions: _suggestions,
    onSuggest: _searchFrom,
  );

  /// Construit les propositions à partir des résultats déjà en main.
  ///
  /// Trois règles, chacune pour une raison vécue :
  ///  - on ne propose rien sous 2 lettres : avec une seule, tout
  ///    correspond et la rangée n'aide pas, elle occupe ;
  ///  - on écarte le nom déjà tapé en entier — se proposer à soi-même
  ///    n'apporte rien et coûte une place ;
  ///  - 5 au maximum : au-delà, choisir devient plus long que taper.
  void _refreshSuggestions(List<Channel> from) {
    if (_q.trim().length < 2) {
      _suggestions.value = const <String>[];
      return;
    }
    final String deja = _q.trim().toLowerCase();
    final List<String> out = <String>[];
    final Set<String> vus = <String>{};
    for (final Channel c in from) {
      final String nom = c.cleanName.trim();
      if (nom.isEmpty || nom.toLowerCase() == deja) continue;
      if (!vus.add(nom.toLowerCase())) continue;
      out.add(nom);
      if (out.length == 5) break;
    }
    _suggestions.value = out;
  }

  // =========================================================
  //  TAPER AVEC AUTRE CHOSE QUE LA GRILLE (12/09/2026)
  // =========================================================
  //  « J'ai une télécommande sur mon téléphone, mais je ne parviens pas à
  //   écrire avec le clavier. » C'était impossible : cet écran n'avait
  //   aucun champ de saisie, donc rien ne pouvait recevoir un caractère
  //   venu d'ailleurs. Deux entrées manquaient, et elles sont différentes.
  //
  //  1. CLAVIER PHYSIQUE (Bluetooth, USB, certaines télécommandes) : il
  //     envoie des ÉVÉNEMENTS DE TOUCHE. Traité par `_surToucheExterne`,
  //     posé en ancêtre de tout l'écran : il voit les touches que la
  //     grille n'a pas consommées. Aucun mode à activer, ça marche tout
  //     de suite — et la navigation reste intacte, parce que la frontière
  //     texte/navigation vit dans external_keyboard.dart.
  //
  //  2. CLAVIER DU TÉLÉPHONE (application Télécommande de Google TV) : il
  //     n'envoie PAS de touches, il écrit dans le champ de saisie ACTIF
  //     du téléviseur. Il faut donc qu'un vrai champ existe et soit au
  //     premier plan — c'est `_champIme`, invisible, activé en ouvrant la
  //     barre de recherche.
  //
  //  POURQUOI LE MODE TÉLÉPHONE S'ACTIVE À LA DEMANDE, et n'est pas
  //  permanent : un champ de saisie au premier plan capte les flèches
  //  pour déplacer son curseur. Le laisser actif en permanence prendrait
  //  la télécommande en otage — la grille de lettres, elle, ne répondrait
  //  plus. On préfère un appui volontaire à une navigation cassée.
  final TextEditingController _champIme = TextEditingController();
  final FocusNode _focusIme = FocusNode(debugLabel: 'recherche-ime');

  /// Le champ de saisie a le focus : le client tape sur son téléphone.
  bool _clavierTelephone = false;

  /// Vrai pendant qu'on recopie la requête DANS le champ, pour que
  /// l'écouteur du champ ne renvoie pas cette écriture comme une frappe
  /// du client (boucle sans fin sinon).
  bool _recopieEnCours = false;

  @override
  void initState() {
    super.initState();
    // Charge l'historique des recherches (best-effort) pour proposer les
    // dernières recherches d'un clic quand la requête est vide.
    SearchHistoryRepository.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    // Favoris + historique : sans ça, « bein 1 » trouverait bien
    // beIN Sports 1, mais la variante que TU regardes ne remonterait
    // pas. Best-effort — une DB pas prête ne casse pas la recherche.
    _loadSignals();
    _champIme.addListener(_surTexteIme);
    _focusIme.addListener(_surFocusIme);
  }

  /// Charge les signaux [SmartSearch] (favoris, récemment, 30 jours).
  /// Même contrat que l'écran téléphone : jamais bloquant.
  Future<void> _loadSignals() async {
    try {
      await FavoritesRepository.instance.initialize();
      await RecentlyWatchedRepository.instance.initialize();
      final Map<String, int> watchMs =
          await WatchHistoryRepository.instance.watchTimeByChannel(days: 30);
      if (!mounted) return;
      setState(() {
        _signals = SearchSignals(
          favoriteIds: FavoritesRepository.instance.current,
          recentIds: RecentlyWatchedRepository.instance.current,
          watchMsById: watchMs,
        );
      });
      // Si le client a déjà tapé pendant le chargement, on reclasse
      // avec le boost — sinon le 1er résultat resterait « froid ».
      if (_q.trim().isNotEmpty) _schedule();
    } catch (_) {
      // Pertinence textuelle seule : toujours mieux que le LIKE d'avant.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestions.dispose();
    _champIme.removeListener(_surTexteIme);
    _focusIme.removeListener(_surFocusIme);
    _champIme.dispose();
    _focusIme.dispose();
    super.dispose();
  }

  /// Le client a tapé (ou effacé) sur le clavier de son téléphone.
  void _surTexteIme() {
    if (_recopieEnCours) return;
    final String t = _champIme.text;
    if (t == _q) return;
    setState(() => _q = t);
    _schedule();
  }

  void _surFocusIme() {
    if (!mounted) return;
    setState(() => _clavierTelephone = _focusIme.hasFocus);
  }

  /// Ouvre la saisie au clavier du téléphone : le champ passe au premier
  /// plan, la télécommande de Google TV a enfin où écrire.
  void _ouvrirClavierTelephone() {
    _recopierDansChamp();
    _focusIme.requestFocus();
  }

  /// Garde le champ invisible en phase avec la requête tapée à la grille.
  /// Sans ça, le client qui tape « CHE » à l'écran puis bascule sur son
  /// téléphone repartirait d'un champ vide et perdrait ses trois lettres.
  void _recopierDansChamp() {
    if (_champIme.text == _q) return;
    _recopieEnCours = true;
    _champIme.value = TextEditingValue(
      text: _q,
      selection: TextSelection.collapsed(offset: _q.length),
    );
    _recopieEnCours = false;
  }

  /// Touches venues d'un clavier PHYSIQUE, vues en ancêtre de l'écran.
  ///
  /// On ne répond qu'aux touches ENFONCÉES (`KeyDownEvent`) : une touche
  /// maintenue produit aussi des répétitions, que Flutter livre en
  /// `KeyRepeatEvent` — les traiter doublerait chaque lettre.
  KeyEventResult _surToucheExterne(FocusNode _, KeyEvent e) {
    // En mode téléphone, le champ de saisie fait déjà tout le travail :
    // traiter la touche ICI l'écrirait une seconde fois.
    if (_clavierTelephone) return KeyEventResult.ignored;
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (estRetourArriere(e.logicalKey)) {
      _backspace();
      return KeyEventResult.handled;
    }
    final String? c = caractereTapable(e.logicalKey, e.character);
    if (c == null) return KeyEventResult.ignored;
    _type(c);
    return KeyEventResult.handled;
  }

  // Relance une recherche depuis une pastille d'historique (sans re-taper).
  void _searchFrom(String query) {
    _debounce?.cancel();
    setState(() => _q = query);
    _recopierDansChamp();
    _runSearch();
  }

  void _type(String ch) {
    setState(() => _q += ch);
    // Le champ invisible suit la grille : le client peut taper trois
    // lettres à l'écran puis continuer sur son téléphone sans les perdre.
    _recopierDansChamp();
    _schedule();
  }

  void _backspace() {
    if (_q.isEmpty) return;
    setState(() => _q = _q.substring(0, _q.length - 1));
    _recopierDansChamp();
    _schedule();
  }

  void _clear() {
    _debounce?.cancel();
    _epoch++; // annule toute recherche en vol
    setState(() {
      _q = '';
      _results = const <Channel>[];
      _airing = const <({Channel channel, EpgProgram program})>[];
      _films = const <VodMovie>[];
      _series = const <VodSeries>[];
    });
    // Les propositions portaient sur une requête qui n'existe plus. Les
    // laisser afficherait des noms sans rapport avec un champ vide.
    _suggestions.value = const <String>[];
    _recopierDansChamp();
  }

  // Debounce : on ne relance la recherche (et le rendu des logos) qu'après une
  // courte pause → frappe fluide et pas de tempête de requêtes/chargements.
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  // CHAÎNES LIVE → [SmartSearch] (via PlaylistRepository.searchLiveChannels).
  // On ne LIKE plus le nom : « bein 1 » / « cine » / une faute légère
  // passent par le moteur partagé. Le bassin est le cache déjà en RAM
  // (plafond anti-OOM), pas un scan SQL à chaque lettre.
  Future<void> _runSearch() async {
    final String t = _q.trim();
    final int epoch = ++_epoch;
    if (t.isEmpty) {
      if (mounted) {
        setState(() {
          _results = const <Channel>[];
          _airing = const <({Channel channel, EpgProgram program})>[];
          _matchs = const <SportSearchHit>[];
          _films = const <VodMovie>[];
          _series = const <VodSeries>[];
        });
      }
      return;
    }
    final List<Channel> r = await PlaylistRepository.instance
        .searchLiveChannels(t, limit: _maxResults, signals: _signals);
    // Une frappe plus récente est partie entre-temps → on jette ce résultat.
    if (!mounted || epoch != _epoch) return;
    setState(() => _results = r);
    // Les propositions se déduisent de ces mêmes résultats : aucune requête
    // supplémentaire, et elles ne peuvent pas se désynchroniser de ce que
    // l'écran affiche.
    _refreshSuggestions(r);

    // ----- EN DIRECT MAINTENANT (recherche par ÉMISSION) -----
    // On interroge le guide pour les programmes À L'ANTENNE dont le titre
    // contient la requête, puis on remonte aux chaînes qui les diffusent.
    // Best-effort : sans guide importé, la section n'apparaît pas et la
    // recherche par nom de chaîne reste intacte.
    try {
      final List<EpgProgram> progs =
          await EpgRepository.instance.searchAiringNow(t);
      if (!mounted || epoch != _epoch) return;
      if (progs.isEmpty) {
        setState(() => _airing = const <({Channel channel, EpgProgram program})>[]);
      } else {
        // Une requête pour toutes les chaînes (IN …), jamais une par
        // programme : 40 résultats = 1 aller-retour SQLite, pas 40.
        final List<Channel> chs = await PlaylistRepository.instance
            .getChannelsByExternalIds(
                progs.map((EpgProgram p) => p.channelId).toList());
        if (!mounted || epoch != _epoch) return;
        final Map<String, Channel> byId = <String, Channel>{
          for (final Channel c in chs) c.id: c,
        };
        setState(() => _airing = <({Channel channel, EpgProgram program})>[
          // Un programme dont la chaîne n'est plus dans la playlist active
          // (guide plus large que la liste) est simplement ignoré.
          for (final EpgProgram p in progs)
            if (byId[p.channelId] != null)
              (channel: byId[p.channelId]!, program: p),
        ]);
      }
    } catch (_) {/* pas de guide → section absente */}

    // ----- MATCHS (recherche par NOM D'ÉQUIPE) -----
    // La quatrième question que peut poser une requête : « Chelsea » n'est
    // ni une chaîne, ni un film, ni un titre d'émission dans un guide
    // presque vide — c'est une ÉQUIPE. On remonte équipe → match → chaîne
    // (sport_search.dart, qui réutilise MatchChannelFinder, celui de
    // l'écran Sport : une seule règle pour « qui diffuse ce match »).
    //
    // Best-effort et jamais bloquant : cette recherche touche le réseau,
    // donc elle arrive APRÈS les chaînes et le guide, qui sont locaux et
    // instantanés. L'écran se remplit au fur et à mesure au lieu
    // d'attendre le maillon le plus lent.
    try {
      final List<SportSearchHit> hits = await SportSearch.rechercher(t);
      if (!mounted || epoch != _epoch) return;
      setState(() => _matchs = hits);
    } catch (_) {/* pas de réseau sport → section absente */}

    // ----- FILMS & SÉRIES (façon Netflix) -----
    // Les catalogues VOD sont en CACHE MÉMOIRE (déjà plafonné RAM). Le tout
    // est best-effort : les sections apparaissent quand elles sont prêtes,
    // et le jeton `epoch` jette tout résultat périmé. Une erreur réseau ne
    // casse jamais la recherche des chaînes.
    final String q = t.toLowerCase();
    try {
      final List<VodMovie> movies = await VodRepository.instance.fetchMovies();
      if (!mounted || epoch != _epoch) return;
      setState(() => _films = movies
          .where((VodMovie m) => m.name.toLowerCase().contains(q))
          .take(20)
          .toList(growable: false));
    } catch (_) {/* pas de VOD → section absente */}
    try {
      final List<VodSeries> series =
          await SeriesRepository.instance.fetchSeries();
      if (!mounted || epoch != _epoch) return;
      setState(() => _series = series
          .where((VodSeries s) => s.name.toLowerCase().contains(q))
          .take(20)
          .toList(growable: false));
    } catch (_) {/* idem */}
  }

  @override
  Widget build(BuildContext context) {
    final List<Channel> res = _results;
    // Material (transparent) au SOMMET de l'écran : cet écran est poussé depuis
    // PLUSIEURS endroits (boutons « Recherche » de tous les templates), parfois
    // sans ancêtre Material → Flutter dessinait alors des DOUBLES SOULIGNEMENTS
    // JAUNES sous chaque lettre du clavier. En s'enveloppant lui-même, l'écran
    // est TOUJOURS propre, quel que soit l'appelant (clavier net, « VIP »).
    return Material(
      type: MaterialType.transparency,
      // ÉCOUTE DES CLAVIERS PHYSIQUES (Bluetooth, USB, télécommandes qui
      // envoient de vraies touches). Placé en ANCÊTRE : il ne prend jamais
      // le focus (`canRequestFocus: false`, `skipTraversal: true`, donc la
      // navigation à la télécommande est rigoureusement inchangée), mais il
      // voit remonter les touches que la grille n'a pas consommées.
      // La frontière « texte ou navigation » vit dans external_keyboard.dart
      // et nulle part ailleurs : une flèche ne doit JAMAIS être écrite
      // comme un caractère, sinon la télécommande cesse de répondre.
      child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _surToucheExterne,
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ----- Clavier (instance STABLE → non reconstruite à chaque frappe) -----
        // 560 px (et non 380) depuis le passage en QWERTY : une rangée
        // compte désormais 10 touches (12 en arabe) au lieu de 6. À 380 px
        // elles seraient tombées sous les 32 px — illisibles à trois mètres.
        SizedBox(width: 560, child: _keyboard),
        const SizedBox(width: TvDimens.gutter),
        // ----- Requête + résultats -----
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // LA BARRE DE RECHERCHE EST DÉSORMAIS UN BOUTON.
              // C'était un simple affichage : on ne pouvait pas s'y poser,
              // donc rien n'ouvrait la saisie au clavier du téléphone. OK
              // dessus met le champ invisible au premier plan — et
              // l'application Télécommande a enfin où écrire.
              TvFocusable(
                scale: TvFocusScale.small,
                baseColor: TvTokens.card,
                onSelect: _ouvrirClavierTelephone,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _q.isEmpty ? context.l10n.tvSearchHint : _q,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color:
                                _q.isEmpty ? TvTokens.mutedDim : TvTokens.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.keyboard_alt_outlined,
                        size: 26,
                        color: _clavierTelephone
                            ? TvTokens.goldBright
                            : TvTokens.mutedDim,
                      ),
                    ],
                  ),
                ),
              ),
              // LE CHAMP INVISIBLE. Il ne se voit pas, mais il doit
              // EXISTER dans l'arbre et pouvoir prendre le focus : c'est
              // la seule chose qu'un clavier système (téléphone) sait
              // viser. Un widget `Offstage` ne conviendrait pas — il n'est
              // pas focalisable, et le clavier n'aurait toujours nulle
              // part où écrire.
              SizedBox(
                height: 0,
                child: Offstage(
                  offstage: false,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: TextField(
                      controller: _champIme,
                      focusNode: _focusIme,
                      autofocus: false,
                      style: const TextStyle(
                          fontSize: 1, color: Colors.transparent),
                      cursorWidth: 0,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _focusIme.unfocus(),
                    ),
                  ),
                ),
              ),
              if (_clavierTelephone) ...<Widget>[
                const SizedBox(height: 8),
                // On DIT au client ce qui se passe. Un champ invisible qui
                // capte la télécommande sans rien annoncer se vivrait
                // comme une panne : les flèches ne bougeraient plus la
                // grille et personne ne saurait pourquoi.
                Text(
                  context.l10n.tvSearchPhoneKeyboardOn,
                  style: const TextStyle(
                    fontSize: TvDimens.caption,
                    color: TvTokens.goldBright,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: (res.isEmpty &&
                        _airing.isEmpty &&
                        _matchs.isEmpty &&
                        _films.isEmpty &&
                        _series.isEmpty)
                    ? _buildEmptyState(context)
                    // RÉSULTATS EN SECTIONS (façon Netflix) : Chaînes, Films,
                    // Séries — chaque section est une rangée HORIZONTALE
                    // paresseuse (seules les vignettes visibles existent).
                    : ListView(
                        children: <Widget>[
                          // LES MATCHS EN PREMIER, et ce n'est pas un
                          // détail de mise en page : quelqu'un qui tape un
                          // nom d'équipe veut voir le match, pas défiler
                          // sous trois rangées de films au titre voisin.
                          // C'est exactement ce qui s'est passé avec
                          // « Chelsea » et « Cheaters ».
                          if (_matchs.isNotEmpty) ...<Widget>[
                            _sectionTitle(context.l10n.tvSearchMatches),
                            SizedBox(
                              height: 132,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                addAutomaticKeepAlives: false,
                                itemExtent: 330,
                                itemCount: _matchs.length,
                                itemBuilder: (BuildContext c, int i) =>
                                    Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _matchTile(_matchs[i]),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_airing.isNotEmpty) ...<Widget>[
                            _sectionTitle(context.l10n.tvProgramLive),
                            SizedBox(
                              height: 132,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                addAutomaticKeepAlives: false,
                                itemExtent: 330,
                                itemCount: _airing.length,
                                itemBuilder: (BuildContext c, int i) =>
                                    Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _airingTile(i),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (res.isNotEmpty) ...<Widget>[
                            _sectionTitle(context.l10n.tvTabChannels),
                            SizedBox(
                              // 152 et non 132 : la vignette porte une ligne
                              // de plus depuis qu'elle annonce l'émission en
                              // cours. Sans ces vingt pixels, le logo se
                              // serait écrasé pour faire de la place.
                              height: 152,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                addAutomaticKeepAlives: false,
                                itemExtent: 210,
                                itemCount: res.length,
                                itemBuilder: (BuildContext c, int i) =>
                                    Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _channelTile(res, i),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_films.isNotEmpty) ...<Widget>[
                            _sectionTitle(context.l10n.tvNavFilms),
                            SizedBox(
                              height: 214,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                addAutomaticKeepAlives: false,
                                itemExtent: 140,
                                itemCount: _films.length,
                                itemBuilder: (BuildContext c, int i) =>
                                    Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _filmCard(_films[i]),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_series.isNotEmpty) ...<Widget>[
                            _sectionTitle(context.l10n.tvNavSeries),
                            SizedBox(
                              height: 214,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                addAutomaticKeepAlives: false,
                                itemExtent: 140,
                                itemCount: _series.length,
                                itemBuilder: (BuildContext c, int i) =>
                                    Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _seriesCard(_series[i]),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
      ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TvTokens.mutedDim,
            letterSpacing: 1.6,
          ),
        ),
      );

  /// Vignette « EN DIRECT » : la chaîne + l'émission qu'elle diffuse en ce
  /// moment. Plus large qu'une vignette de chaîne : elle porte deux lignes
  /// d'information au lieu d'une. OK = lecture, dans la liste des chaînes
  /// « en direct » (◀ ▶ dans le lecteur zappe alors entre elles).
  ///
  /// LE BADGE EST BLEU, pas rouge. Le rouge (`TvTokens.live`) est réservé
  /// à la pastille du lecteur ; ici on est dans la recherche, et l'accent
  /// glacier de l'app (`gold`/`badgeBg`) dit « résultat mis en avant »
  /// sans crier. C'est ce que le propriétaire a demandé (« un bouton
  /// bleu »), et ça reste dans la palette — aucune couleur en dur.
  Widget _airingTile(int i) {
    final ({Channel channel, EpgProgram program}) hit = _airing[i];
    final Channel ch = hit.channel;
    final List<Channel> liste = _airing
        .map((({Channel channel, EpgProgram program}) e) => e.channel)
        .toList(growable: false);
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: () {
        SearchHistoryRepository.instance.add(_q);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TvPlayerScreen(channels: liste, startIndex: i),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: <Widget>[
            // Logo à gauche, taille fixe : les deux lignes de texte à
            // droite ont ainsi toujours la même largeur, quel que soit le
            // logo (certains sont très larges).
            SizedBox(
              width: 84,
              child: (ch.logoUrl != null && ch.logoUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: ch.logoUrl!,
                      fit: BoxFit.contain,
                      memCacheWidth: 200,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) =>
                          Opacity(opacity: 0.35, child: _ini(ch)),
                      errorWidget: (_, __, ___) => _ini(ch))
                  : _ini(ch),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Le badge bleu « EN DIRECT ».
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: TvTokens.badgeBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: TvTokens.gold),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.play_arrow_rounded,
                            size: 14, color: TvTokens.goldBright),
                        const SizedBox(width: 4),
                        Text(context.l10n.tvProgramLive,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: TvTokens.goldBright)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // L'ÉMISSION d'abord : c'est elle que l'utilisateur a
                  // tapée, c'est elle qu'il doit reconnaître au premier
                  // coup d'œil.
                  Text(hit.program.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: TvDimens.caption,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.text)),
                  const SizedBox(height: 2),
                  Text(ch.cleanName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: TvDimens.caption,
                          color: TvTokens.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vignette MATCH : l'affiche, l'heure, et OÙ LE REGARDER.
  ///
  /// DEUX ÉTATS, ET LA DIFFÉRENCE EST VOULUE :
  ///
  ///  • CHAÎNE TROUVÉE → la vignette prend le focus, OK lance la chaîne.
  ///    C'est la réponse complète à « montre-moi le match ».
  ///
  ///  • CHAÎNE INCONNUE → la vignette s'affiche quand même, en retrait, et
  ///    ne prend PAS le focus. On donne l'information qu'on a (le match,
  ///    son heure) sans poser un bouton qui ne mène nulle part : sur une
  ///    télécommande, appuyer sur OK et qu'il ne se passe rien se lit
  ///    comme une panne.
  ///
  /// Pourquoi ne pas simplement cacher ces matchs-là : parce que le guide
  /// du client couvre une douzaine de chaînes sur neuf cents. Les cacher
  /// ferait répondre « il n'y a pas de match » alors qu'il y en a un — le
  /// malentendu exact qu'on répare ici.
  Widget _matchTile(SportSearchHit hit) {
    final SportEvent e = hit.event;
    final Channel? ch = hit.channel;
    final Widget contenu = Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 84,
            child: (ch != null && ch.logoUrl != null && ch.logoUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: ch.logoUrl!,
                    fit: BoxFit.contain,
                    memCacheWidth: 200,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, __) => const Icon(Icons.sports_soccer,
                        size: 34, color: TvTokens.mutedDim),
                    errorWidget: (_, __, ___) => const Icon(
                        Icons.sports_soccer,
                        size: 34,
                        color: TvTokens.mutedDim),
                  )
                : const Icon(Icons.sports_soccer,
                    size: 34, color: TvTokens.mutedDim),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // EN DIRECT quand ça joue vraiment — c'est la source qui
                // le déclare (SportEvent.isLive), jamais notre horloge.
                if (e.isLive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: TvTokens.badgeBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: TvTokens.gold),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.play_arrow_rounded,
                            size: 14, color: TvTokens.goldBright),
                        const SizedBox(width: 4),
                        Text(context.l10n.tvProgramLive,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: TvTokens.goldBright)),
                      ],
                    ),
                  )
                else
                  Text(_quandMatch(e),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: TvTokens.mutedDim)),
                const SizedBox(height: 6),
                // L'AFFICHE d'abord : c'est le nom qu'il vient de taper.
                Text(e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: TvDimens.caption,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text)),
                const SizedBox(height: 2),
                Text(
                    ch != null
                        ? context.l10n.sportWatchOn(ch.cleanName)
                        : context.l10n.tvSearchMatchNoChannel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.caption,
                        color: ch != null
                            ? TvTokens.muted
                            : TvTokens.mutedDim)),
              ],
            ),
          ),
        ],
      ),
    );

    if (ch == null) {
      // Informatif : même gabarit, pas de focus, pas d'action.
      return Opacity(
        opacity: 0.55,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TvTokens.card,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          ),
          child: contenu,
        ),
      );
    }
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: () {
        SearchHistoryRepository.instance.add(_q);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                TvPlayerScreen(channels: <Channel>[ch], startIndex: 0),
          ),
        );
      },
      child: contenu,
    );
  }

  /// « 21:00 » pour ce soir, « 14 sept. · 21:00 » pour un autre jour.
  ///
  /// Formaté par MaterialLocalizations : la langue ET le format horaire
  /// (12 h / 24 h) suivent le réglage de la box, sans qu'on code une seule
  /// règle de date à la main.
  String _quandMatch(SportEvent e) {
    final DateTime? d = e.startsAt;
    if (d == null) return '';
    final MaterialLocalizations ml = MaterialLocalizations.of(context);
    final String heure = ml.formatTimeOfDay(
      TimeOfDay.fromDateTime(d),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    final DateTime n = DateTime.now();
    final bool aujourdhui =
        d.year == n.year && d.month == n.month && d.day == n.day;
    return aujourdhui ? heure : '${ml.formatMediumDate(d)} · $heure';
  }

  /// Vignette CHAÎNE (logo + nom). OK = lecture dans la liste des résultats.
  Widget _channelTile(List<Channel> list, int i) {
    final Channel ch = list[i];
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: () {
        // La recherche a servi (on ouvre un résultat) → on la mémorise.
        SearchHistoryRepository.instance.add(_q);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TvPlayerScreen(channels: list, startIndex: i),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: (ch.logoUrl != null && ch.logoUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: ch.logoUrl!,
                      fit: BoxFit.contain,
                      memCacheWidth: 200,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) =>
                          Opacity(opacity: 0.35, child: _ini(ch)),
                      errorWidget: (_, __, ___) => _ini(ch))
                  : _ini(ch),
            ),
            const SizedBox(height: 6),
            Text(ch.cleanName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: TvDimens.caption,
                    fontWeight: FontWeight.w600,
                    color: TvTokens.text)),
            // CE QUI PASSE MAINTENANT (12/09/2026). Le propriétaire, photo
            // à l'appui : les chaînes remontent, « mais les informations ne
            // viennent pas ». Une vignette qui ne porte qu'un logo et un
            // nom ne dit pas si la chaîne vaut le déplacement.
            _ProgrammeEnCours(key: ValueKey<String>(ch.id), channel: ch),
          ],
        ),
      ),
    );
  }

  /// Affiche FILM (poster 2:3 + titre). OK = lecture + mémorise la recherche.
  Widget _filmCard(VodMovie m) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: () {
        SearchHistoryRepository.instance.add(_q);
        RecentVodRepository.instance.add(m); // alimente « Derniers vus »
        final Channel ch = Channel(
          id: m.id,
          name: m.name,
          category: m.category,
          streamUrl: m.streamUrl,
          isLive: false,
          logoUrl: m.posterUrl,
        );
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                TvPlayerScreen(channels: <Channel>[ch], startIndex: 0),
          ),
        );
      },
      child: _posterAndTitle(m.posterUrl, m.name, Icons.movie_rounded),
    );
  }

  /// Affiche SÉRIE (poster + titre). OK = fiche de la série (saisons/épisodes).
  Widget _seriesCard(VodSeries s) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: () {
        SearchHistoryRepository.instance.add(_q);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TvSeriesDetailScreen(series: s),
          ),
        );
      },
      child: _posterAndTitle(s.posterUrl, s.name, Icons.live_tv_rounded),
    );
  }

  Widget _posterAndTitle(String? url, String name, IconData fallbackIcon) {
    final Widget fallback = Container(
      color: TvTokens.tile,
      child: Center(
          child: Icon(fallbackIcon, size: 30, color: TvTokens.mutedDim)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (url == null || url.isEmpty)
                ? fallback
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: 300,
                    // Fade court uniforme (150 ms, comme les autres tuiles)
                    // — le défaut (500 ms) traînait. Revue images V1.
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, __) => fallback,
                    errorWidget: (_, __, ___) => fallback,
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: TvDimens.caption,
                  fontWeight: FontWeight.w600,
                  color: TvTokens.text)),
        ),
      ],
    );
  }

  // État « pas de grille » : soit « aucun résultat » (requête en cours), soit
  // les RECHERCHES RÉCENTES cliquables (requête vide) — confort D-pad.
  Widget _buildEmptyState(BuildContext context) {
    if (_q.trim().isNotEmpty) {
      return Center(
        child: Text(
          context.l10n.tvNoResult,
          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim),
        ),
      );
    }
    final List<String> hist = SearchHistoryRepository.instance.items;
    if (hist.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.tvRecentSearches,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: TvTokens.mutedDim,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final String h in hist)
                TvFocusable(
                  scale: TvFocusScale.small,
                  onSelect: () => _searchFrom(h),
                  child: _chip(icon: Icons.history_rounded, label: h),
                ),
              TvFocusable(
                scale: TvFocusScale.small,
                onSelect: () async {
                  await SearchHistoryRepository.instance.clear();
                  if (mounted) setState(() {});
                },
                child: _chip(
                    icon: Icons.close_rounded,
                    label: context.l10n.buttonClear,
                    muted: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, bool muted = false}) {
    final Color fg = muted ? TvTokens.muted : TvTokens.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: TvTokens.muted),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

  Widget _ini(Channel c) => Center(
        child: Text(c.initials,
            style: TextStyle(fontSize: TvDimens.title, fontWeight: FontWeight.w800, color: TvTokens.muted)),
      );
}

/// Une ligne discrète sous le nom d'une chaîne : l'émission à l'antenne.
///
/// POURQUOI UN WIDGET À ÉTAT et pas un `FutureBuilder` posé dans la
/// vignette : la rangée de résultats se reconstruit à CHAQUE lettre tapée.
/// Un `FutureBuilder` recréerait sa future à chaque fois, donc repartirait
/// de « rien » et ferait clignoter la ligne sous les yeux du client. Ici
/// l'état survit tant que la chaîne reste à sa place (clé = son
/// identifiant), et la recherche ne clignote pas.
///
/// SILENCE QUAND ON NE SAIT PAS. Pas de « Programme non disponible », pas
/// de place réservée : la vignette reste exactement comme avant. Chez ce
/// client, le guide ne couvre qu'une douzaine de chaînes sur neuf cents —
/// annoncer l'absence sous huit cents vignettes transformerait un manque
/// discret en défaut criant.
class _ProgrammeEnCours extends StatefulWidget {
  const _ProgrammeEnCours({super.key, required this.channel});
  final Channel channel;

  @override
  State<_ProgrammeEnCours> createState() => _ProgrammeEnCoursState();
}

class _ProgrammeEnCoursState extends State<_ProgrammeEnCours> {
  EpgProgram? _prog;

  @override
  void initState() {
    super.initState();
    // Chemin RAPIDE : si la base locale l'a déjà en mémoire (cache de 60 s
    // de l'EPG), on affiche sans la moindre attente ni le moindre I/O.
    _prog = EpgRepository.instance.cachedCurrent(widget.channel.id);
    if (_prog == null) _charger();
  }

  Future<void> _charger() async {
    final EpgProgram? p = await NowPlaying.pour(widget.channel);
    if (!mounted || p == null) return;
    setState(() => _prog = p);
  }

  @override
  Widget build(BuildContext context) {
    final EpgProgram? p = _prog;
    if (p == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        p.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: TvDimens.caption,
          color: TvTokens.muted,
        ),
      ),
    );
  }
}

/// Langues du clavier à l'écran. Le client peut BASCULER d'une langue à l'autre
/// pour taper des noms de chaînes/films dans leur alphabet (ex. chaînes arabes,
/// chaînes nordiques). Ajouter une langue = ajouter une entrée ici + son tracé.
enum _KbLang { latin, nordic, arabic }

class _Keyboard extends StatefulWidget {
  const _Keyboard({
    required this.onType,
    required this.onBackspace,
    required this.onClear,
    required this.suggestions,
    required this.onSuggest,
  });
  final ValueChanged<String> onType;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// Noms complets proposés pour la requête en cours. Un notifier et non
  /// une liste : le clavier ne doit jamais être reconstruit (cf. l'écran).
  final ValueListenable<List<String>> suggestions;

  /// L'humain a choisi une proposition : elle devient la requête entière.
  final ValueChanged<String> onSuggest;

  @override
  State<_Keyboard> createState() => _KeyboardState();
}

class _KeyboardState extends State<_Keyboard> {
  // Langue de saisie ACTIVE (par défaut l'alphabet latin, qui couvre FR/EN…).
  _KbLang _lang = _KbLang.latin;

  // =========================================================
  //  TRACÉS EN RANGÉES — QWERTY (09/09/2026)
  // =========================================================
  //  Demandé par le propriétaire : « change ce clavier côté TV ».
  //
  //  CE QUI N'ALLAIT PAS. Les lettres étaient rangées dans l'ORDRE DE
  //  L'ALPHABET (A B C D E F / G H I J K L…). C'est la seule disposition
  //  que personne n'a dans les mains : ni sur un téléphone, ni sur un PC,
  //  ni sur les autres apps de la télé. Le client devait donc LIRE la
  //  grille lettre par lettre au lieu de viser d'instinct — six lignes à
  //  balayer pour trouver un « S ».
  //
  //  Et ce n'était pas un choix : c'était la conséquence d'un `Wrap`, qui
  //  se contente d'aligner une liste à plat et coupe où ça déborde. D'où
  //  aussi les rangées irrégulières, qui rendent le D-pad imprévisible —
  //  « bas » ne tombait pas sur la touche qu'on visait des yeux.
  //
  //  MAINTENANT : de vraies RANGÉES, en QWERTY. La mémoire des doigts
  //  fonctionne enfin, et chaque « bas » tombe droit sous la touche
  //  précédente parce que les rangées sont alignées.
  //
  //  Les CHIFFRES restent présents dans chaque langue (numéros de chaîne,
  //  années de films), sur leur propre rangée, comme sur un vrai clavier.
  static const List<String> _digitRow = <String>[
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
  ];

  static const List<List<String>> _latinRows = <List<String>>[
    <String>['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    <String>['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    <String>['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
  ];

  // Nordique : le QWERTY scandinave place Å après P, puis Ä Ö après L.
  // Æ et Ø (danois/norvégien) suivent, pour couvrir les trois pays avec
  // un seul tracé — c'est déjà le choix fait par l'app côté langues.
  static const List<List<String>> _nordicRows = <List<String>>[
    <String>['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', 'Å'],
    <String>['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'Ä', 'Ö'],
    <String>['Z', 'X', 'C', 'V', 'B', 'N', 'M', 'Æ', 'Ø'],
  ];

  // Arabe : l'ordre du CLAVIER arabe standard, pas l'ordre de l'alphabet.
  // Un arabophone cherche « ش » en haut à gauche de la 2e rangée, jamais
  // en 13e position d'un abécédaire. Les 32 caractères d'avant sont tous
  // conservés — aucune lettre perdue, seul l'ordre change.
  static const List<List<String>> _arabicRows = <List<String>>[
    <String>['ض', 'ص', 'ث', 'ق', 'ف', 'غ', 'ع', 'ه', 'خ', 'ح', 'ج', 'د'],
    <String>['ش', 'س', 'ي', 'ب', 'ل', 'ا', 'ت', 'ن', 'م', 'ك', 'ط', 'ذ'],
    <String>['ء', 'ر', 'ى', 'ة', 'و', 'ز', 'ظ', 'آ'],
  ];

  List<List<String>> get _rows => switch (_lang) {
        _KbLang.latin => _latinRows,
        _KbLang.nordic => _nordicRows,
        _KbLang.arabic => _arabicRows,
      };

  // Étiquette COURTE de chaque langue (sur le bouton de bascule).
  static String _label(_KbLang l) => switch (l) {
        _KbLang.latin => 'ABC',
        _KbLang.nordic => 'ÅÄÖ',
        _KbLang.arabic => 'عربي',
      };

  // Nom LISIBLE de la langue (pour le libellé « Langue : … »).
  static String _name(_KbLang l) => switch (l) {
        _KbLang.latin => 'ABC (latin)',
        _KbLang.nordic => 'Nordique ÅÄÖ',
        _KbLang.arabic => 'العربية',
      };

  void _cycleLang() {
    setState(() {
      const List<_KbLang> all = _KbLang.values;
      _lang = all[(_lang.index + 1) % all.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<List<String>> rows = _rows;
    final _KbLang next = _KbLang.values[(_lang.index + 1) % _KbLang.values.length];
    // La rangée la plus longue impose la taille des touches : toutes les
    // rangées partagent la même largeur de touche, sinon les colonnes ne
    // s'alignent plus et le D-pad redevient imprévisible.
    int plusLongue = _digitRow.length;
    for (final List<String> r in rows) {
      if (r.length > plusLongue) plusLongue = r.length;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.l10n.tvNavSearch,
            style: TextStyle(
                fontSize: TvDimens.displayS,
                fontWeight: FontWeight.w800,
                color: TvTokens.text)),
        const SizedBox(height: 12),
        // BOUTON DE LANGUE — en HAUT, bien visible (pensé personnes âgées).
        // Montre la langue ACTIVE et vers quoi on bascule. OK = langue suivante.
        _LangKey(
          current: _name(_lang),
          next: _label(next),
          onTap: _cycleLang,
        ),
        const SizedBox(height: 12),
        // ----- PROPOSITIONS : trois lettres au lieu de vingt -----
        // Placées ENTRE le bouton de langue et les touches, donc à un seul
        // « haut » depuis la première rangée. Une proposition qu'il faut
        // aller chercher à l'autre bout de l'écran ne sert à personne.
        ValueListenableBuilder<List<String>>(
          valueListenable: widget.suggestions,
          builder: (BuildContext context, List<String> noms, _) {
            if (noms.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String n in noms)
                    _SuggestChip(label: n, onTap: () => widget.onSuggest(n)),
                ],
              ),
            );
          },
        ),
        // La taille des touches se DÉDUIT de la place disponible au lieu
        // d'être gravée en dur : le même clavier tient sur une box 720p et
        // sur une 4K, et l'ajout d'une langue à rangées plus longues ne
        // déborde pas de la colonne.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            const double espace = 8;
            final double dispo = c.maxWidth;
            final double touche =
                ((dispo - espace * (plusLongue - 1)) / plusLongue)
                    .clamp(32.0, 56.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int r = 0; r < rows.length; r++) ...<Widget>[
                  _Row(
                    keys: rows[r],
                    size: touche,
                    gap: espace,
                    // Le focus arrive sur la 1re touche de la 1re rangée :
                    // le pouce part toujours du même endroit.
                    autofocusFirst: r == 0,
                    onTap: widget.onType,
                  ),
                  const SizedBox(height: espace),
                ],
                _Row(
                  keys: _digitRow,
                  size: touche,
                  gap: espace,
                  onTap: widget.onType,
                ),
                const SizedBox(height: espace),
                // Rangée d'action : espace (large, comme sur un vrai
                // clavier), effacer une lettre, tout effacer.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _Key(
                        label: '␣',
                        size: touche,
                        widthFactor: 3,
                        gap: espace,
                        onTap: () => widget.onType(' ')),
                    SizedBox(width: espace),
                    // MAINTENIR = TOUT EFFACER. Corriger une requête de
                    // vingt caractères coûtait vingt appuis. Le geste est
                    // celui qu'on a déjà dans les mains sur un téléphone.
                    _Key(
                        label: '⌫',
                        size: touche,
                        onTap: widget.onBackspace,
                        onHold: widget.onClear),
                    SizedBox(width: espace),
                    _Key(label: '✕', size: touche, onTap: widget.onClear),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// UNE rangée de touches. Exister en tant que widget n'est pas cosmétique :
/// c'est ce qui donne à Flutter des rangées ALIGNÉES, donc un déplacement
/// D-pad prévisible — « bas » tombe sous la touche qu'on regarde.
class _Row extends StatelessWidget {
  const _Row({
    required this.keys,
    required this.size,
    required this.gap,
    required this.onTap,
    this.autofocusFirst = false,
  });
  final List<String> keys;
  final double size;
  final double gap;
  final ValueChanged<String> onTap;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < keys.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: gap),
          _Key(
            label: keys[i],
            size: size,
            autofocus: autofocusFirst && i == 0,
            onTap: () => onTap(keys[i]),
          ),
        ],
      ],
    );
  }
}

/// Bouton DORÉ de bascule de langue du clavier. Large et lisible : montre la
/// langue active + un chevron vers la suivante. OK = passe à la langue suivante.
class _LangKey extends StatelessWidget {
  const _LangKey(
      {required this.current, required this.next, required this.onTap});
  final String current;
  final String next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 244,
      height: 54,
      child: TvFocusBuilder(
        scale: TvFocusScale.small,
        onSelect: onTap,
        builder: (BuildContext context, bool focused) {
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: focused ? TvTokens.gold : TvTokens.sel,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              border: Border.all(
                  color: focused ? TvTokens.gold : TvTokens.goldBright,
                  width: 1.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.language_rounded,
                    size: 22,
                    color: focused ? const Color(0xFF1A1206) : TvTokens.goldBright),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Langue : $current  →  $next',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.body,
                        fontWeight: FontWeight.w800,
                        color: focused ? const Color(0xFF1A1206) : TvTokens.text),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// UNE touche.
///
/// [size] est la taille de base ; [widthFactor] permet à la barre d'espace
/// d'occuper plusieurs colonnes SANS casser l'alignement (3 touches + les
/// 2 espacements qu'elle recouvre).
class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    required this.size,
    this.widthFactor = 1,
    this.gap = 8,
    this.autofocus = false,
    this.onHold,
  });
  final String label;
  final VoidCallback onTap;
  final double size;
  final int widthFactor;
  final double gap;
  final bool autofocus;

  /// Action au MAINTIEN d'OK (450 ms). Sert au retour arrière : maintenir
  /// efface tout, au lieu de vingt appuis.
  final VoidCallback? onHold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * widthFactor + gap * (widthFactor - 1),
      height: size,
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onTap,
        onLongPress: onHold,
        // `pressedBuilder` (et non `builder`) : il donne en plus l'état
        // APPUYÉ. Sans lui, la touche ne bronchait pas au moment du clic —
        // sur une télécommande, où il n'y a ni doigt ni curseur pour
        // confirmer, c'est le seul signal qui dit « c'est bien parti ».
        pressedBuilder: (BuildContext context, bool focused, bool pressed) {
          return AnimatedScale(
            // Enfoncement franc puis retour, comme une vraie touche.
            scale: pressed ? 0.94 : 1,
            duration: TvDimens.focusAnim,
            curve: TvDimens.focusCurve,
            child: AnimatedContainer(
              duration: TvDimens.focusAnim,
              curve: TvDimens.focusCurve,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: focused ? TvTokens.ember : TvTokens.sel,
                borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                // HALO au focus. Sur une télé regardée à trois mètres, le
                // seul changement de couleur se perd ; le halo dit où on
                // est d'un coup d'œil, même de loin et de biais.
                boxShadow: focused
                    ? <BoxShadow>[
                        BoxShadow(
                          color: TvTokens.ember.withValues(alpha: 0.55),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: TvDimens.title,
                      fontWeight: FontWeight.w800,
                      color: focused ? TvTokens.onEmber : TvTokens.text)),
            ),
          );
        },
      ),
    );
  }
}

/// PROPOSITION DE NOM COMPLET, au-dessus des touches.
///
/// Large et lisible : c'est un nom de chaîne, pas une lettre. On le
/// tronque plutôt que de laisser une puce s'étirer sur toute la colonne —
/// « SE - C More Stars [multi-sub] » ne doit pas pousser les touches hors
/// de l'écran. Le début du nom suffit à décider.
class _SuggestChip extends StatelessWidget {
  const _SuggestChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: TvFocusBuilder(
        scale: TvFocusScale.small,
        onSelect: onTap,
        builder: (BuildContext context, bool focused) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: focused ? TvTokens.ember : TvTokens.sel,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              // Contour discret hors focus : la rangée doit se lire comme
              // une proposition, pas comme une deuxième rangée de touches.
              border: Border.all(
                  color: focused ? TvTokens.ember : TvTokens.lineSoft),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.north_west_rounded,
                    size: 16,
                    color: focused ? TvTokens.onEmber : TvTokens.mutedDim),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: TvDimens.body,
                      fontWeight: FontWeight.w700,
                      color: focused ? TvTokens.onEmber : TvTokens.text,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
