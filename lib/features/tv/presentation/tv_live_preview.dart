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

class _TvLivePreviewState extends State<TvLivePreview> with RouteAware {
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
    if (widget.enabled) _schedule();
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

  /// Retour sur cet écran : on réarme l'aperçu (anti-rebond normal).
  @override
  void didPopNext() {
    _covered = false;
    if (widget.enabled) _schedule();
  }

  @override
  void didUpdateWidget(TvLivePreview old) {
    super.didUpdateWidget(old);
    // (Pas de setState ici : didUpdateWidget précède déjà un rebuild.)
    if (old.enabled != widget.enabled) {
      // Suspension / reprise (plein écran) : libération COMPLÈTE du lecteur
      // natif — c'est la garantie « jamais 2 flux ouverts ».
      _reset(disposePlayer: true);
      if (widget.enabled) _schedule();
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
    _resolving = false;
    _loggedFirstFrame = false;
    _loggedError = false;
    if (disposePlayer) {
      _ctrl?.removeListener(_onPlayer);
      _ctrl?.dispose();
      _ctrl = null;
      _playingChannelId = null;
      _uiFirstFrame = false;
      _uiHasError = false;
    }
  }

  void _schedule() {
    if (_covered) return; // un écran est posé par-dessus → aperçu coupé
    _debounce?.cancel();
    // TOUJOURS anti-rebondi ici : le démarrage immédiat d'une SÉLECTION (OK)
    // passe par la branche dédiée de didUpdateWidget (transition
    // startImmediately false→true), PAS par ce timer — sinon un simple
    // retour de focus sur la chaîne sélectionnée rouvrirait un flux sans
    // répit (churn de connexions, revue de code 2026-07-16).
    // PETITE BOX : anti-rebond rallongé (×2) — on n'ouvre un flux qu'après
    // une vraie pause du défilement (moins de churn décodeur/réseau).
    final Duration wait = TvMemoryGuard.instance.lowSpec
        ? widget.debounce * 2
        : widget.debounce;
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
      c = NativeVideoController(preview: true);
      c.setVolume(0); // muet d'office — le son n'arrive qu'en plein écran
      c.addListener(_onPlayer);
    }
    c.setUrl(src.url, userAgent: src.userAgent);
    setState(() {
      _ctrl = c;
      _playingChannelId = widget.channel.id;
      _uiFirstFrame = false; // setUrl remet firstFrame à false côté contrôleur
      _uiHasError = false;
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
                ],
              ),
            ),
        ],
      ),
    );
  }
}
