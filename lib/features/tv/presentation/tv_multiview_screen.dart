// =========================================================
//  tv_multiview_screen.dart — Multi-vue 2 chaînes (sport)
// =========================================================
//  Affiche DEUX chaînes côte à côte (chacune son propre lecteur ExoPlayer).
//  ◀ ▶ : change la tuile ACTIVE (celle qui a le SON ; l'autre est muette).
//  OK  : ouvre la tuile active en plein écran. Retour : ferme la multi-vue.
//
//  ANTI-OOM / STABILITÉ : décoder 2 flux HD simultanément demande du matériel.
//  On RÉSERVE donc la multi-vue aux box assez puissantes (RAM ≥ ~2 Go, hors
//  mode « low RAM ») — sur une petite box (type Fire Stick 1 Go), on n'essaie
//  même pas (message clair) plutôt que de risquer un plantage. C'est cohérent
//  avec la promesse « ça ne crashe jamais ».
//
//  CONNEXIONS AMONT (« max connexions » du fournisseur) — CONTRAT EXPLICITE
//  ----------------------------------------------------------------------
//  La multi-vue est la SEULE partie de l'app qui ouvre VOLONTAIREMENT plus
//  d'un flux amont : EXACTEMENT DEUX (une par tuile), c'est son but même.
//  Ces deux flux sont tirés EN DIRECT par le lecteur natif (URL réelle du
//  fournisseur), ils NE passent PAS par LocalStreamRelay — ils échappent donc
//  au comptage du relais (activeUpstreamCount). Depuis l'audit du 19/08 :
//    • ENTRÉE : les deux tuiles S'INSCRIVENT au StreamSlot (groupe
//      `multiview` — elles se tolèrent entre elles) et RÉCLAMENT le créneau
//      avant d'ouvrir : l'aperçu, la file de téléchargements et le lecteur
//      du dessous (déjà arrêté par _openMultiview) sont démontés ET attendus.
//      Sur une ligne 1-connexion, l'entrée est refusée en amont avec un
//      message clair (tv_player_screen._openMultiview).
//    • SORTIE (dispose / BACK / plein écran) : l'arrêt réel des deux tuiles
//      (stop natif attendu puis dispose) est confié au créneau via handOff —
//      le lecteur qui suit (pushReplacement) ATTEND cette fermeture au lieu
//      d'ouvrir sa connexion pendant que les tuiles décodent encore.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:native_video_player/native_video_player.dart';

import '../../../core/app/device_memory.dart';
import '../../../core/playback/stream_slot.dart';
import '../../channels/domain/channel.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_player_screen.dart';

/// Vrai si la box est jugée assez puissante pour 2 flux simultanés.
bool multiViewSupported() =>
    DeviceMemory.isLoaded &&
    !DeviceMemory.lowRam &&
    DeviceMemory.totalMb >= 2048;

class TvMultiViewScreen extends StatefulWidget {
  const TvMultiViewScreen({
    required this.channels,
    required this.startIndex,
    super.key,
  });

  final List<Channel> channels;
  final int startIndex;

  @override
  State<TvMultiViewScreen> createState() => _TvMultiViewScreenState();
}

