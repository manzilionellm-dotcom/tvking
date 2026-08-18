// =========================================================
//  tv_live_preview.dart — Aperçu vidéo EN DIRECT (écran « En direct »)
// =========================================================
//  Vignette de PRÉ-VISUALISATION de la chaîne focalisée (façon TiviMate/IBO) :
//    • moteur : plugin local `native_video_player` (ExoPlayer/Media3) — le
//      MÊME que TvPlayerScreen. JAMAIS media_kit (interdit dans le build TV) ;
//    • anti-rebond : le flux ne s'ouvre que [debounce] (~600 ms) après la
//      stabilisation du focus — zapper dans la liste n'ouvre AUCUNE connexion
//      pour les chaînes traversées (parité avec le zapping du plein écran) ;
//    • muet d'office (volume 0) : le son n'arrive qu'en plein écran ;
//    • repli : logo (+ petit spinner pendant le chargement) tant que la 1re
//      trame n'est pas dessinée ; si le flux échoue on RESTE sur le logo —
//      jamais de cadre noir vide ;
//    • cycle de vie : chaque changement de chaîne / retrait de l'arbre DISPOSE
//      le lecteur natif → jamais 2 flux d'aperçu ouverts en même temps.
//
//  L'URL jouée profite des MÊMES fallbacks que le plein écran (parité
//  TvPlayerScreen._loadCurrentUrl) : format gagnant mémorisé par la cascade
//  (XtreamUrlFormatStore), signature (User-Agent) gagnante de la source, et
//  relais local 1-connexion + DoH pour le live TS. On ne relance PAS la
//  cascade de sondes complète ici (elle ouvre jusqu'à 8 connexions — réservée
//  au plein écran) : un aperçu qui échoue retombe simplement sur le logo.
// =========================================================
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/playback/stream_slot.dart';

import '../../channels/domain/channel.dart';
import '../../player/data/local_stream_relay.dart';
import '../../player/data/stream_blocked_fallback.dart';
import '../../player/data/stream_diagnostics.dart';
import '../../player/data/xtream_url_variants.dart';
import '../../playlists/data/xtream_url_format_store.dart';
import '../../playlists/domain/playlist.dart' as pl;
import '../core/tv_dimens.dart';
import '../core/tv_logo.dart';
import '../core/tv_memory_guard.dart';
import '../core/tv_tokens.dart';

/// URL (et signature) effectives à jouer pour un aperçu.
class TvPreviewSource {
  const TvPreviewSource({required this.url, this.userAgent});
  final String url;
  final String? userAgent;
}

/// Résout l'URL d'aperçu d'une chaîne avec les mêmes fallbacks que le plein
/// écran. Injectable dans [TvLivePreview] (les tests fournissent un faux).
typedef TvPreviewResolver = Future<TvPreviewSource> Function(Channel channel);

class TvLivePreview extends StatefulWidget {
  const TvLivePreview({
    super.key,
    required this.channel,
    this.enabled = true,
    this.startImmediately = false,
    this.debounce = const Duration(milliseconds: 600),
    this.resolver,
  });

  /// Observer de navigation GLOBAL (enregistré par TvApp sur son Navigator).
  /// GARDE-FOU STABILITÉ : quand un écran est poussé PAR-DESSUS un écran qui
  /// contient un aperçu (l'accueil reste monté sous la route !), l'aperçu se
  /// LIBÈRE tout seul (didPushNext) et se réarme au retour (didPopNext).
  /// Sans ça, l'aperçu de l'accueil continuait de décoder sous « En
  /// direct » → 2 lecteurs ExoPlayer simultanés → RAM saturée sur les box
  /// modestes (retour terrain : « l'application s'est fermée ») + compte
  /// 1-connexion consommé pour rien.
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  /// TESTS UNIQUEMENT (simulateur TV, tests widget) : `true` = l'aperçu ne
  /// DÉMARRE jamais (il reste sur le repli logo, aucun lecteur créé).
  /// POURQUOI : en environnement de test il n'y a pas de plateforme native —
  /// monter une NativeVideoView (PlatformView hybrid composition) ferait
  /// échouer le test (canal `platform_views` absent). Ce drapeau permet de
  /// monter les VRAIS écrans d'accueil (qui embarquent l'aperçu) sans lui.
  /// `false` par défaut → comportement PRODUIT strictement inchangé.
  @visibleForTesting
  static bool debugDisableAutoStart = false;

  /// Chaîne focalisée dans la colonne du milieu.
  final Channel channel;

