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

import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';

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
import '../data/failure_explainer.dart';
import '../data/tv_preview_arbiter.dart';

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
    this.onUnavailable,
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

  /// Signalé AU PLUS UNE fois par tentative quand l'aperçu ne peut pas
  /// montrer cette chaîne : résolution d'URL impossible, erreur du lecteur,
  /// ou AUCUNE image dessinée dans le délai du garde-fou de démarrage.
  /// L'accueil s'en sert pour basculer sur un AUTRE candidat héro (photo
  /// terrain 2026-08-01 : chaîne morte côté fournisseur → grand cadre
  /// inutile). L'aperçu, lui, reste sur le logo — jamais de noir.
  final VoidCallback? onUnavailable;

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

  /// Garde-fou de démarrage : un flux « accepté » qui ne dessine JAMAIS de
  /// première image (serveur qui pend) ne doit pas laisser l'accueil espérer
  /// indéfiniment — au délai, on signale [TvLivePreview.onUnavailable].
  Timer? _startupWatchdog;
  static const Duration _kStartupTimeout = Duration(seconds: 12);

  /// `true` dès que l'indisponibilité de la TENTATIVE courante a été
  /// signalée — jamais deux signaux pour la même tentative.
  bool _unavailableFired = false;

  /// SECONDE CHANCE (terrain 2026-08-01) : formats d'URL déjà essayés pour
  /// CETTE chaîne. Beaucoup de panels ne servent le live que sous
  /// `live/USER/PASS/ID.ts` — la forme nue renvoie 404 et l'aperçu mourait
  /// alors que le plein écran (qui déroule la cascade) jouait très bien.
  final Set<String> _triedFormats = <String>{};
  int _variantAttempts = 0;
  static const int _kMaxVariantAttempts = 2;

  /// Signature (User-Agent) retenue à la résolution — rejouée telle quelle
  /// sur les tentatives suivantes.
  String? _lastUserAgent;

  /// Format d'URL de la tentative EN COURS quand elle vient d'une seconde
  /// chance (ex. « live:ts »). S'il finit par donner une image, on le
  /// MÉMORISE pour toute la source : les autres aperçus et le plein écran
  /// partiront directement sur le bon format (terrain 2026-08-01 — une
  /// source neuve faisait échouer TOUS les aperçus tant qu'aucune chaîne
  /// n'avait été ouverte en plein écran, seul chemin qui apprenait).
  String? _pendingWinningFormat;

  /// Phrase AFFICHÉE sous le logo quand aucune image n'arrive : le client
  /// (et toi) savez tout de suite si c'est l'app ou le fournisseur.
  /// `null` tant qu'il n'y a rien d'anormal à dire.
  String? _whyNoImage;

  /// L'ABONNEMENT prime sur tout le reste : si le compte est expiré, AUCUNE
  /// chaîne ne peut marcher — inutile d'accuser la chaîne ou le réseau.
  void _setWhy(String fallback) {
    _whyNoImage = StreamDiagnostics.instance.subscriptionIssue ?? fallback;
  }

  /// L'APERÇU APPREND AUSSI (terrain 2026-08-01) : jusqu'ici, seul le
  /// plein écran mémorisait le format gagnant d'une source. Sur une source
  /// NEUVE, tous les aperçus échouaient donc tant que le client n'avait pas
  /// ouvert une chaîne en grand. Désormais, dès qu'une seconde chance donne
  /// une vraie image, son format est mémorisé pour toute la source.
  void _rememberWinningFormat() {
    final String? code = _pendingWinningFormat;
    _pendingWinningFormat = null;
    if (code == null) return;
    final pl.Playlist? src =
        StreamBlockedFallback.xtreamPlaylistFor(widget.channel);
    final int? id = src?.id;
    if (id == null) return;
    final XtreamContentType type =
        StreamBlockedFallback.contentTypeOf(widget.channel);
    _diag('[${widget.channel.cleanName}] format « $code » mémorisé depuis '
        'l\'aperçu — les prochaines chaînes partiront directement dessus');
    unawaited(
      XtreamUrlFormatStore.instance.saveWinningFormat(id, type, code),
    );
  }

  /// Tente la forme d'URL SUIVANTE de la cascade Xtream (au plus
  /// [_kMaxVariantAttempts] fois). Renvoie `true` si une nouvelle tentative
  /// est partie — l'aperçu ne se déclare alors PAS indisponible.
  Future<bool> _tryNextVariant() async {
    if (_variantAttempts >= _kMaxVariantAttempts) return false;
    final NativeVideoController? c = _ctrl;
    if (c == null || _covered || !mounted) return false;
    final XtreamContentType type =
        StreamBlockedFallback.contentTypeOf(widget.channel);
    if (_triedFormats.isEmpty) {
      // La 1re tentative a DÉJÀ essayé la forme d'origine — inutile de la
      // rejouer (terrain 2026-08-01 : l'aperçu re-testait la forme nue qui
      // venait de renvoyer 404, soit ~4 s perdues avant d'atteindre la
      // forme « live/… » qui, elle, répond 200).
      _triedFormats
        ..add('original')
        ..add(XtreamUrlVariants.formatCodeOf(widget.channel.streamUrl) ??
            'original');
    }
    final XtreamUrlCandidate? next = nextPreviewVariant(
      url: widget.channel.streamUrl,
      type: type,
      tried: _triedFormats,
    );
    if (next == null) return false;
    _variantAttempts++;
    _triedFormats.add(next.formatCode);
    final int session = _session;
    String url = next.url;
    // Même plomberie que la 1re tentative : relais local pour le TS
    // (1 connexion, reconnexion, DoH), URL directe pour le HLS.
    if (!url.toLowerCase().contains('.m3u8')) {
      try {
        url = await LocalStreamRelay.instance.playUrlFor(url);
      } catch (_) {
        // relais indisponible → URL directe
      }
    }
    if (!mounted || session != _session || _ctrl == null) return false;
    _diag('[${widget.channel.cleanName}] seconde chance (${next.formatCode}) : '
        '${StreamDiagnostics.maskCredentials(url)}');
    _unavailableFired = false;
    _loggedError = false;
    _pendingWinningFormat = next.formatCode;
    _ctrl!.setUrl(url, userAgent: _lastUserAgent);
    setState(() {
      _uiFirstFrame = false;
      _uiHasError = false;
      _whyNoImage = null;
    });
    _armStartupWatchdog();
    return true;
  }

  void _fireUnavailable(String reason) {
    if (_unavailableFired) return;
    _unavailableFired = true;
    _diag('[${widget.channel.cleanName}] aperçu indisponible ($reason)',
        level: 'warn');
    widget.onUnavailable?.call();
  }

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
    // ÉTATS INDÉPENDANTS (demande client) : dès qu'un AUTRE écran prend le
    // créneau d'aperçu (changement de template, ouverture de En direct…),
    // celui-ci rend son décodeur IMMÉDIATEMENT — plus jamais deux flux qui
    // se marchent dessus.
    TvPreviewArbiter.instance.addListener(_onArbiter);
    if (widget.enabled) _schedule();
  }

  void _onArbiter() {
    if (!mounted) return;
    if (_ctrl != null && !TvPreviewArbiter.instance.holds(this)) {
      _diag('[${widget.channel.cleanName}] créneau repris par un autre écran '
          '→ libération du décodeur');
      _reset(disposePlayer: true);
      setState(() {});
    }
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
    if (route != null) TvLivePreview.routeObserver.subscribe(this, route);
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
      // zappe — exactement comme le plein écran. On met la lecture en PAUSE
      // pendant la navigation : décoder une vidéo cachée sous le logo
      // gaspillerait le CPU de la box au moment où l'UI en a besoin.
      _ctrl?.pause();
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
    WidgetsBinding.instance.removeObserver(this);
    TvLivePreview.routeObserver.unsubscribe(this);
    TvPreviewArbiter.instance.removeListener(_onArbiter);
    TvPreviewArbiter.instance.release(this);
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
    _startupWatchdog?.cancel();
    _startupWatchdog = null;
    _unavailableFired = false;
    _whyNoImage = null; // nouvelle tentative → on repart sans verdict
    if (disposePlayer) {
      // Changement de chaîne / sortie d'écran : le crédit de secondes
      // chances repart à neuf (il est PAR CHAÎNE).
      _triedFormats.clear();
      _variantAttempts = 0;
    }
    _resolving = false;
    _loggedFirstFrame = false;
    _loggedError = false;
    if (disposePlayer) {
      // On rend le créneau : le prochain aperçu (autre template, autre
      // écran) démarrera INSTANTANÉMENT au lieu d'attendre une passation.
      // Sans effet si quelqu'un d'autre l'a déjà pris.
      TvPreviewArbiter.instance.release(this);
      _ctrl?.removeListener(_onPlayer);
      _ctrl?.dispose();
      _ctrl = null;
      _playingChannelId = null;
      _uiFirstFrame = false;
      _uiHasError = false;
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
  /// RAMENÉ de 1800 à 700 ms (demande client « une seconde c'est beaucoup ») :
  /// ce répit compensait à l'aveugle le fait que le décodeur du plein écran
  /// qu'on vient de quitter n'était pas encore rendu. L'ARBITRE sérialise
  /// désormais les créneaux (un seul aperçu vivant, passation explicite) —
  /// il ne reste à couvrir que la libération du LECTEUR plein écran, bien
  /// plus courte.
  static const Duration _kResumeAfterRoute = Duration(milliseconds: 700);

  void _schedule({bool afterRouteReturn = false}) {
    if (_covered) return; // un écran est posé par-dessus → aperçu coupé
    _debounce?.cancel();
    // DÉMARRAGE INSTANTANÉ (héro d'accueil) : quand l'appelant demande
    // explicitement zéro anti-rebond, la chaîne est FIXE (elle ne défile
    // pas sous le focus) — rien à protéger, on part sur-le-champ, sans
    // même passer par un timer (qui coûterait déjà une frame).
    if (!afterRouteReturn && widget.debounce == Duration.zero) {
      _start();
      return;
    }
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
    // Retour de focus sur la chaîne DÉJÀ chargée (sans erreur) : rien à
    // recharger — on relance juste la lecture (mise en pause pendant la
    // navigation) et la vidéo réapparaît instantanément.
    final NativeVideoController? already = _ctrl;
    if (already != null &&
        _playingChannelId == widget.channel.id &&
        !already.hasError) {
      already.play();
      return;
    }
    final int session = _session;
    final String name = widget.channel.cleanName;
    // PASSATION (états indépendants) : on prend le créneau — tout autre
    // aperçu vivant (template précédent, écran quitté) libère son décodeur
    // en recevant la notification. Le délai rendu vaut ZÉRO si personne ne
    // jouait (ouverture instantanée) ; sinon on laisse le temps au décodeur
    // sortant d'être réellement rendu avant d'en ouvrir un neuf.
    final Duration handover = TvPreviewArbiter.instance.acquire(this);
    _diag('[$name] anti-rebond écoulé → résolution de l\'URL d\'aperçu'
        '${handover > Duration.zero ? ' (passation ${handover.inMilliseconds} ms)' : ''}');
    setState(() => _resolving = true);
    if (handover > Duration.zero) {
      await Future<void>.delayed(handover);
      if (!mounted || session != _session) return;
    }
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
      setState(() {
        _resolving = false;
        _setWhy('Adresse du flux introuvable pour cette chaîne.');
      });
      _fireUnavailable('résolution impossible');
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
      c = NativeVideoController(preview: true);
      c.setVolume(0); // muet d'office — le son n'arrive qu'en plein écran
      c.addListener(_onPlayer);
    }
    _lastUserAgent = src.userAgent;
    c.setUrl(src.url, userAgent: src.userAgent);
    setState(() {
      _ctrl = c;
      _playingChannelId = widget.channel.id;
      _uiFirstFrame = false; // setUrl remet firstFrame à false côté contrôleur
      _uiHasError = false;
      _resolving = false;
    });
    // Nouvelle tentative → nouveau droit de signal + garde-fou réarmé.
    _unavailableFired = false;
    _armStartupWatchdog();
  }

  /// Garde-fou : si NI première image NI erreur n'arrive dans le délai
  /// (serveur qui accepte la connexion puis pend), on tente la forme d'URL
  /// suivante, et à défaut on déclare l'aperçu indisponible.
  void _armStartupWatchdog() {
    _startupWatchdog?.cancel();
    final int watchedSession = _session;
    _startupWatchdog = Timer(_kStartupTimeout, () async {
      if (!mounted || watchedSession != _session) return;
      final NativeVideoController? w = _ctrl;
      if (w == null || w.firstFrame || w.hasError) return;
      if (await _tryNextVariant()) return;
      if (!mounted || watchedSession != _session) return;
      // Le serveur a accepté la connexion mais n'envoie aucune image :
      // le cas typique d'une chaîne coupée côté fournisseur.
      setState(() => _setWhy(
          'Le serveur répond mais n\'envoie aucune image — chaîne '
          'probablement coupée chez le fournisseur.'));
      _fireUnavailable('aucune image en ${_kStartupTimeout.inSeconds} s');
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

  void _onPlayer() {
    if (!mounted) return;
    final NativeVideoController? c = _ctrl;
    if (c == null) return;
    if (c.firstFrame && !_loggedFirstFrame) {
      _loggedFirstFrame = true;
      _startupWatchdog?.cancel(); // 1re image → garde-fou inutile
      _diag('[${widget.channel.cleanName}] 1re image aperçu OK');
      _rememberWinningFormat();
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
      _startupWatchdog?.cancel();
      // Le POURQUOI humain, depuis la table de traduction déjà testée de
      // la Boîte noire (codes Media3 stables → phrase française).
      final PlaybackFailureExplanation why = explainPlaybackFailure(
        errorCodeName: c.lastErrorCodeName,
        errorCode: c.lastErrorCode,
        cause: c.lastErrorCauseMessage ?? c.lastErrorMessage,
      );
      // SECONDE CHANCE d'abord : beaucoup de panels ne servent le live que
      // sous une AUTRE forme d'URL (terrain : 404 en aperçu, plein écran OK).
      unawaited(_tryNextVariant().then((bool retried) {
        if (retried || !mounted) return;
        setState(() => _setWhy(why.why));
        _fireUnavailable('erreur lecteur');
      }));
    }
    // Reconstruction UNIQUEMENT sur changement visuel (1re image / erreur).
    if (c.firstFrame != _uiFirstFrame || c.hasError != _uiHasError) {
      setState(() {
        _uiFirstFrame = c.firstFrame;
        _uiHasError = c.hasError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final NativeVideoController? c = _ctrl;
    // La vidéo ne remplace le logo QU'À la 1re trame dessinée, SANS erreur,
    // et seulement si le lecteur joue bien LA chaîne focalisée (pendant un
    // zap, le logo de la nouvelle chaîne recouvre l'ancienne vidéo) →
    // jamais de cadre noir vide, jamais d'image d'une autre chaîne.
    final bool sameChannel = _playingChannelId == widget.channel.id;
    final bool videoReady =
        c != null && sameChannel && c.firstFrame && !c.hasError;
    final bool loading = _resolving ||
        (c != null && sameChannel && !c.firstFrame && !c.hasError);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
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
                  if (loading) ...<Widget>[
                    const SizedBox(height: 10),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: TvTokens.gold),
                    ),
                  ],
                  // LE POURQUOI, À L'ÉCRAN (demande client) : quand aucune
                  // image ne vient, on ne laisse plus le client deviner si
                  // c'est l'app ou son fournisseur. Deux lignes maximum,
                  // discrètes, jamais pendant le chargement normal.
                  if (!loading && _whyNoImage != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        _whyNoImage!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(12, color: TvTokens.mutedDim),
                      ),
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