class _TvMultiViewScreenState extends State<TvMultiViewScreen>
    with WidgetsBindingObserver {
  final FocusNode _focus = FocusNode();
  late final List<Channel> _two;
  late final List<NativeVideoController> _ctrl;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final int n = widget.channels.length;
    final Channel a = widget.channels[widget.startIndex.clamp(0, n - 1)];
    final Channel b = widget.channels[(widget.startIndex + 1) % n];
    _two = <Channel>[a, b];
    // SANS initialUrl (audit 19/08, même mécanisme que le lecteur plein
    // écran) : la vue native joue initialUrl dès son attach — AVANT que le
    // créneau ait démonté et attendu les autres consommateurs (aperçu,
    // téléchargements, lecteur du dessous en cours de fermeture). Rien ne
    // se joue tant que claim() n'a pas rendu la main.
    _ctrl = <NativeVideoController>[
      NativeVideoController(),
      NativeVideoController(),
    ];
    // La tuile 1 (droite) démarre MUETTE : une seule source audio à la fois.
    _ctrl[1].setVolume(0);
    // VERROU DE CONNEXION (audit 19/08 : la multi-vue vivait hors créneau —
    // ni l'aperçu ni les téléchargements n'étaient démontés, et rien ne
    // pouvait la démonter). Les DEUX tuiles s'inscrivent dans le groupe
    // `multiview` (elles se tolèrent entre elles) ; UNE réclamation suffit
    // à démonter — et attendre — tous les détenteurs solo/downloads.
    StreamSlot.instance.register(
      _ctrl[0],
      group: StreamSlot.groupMultiview,
      label: 'multi-vue tuile A',
      teardown: () => _ctrl[0].stop(),
    );
    StreamSlot.instance.register(
      _ctrl[1],
      group: StreamSlot.groupMultiview,
      label: 'multi-vue tuile B',
      teardown: () => _ctrl[1].stop(),
    );
    unawaited(StreamSlot.instance.claim(_ctrl[0]).then((_) {
      if (!mounted) return;
      _openTiles();
    }));
  }

  /// (Ré)ouvre les deux tuiles sur leurs chaînes, volume selon la tuile
  /// active. Appelé après l'obtention du créneau (initState, retour de
  /// veille) — jamais directement.
  void _openTiles() {
    for (int k = 0; k < _ctrl.length; k++) {
      _ctrl[k].setUrl(_two[k].streamUrl);
      // RÉ-APPLIQUE le volume : on ne suppose pas qu'il survit à setUrl.
      _ctrl[k].setVolume(k == _active ? 1.0 : 0.0);
    }
  }

  // App minimisée (Home / veille / autre app) → ARRÊT COMPLET des deux
  // tuiles : pas de son en arrière-plan sur TV, et surtout les DEUX sockets
  // amont sont rendues au fournisseur (l'ancienne « LIMITE CONNUE » — pause
  // qui gardait les sockets — est levée depuis que le plugin expose stop(),
  // attendable, qui ferme démuxeur + connexion sans détruire le contrôleur).
  // Au retour : ré-arbitrage par le créneau puis réouverture des deux URLs.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // ARRÊT COMPLET, pas une pause (audit 19/08) : le plugin expose
        // désormais stop() — une pause gardait les DEUX sockets amont
        // ouvertes pendant toute la mise en veille (la « LIMITE CONNUE »
        // historique de ce fichier n'a plus lieu d'être).
        for (final NativeVideoController c in _ctrl) {
          unawaited(c.stop());
        }
      case AppLifecycleState.resumed:
        // Retour de veille : ré-arbitrage par le créneau AVANT de rouvrir
        // (l'aperçu ou un téléchargement a pu prendre la ligne entre-temps),
        // puis réouverture séquencée des deux tuiles.
        unawaited(StreamSlot.instance.claim(_ctrl[0]).then((_) {
          if (mounted) _openTiles();
        }));
      case AppLifecycleState.inactive:
        break; // transitions brèves (dialogue…) → on ne coupe pas
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // TEARDOWN GARANTI « zéro flux fantôme » (BACK, plein écran, fermeture) —
    // et ATTENDU par le suivant (audit 19/08) : le pushReplacement vers le
    // plein écran ne dispose cette route qu'APRÈS la transition ; sans
    // détenteur de transition, le lecteur plein écran ouvrait sa connexion
    // pendant que les 2 tuiles décodaient encore (3 flux amont). handOff :
    // le claim() du lecteur suivant attend l'arrêt réel des deux tuiles.
    final List<NativeVideoController> leaving = _ctrl;
    final Future<void> shutdown = () async {
      for (final NativeVideoController c in leaving) {
        try {
          await c.stop();
        } catch (_) {
          // canal natif déjà mort : la socket est fermée de toute façon.
        }
      }
      for (final NativeVideoController c in leaving) {
        try {
          c.dispose();
        } catch (_) {
          // best-effort : le natif a peut-être déjà relâché ce lecteur ; on
          // continue impérativement avec la ou les tuiles suivantes.
        }
      }
    }();
    StreamSlot.instance.handOff(leaving[0], shutdown,
        label: 'fermeture multi-vue');
    StreamSlot.instance.unregister(leaving[1]);
    _focus.dispose();
    super.dispose();
  }

  void _setActive(int i) {
    if (i == _active) return;
    setState(() => _active = i);
    for (int k = 0; k < _ctrl.length; k++) {
      _ctrl[k].setVolume(k == i ? 1.0 : 0.0);
    }
  }

  void _fullscreenActive() {
    // Ouvre la tuile active en plein écran (lecteur normal). On quitte la
    // multi-vue pour libérer le 2e décodeur.
    final Channel ch = _two[_active];
    final int idx = widget.channels.indexOf(ch);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(
          channels: widget.channels,
          startIndex: idx < 0 ? 0 : idx,
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _setActive(0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _setActive(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA) {
      _fullscreenActive();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Row(
          children: <Widget>[
            Expanded(child: _tile(0)),
            const SizedBox(width: 4),
            Expanded(child: _tile(1)),
          ],
        ),
      ),
    );
  }

  Widget _tile(int i) {
    final bool active = i == _active;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        NativeVideoView(controller: _ctrl[i]),
        // Cadre or sur la tuile active (celle qui a le son).
        IgnorePointer(
          child: AnimatedContainer(
            duration: TvDimens.focusAnim,
            decoration: BoxDecoration(
              border: Border.all(
                color: active ? TvTokens.gold : Colors.transparent,
                width: 3,
              ),
            ),
          ),
        ),
        // Bandeau nom + pastille son.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xB3000000),
            child: Row(
              children: <Widget>[
                Icon(active ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    size: 16,
                    color: active ? TvTokens.gold : TvTokens.mutedDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _two[i].cleanName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.label,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