  /// `false` = aperçu suspendu (logo seul, aucun flux ouvert). L'écran le
  /// passe à `false` AVANT d'ouvrir le plein écran → jamais 2 flux ouverts.
  final bool enabled;

  /// `true` = la chaîne vient d'être SÉLECTIONNÉE (appui OK) : on saute
  /// l'anti-rebond et on démarre tout de suite — un choix explicite mérite
  /// une réponse immédiate. Le simple focus (défilement) reste anti-rebondi.
  final bool startImmediately;

  /// Répit sans changement de focus avant d'ouvrir le flux.
  final Duration debounce;

  /// Résolution d'URL (défaut : [resolveSource]). Surchargé par les tests.
  final TvPreviewResolver? resolver;

  /// Parité TvPlayerScreen._loadCurrentUrl : format gagnant mémorisé par la
  /// cascade + signature (UA) gagnante de la source + relais local pour le
  /// live TS (1 connexion, reconnexion, DoH). Best-effort : si le relais ne
  /// démarre pas, on retombe sur l'URL directe.
  static Future<TvPreviewSource> resolveSource(Channel channel) async {
    String url = channel.streamUrl;
    String? userAgent;
    final pl.Playlist? src = StreamBlockedFallback.xtreamPlaylistFor(channel);
    if (src?.id != null) {
      final XtreamContentType type =
          StreamBlockedFallback.contentTypeOf(channel);
      final String? code =
          await XtreamUrlFormatStore.instance.winningFormat(src!.id!, type);
      // Même auto-correctif que le plein écran : un format HLS mémorisé pour
      // du LIVE sature les comptes « max 1 connexion » → on l'ignore.
      final bool hlsLiveMemorized = type == XtreamContentType.live &&
          code != null &&
          code.contains('m3u8');
      if (code != null && !hlsLiveMemorized) {
        final String? remembered = XtreamUrlVariants.applyFormat(url, code);
        if (remembered != null) url = remembered;
      }
      userAgent = await XtreamUrlFormatStore.instance.sourceUserAgent(src.id!);
    }
    final String lower = url.toLowerCase();
    final bool isHls = lower.contains('.m3u8') || lower.contains('.m3u');
    if (!isHls) {
      try {
        url = await LocalStreamRelay.instance.playUrlFor(url);
      } catch (_) {
        // Relais indisponible → URL directe (ExoPlayer se débrouille).
      }
    }
    return TvPreviewSource(url: url, userAgent: userAgent);
  }

  @override
  State<TvLivePreview> createState() => _TvLivePreviewState();
}

class _TvLivePreviewState extends State<TvLivePreview>
    with RouteAware, WidgetsBindingObserver {
  NativeVideoController? _ctrl;
  Timer? _debounce;
  bool _resolving = false;

  /// `true` quand un AUTRE écran est posé par-dessus celui-ci (didPushNext) :
  /// l'aperçu reste coupé tant qu'on n'est pas revenu (didPopNext).
  bool _covered = false;

  /// Jeton anti-course : incrémenté à chaque reset — une résolution d'URL
  /// revenue APRÈS un changement de chaîne est simplement jetée.
  int _session = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) _schedule();
  }

  /// TERRAIN (2026-07-16) : « on quitte l'app TV et l'audio continue en
  /// arrière-plan ». Le lecteur PLEIN ÉCRAN se coupait déjà (son propre
  /// observer), mais PAS l'aperçu d'accueil : appuyer sur Home depuis
  /// l'accueil laissait l'ExoPlayer de l'aperçu jouer derrière le
  /// lanceur. Sur TV, quitter l'app = SILENCE, point. On libère tout en
  /// arrière-plan et on ré-arme au retour.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _reset(disposePlayer: true);
        if (mounted) setState(() {});
      case AppLifecycleState.resumed:
        if (widget.enabled && !_covered) _schedule();
      case AppLifecycleState.inactive:
        break; // transitions brèves (dialogue…) → on ne coupe pas
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<void>? route = ModalRoute.of(context);
    if (route != null) {
      TvLivePreview.routeObserver.subscribe(this, route);
      // MONTÉ SOUS UNE ROUTE (terrain : « la vidéo ne vient pas sur le
      // Modèle B »). Quand on choisit un template depuis l'écran
      // « Templates », le NOUVEL accueil se monte SOUS cette route encore
      // affichée — trop tard pour recevoir son didPushNext. Sans ce garde,
      // l'aperçu se croyait visible : il ouvrait le flux À COUVERT
      // (connexion 1-conn consommée pour rien) avec une SurfaceView créée
      // sous une route opaque — sur certaines box, cette surface ne
      // composite jamais → au retour, le raccourci « déjà chargé » gardait
      // ce lecteur mort et l'aperçu restait sans image. Ici : couvert tant
      // que la route n'est pas au sommet ; le didPopNext du retour ré-arme
      // un cycle COMPLET (lecteur + surface neufs, créés visibles).
      if (!route.isCurrent && !_covered) {
        _covered = true;
        _reset(disposePlayer: true);
      }
    }
  }

  /// Un écran vient d'être poussé PAR-DESSUS : libération complète du
  /// lecteur — jamais 2 flux/décodeurs ouverts en même temps (stabilité
  /// box faible RAM + comptes 1-connexion).
  @override
  void didPushNext() {
    _covered = true;
    _reset(disposePlayer: true);
    if (mounted) setState(() {});
  }

  /// Retour sur cet écran : on réarme l'aperçu — avec le RÉPIT LONG
  /// « retour de route » (cf. _schedule) : le lecteur plein écran qu'on
  /// vient de quitter est encore en train de rendre son décodeur.
  @override
  void didPopNext() {
    _covered = false;
    if (widget.enabled) _schedule(afterRouteReturn: true);
  }

  @override
  void didUpdateWidget(TvLivePreview old) {
    super.didUpdateWidget(old);
    // (Pas de setState ici : didUpdateWidget précède déjà un rebuild.)
    if (old.enabled != widget.enabled) {
      // Suspension / reprise (plein écran) : libération COMPLÈTE du lecteur
      // natif — c'est la garantie « jamais 2 flux ouverts ». La reprise
      // (false→true) n'arrive qu'au RETOUR d'un plein écran → répit long.
      _reset(disposePlayer: true);
      if (widget.enabled) _schedule(afterRouteReturn: true);
    } else if (old.channel.id != widget.channel.id) {
      // FLUIDITÉ : changer de chaîne NE détruit PAS la vue native (créer /
      // détruire une PlatformView + un ExoPlayer à chaque cran de défilement
      // saccadait toute l'UI). On garde le lecteur, on annule juste
      // l'anti-rebond en cours ; au prochain déclenchement, un simple setUrl
      // zappe — exactement comme le plein écran. On ARRÊTE la lecture pendant
      // la navigation : décoder une vidéo cachée sous le logo gaspillerait le
      // CPU de la box au moment où l'UI en a besoin.
      //
      // STOP et NON PAUSE (photo client 17/08, « Limite de connexions
      // atteinte — un autre écran regarde déjà avec ce compte ») : un lecteur
      // en PAUSE garde sa connexion HTTP ouverte vers le panel. En parcourant
      // la liste, chaque chaîne survolée laissait donc une session vivante, et
      // le plein écran suivant se voyait refuser par un abonnement 1-connexion.
      // `stop` libère la source et FERME la socket ; le prochain `setUrl`
      // rouvre proprement, sans détruire la vue native (donc sans saccade).
      _ctrl?.stop();
      _reset(disposePlayer: false);
      if (widget.enabled) _schedule();
    } else if (widget.enabled &&
        widget.startImmediately &&
        !old.startImmediately &&
        _playingChannelId != widget.channel.id &&
        !_resolving) {
      // La chaîne déjà focalisée vient d'être SÉLECTIONNÉE (OK) alors que
      // l'anti-rebond courait encore : on démarre sans attendre.
      _debounce?.cancel();
      _start();
    }
  }

  @override
  void dispose() {
    StreamSlot.instance.unregister(this);
    WidgetsBinding.instance.removeObserver(this);
    TvLivePreview.routeObserver.unsubscribe(this);
    _reset(disposePlayer: true);
    super.dispose();
  }

  /// Annule la tentative en cours. [disposePlayer] libère aussi le lecteur
  /// natif (sortie d'écran / plein écran) — sinon il est CONSERVÉ pour le
  /// prochain zap (fluidité).
  void _reset({required bool disposePlayer}) {
    _session++;
    _debounce?.cancel();
    _debounce = null;
    _presentGuard?.cancel();
    _presentGuard = null;
    _resolving = false;
    _loggedFirstFrame = false;
    _loggedError = false;
    if (disposePlayer) {
      // Le lecteur part : on se retire du verrou de connexion (un prochain
      // aperçu se ré-inscrira avec son nouveau lecteur).
      StreamSlot.instance.unregister(this);
      _ctrl?.removeListener(_onPlayer);
      _ctrl?.dispose();
      _ctrl = null;
      _playingChannelId = null;
      _uiFirstFrame = false;
      _uiHasError = false;
      _uiPlaying = false;
      _presented = false;
    }
  }

  /// RÉPIT LONG au retour d'un plein écran (lecteur/fiche) : à 600 ms,
  /// l'aperçu recréait un ExoPlayer pile pendant le release (thread player)
  /// de celui qu'on vient de quitter — et si l'utilisateur enchaînait vers
  /// Cinéma, ce lecteur tout neuf était re-détruit aussitôt : jusqu'à 3
  /// cycles création/destruction de décodeur en ~2 s autour d'une simple
  /// navigation (l'« accroche » sortie du live → Cinéma). À 1,8 s, une
  /// navigation enchaînée n'ouvre plus RIEN ; celui qui reste sur l'accueil
  /// ne voit qu'un logo ~1 s de plus.
  static const Duration _kResumeAfterRoute = Duration(milliseconds: 1800);

  void _schedule({bool afterRouteReturn = false}) {
    // Tests widget : aperçu neutralisé (cf. debugDisableAutoStart).
    if (TvLivePreview.debugDisableAutoStart) return;
    if (_covered) return; // un écran est posé par-dessus → aperçu coupé
    _debounce?.cancel();
    // TOUJOURS anti-rebondi ici : le démarrage immédiat d'une SÉLECTION (OK)
    // passe par la branche dédiée de didUpdateWidget (transition
    // startImmediately false→true), PAS par ce timer — sinon un simple
    // retour de focus sur la chaîne sélectionnée rouvrirait un flux sans
    // répit (churn de connexions, revue de code 2026-07-16).
    // PETITE BOX : anti-rebond rallongé (×2) — on n'ouvre un flux qu'après
    // une vraie pause du défilement (moins de churn décodeur/réseau).
    final Duration base = afterRouteReturn
        ? (_kResumeAfterRoute > widget.debounce
            ? _kResumeAfterRoute
            : widget.debounce)
        : widget.debounce;
    final Duration wait =
        TvMemoryGuard.instance.lowSpec ? base * 2 : base;
    _debounce = Timer(wait, _start);
  }

  /// Trace « boîte noire » (StreamDiagnostics, onglet Diagnostic des
  /// Réglages) : chaque étape de l'aperçu est journalisée pour qu'un échec
  /// silencieux (repli logo) reste DIAGNOSTICABLE à distance.
  void _diag(String message, {String level = 'info'}) {
    StreamDiagnostics.instance.recordEvent('aperçu', message, level: level);
  }

  Future<void> _start() async {
    // Tests widget : aucun démarrage (la branche startImmediately de
    // didUpdateWidget appelle _start directement — d'où ce second garde).
    if (TvLivePreview.debugDisableAutoStart) return;
    // Retour de focus sur la chaîne DÉJÀ chargée (sans erreur) : rien à
    // recharger — on relance juste la lecture (mise en pause pendant la
    // navigation) et la vidéo réapparaît instantanément.
    final NativeVideoController? already = _ctrl;
    if (already != null &&
        _playingChannelId == widget.channel.id &&
        !already.hasError &&
        // Arrêté (connexion rendue au panel pendant la navigation) : `play`
        // ne ferait rien, il n'y a plus de média chargé → on repasse par la
        // résolution + `setUrl` ci-dessous.
        !already.isStopped) {
      already.play();
      return;
    }
    final int session = _session;
    final String name = widget.channel.cleanName;
    _diag('[$name] anti-rebond écoulé → résolution de l\'URL d\'aperçu');
    setState(() => _resolving = true);
    TvPreviewSource? src;
    try {
      src = await (widget.resolver ?? TvLivePreview.resolveSource)(
          widget.channel);
    } catch (e) {
      src = null; // échec de résolution → on reste sur le logo
      _diag('[$name] résolution impossible : $e', level: 'warn');
    }
    if (!mounted || session != _session) {
      _diag('[$name] résolution abandonnée (focus déjà reparti)');
      return;
    }
    if (src == null) {
      setState(() => _resolving = false);
      return;
    }
    _diag('[$name] lecture aperçu : '
        '${StreamDiagnostics.maskCredentials(src.url)}'
        '${src.userAgent == null ? '' : ' (UA: ${src.userAgent})'}');
    // Lecteur PERSISTANT : créé au 1er aperçu, puis simple setUrl aux zaps
    // suivants (créer/détruire la vue native à chaque chaîne saccadait l'UI).
    if (_covered) return; // recouvert pendant la résolution → on n'ouvre pas
    NativeVideoController? c = _ctrl;
    if (c == null) {
      final NativeVideoController created = NativeVideoController(preview: true);
      created.setVolume(0); // muet — le son n'arrive qu'en plein écran
      created.addListener(_onPlayer);
      StreamSlot.instance.register(
        this,
        label: 'apercu accueil',
        // Référence STABLE (et non `_ctrl`, qui peut être remis à null par un
        // reset entre-temps) : le démontage doit rester valable même si
        // l'aperçu a changé d'état depuis l'inscription.
        teardown: () => created.stop(),
      );
      c = created;
    }
    // L'aperçu réclame le créneau comme tout le monde : il fait taire la file
    // de téléchargements avant d'ouvrir, et il sera lui-même démonté dès que
    // le plein écran réclamera. Une connexion à la fois, sans exception.
    await StreamSlot.instance.claim(this);
    if (!mounted || session != _session || _covered) return;
    c.setUrl(src.url, userAgent: src.userAgent);
    _presentGuard?.cancel(); // nouvelle chaîne : on ré-arme sur SA 1re trame
    _presentGuard = null;
    setState(() {
      _ctrl = c;
      _playingChannelId = widget.channel.id;
      _uiFirstFrame = false; // setUrl remet firstFrame à false côté contrôleur
      _uiHasError = false;
      _uiPlaying = false;
      _presented = false; // nouvelle chaîne : on ré-attend une vraie image
      _resolving = false;
    });
  }

  /// Chaîne actuellement CHARGÉE dans le lecteur persistant (null tant que
  /// rien n'a joué). Le logo recouvre la vidéo dès que la chaîne focalisée
  /// n'est plus celle-ci.
  String? _playingChannelId;

  // Journalise 1re image / erreur UNE seule fois par tentative (le
  // contrôleur notifie ~2×/s : sans ces verrous, la boîte noire déborde).
  bool _loggedFirstFrame = false;
  bool _loggedError = false;

  // Derniers états VISUELS pris en compte : on ne reconstruit le widget que
  // quand l'un d'eux change — pas à chaque tick de position (2×/s) du
  // lecteur, qui faisait travailler l'UI pour rien (fluidité).
  bool _uiFirstFrame = false;
  bool _uiHasError = false;
  bool _uiPlaying = false;

  // VERROU « aperçu réellement présenté » (correctif cadre NOIR, terrain
  // 2026-07-30). La `firstFrame` d'ExoPlayer est annoncée dès la PREMIÈRE
  // trame décodée ; sur certaines box la SurfaceView native peut afficher du
  // NOIR à cet instant précis (surface pas encore synchronisée, ou trame
  // noire de début de flux). Retirer le logo sur la SEULE `firstFrame`
  // laissait alors un cadre 100 % noir SANS repli. On ne masque donc le logo
  // qu'une fois la lecture VRAIMENT en cours (firstFrame + isPlaying) ; ce
  // drapeau se VERROUILLE à ce moment-là pour que la vidéo ne re-disparaisse
  // pas derrière le logo à chaque micro-rebuffer (isPlaying qui retombe).
  // Remis à false à chaque (re)chargement de chaîne et à chaque dispose.
  bool _presented = false;

  // FILET DE SÉCURITÉ (bug terrain 2026-07-30, aperçu bloqué sur le logo).
  // Sur certaines box, la 1re trame est bien rendue mais `isPlaying` n'est
  // JAMAIS notifié `true` (SurfaceView muette en hybrid-composition, volume 0,
  // pas de gestion d'audio-focus). Sans filet, `_presented` ne se verrouillait
  // jamais et l'aperçu restait coincé sur le logo POUR TOUJOURS. Ce timer, armé
  // dès une 1re trame saine, présente la vidéo après un COURT répit (surface
  // synchronisée → toujours pas de cadre noir) même si `isPlaying` n'arrive pas.
  Timer? _presentGuard;
  static const Duration _kPresentGuard = Duration(milliseconds: 400);

  void _onPlayer() {
    if (!mounted) return;
    final NativeVideoController? c = _ctrl;
    if (c == null) return;
    if (c.firstFrame && !_loggedFirstFrame) {
      _loggedFirstFrame = true;
      _diag('[${widget.channel.cleanName}] 1re image aperçu OK');
    }
    if (c.hasError && !_loggedError) {
      _loggedError = true;
      _diag(
          '[${widget.channel.cleanName}] échec aperçu : '
          '${c.lastErrorCodeName ?? 'erreur'}'
          '${c.lastErrorCode == null ? '' : ' (${c.lastErrorCode})'}'
          ' — ${c.lastErrorCauseMessage ?? c.lastErrorMessage ?? 'lecture impossible'}'
          ' → repli logo',
          level: 'warn');
    }
    // Le flux a-t-il VRAIMENT présenté une image animée ? (cf. _presented)
    if (c.firstFrame && c.isPlaying) _presented = true;
    // FILET : 1re trame saine mais `isPlaying` absent → on présente quand même
    // après un court répit (sinon l'aperçu reste bloqué sur le logo à vie).
    if (c.firstFrame && !c.hasError && !_presented && _presentGuard == null) {
      _presentGuard = Timer(_kPresentGuard, () {
        _presentGuard = null;
        if (!mounted) return;
        final NativeVideoController? c2 = _ctrl;
        if (c2 != null && c2.firstFrame && !c2.hasError && !_presented) {
          setState(() => _presented = true);
        }
      });
    }
    // Reconstruction UNIQUEMENT sur changement visuel (1re image / erreur /
    // lecture en cours) — jamais à chaque tick de position (2×/s).
    if (c.firstFrame != _uiFirstFrame ||
        c.hasError != _uiHasError ||
        c.isPlaying != _uiPlaying) {
      setState(() {
        _uiFirstFrame = c.firstFrame;
        _uiHasError = c.hasError;
        _uiPlaying = c.isPlaying;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final NativeVideoController? c = _ctrl;
    // La vidéo ne remplace le logo QU'UNE FOIS RÉELLEMENT PRÉSENTÉE (1re
    // trame dessinée + lecture EN COURS, cf. _presented), SANS erreur, et
    // seulement si le lecteur joue bien LA chaîne focalisée (pendant un zap,
    // le logo de la nouvelle chaîne recouvre l'ancienne vidéo).
    //
    // CORRECTIF « cadre NOIR » (terrain 2026-07-30) : on ne se fie plus à la
    // seule `firstFrame`. Sur certaines box la SurfaceView native peut être
    // NOIRE au moment exact où `firstFrame` est annoncée (surface pas encore
    // synchronisée / trame noire de début de flux) — on retirait alors le
    // logo pour ne montrer que du noir. Désormais on exige `isPlaying` (ou le
    // verrou `_presented` une fois la lecture réellement partie) : tant que le
    // flux ne joue pas pour de vrai, on RESTE sur le repli logo — jamais de
    // cadre noir. Le verrou évite que la vidéo re-disparaisse à chaque
    // micro-rebuffer.
    final bool sameChannel = _playingChannelId == widget.channel.id;
    final bool videoReady = c != null &&
        sameChannel &&
        !c.hasError &&
        c.firstFrame &&
        (c.isPlaying || _presented);
    final bool loading = _resolving ||
        (c != null && sameChannel && !videoReady && !c.hasError);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Fond de base OPAQUE : filet de sécurité ultime — même l'espace d'une
        // trame (vue vidéo pas encore montée ET repli pas encore peint), la
        // tuile n'est jamais transparente/noire mais d'un noir CHAUD de marque.
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: TvTokens.hairline),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (c != null) NativeVideoView(controller: c),
          if (!videoReady)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[TvTokens.card, TvTokens.bg],
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TvChannelLogo(
                      logoUrl: widget.channel.logoUrl,
                      label: widget.channel.name,
                      size: 88,
                      radius: 12),
                  const SizedBox(height: 12),
                  // NOM de la chaîne TOUJOURS affiché sous le logo. Repli
                  // ROBUSTE : même si le logo distant se charge en
                  // transparent / se rend en noir (ou si le monogramme
                  // n'apparaît pas), l'aperçu reste IDENTIFIABLE et n'est
                  // jamais un cadre « noir » anonyme. Le fond dégradé opaque
                  // ci-dessus garantit déjà la lisibilité du texte clair.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      widget.channel.cleanName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TvTokens.ui(TvDimens.label,
                          weight: FontWeight.w600, color: TvTokens.text),
                    ),
                  ),
                  if (loading) ...<Widget>[
                    const SizedBox(height: 10),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: TvTokens.gold),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
