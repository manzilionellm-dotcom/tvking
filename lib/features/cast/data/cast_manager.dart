// =========================================================
//  cast_manager.dart — État global du casting
// =========================================================
//  Centralise tout le cycle de vie d'une session de cast :
//    - Discovery (SSDP)
//    - Sélection d'un device
//    - Envoi du flux
//    - Play / Pause / Stop / Disconnect
//
//  Exposé en singleton ChangeNotifier pour que tous les écrans
//  qui veulent afficher l'état (mini-player, bouton cast, etc.)
//  se mettent à jour automatiquement.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Socket;

import 'package:flutter/foundation.dart';

import '../../../core/observability/structured_logger.dart';
import '../../player/data/pip_service.dart';
import '../domain/cast_device.dart';
import 'cast_progress.dart';
import 'cast_session_diagnostic.dart';
import 'cast_transport.dart';
import 'google_cast_transport.dart';
import 'dlna_capabilities.dart';
import 'dlna_profiles.dart';
import 'google_cast_api.dart';
import 'local_cast_server.dart';
import 'mdns_discovery.dart';
import 'ssdp_discovery.dart';
import 'stream_probe.dart';
import 'upnp_av_transport.dart';

/// Phase 1 / F-09 : plafond dur sur une session [castTo]. Au-dela,
/// on coupe net et on remonte un message UX clair plutot que de
/// laisser l'utilisateur attendre 60-90s sans signal.
///
/// 25s = compromis empirique : assez large pour 5 strategies x ~3-5s
/// chacune dans le cas median, assez court pour ne pas faire
/// abandonner l'utilisateur.
///
/// 2026-06-06 : releve de 25 s -> 40 s. Diag terrain LG QNED816QA :
/// la 1re tentative DIRECTE timeout a 15 s, et avec un budget de 25 s
/// le RELAIS (s=3/4) n'etait jamais atteint avant la coupe globale.
/// 40 s laisse la place a "1 direct (15 s) + relais (jusqu'a ~20 s)".
/// Couple a la regle skip-direct->relais (cf. _castDlnaWithFailover),
/// le cas median reste rapide ; seul l'echec complet va jusqu'a 40 s.
const Duration kCastTotalTimeout = Duration(seconds: 40);

/// Budget global DLNA — plus large que le Chromecast : l'échelle de
/// failover (jusqu'à 9 stratégies, SOAP 15 s chacune) + les rendeurs
/// LENTS (diag Nebula 2026-07-09 : relay+full réussit en ~30 s à lui
/// seul) ne tiennent pas dans 40 s. Le timeout tuait des sessions
/// PENDANT que la stratégie gagnante travaillait (« Nouvel essai en
/// mode compatible (5/9)… » figé en échec).
const Duration kCastTotalTimeoutDlna = Duration(seconds: 90);

/// Fenêtre de validité de la mémoire de chemin DLNA. Passé ce délai
/// sans nouvel échec, l'appareil retrouve le comportement par défaut
/// (direct d'abord, timeout SOAP plein) — les conditions réseau ont
/// pu changer, on re-sonde le chemin le plus autonome.
const Duration kDlnaPathMemoTtl = Duration(minutes: 15);

/// Timeout SOAP raccourci pour une tentative DIRECTE quand l'appareil
/// vient de timeout en direct. 8 s couvre encore les TVs lentes au
/// réveil (LG webOS : 8-12 s constatés SEULEMENT à la sortie de
/// standby — or ici la TV vient de nous parler, elle n'est pas en
/// standby) tout en divisant par ~2 le coût d'un direct muet.
const Duration kDlnaShortSoapTimeout = Duration(seconds: 8);

/// Mémoire de chemin DLNA par appareil (clé : `device.id`).
///
/// Diag boîte noire Nebula 2026-07-09 : le MÊME appareil accepte le
/// direct en ~3 s la plupart du temps, puis reste muet 15 s (timeout
/// SOAP) par vagues — et chaque vague coûtait 15 s de direct + ~22 s
/// de relais = sessions à 40-70 s. Cette mémoire apprend :
///   - 1 échec CONNEXION direct récent  → timeout direct raccourci (8 s)
///   - 2 échecs consécutifs ou plus     → on démarre directement au
///     relais (stratégie 3) tant que la fenêtre [kDlnaPathMemoTtl]
///     n'a pas expiré, puis on re-sonde le direct.
/// Un SUCCÈS direct remet le compteur à zéro — un appareil sain garde
/// exactement le comportement historique.
class _DlnaPathMemo {
  int directConnFailStreak = 0;
  DateTime? lastDirectConnFail;
}

/// Phase 1+/B5 — Exception interne levee par `_checkCancelled` quand
/// une session inner a ete supersede par un timeout outer ou une
/// nouvelle castTo. Type dedie pour pouvoir la distinguer d'une vraie
/// erreur de cast dans les logs / diag.
class _CastSessionCancelled implements Exception {
  _CastSessionCancelled(this.message);
  final String message;
  @override
  String toString() => 'CastSessionCancelled: $message';
}

enum CastState {
  idle,
  discovering,
  connecting,
  casting,
  paused,
  error,
}

class CastManager extends ChangeNotifier {
  CastManager._() {
    _subscribeToNativeEvents();
  }
  static final CastManager instance = CastManager._();

  /// Phase 1+/G2 — abonnements aux streams natifs Google Cast SDK
  /// (sessionEvent + mediaStateChanged). Garde l'etat Dart aligne
  /// avec ce que la TV fait reellement, meme quand l'utilisateur
  /// pause depuis sa telecommande SHIELD ou un autre sender.
  StreamSubscription<CastNativeSessionEvent>? _nativeSessionSub;
  StreamSubscription<CastNativeMediaState>? _nativeMediaSub;

  void _subscribeToNativeEvents() {
    _nativeSessionSub = GoogleCastApi.instance.sessionEventStream.listen(
      _onNativeSessionEvent,
      onError: (Object e) {
        StructuredLogger.instance.warn(
          domain: 'cast',
          event: 'native.session_stream_error',
          ctx: <String, Object?>{'error': e.toString()},
        );
      },
    );
    _nativeMediaSub = GoogleCastApi.instance.mediaStateStream.listen(
      _onNativeMediaState,
      onError: (Object e) {
        StructuredLogger.instance.warn(
          domain: 'cast',
          event: 'native.media_stream_error',
          ctx: <String, Object?>{'error': e.toString()},
        );
      },
    );
  }

  void _onNativeSessionEvent(CastNativeSessionEvent evt) {
    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'native.session_event',
      ctx: <String, Object?>{
        'kind': evt.kind,
        if (evt.errorCode != 0) 'errorCode': evt.errorCode,
      },
    );
    switch (evt.kind) {
      case 'ended':
        // Le SDK signale la fin DEFINITIVE de la session — on aligne
        // notre etat. ATTENTION : ne pas appeler disconnect() ici
        // (boucle : notre disconnect() ferme aussi la session SDK).
        if (_state == CastState.casting || _state == CastState.paused) {
          _state = CastState.idle;
          _setProgress(CastProgress.idle);
        }
        // Une session terminee invalide aussi le device/transport et la
        // cible memorisee (si c'etait un Chromecast). Sans ce nettoyage,
        // le bouton Cast restait dore "connecte" et le picker montrait
        // un bandeau Stop pour une session qui n'existe plus, jusqu'a
        // un disconnect() manuel.
        _transport = null;
        _device = null;
        _currentTitle = null;
        if (_selectedDevice?.kind == CastDeviceKind.chromecast) {
          _selectedDevice = null;
        }
        // Revue 2026-07-09 (MAJEUR 2) : la fin de session peut venir de
        // la TV elle-meme (stop TV, extinction) — sans ce nettoyage, le
        // foreground service (wakelock + wifilock, notification
        // « Diffusion sur la TV ») et la session relais tournaient
        // indefiniment, plus rien ne declenchant disconnect().
        _stopRelayKeepAlive();
        if (_currentRelayUrl != null) {
          LocalCastServer.instance.clearRelay(_currentRelayUrl!);
          _currentRelayUrl = null;
        }
        notifyListeners();
        break;
      case 'receiver_switching':
        // Fin de session PILOTÉE par le sender lui-même : bascule de
        // receiver custom ⇄ Default (GoogleCastTransport, CAST_HANDOFF
        // §6.2). Le natif re-sélectionne la même TV tout seul et
        // playStream attend la reconnexion — on ne détruit PAS l'état
        // (contrairement à 'ended'), sinon le cast en cours
        // d'établissement perdrait device/transport.
        break;
      case 'suspended':
        // Suspension TEMPORAIRE (changement de reseau, veille) : le SDK
        // peut la reprendre tout seul (`resumed`). On reflete juste
        // l'etat sans jeter device/cible — comportement historique.
        if (_state == CastState.casting || _state == CastState.paused) {
          _state = CastState.idle;
          _setProgress(CastProgress.idle);
        }
        break;
      case 'resumed_at_boot':
        // Le SDK a restaure une session via setResumeSavedSession au
        // boot — on n'a pas de _device/_transport associes cote Dart,
        // mais on doit refleter qu'une session est techniquement
        // active. L'utilisateur peut casser cette session via
        // disconnect() depuis l'UI ou le picker.
        if (_state == CastState.idle) {
          _state = CastState.casting;
          _setProgress(CastProgress.live);
        }
        break;
      case 'load_failed':
        // Le recepteur a REFUSE le media APRES coup (le load reussit
        // cote SDK mais la TV rejette le flux quelques secondes plus
        // tard — typiquement codec/conteneur non supporte par le
        // Default Media Receiver, ou URL relais injoignable depuis la
        // TV). loadMedia() a deja renvoye `true`, donc sans ce signal
        // l'app afficherait "en cours de lecture" pour un ecran noir.
        StructuredLogger.instance.error(
          domain: 'cast',
          event: 'google.receiver_rejected',
          ctx: <String, Object?>{'statusCode': evt.errorCode},
        );
        if (_state == CastState.connecting ||
            _state == CastState.casting ||
            _state == CastState.paused) {
          _state = CastState.error;
          _errorMessage =
              'La TV a refusé ce flux — format probablement non pris en '
              'charge par ce récepteur. Essaie une autre chaîne.';
          _setProgress(CastProgress.failure(_errorMessage!));
        }
        break;
    }
  }

  void _onNativeMediaState(CastNativeMediaState state) {
    // L'etat Dart ne refait surface que pour les transitions
    // play/pause utiles a l'UI. On n'a pas (encore) de mapping
    // buffering -> CastState dedie (sera utile quand on aura un
    // mini-player synchronise).
    switch (state.playerState) {
      case CastNativePlayerState.playing:
        if (_state == CastState.paused) {
          _state = CastState.casting;
          _setProgress(CastProgress.live);
        }
        break;
      case CastNativePlayerState.paused:
        if (_state == CastState.casting) {
          _state = CastState.paused;
          _setProgress(CastProgress.pausedState);
        }
        break;
      case CastNativePlayerState.idle:
        // Lecture finie ou stop par la TV. Si on etait en cours, on
        // revient en idle (l'utilisateur peut relancer une chaine).
        if (_state == CastState.casting || _state == CastState.paused) {
          _state = CastState.idle;
          _setProgress(CastProgress.idle);
        }
        break;
      case CastNativePlayerState.loading:
      case CastNativePlayerState.buffering:
      case CastNativePlayerState.unknown:
        // Pas de transition Dart — le state existant est conserve.
        break;
    }
    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'native.media_state',
      ctx: <String, Object?>{
        'playerState': state.playerState.name,
        'castManagerState': _state.name,
      },
    );
  }

  @override
  void dispose() {
    _nativeSessionSub?.cancel();
    _nativeMediaSub?.cancel();
    super.dispose();
  }

  CastState _state = CastState.idle;
  CastDevice? _device;
  CastTransport? _transport;
  String? _currentTitle;

  /// Phase 1+/B5 (2026-06-01) — Annulation cooperative du `_castToInner`.
  ///
  /// Le `.timeout(kCastTotalTimeout)` cote outer leve TimeoutException
  /// apres 25s, mais le Future inner CONTINUE silencieusement parce
  /// que Dart ne peut pas reellement annuler un Future ([HYPOTHESE]
  /// documentee inline). Resultat observe en diag terrain :
  ///   - User voit l'erreur a 25s
  ///   - Inner archive le diag a 90-157s
  ///   - Pendant ces 65-130s d'orphelin, le HttpClient + le relay
  ///     restent vivants et envoient encore des SOAP a la TV
  ///   - Le prochain `castTo` voit une TV deja confuse par les SOAP
  ///     orphelins de la session precedente
  ///
  /// Fix : chaque appel a `castTo` increments `_sessionSeq`. L'inner
  /// capture sa propre valeur (`mySeq`). Entre chaque etape (probe,
  /// caps, attempt N), il appelle `_checkCancelled(mySeq)` qui throw
  /// si _sessionSeq a ete bumpe ailleurs. Resultat :
  ///   - Inner s'arrete proprement au prochain await boundary
  ///   - Pas plus de quelques secondes d'orphelin (le temps du SOAP
  ///     en cours de completer)
  ///   - Diag totalDurationMs proche de la realite UX
  int _sessionSeq = 0;

  /// Phase 1+/B5 — Helper d'annulation cooperative. Appele entre
  /// chaque etape de `_castToInner` / `_castDlnaWithFailover`. Si le
  /// `_sessionSeq` global a ete bumpe par un autre call (outer
  /// timeout ou nouvelle session castTo), on throw avec un type
  /// dedie qui sera capture par le `on Exception catch` du caller
  /// et archive proprement (sans noise UX vers le user puisque
  /// l'outer a deja rendu).
  void _checkCancelled(int mySeq) {
    if (_sessionSeq != mySeq) {
      throw _CastSessionCancelled(
        'Session cast superseded (mySeq=$mySeq, current=$_sessionSeq)',
      );
    }
  }
  String? _errorMessage;

  /// URL relay actuellement enregistrée pour la session courante,
  /// pour pouvoir la libérer dans `disconnect()`.
  String? _currentRelayUrl;

  /// Mémoire de chemin DLNA par appareil (cf. [_DlnaPathMemo]).
  final Map<String, _DlnaPathMemo> _dlnaPathMemos = <String, _DlnaPathMemo>{};

  /// Dernier cast RÉUSSI par appareil (clé : `device.id`). Sert au
  /// pré-vol TCP « soft-pass » : un appareil qui vient de jouer une
  /// chaîne il y a quelques secondes n'est PAS derrière une isolation
  /// AP — un refus de connexion ponctuel est un artefact de zapping
  /// (renderer mono-connexion occupé), pas une TV injoignable.
  final Map<String, DateTime> _lastCastSuccessAt = <String, DateTime>{};

  // ----- Surveillance de session DLNA (reconnexion auto) -----
  //  En DLNA, c'est le lecteur INTERNE de la TV qui bufferise (pas l'app) :
  //  on ne peut PAS faire un buffer « façon YouTube » côté sender. Le maximum
  //  réaliste = flux direct stable + RELANCE automatique si le flux coupe.
  //  Ces champs portent l'état du watchdog (cf. _startDlnaWatchdog).
  Timer? _dlnaWatchdog;
  String? _dlnaLiveUrl;
  String? _dlnaLiveTitle;
  final List<DateTime> _dlnaReconnects = <DateTime>[];
  bool _dlnaReconnecting = false;

  /// Contexte de REPLI RELAIS pour la reconnexion auto : URL upstream
  /// (portail d'origine — token frais à chaque connexion) et profil
  /// DLNA gagnant. Posés au démarrage du watchdog. Permettent, quand le
  /// replay DIRECT reste muet (timeout connexion), de retenter UNE fois
  /// via le relais du téléphone au lieu d'abandonner la session
  /// (boîte noire 2026-07-09 : `dlna.auto_reconnect_fail` après 15 s,
  /// l'utilisateur devait re-caster à la main).
  String? _dlnaRelayFallbackUpstream;
  DlnaProfile? _dlnaRelayFallbackProfile;

  /// Progression friendly-french exposée à l'UI. Le picker, la
  /// mini-bar et le VideoPlayerScreen s'abonnent via ListenableBuilder
  /// pour afficher des messages humains au lieu de stack traces.
  CastProgress _progress = CastProgress.idle;
  CastProgress get progress => _progress;

  /// Ring buffer des 20 dernières sessions de cast. L'écran Diagnostic
  /// les liste pour identifier les patterns d'échec (quelle TV ?
  /// quelle stratégie a marché ? quel genre de stream tombe ?).
  /// Réinitialisé seulement à la mort du process — pas persisté
  /// sur disque, c'est de la donnée de session.
  static const int _kMaxRecentDiagnostics = 20;
  final List<CastSessionDiagnostic> _recentDiagnostics =
      <CastSessionDiagnostic>[];
  List<CastSessionDiagnostic> get recentDiagnostics =>
      List<CastSessionDiagnostic>.unmodifiable(_recentDiagnostics);

  /// Device "sélectionné" — différent du device "casting actif".
  /// Quand l'utilisateur ouvre le picker global (depuis Home, Live...)
  /// sans flux à envoyer, on retient quand même son choix. Plus tard
  /// quand il tape sur une chaîne, on route le flux vers ce device au
  /// lieu d'ouvrir le player local. C'est le modèle YouTube/Netflix :
  /// "connecte ta TV une fois, ensuite tout y va".
  CastDevice? _selectedDevice;

  // Liste des devices découverts. NE PAS clear à chaque discovery —
  // on garde la liste chaude entre les ouvertures du picker pour
  // qu'elle s'ouvre instantanément la 2e fois.
  final List<CastDevice> _discovered = <CastDevice>[];
  StreamSubscription<CastDevice>? _discoverySub;
  StreamSubscription<CastDevice>? _mdnsSub;
  Timer? _discoveryTimer;
  Timer? _warmupTimer;

  // ----- Getters -----

  CastState get state => _state;
  CastDevice? get device => _device;
  CastDevice? get selectedDevice => _selectedDevice;
  String? get currentTitle => _currentTitle;
  String? get errorMessage => _errorMessage;
  List<CastDevice> get discoveredDevices =>
      List<CastDevice>.unmodifiable(_discovered);

  bool get isCasting =>
      _state == CastState.casting || _state == CastState.paused;

  /// `true` dès qu'un device est prêt à recevoir un flux — qu'il
  /// soit déjà en train de caster ou simplement "connecté en attente".
  /// Utilisé par `playChannel()` pour décider de router le flux vers
  /// la TV au lieu d'ouvrir le player local.
  bool get hasTarget => _selectedDevice != null;

  // ----- Discovery -----

  /// Lance la découverte SSDP et expose les résultats dans
  /// [discoveredDevices]. Notifie ses listeners à chaque ajout.
  ///
  /// Si [keepExisting] est `true` (cas du refresh dans le picker
  /// déjà ouvert ou du warmup), on n'efface pas la liste avant le
  /// scan — au pire on rajoute des devices, jamais on n'en enlève.
  /// Ça évite le flash "liste vide → liste pleine" qui rend l'UI
  /// peu fluide.
  Future<void> startDiscovery({
    Duration timeout = const Duration(seconds: 5),
    bool keepExisting = true,
  }) async {
    if (_state == CastState.discovering) return;
    if (!keepExisting) _discovered.clear();
    _state = CastState.discovering;
    notifyListeners();

    _discoverySub?.cancel();
    _mdnsSub?.cancel();
    _discoveryTimer?.cancel();

    void onDevice(CastDevice d) {
      // Double dédup : par id ET par host+port pour ne jamais lister
      // la même TV plusieurs fois même si SSDP et mDNS la renvoient
      // tous les deux (cas typique des Google TV qui font SSDP +
      // Chromecast en même temps).
      final bool already = _discovered.any((CastDevice e) =>
          e.id == d.id ||
          (e.host == d.host && e.port == d.port));
      if (already) return;
      _discovered.add(d);
      notifyListeners();
    }

    // SSDP en parallèle (DLNA + Roku)
    _discoverySub =
        SsdpDiscovery.instance.discover(timeout: timeout).listen(onDevice);

    // mDNS en parallèle (Chromecast / Google TV)
    _mdnsSub =
        MdnsDiscovery.instance.discover(timeout: timeout).listen(onDevice);

    _discoveryTimer = Timer(timeout, () {
      // On COUPE aussi les abonnements au timeout, pas seulement l'état.
      // Sans ça, les générateurs SSDP/mDNS restaient vivants jusqu'à la
      // PROCHAINE découverte (60s en warmup) : leur `finally` (fermeture
      // socket UDP + release du MulticastLock) ne tournait jamais à
      // temps → lock multicast tenu quasi en permanence (batterie) et
      // sockets orphelines. Annuler la subscription complète le
      // générateur async* → son finally s'exécute immédiatement.
      _discoverySub?.cancel();
      _mdnsSub?.cancel();
      _discoverySub = null;
      _mdnsSub = null;
      if (_state == CastState.discovering) {
        _state = isCasting ? CastState.casting : CastState.idle;
        notifyListeners();
      }
    });
  }

  void stopDiscovery() {
    _discoverySub?.cancel();
    _mdnsSub?.cancel();
    _discoveryTimer?.cancel();
    _discoverySub = null;
    _mdnsSub = null;
    _discoveryTimer = null;
    if (_state == CastState.discovering) {
      _state = isCasting ? CastState.casting : CastState.idle;
      notifyListeners();
    }
  }

  /// Démarre un cycle de scan silencieux en arrière-plan : un premier
  /// scan rapide après [initialDelay], puis un re-scan toutes les
  /// [interval]. Comme ça, dès que l'utilisateur ouvre le picker, la
  /// liste est déjà chaude — pas d'attente, expérience YouTube/Netflix.
  void startWarmup({
    Duration initialDelay = const Duration(seconds: 2),
    Duration interval = const Duration(seconds: 60),
  }) {
    _warmupTimer?.cancel();
    Future<void>.delayed(initialDelay, () {
      if (_state != CastState.discovering &&
          _state != CastState.connecting &&
          !isCasting) {
        startDiscovery(timeout: const Duration(seconds: 3));
      }
    });
    _warmupTimer = Timer.periodic(interval, (_) {
      // On ne dérange jamais une session active, une CONNEXION en cours
      // ou une discovery en cours. Le garde `connecting` manquait : un
      // castTo peut durer jusqu'à kCastTotalTimeout (40s) et le tick
      // warmup (60s) pouvait tomber pendant — startDiscovery écrasait
      // alors l'état `connecting` par `discovering` puis `idle`,
      // corrompant l'UI (mini-bar / overlay / picker) en pleine
      // négociation.
      if (_state == CastState.discovering ||
          _state == CastState.connecting ||
          isCasting) {
        return;
      }
      startDiscovery(timeout: const Duration(seconds: 3));
    });
  }

  void stopWarmup() {
    _warmupTimer?.cancel();
    _warmupTimer = null;
  }

  // ----- Sélection sans lecture (mode "global picker") -----

  /// Mémorise un device comme cible par défaut, sans envoyer de flux.
  /// `playChannel()` enverra automatiquement les chaînes vers ce
  /// device tant qu'il n'est pas désélectionné via [clearTarget].
  void selectDevice(CastDevice device) {
    _selectedDevice = device;
    notifyListeners();
  }

  void clearTarget() {
    _selectedDevice = null;
    notifyListeners();
  }

  // ----- Cast vers un device -----

  Future<void> castTo(
    CastDevice device, {
    required String streamUrl,
    required String title,
    String? channelName,
    String? channelGenre,
    String? imageUrl,
  }) async {
    // Phase 1 / F-09 : on borne la session entiere a kCastTotalTimeout.
    // En cas de depassement, _castToInner sera abandonne, on coupe
    // proprement (disconnect best-effort) et on remonte une
    // TimeoutException avec un message UX clair.
    try {
      await _castToInner(
        device,
        streamUrl: streamUrl,
        title: title,
        channelName: channelName,
        channelGenre: channelGenre,
        imageUrl: imageUrl,
      ).timeout(device.kind == CastDeviceKind.dlna
          ? kCastTotalTimeoutDlna
          : kCastTotalTimeout);
    } on TimeoutException {
      // Phase 1+/B5 (2026-06-01) — Annulation cooperative.
      // Bump `_sessionSeq` immediatement. L'inner orphelin verra
      // au prochain `_checkCancelled` que sa session est obsolete
      // et s'arretera proprement au lieu de continuer 90-157s.
      _sessionSeq++;
      StructuredLogger.instance.warn(
        domain: 'cast',
        event: 'session.global_timeout',
        ctx: <String, Object?>{
          'deviceKind': device.kind.name,
          'deviceName': device.name,
          'timeoutSeconds': (device.kind == CastDeviceKind.dlna
                  ? kCastTotalTimeoutDlna
                  : kCastTotalTimeout)
              .inSeconds,
          'newSessionSeq': _sessionSeq,
        },
      );
      // Note : annulation cooperative — le Future inner finit son
      // SOAP en cours (15s max) puis voit le mismatch de seq et exit.
      // Plus court que les 90-157s pre-B5 mais pas instantane.
      // [HYPOTHESE — historique] Limitation connue avant B5 :
      // `.timeout()` abandonnait le Future de _castToInner mais Dart
      // ne savait pas reellement
      // l'interrompre. Les SOAP en cours continuent en arriere-plan
      // jusqu'a leurs propres timeouts (15s SOAP x N), puis leurs
      // exceptions deviennent des unhandled errors. Pas de leak
      // memoire grave (HttpClient se fermera tout seul), juste du
      // bruit dans les logs. Une vraie annulation cooperative (flag
      // _cancelled verifie entre chaque strategie) sera ajoutee en
      // Phase 2 si besoin.
      //
      // Best-effort cleanup : on coupe le transport courant pour ne
      // pas laisser une connexion ouverte cote TV ; disconnect()
      // reset l'etat.
      try {
        await disconnect();
      } catch (_) {
        // disconnect best-effort, on continue meme si echec.
      }
      // On remplace l'etat residuel par un error explicite — prend
      // le pas sur le `idle` que disconnect() vient de poser. Si
      // _castToInner finit sa course apres et re-ecrit le state, ce
      // sera aussi vers error (son propre catch) → pas
      // d'inconsistance visible utilisateur.
      _state = CastState.error;
      _errorMessage = 'Cast trop long — la TV ou le réseau ne répondent pas';
      _setProgress(
        CastProgress.failure(
          'La TV met trop de temps à répondre. Réessaie ou choisis une '
              'autre TV.',
          details: 'castTo timeout after '
              '${(device.kind == CastDeviceKind.dlna ? kCastTotalTimeoutDlna : kCastTotalTimeout).inSeconds}s',
        ),
      );
      throw Exception(_errorMessage);
    }
  }

  Future<void> _castToInner(
    CastDevice device, {
    required String streamUrl,
    required String title,
    String? channelName,
    String? channelGenre,
    String? imageUrl,
  }) async {
    stopDiscovery();
    // Coupe une éventuelle surveillance DLNA de la session précédente
    // avant d'en démarrer une nouvelle (évite deux watchdogs concurrents).
    _stopDlnaWatchdog();
    // Phase 1+/B5 (2026-06-01) — Capture ma seq des le start. Si une
    // autre castTo bumpe _sessionSeq pendant que je tourne, j'arrete.
    final int mySeq = ++_sessionSeq;
    _state = CastState.connecting;
    _device = device;
    _errorMessage = null;
    // Libere le relais de la session precedente (zap) : sinon la
    // session HLS continuait de tirer le flux jusqu'au GC d'inactivite.
    if (_currentRelayUrl != null) {
      LocalCastServer.instance.clearRelay(_currentRelayUrl!);
    }
    _currentRelayUrl = null;
    // Zap depuis un cast ou la TV tire ELLE-MEME le flux fournisseur
    // (direct_tv, cast_proxy) : sur les comptes 1-connexion, cette
    // connexion encore ouverte ferait refuser le probe de la NOUVELLE
    // chaine (« limite atteinte »). On arrete la lecture de la TV
    // d'abord — media stop SEULEMENT, la session Cast reste ouverte
    // (la re-etablir couterait 5-20 s).
    final GoogleCastTransport? prevGct =
        _transport is GoogleCastTransport
            ? _transport as GoogleCastTransport
            : null;
    if (prevGct != null &&
        (prevGct.lastCastPath == 'direct_tv' ||
            prevGct.lastCastPath == 'cast_proxy')) {
      try {
        await GoogleCastApi.instance.stop();
      } on Exception catch (_) {/* best-effort : le probe tranchera */}
    }
    _setProgress(CastProgress.validating);

    final CastSessionDiagnostic diag = CastSessionDiagnostic(
      startedAt: DateTime.now(),
      device: device,
      originalUrl: streamUrl,
      channelName: channelName,
      channelGenre: channelGenre,
    );
    final Stopwatch totalSw = Stopwatch()..start();

    try {
      // (0) Pré-vol RÉSEAU (2026-06-01) : avant tout, on vérifie que la
      //     TV est JOIGNABLE en TCP sur son port de contrôle. Sans ça,
      //     une TV endormie / sur un autre WiFi / isolée par l'« AP
      //     isolation » de la box faisait grinder les 5 stratégies
      //     pendant ~25s (chaque SOAP timeout sur errno 113 "No route
      //     to host") avant d'échouer. Ici on échoue en ~2,5s avec un
      //     message clair et actionnable. On ne fait ce test que pour
      //     les récepteurs pilotés en TCP direct sur le LAN (DLNA, Roku) :
      //     Chromecast (SDK natif via Google Play Services) a un autre
      //     chemin réseau.
      if (device.kind == CastDeviceKind.dlna ||
          device.kind == CastDeviceKind.roku) {
        _checkCancelled(mySeq);
        _setProgress(CastProgress.connecting());
        final bool reachable = await _probeDeviceReachable(device);
        diag.deviceReachable = reachable;
        if (!reachable) {
          // SOFT-PASS (boîte noire 2026-07-09, 15:51) : 4 sessions
          // consécutives déclarées « TV ne répond pas » en 2,5 s
          // (attempts:0) alors que la MÊME TV castait avec succès 5 s
          // avant ET 5 s après. Un renderer occupé (zapping rapide,
          // socket de contrôle mono-connexion) peut refuser une
          // connexion TCP ponctuellement SANS être injoignable. Si
          // l'appareil a réussi un cast très récemment, on laisse la
          // chaîne de failover trancher au lieu d'accuser le réseau.
          final DateTime? lastOk = _lastCastSuccessAt[device.id];
          final bool recentlyCasting = lastOk != null &&
              DateTime.now().difference(lastOk) < const Duration(minutes: 2);
          if (recentlyCasting) {
            StructuredLogger.instance.warn(
              domain: 'cast',
              event: 'preflight.soft_pass',
              ctx: <String, Object?>{
                'deviceName': device.name,
                'lastSuccessAgoMs':
                    DateTime.now().difference(lastOk).inMilliseconds,
              },
            );
          } else {
            // Message contient "no route to host" → friendlyMessageFor
            // le route vers le hint réseau/AP-isolation dédié (B4).
            throw Exception(
              'TV injoignable sur le réseau (${device.host}:${device.port}) '
              '— no route to host (pré-vol TCP)',
            );
          }
        }
      }

      // (1) Pré-vol : on vérifie l'URL avant de la pousser au récepteur.
      _checkCancelled(mySeq);
      final StreamProbeResult probe =
          await StreamProbe.instance.probe(streamUrl);
      diag.probe = ProbeSummary(
        success: probe.success,
        finalUrl: probe.finalUrl, // redacté à l'export JSON
        redirectCount: probe.redirectCount,
        timeToFirstByteMs: probe.timeToFirstByte,
        mime: probe.mime,
        contentLength: probe.contentLength,
        acceptsRanges: probe.acceptsRanges,
        requiresAuth: probe.requiresAuth,
        errorCode: probe.errorCode,
        errorReason: probe.errorReason,
      );
      if (!probe.success) {
        throw Exception(probe.errorReason ?? 'Flux indisponible');
      }

      // (2) Branche DLNA = chaîne de failover (direct → relay → meta minimal).
      //     Branche non-DLNA = appel direct simple, comportement historique
      //     conservé pour ne pas régresser Roku / Web / Chromecast-stub.
      _checkCancelled(mySeq);
      _transport = CastTransport.forDevice(device);
      if (device.kind == CastDeviceKind.dlna) {
        await _castDlnaWithFailover(
          transport: _transport! as UpnpAvTransport,
          probe: probe,
          title: title,
          diag: diag,
          imageUrl: imageUrl,
          mySeq: mySeq,
        );
      } else {
        _setProgress(CastProgress.connecting());
        // Pour Google Cast, on fournit l'URL D'ORIGINE au transport : le
        // proxy /cast-proxy re-suivra la redirection au play-time (token
        // IPTV frais côté TV) au lieu de recevoir le token périssable déjà
        // résolu par le probe du téléphone. Cf. GoogleCastTransport
        // .originalUpstreamUrl (diag SHIELD 2026-07-06 : redirect /live/).
        if (_transport is GoogleCastTransport) {
          (_transport as GoogleCastTransport).originalUpstreamUrl =
              probe.originalUrl;
        }
        final Stopwatch sw = Stopwatch()..start();
        try {
          await _transport!.playStream(
            streamUrl: probe.finalUrl,
            title: title,
            imageUrl: imageUrl,
          );
          // Le vrai chemin de routage ('cast_proxy'/'local_hls_relay'/'direct')
          // n'est connu qu'apres coup, expose par GoogleCastTransport.
          final GoogleCastTransport? gct =
              _transport is GoogleCastTransport
                  ? _transport as GoogleCastTransport
                  : null;
          final String realPath = gct?.lastCastPath ?? 'direct';
          diag.attempts.add(AttemptResult(
            strategyIndex: 0,
            strategyName: realPath,
            urlKind: realPath,
            metadataMode: 'n/a',
            durationMs: sw.elapsedMilliseconds,
            success: true,
            lastCastUrlRedacted: gct?.lastCastUrlRedacted,
          ));
        } on Exception catch (e) {
          final GoogleCastTransport? gctF =
              _transport is GoogleCastTransport
                  ? _transport as GoogleCastTransport
                  : null;
          final String realPathF = gctF?.lastCastPath ?? 'direct';
          diag.attempts.add(AttemptResult(
            strategyIndex: 0,
            strategyName: realPathF,
            urlKind: realPathF,
            metadataMode: 'n/a',
            durationMs: sw.elapsedMilliseconds,
            success: false,
            errorMessage: e.toString(),
            lastCastUrlRedacted: gctF?.lastCastUrlRedacted,
          ));
          rethrow;
        }
      }

      // Revue 2026-07-09 (MAJEUR 1) : playStream peut durer plus que le
      // timeout global (picker 30 s + lecture 25 s > 40 s) — cette
      // session est peut-etre devenue ORPHELINE (zap, timeout) pendant
      // l'attente. Ne JAMAIS ecraser l'etat/le relais/le keep-alive de
      // la session plus recente.
      _checkCancelled(mySeq);
      _currentTitle = title;
      _selectedDevice = device;
      _state = CastState.casting;
      _setProgress(CastProgress.live);
      diag.success = true;
      // Horodatage pour le soft-pass du pré-vol TCP (cf. étape 0).
      _lastCastSuccessAt[device.id] = DateTime.now();
      // CAST AUTONOME (« je pars a la douche, ca continue ») : si le
      // flux passe par le TELEPHONE (relais HLS Chromecast — le relais
      // DLNA pose deja _currentRelayUrl), on memorise l'URL pour la
      // liberer au disconnect, et on demarre le foreground service
      // (notification + wakelock + wifilock) : sans lui, Android
      // suspend l'app ecran eteint / en arriere-plan → saccades puis
      // gel sur la TV au bout de quelques dizaines de secondes.
      if (_transport is GoogleCastTransport) {
        final String? relayUrl =
            (_transport as GoogleCastTransport).lastRelayUrl;
        if (relayUrl != null) _currentRelayUrl = relayUrl;
      }
      _updateRelayKeepAlive(title);
    } on Exception catch (e) {
      // Revue 2026-07-09 (MAJEUR 1) : une session ORPHELINE (zap ou
      // timeout global — mySeq depasse) qui echoue tardivement ne doit
      // toucher NI l'etat NI le keep-alive : une session plus recente
      // est peut-etre en train d'alimenter la TV. On libere seulement
      // le relais que CE playStream aurait enregistre (fuite sinon,
      // MINEUR 7) et on sort.
      final GoogleCastTransport? gctLeak =
          _transport is GoogleCastTransport
              ? _transport as GoogleCastTransport
              : null;
      final String? leakedRelay = gctLeak?.lastRelayUrl;
      if (leakedRelay != null && leakedRelay != _currentRelayUrl) {
        LocalCastServer.instance.clearRelay(leakedRelay);
      }
      if (mySeq != _sessionSeq) {
        return;
      }
      _state = CastState.error;
      _errorMessage = e.toString();
      // Le cast a echoue → plus personne a alimenter : coupe le
      // foreground service d'une eventuelle session relais precedente.
      _stopRelayKeepAlive();
      // Phase 1 / F-12 + B1 (2026-06-01) : le hint "WiFi isolation"
      // ne doit s'afficher QUE quand les deux strategies relay ont
      // timeout (= la TV ne joint pas notre serveur). Si elles ont
      // echoue avec un message explicite cote TV ("Transition not
      // available", "Action Failed", "Resource not found"...), le
      // probleme N'EST PAS le WiFi — c'est la TV qui refuse pour
      // d'autres raisons. Diag terrain LG QNED816QA 2026-06-01 a
      // montre le faux positif.
      final bool relayPathBlocked = bothRelayStrategiesTimedOut(diag);
      final String userMessage = relayPathBlocked
          ? 'Ta TV ne joint pas le téléphone (WiFi invité ou isolation '
              'AP ?). Mets le téléphone et la TV sur le MÊME réseau WiFi '
              '(pas le réseau invité) et désactive l\'isolation AP.'
          : friendlyMessageFor(e);
      _setProgress(
        CastProgress.failure(
          userMessage,
          details: e.toString(),
        ),
      );
      diag.finalErrorMessage = e.toString();
      if (relayPathBlocked) {
        StructuredLogger.instance.warn(
          domain: 'cast',
          event: 'session.relay_unreachable',
          ctx: <String, Object?>{
            'deviceKind': device.kind.name,
            'deviceName': device.name,
            'attempts': diag.attempts.length,
          },
        );
      }
      // On garde _device/_transport pour permettre le diagnostic UI ;
      // ils seront vraiment nettoyés au prochain disconnect().
      rethrow;
    } finally {
      diag.totalDurationMs = totalSw.elapsedMilliseconds;
      diag.finalUserMessage = _progress.message;
      _archiveDiagnostic(diag);
    }
  }

  void _archiveDiagnostic(CastSessionDiagnostic d) {
    _recentDiagnostics.insert(0, d);
    while (_recentDiagnostics.length > _kMaxRecentDiagnostics) {
      _recentDiagnostics.removeLast();
    }
    StructuredLogger.instance.info(
      domain: 'cast',
      event: d.success ? 'session.success' : 'session.failure',
      ctx: <String, Object?>{
        'deviceKind': d.device.kind.name,
        'deviceName': d.device.name,
        'totalDurationMs': d.totalDurationMs,
        'attempts': d.attempts.length,
        if (d.winningAttempt != null)
          'winningStrategy': d.winningAttempt!.strategyName,
        if (!d.success && d.finalUserMessage != null)
          'userMessage': d.finalUserMessage,
      },
    );
  }

  /// Phase 1 / F-12 : retourne `true` si LES DEUX strategies relay
  /// (index 3 = relay+full, index 4 = relay+minimal) ont ete tentees
  /// et ont echoue, peu importe la cause. Conservee pour
  /// retrocompatibilite des tests existants.
  @visibleForTesting
  bool bothRelayStrategiesFailed(CastSessionDiagnostic d) {
    bool sawFail3 = false;
    bool sawFail4 = false;
    for (final AttemptResult a in d.attempts) {
      if (a.success) continue;
      if (a.strategyIndex == 3) sawFail3 = true;
      if (a.strategyIndex == 4) sawFail4 = true;
    }
    return sawFail3 && sawFail4;
  }

  /// Phase 1+/B1 (2026-06-01) : version raffinee de
  /// [bothRelayStrategiesFailed] qui exige que les deux echecs soient
  /// des **timeouts**.
  ///
  /// Rationale : un timeout SOAP relay = la TV n'a meme pas reussi a
  /// joindre notre serveur (vrai signal WiFi isolation). Un echec
  /// type "Transition not available" / "Action Failed" relay = la TV
  /// nous joint mais REFUSE pour une autre raison (etat interne,
  /// codec, etc.). Avant B1, on confondait les deux et on affichait
  /// le faux hint "WiFi invite" sur le mauvais diagnostic.
  ///
  /// Cas observe sur LG QNED816QA 2026-06-01 : strategies relay ont
  /// echoue avec "Transition not available" -> N'EST PAS un cas WiFi
  /// -> on doit montrer le message specifique TRANSITIONING, pas le
  /// hint WiFi.
  @visibleForTesting
  bool bothRelayStrategiesTimedOut(CastSessionDiagnostic d) {
    AttemptResult? a3;
    AttemptResult? a4;
    for (final AttemptResult a in d.attempts) {
      if (a.strategyIndex == 3) a3 = a;
      if (a.strategyIndex == 4) a4 = a;
    }
    if (a3 == null || a4 == null) return false;
    if (a3.success || a4.success) return false;
    return _looksLikeTimeout(a3.errorMessage) &&
        _looksLikeTimeout(a4.errorMessage);
  }

  bool _looksLikeTimeout(String? msg) {
    if (msg == null) return false;
    final String s = msg.toLowerCase();
    return s.contains('timeoutexception') ||
        s.contains('timed out') ||
        s.contains('future not completed');
  }

  /// `true` si l'erreur est un echec de NIVEAU CONNEXION (la TV ne
  /// repond pas / coupe la socket) plutot qu'un refus applicatif SOAP.
  /// Couvre les timeouts ET les resets de connexion ("Software caused
  /// connection abort", "connection closed/reset"). Sert a decider de
  /// sauter directement au relais quand le direct ne repond pas.
  bool _looksLikeConnFailure(String? msg) {
    if (_looksLikeTimeout(msg)) return true;
    if (msg == null) return false;
    final String s = msg.toLowerCase();
    return s.contains('connection abort') ||
        s.contains('connection closed') ||
        s.contains('connection reset') ||
        s.contains('software caused connection') ||
        s.contains('connection refused') ||
        s.contains('broken pipe');
  }

  /// Chaîne de failover spécifique DLNA — 3 tentatives :
  ///   1) Direct si le probe le permet, sinon relay d'emblée
  ///   2) Relay forcé avec métadonnée DLNA complète
  ///   3) Relay avec métadonnée minimale (sans PN)
  ///
  /// Latence cible : 1-2s en cas de succès direct, 3-5s si on tombe
  /// jusqu'au step 3. À chaque tentative on met à jour `progress`
  /// pour que l'UI montre clairement ce qui se passe.
  Future<void> _castDlnaWithFailover({
    required UpnpAvTransport transport,
    required StreamProbeResult probe,
    required String title,
    required CastSessionDiagnostic diag,
    String? imageUrl,
    required int mySeq,
  }) async {
    // Phase 1+/B5 — Annulation cooperative check juste apres l'entree.
    _checkCancelled(mySeq);
    // Capabilities (Sink) — best-effort, on continue même si vide.
    _setProgress(CastProgress.detecting);
    final DlnaSink sink =
        await DlnaCapabilities.instance.fetchSink(transport.device);

    // Snapshot des caps pour le diagnostic (max 12 entries pour rester
    // lisible dans le rapport copié).
    final List<String> profileNames = <String>[];
    for (final String e in sink.entries) {
      final List<String> parts = e.split(':');
      if (parts.length < 4) continue;
      final RegExpMatch? m =
          RegExp(r'DLNA\.ORG_PN=([A-Z0-9_]+)').firstMatch(parts[3]);
      if (m != null) profileNames.add(m.group(1)!);
    }
    diag.sink = SinkSummary(
      entryCount: sink.entries.length,
      mimeTypes: sink.mimeTypes.take(12).toList(growable: false),
      profileNames: profileNames.toSet().take(12).toList(growable: false),
    );

    // Profil retenu pour ce flux (informé par MIME + LIVE/VOD heuristique).
    DlnaProfile profile = DlnaProfiles.select(
      url: probe.finalUrl,
      finalMime: probe.mime,
      isLive: probe.isLive,
    );

    // Adaptation MIME selon la sink réelle de la TV. Cas constaté
    // empiriquement sur LG QNED816QA : sa sink annonce
    // `video/vnd.dlna.mpeg-tts` (MIME DLNA-standard pour MPEG-TS) mais
    // PAS `video/mp2t`. Quand on envoie un DIDL-Lite avec `video/mp2t`,
    // la TV refuse avec "Resource not found". On rewrite le MIME (et on
    // drop le profileName DLNA qui n'est pas dans sa sink non plus).
    if (profile.mime == 'video/mp2t' &&
        sink.entries.isNotEmpty &&
        !sink.mimeTypes.contains('video/mp2t') &&
        sink.mimeTypes.contains('video/vnd.dlna.mpeg-tts')) {
      profile = DlnaProfile(
        mime: 'video/vnd.dlna.mpeg-tts',
        profileName: null, // pas de PN MPEG_TS_* dans la sink LG
        transferMode: profile.transferMode,
        objectClass: profile.objectClass,
        fileExtension: profile.fileExtension,
      );
    }

    // RÉGLAGE PAR MARQUE (recherche 2026-07-09, sourcée — MediaTomb/
    // SamyGO/minidlna/Serviio/BubbleUPnP) : le MÊME flux TS doit être
    // étiqueté différemment selon le constructeur pour être accepté.
    profile = brandTunedProfile(device: transport.device, base: profile);

    diag.profile = ProfileSummary.from(profile);

    // Si le profil n'est pas du tout annoncé dans la Sink, on log mais
    // on tente quand même — la Sink est souvent incomplète.
    if (sink.entries.isNotEmpty &&
        !DlnaProfiles.isAdvertised(profile, sink.entries) &&
        kDebugMode) {
      debugPrint(
        '[Cast] Profil ${profile.profileName} non annoncé dans la Sink '
        'de ${transport.device.name} — tentative quand même',
      );
    }

    transport.profile = profile;

    // Échelle de stratégies en gradient (étendue à 5 niveaux) :
    //   0 = direct + métadonnée DLNA complète (cas idéal, latence min ;
    //       la TV tire l'upstream elle-même → téléphone-éteint-TV-continue)
    //   1 = direct + métadonnée minimale (juste MIME, pas de PN)
    //   2 = direct + AUCUNE métadonnée (URL upstream nue → fallback direct)
    //   3 = relay  + métadonnée DLNA complète (relais téléphone, legacy)
    //   4 = relay  + métadonnée minimale (sans PN, dernier recours)
    //
    // ATTENTION : on essaie TOUJOURS les 3 stratégies "direct" d'abord,
    // MÊME si le probe dit shouldUseRelay = true. Constaté empiriquement
    // sur la TV LG de l'utilisateur : le relay timeout systématiquement
    // (la TV ne joint pas notre serveur local — VLAN ou firewall) alors
    // que la TV elle-même a accès Internet et pourrait fetch Xtream
    // directement. Le probe est conservateur, mais ça n'aide pas pour
    // les TVs qui rejettent le relay.
    // VARIANTES DE MIME (universalité TV) — le MÊME flux MPEG-TS doit
    // parfois être étiqueté différemment selon la marque : Samsung accepte
    // souvent `video/mpeg`, LG `video/vnd.dlna.mpeg-tts`, la norme étant
    // `video/mp2t`. Si les 5 stratégies de base (toutes sur le MIME
    // d'origine) échouent par REFUS DE FORMAT, on RE-tente en DIRECT avec
    // ces étiquettes alternatives. 100 % ADDITIF : une TV qui caste déjà
    // réussit en stratégie 0-4 et ne touche jamais ces variantes.
    final List<DlnaProfile> altProfiles = buildAltMimeProfiles(profile);
    final int altCount = altProfiles.length;
    // Chaque variante MIME est tentée en DIRECT (5..5+N-1) PUIS via le RELAIS
    // (5+N..5+2N-1) — d'où le *2. POURQUOI le relais en plus : Samsung sonde
    // l'URL média en HEAD avant de lire et a besoin du relais (qui répond au
    // HEAD + résout les redirections) AVEC la bonne étiquette MIME. Jusqu'ici
    // l'étiquette `video/mpeg` (préférée Samsung) n'était essayée qu'en DIRECT
    // → la combinaison « MIME Samsung + relais » manquait. 100% ADDITIF : une
    // TV qui caste déjà (LG) réussit en stratégie 0 et n'atteint JAMAIS ces
    // variantes — son comportement est strictement inchangé.
    final int totalStrategies = 5 + altCount * 2;
    // MÉMOIRE DE CHEMIN (2026-07-09, boîte noire Nebula) : si ce même
    // appareil vient d'enchaîner ≥ 2 échecs CONNEXION en direct, on
    // démarre directement au relais (s=3) — le direct muet coûtait
    // 15 s de SOAP timeout à CHAQUE session pendant la vague. La
    // fenêtre expire (kDlnaPathMemoTtl) : le direct — plus autonome
    // (téléphone-éteint-TV-continue) — est re-sondé ensuite.
    final _DlnaPathMemo memo =
        _dlnaPathMemos.putIfAbsent(transport.device.id, _DlnaPathMemo.new);
    final DateTime nowForMemo = DateTime.now();
    final int startStrategy = dlnaStartStrategyFor(
      failStreak: memo.directConnFailStreak,
      lastFail: memo.lastDirectConnFail,
      now: nowForMemo,
    );
    if (startStrategy > 0) {
      StructuredLogger.instance.info(
        domain: 'cast',
        event: 'failover.start_at_relay',
        ctx: <String, Object?>{
          'deviceName': transport.device.name,
          'directConnFailStreak': memo.directConnFailStreak,
        },
      );
    }
    // Timeout SOAP adaptatif pour les tentatives DIRECTES : plein
    // (15 s) par défaut, raccourci (8 s) si le direct vient déjà de
    // rester muet sur cet appareil. Les stratégies RELAIS gardent
    // toujours le timeout plein.
    final Duration directSoapTimeout = dlnaDirectSoapTimeoutFor(
      failStreak: memo.directConnFailStreak,
      lastFail: memo.lastDirectConnFail,
      now: nowForMemo,
    );
    final int budget = totalStrategies;

    Exception? lastError;
    for (int s = startStrategy; s < totalStrategies; s++) {
      // Phase 1+/B5 — Check cancellation entre chaque strategie. Si
      // l'outer a timeout (25s) et bump _sessionSeq, on s'arrete au
      // lieu d'enchainer les strategies restantes (qui ajoutaient
      // 60-90s d'orphelin avant ce fix).
      _checkCancelled(mySeq);
      final int displayAttempt = s + 1;
      final Stopwatch attemptSw = Stopwatch()..start();
      // Variantes MIME : 5..5+N-1 = DIRECT, 5+N..5+2N-1 = RELAIS.
      //   direct = stratégies 0,1,2 et les variantes MIME directes ;
      //   relay  = stratégies 3,4 et les variantes MIME via relais.
      final bool isAltDirect = s >= 5 && s < 5 + altCount;
      final bool isAltRelay = s >= 5 + altCount;
      final String urlKind =
          (s < 3 || isAltDirect) ? 'direct' : 'relay';
      transport.soapTimeout = urlKind == 'direct'
          ? directSoapTimeout
          : UpnpAvTransport.kDefaultSoapTimeout;
      final String strategyName =
          (s >= 5) ? '$urlKind+altmime' : _strategyName(s);
      final String metaName = (s == 1 || s == 4) ? 'minimal' : (s == 2 ? 'none' : 'full');

      try {
        _setProgress(
          CastProgress.connecting(attempt: displayAttempt, total: budget),
        );

        final String urlToCast;
        switch (s) {
          case 0:
            // ENVOI DIRECT de l'URL upstream (restauré — régression 3586027).
            // Le Worker /cs/ (stratégie 0 du 2026-06-20) proxifiait le live
            // via Cloudflare, mais le Worker COUPE un flux continu à ~105 s
            // (limite de durée Cloudflare) → le live s'arrêtait en plein
            // match. En direct, la LG tire le flux du serveur IPTV elle-même :
            // pas d'intermédiaire à durée bornée, et le téléphone peut
            // s'éteindre (TV autonome). Le Worker reste utilisé pour le
            // chemin Chromecast (cf. _workerTsUrl, conservé).
            // Upstream direct ; on bascule sur l'URL http d'origine si une
            // redirection l'a fait passer en https (webOS gère mal le TLS).
            urlToCast = dlnaDirectUrlFor(
              finalUrl: probe.finalUrl,
              originalUrl: probe.originalUrl,
            );
            transport.metadataMode = MetadataMode.full;
            break;
          case 1:
            urlToCast = dlnaDirectUrlFor(
              finalUrl: probe.finalUrl,
              originalUrl: probe.originalUrl,
            );
            transport.metadataMode = MetadataMode.minimal;
            break;
          case 2:
            urlToCast = probe.finalUrl;
            transport.metadataMode = MetadataMode.none;
            break;
          case 3:
            urlToCast = await _ensureRelayUrl(
              // URL D'ORIGINE, pas finalUrl : token Xtream frais a
              // chaque connexion du relais (cf. relayUpstreamUrlFor).
              upstreamUrl: relayUpstreamUrlFor(
                originalUrl: probe.originalUrl,
                finalUrl: probe.finalUrl,
              ),
              profile: profile,
              receiverHost: transport.device.host,
            );
            transport.metadataMode = MetadataMode.full;
            break;
          case 4:
            urlToCast = await _ensureRelayUrl(
              upstreamUrl: relayUpstreamUrlFor(
                originalUrl: probe.originalUrl,
                finalUrl: probe.finalUrl,
              ),
              profile: profile,
              receiverHost: transport.device.host,
            );
            transport.metadataMode = MetadataMode.minimal;
            break;
          default:
            // Variante d'étiquette MIME (universalité TV, ex. Samsung qui
            // veut `video/mpeg`). En DIRECT (5..5+N-1) ou via le RELAIS
            // (5+N..5+2N-1) — le relais sert le bon Content-Type ET répond au
            // HEAD de sonde Samsung + résout les redirections.
            {
              final int altIdx = isAltRelay ? (s - 5 - altCount) : (s - 5);
              transport.profile = altProfiles[altIdx];
              transport.metadataMode = MetadataMode.full;
              urlToCast = isAltRelay
                  ? await _ensureRelayUrl(
                      upstreamUrl: relayUpstreamUrlFor(
                        originalUrl: probe.originalUrl,
                        finalUrl: probe.finalUrl,
                      ),
                      profile: altProfiles[altIdx],
                      receiverHost: transport.device.host,
                    )
                  : probe.finalUrl;
            }
            break;
        }

        await transport.playStream(
          streamUrl: urlToCast,
          title: title,
          imageUrl: imageUrl,
        );
        diag.attempts.add(AttemptResult(
          strategyIndex: s,
          strategyName: strategyName,
          urlKind: urlKind,
          metadataMode: metaName,
          durationMs: attemptSw.elapsedMilliseconds,
          success: true,
        ));
        // Mémoire de chemin : un SUCCÈS direct efface l'historique
        // d'échecs — l'appareil retrouve le comportement par défaut.
        if (urlKind == 'direct') {
          memo.directConnFailStreak = 0;
          memo.lastDirectConnFail = null;
        }
        // Revue 2026-07-09 (MINEUR 6) : si une strategie RELAIS a
        // echoue avant qu'une strategie DIRECTE ne gagne,
        // _currentRelayUrl est reste pose → le keep-alive foreground
        // (wakelock/wifilock) demarrait pour rien (la TV tire le flux
        // elle-meme). On libere le relais inutilise.
        if (urlKind == 'direct' && _currentRelayUrl != null) {
          LocalCastServer.instance.clearRelay(_currentRelayUrl!);
          _currentRelayUrl = null;
        }
        // Lecture confirmée PLAYING → on arme la surveillance de session
        // (reconnexion auto si le flux coupe). On relance sur l'URL
        // GAGNANTE (`urlToCast`), donc avec la même stratégie/profil ;
        // le contexte de repli relais (upstream d'origine + profil
        // EFFECTIF de la tentative gagnante) permet au watchdog de
        // basculer sur le relais si le replay direct reste muet.
        _startDlnaWatchdog(
          transport,
          urlToCast,
          title,
          mySeq,
          relayFallbackUpstream: relayUpstreamUrlFor(
            originalUrl: probe.originalUrl,
            finalUrl: probe.finalUrl,
          ),
          relayFallbackProfile: transport.profile,
        );
        return; // succès
      } on Exception catch (e) {
        lastError = e;
        diag.attempts.add(AttemptResult(
          strategyIndex: s,
          strategyName: strategyName,
          urlKind: urlKind,
          metadataMode: metaName,
          durationMs: attemptSw.elapsedMilliseconds,
          success: false,
          errorMessage: e.toString(),
        ));

        // SKIP DIRECT -> RELAIS (2026-06-06). Si une tentative DIRECTE
        // (s < 3) echoue au niveau CONNEXION (timeout SOAP ou
        // "connection abort"), la TV ne repond tout simplement pas a
        // SetAVTransportURI en direct — ce n'est PAS un refus de format.
        // Re-essayer les autres variantes directes (minimal, none) tape
        // le meme endpoint muet et gaspille le budget global AVANT
        // d'avoir tente le RELAIS. Diag terrain LG QNED816QA 2026-06-06 :
        // direct+full ET direct+minimal timeout 15 s chacun -> le relais
        // n'etait jamais atteint. On saute donc au relais (s=3) des la
        // 1re tentative directe qui echoue en connexion. A l'inverse, un
        // ECHEC SOAP explicite (faute 500/716 "Resource not found",
        // "Transition not available") signifie que la TV NOUS PARLE mais
        // refuse ce DIDL precis -> la on garde le gradient direct (une
        // metadonnee differente peut passer).
        if (s < 3 && _looksLikeConnFailure(e.toString())) {
          StructuredLogger.instance.warn(
            domain: 'cast',
            event: 'failover.skip_direct_to_relay',
            ctx: <String, Object?>{
              'fromStrategy': s,
              'reason': e.toString(),
            },
          );
          // Mémoire de chemin : cet appareil vient (encore) de rester
          // muet en direct — la prochaine session raccourcira son
          // timeout direct, puis démarrera au relais dès 2 échecs.
          memo.directConnFailStreak++;
          memo.lastDirectConnFail = DateTime.now();
          s = 2; // la boucle fera s++ -> s=3 (relay+full)
        }

        if (s + 1 < totalStrategies) {
          _setProgress(
            CastProgress.retrying(
              attempt: displayAttempt + 1,
              total: budget,
              reason: e.toString(),
            ),
          );
        }
      }
    }
    throw lastError ?? Exception('Cast DLNA échec inconnu');
  }

  String _strategyName(int strategyIndex) {
    switch (strategyIndex) {
      case 0:
        return 'direct+full';
      case 1:
        return 'direct+minimal';
      case 2:
        return 'direct+nometa';
      case 3:
        return 'relay+full';
      case 4:
        return 'relay+minimal';
      default:
        return 'direct+altmime'; // variantes de MIME (s >= 5)
    }
  }

  // ⚠️ NE JAMAIS remettre _workerTsUrl en stratégie 0/1 DLNA. Le Worker
  // Cloudflare coupe le flux LIVE à ~105s (limite de durée). La LG doit
  // recevoir l'URL upstream DIRECTE (probe.finalUrl) pour tirer le flux
  // elle-même → téléphone-éteint-TV-continue. Régression historique:
  // commit 3586027 (2026-06-20), réparée. Worker réservé au chemin Chromecast.
  //
  /// URL MPEG-TS https servie par le Worker Cloudflare (route /cs/) qui
  /// re-sert le flux IPTV (redirect upstream resolu, UA VLC, en-tetes DLNA).
  /// Réservé au chemin Chromecast/QR ; cf. worker.js. NE PAS appeler en DLNA.
  // ignore: unused_element
  String _workerTsUrl(String upstreamUrl) {
    final String b64 =
        base64Url.encode(utf8.encode(upstreamUrl)).replaceAll('=', '');
    return 'https://app.7themotion.com/cs/$b64.ts';
  }

  /// Choisit l'URL à pousser en stratégie DIRECT (0/1) vers une TV DLNA.
  ///
  /// `StreamProbe` suit les redirections : si l'upstream redirige
  /// `http → https`, `probe.finalUrl` devient https. Or la pile DLNA de
  /// webOS (LG QNED816QA) — et de beaucoup de Smart TV — gère mal le TLS
  /// sur le chemin média (handshake qui échoue, flux qui coupe). On
  /// préfère donc l'URL HTTP d'origine quand la finalUrl est passée en
  /// https par redirection : la TV évite le TLS, au prix de devoir suivre
  /// elle-même la redirection (compromis + fiable en pratique sur webOS).
  /// Si la finalUrl est déjà http (cas le plus courant en IPTV), on la
  /// renvoie telle quelle → aucun changement de comportement.
  ///
  /// Construit la liste des PROFILS À ÉTIQUETTE MIME ALTERNATIVE essayés en
  /// dernier recours (universalité TV). Le MÊME flux MPEG-TS est parfois
  /// étiqueté différemment selon la marque : Samsung accepte souvent
  /// `video/mpeg`, LG `video/vnd.dlna.mpeg-tts`, la norme étant `video/mp2t`.
  /// On renvoie les étiquettes DIFFÉRENTES de celle du profil de base (sans
  /// `DLNA.ORG_PN` : étiquette MIME nue). Liste vide si le flux n'est pas du
  /// MPEG-TS (mp4/mkv… → aucune variante).
  ///
  /// Stratégie de DÉPART de l'échelle DLNA selon la mémoire de chemin.
  /// 0 = comportement historique (direct d'abord) ; 3 = relais d'abord
  /// (≥ 2 échecs CONNEXION direct consécutifs dans la fenêtre
  /// [kDlnaPathMemoTtl]). Pur + statique → testable sans stack réseau.
  @visibleForTesting
  static int dlnaStartStrategyFor({
    required int failStreak,
    required DateTime? lastFail,
    required DateTime now,
  }) {
    final bool recent =
        lastFail != null && now.difference(lastFail) < kDlnaPathMemoTtl;
    return (recent && failStreak >= 2) ? 3 : 0;
  }

  /// Timeout SOAP des tentatives DIRECTES selon la mémoire de chemin :
  /// plein (15 s) par défaut, raccourci (8 s) dès 1 échec CONNEXION
  /// direct récent. Pur + statique → testable sans stack réseau.
  @visibleForTesting
  static Duration dlnaDirectSoapTimeoutFor({
    required int failStreak,
    required DateTime? lastFail,
    required DateTime now,
  }) {
    final bool recent =
        lastFail != null && now.difference(lastFail) < kDlnaPathMemoTtl;
    return (recent && failStreak >= 1)
        ? kDlnaShortSoapTimeout
        : UpnpAvTransport.kDefaultSoapTimeout;
  }

  /// Pur + statique → testable (simulation Samsung/LG sans stack réseau).
  @visibleForTesting
  static List<DlnaProfile> buildAltMimeProfiles(DlnaProfile base) {
    final bool isTs = base.mime == 'video/mp2t' ||
        base.mime == 'video/vnd.dlna.mpeg-tts' ||
        base.mime == 'video/mpeg';
    final List<DlnaProfile> out = <DlnaProfile>[];
    if (!isTs) return out;
    for (final String m in const <String>[
      'video/vnd.dlna.mpeg-tts',
      'video/mpeg',
      'video/mp2t',
    ]) {
      if (m != base.mime && !out.any((DlnaProfile p) => p.mime == m)) {
        out.add(DlnaProfile(
          mime: m,
          profileName: null, // sans PN : étiquette MIME nue
          transferMode: base.transferMode,
          objectClass: base.objectClass,
          fileExtension: base.fileExtension,
        ));
      }
    }
    return out;
  }

  /// URL upstream que le RELAIS du téléphone doit tirer. TOUJOURS
  /// l'URL PORTAIL D'ORIGINE quand on l'a : les serveurs Xtream
  /// redirigent vers un endpoint à TOKEN PAR-CONNEXION — celui de
  /// `probe.finalUrl` a déjà été consommé par le probe du téléphone.
  /// Le re-donner au relais (ou à la TV) = « Resource not found » /
  /// timeout (diag LG QNED816QA 2026-07-09 : 6/8 échecs, seuls les
  /// serveurs à token réutilisable passaient). Le relais, lui, suit
  /// la redirection à CHAQUE connexion → token frais, IP du téléphone.
  /// Nettoie les « ? » orphelins de fin (fréquents sur les URLs Xtream).
  @visibleForTesting
  static String relayUpstreamUrlFor({
    required String originalUrl,
    required String finalUrl,
  }) {
    String u = originalUrl.trim();
    while (u.endsWith('?')) {
      u = u.substring(0, u.length - 1);
    }
    final bool usable =
        u.startsWith('http://') || u.startsWith('https://');
    return usable ? u : finalUrl;
  }

  /// Étiquetage DLNA PAR MARQUE pour le MPEG-TS live (recherche sourcée
  /// 2026-07-09) :
  ///   - SAMSUNG (Tizen) : ne JAMAIS commencer par `video/mp2t` — le
  ///     protocolInfo rapporté fonctionnel est `video/mpeg` +
  ///     `MPEG_TS_HD_NA_ISO` (MediaTomb/SamyGO). Nos FLAGS live
  ///     `01700000…` correspondent déjà aux valeurs validées.
  ///   - PANASONIC (Viera) : client STRICT sur le DLNA_PN (minidlna
  ///     FLAG_DLNA) ; les profils Serviio qui marchent mappent
  ///     `video/vnd.dlna.mpeg-tts` + `AVC_TS_MP_HD_AC3`.
  ///   - HISENSE (VIDAA) : renderer fragile, profil générique —
  ///     `video/mpeg` SANS PN (best-effort, les variantes altmime
  ///     couvrent le reste).
  /// Les autres marques gardent le profil de base (LG a déjà sa règle
  /// adaptée à sa Sink). Ne touche que les MIME MPEG-TS.
  @visibleForTesting
  static DlnaProfile brandTunedProfile({
    required CastDevice device,
    required DlnaProfile base,
  }) {
    const Set<String> tsMimes = <String>{
      'video/mp2t',
      'video/vnd.dlna.mpeg-tts',
      'video/mpeg',
    };
    if (!tsMimes.contains(base.mime)) return base;
    final String hay =
        '${device.name} ${device.manufacturer ?? ''} ${device.model ?? ''}'
            .toLowerCase();
    DlnaProfile retag(String mime, String? pn) => DlnaProfile(
          mime: mime,
          profileName: pn,
          transferMode: base.transferMode,
          objectClass: base.objectClass,
          fileExtension: base.fileExtension,
        );
    if (hay.contains('samsung') || hay.contains('tizen')) {
      return retag('video/mpeg', 'MPEG_TS_HD_NA_ISO');
    }
    if (hay.contains('panasonic') || hay.contains('viera')) {
      return retag('video/vnd.dlna.mpeg-tts', 'AVC_TS_MP_HD_AC3');
    }
    if (hay.contains('hisense') || hay.contains('vidaa')) {
      return retag('video/mpeg', null);
    }
    return base;
  }

  /// Pur + statique → testable sans stack réseau (cf. tests cast).
  @visibleForTesting
  static String dlnaDirectUrlFor({
    required String finalUrl,
    required String originalUrl,
  }) {
    final bool finalIsHttps = finalUrl.toLowerCase().startsWith('https:');
    final bool originIsHttp = originalUrl.toLowerCase().startsWith('http:');
    if (finalIsHttps && originIsHttp) return originalUrl;
    return finalUrl;
  }

  Future<String> _ensureRelayUrl({
    required String upstreamUrl,
    required DlnaProfile profile,
    required String receiverHost,
  }) async {
    if (_currentRelayUrl != null) return _currentRelayUrl!;
    _setProgress(CastProgress.relayStarting);
    final String? url = await LocalCastServer.instance.registerRelay(
      upstreamUrl: upstreamUrl,
      profile: profile,
      receiverHost: receiverHost,
    );
    if (url == null) {
      throw Exception(
        'Impossible de démarrer le relais local (réseau indisponible ?)',
      );
    }
    _currentRelayUrl = url;
    return url;
  }

  /// Pré-vol réseau (2026-06-01) : tente une connexion TCP brève vers le
  /// port de contrôle de la TV. Retourne `true` si la socket s'ouvre,
  /// `false` sur timeout / refus / "no route to host".
  ///
  /// Pourquoi : la découverte SSDP/mDNS se fait en MULTICAST (UDP), qui
  /// traverse souvent l'« AP isolation » d'une box — donc la TV apparaît
  /// dans la liste. Mais le cast réel se fait en UNICAST TCP, que l'AP
  /// isolation BLOQUE. Résultat avant ce fix : la TV est listée mais
  /// chaque tentative de cast échoue en `errno 113` après un long
  /// timeout. Ce pré-vol détecte le cas en ~2,5s et permet d'afficher
  /// tout de suite le bon diagnostic (cf. friendlyMessageFor).
  ///
  /// 2026-07-09 : le tir UNIQUE de 2,5 s produisait des FAUX NÉGATIFS
  /// en rafale de zapping (renderer occupé qui ignore un SYN) → message
  /// « TV ne répond pas » à tort (boîte noire, 4 échecs attempts:0
  /// encadrés de succès). On tente désormais jusqu'à 3 connexions
  /// courtes (1,2 s / 1,2 s / 2,5 s, pause 250 ms) : une TV vraiment
  /// injoignable échoue toujours en ~5,4 s, une TV momentanément
  /// occupée est récupérée dès le 2e essai.
  Future<bool> _probeDeviceReachable(CastDevice device) async {
    const List<Duration> attempts = <Duration>[
      Duration(milliseconds: 1200),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2500),
    ];
    for (int i = 0; i < attempts.length; i++) {
      try {
        final Socket socket = await Socket.connect(
          device.host,
          device.port,
          timeout: attempts[i],
        );
        socket.destroy();
        if (i > 0) {
          StructuredLogger.instance.info(
            domain: 'cast',
            event: 'preflight.retry_success',
            ctx: <String, Object?>{'attempt': i + 1},
          );
        }
        return true;
      } on Exception {
        // SocketException (timeout, no route to host, connection
        // refused) → on retente ; le diagnostic final est porté par le
        // caller (message dédié archivé dans le diag de session).
        if (i + 1 < attempts.length) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }
    return false;
  }

  /// Convertit une Exception interne en message court pour l'UI.
  /// Les libellés évitent tout jargon technique.
  ///
  /// `@visibleForTesting` : public uniquement pour tests unitaires
  /// (cf. test/features/cast/data/friendly_message_test.dart). En
  /// prod, le seul caller est `_castToInner`.
  ///
  /// Phase 1+/B1-B2 (2026-06-01) : ORDRE des branches affine apres
  /// retour diag terrain LG QNED816QA. Les patterns specifiques
  /// (Transition not available, Action Failed, HTTP 458) passent
  /// AVANT le hint generique "reseau" pour eviter de faussement
  /// pointer du doigt le WiFi.
  @visibleForTesting
  String friendlyMessageFor(Exception e) {
    final String s = e.toString().toLowerCase();

    // --- Google Cast indisponible (pas de Google Play Services) ---
    // Levé par GoogleCastTransport quand api.isCastAvailable() == false :
    // téléphones sans GMS (Huawei récents, /e/OS, GrapheneOS, certaines
    // ROMs custom). Le SDK Cast NE PEUT PAS fonctionner — on oriente
    // l'utilisateur vers une Smart TV (DLNA) ou un Roku, qui ne
    // dependent pas des services Google.
    if (s.contains('google play services') ||
        s.contains('cast indisponible') ||
        s.contains('google cast indisponible')) {
      return 'Le Chromecast officiel a besoin des services Google Play, '
          'absents sur ce téléphone. Tu peux quand même caster vers une '
          'Smart TV (DLNA) ou un Roku depuis la liste.';
    }

    // --- DNS / hostname (Phase 1+) ---
    if (s.contains('hostname') ||
        s.contains('no address') ||
        s.contains('failed host lookup') ||
        s.contains('name resolution') ||
        s.contains('nodename') ||
        s.contains('servname')) {
      return 'Internet ou DNS instable. Réessaie dans quelques secondes.';
    }

    // --- TV bloquee en TRANSITIONING (Phase 1+/B2) ---
    // Symptome observe sur LG QNED816QA : un cast precedent a laisse
    // l'AVTransport dans un etat "TRANSITIONING" non recuperable
    // depuis le sender. La TV refuse alors toutes les commandes
    // SetURI / Play. Solution utilisateur fiable : redemarrer la TV.
    if (s.contains('transition not available') ||
        s.contains('transitioning')) {
      return 'Ta TV est bloquée sur un précédent cast. '
          'Éteins-la quelques secondes puis rallume-la et réessaie.';
    }

    // --- Action refusee par le recepteur (codec / format inconnu) ---
    if (s.contains('action failed') ||
        s.contains('resource not found')) {
      return 'Ta TV n\'accepte pas ce format. Essaie une autre chaîne.';
    }

    // --- HTTP 458 ou autres 4xx custom des providers IPTV ---
    // Beaucoup de revendeurs Xtream renvoient 458 pour "trop de
    // connexions simultanees" (la limite de l'abonnement).
    if (s.contains('458')) {
      return 'Ton fournisseur IPTV refuse une connexion supplémentaire '
          '(limite atteinte). Coupe une autre app qui regarde et réessaie.';
    }

    // --- Timeout serveur generique ---
    if (s.contains('timeout') || s.contains('ne répond pas')) {
      return 'La TV ne répond pas. Vérifie le WiFi.';
    }

    // --- Auth / abonnement expire ---
    if (s.contains('auth') || s.contains('401') || s.contains('403')) {
      return 'Accès au flux refusé — ton abonnement a peut-être expiré.';
    }

    // --- Refus generique du recepteur (500, STOPPED apres Play) ---
    if (s.contains('refusé') || s.contains('500') || s.contains('stopped')) {
      return 'Cette TV n\'a pas accepté ce flux. Essaie une autre chaîne.';
    }

    // --- TV physiquement injoignable au niveau IP (Phase 1+/B4) ---
    // Cas observe diag LG QNED816QA 2026-06-01 18:33 : "No route to
    // host (errno=113)" / "Network is unreachable (errno=101)" sur
    // TOUTES les tentatives SOAP. Signal sans ambiguite : la TV est
    // physiquement injoignable depuis le phone.
    //
    // Causes typiques (par frequence) :
    //   1. La TV s'est endormie / a ete eteinte pendant que la
    //      decouverte SSDP gardait son IP en cache.
    //   2. Phone et TV sur des WiFis differents (frequent quand le
    //      phone bascule sur 4G ou un WiFi voisin).
    //   3. Vraie isolation reseau (VLAN, AP isolation guest).
    //
    // On donne un message qui couvre les 3 sans accuser une cause
    // specifique.
    if (s.contains('no route to host') ||
        s.contains('network is unreachable') ||
        s.contains('errno = 113') ||
        s.contains('errno = 101') ||
        s.contains('connection refused') ||
        s.contains('errno = 111')) {
      // La TV apparaît dans la liste (découverte multicast) mais ne
      // répond pas en TCP direct → 3 causes possibles, de la plus
      // simple à la plus probable quand ça persiste :
      //   1. TV endormie / éteinte
      //   2. Téléphone et TV sur des WiFi différents (invité, 4G…)
      //   3. « Isolation client / AP isolation » activée sur la box —
      //      le routeur bloque la communication entre appareils. C'est
      //      LA cause quand la TV est bien listée mais qu'aucun cast ne
      //      passe (cf. errno 113 répété).
      return 'Ta TV ne répond pas sur le réseau. Vérifie : '
          '(1) qu\'elle est allumée, '
          '(2) qu\'elle est sur le MÊME WiFi que ton téléphone '
          '(pas le réseau "invité"), '
          '(3) que l\'option « Isolation client / AP isolation » est '
          'DÉSACTIVÉE dans les réglages de ta box internet.';
    }

    // --- Reseau bas-niveau ---
    if (s.contains('réseau') || s.contains('socket')) {
      return 'Connexion impossible avec la TV.';
    }

    return 'Le cast a échoué. Essaie de relancer.';
  }

  void _setProgress(CastProgress p) {
    _progress = p;
    notifyListeners();
  }

  Future<void> pause() async {
    if (_transport == null) return;
    try {
      await _transport!.pause();
      _state = CastState.paused;
      notifyListeners();
    } catch (_) {
      // best effort — on remet l'état "casting" si la pause échoue
    }
  }

  Future<void> resume() async {
    if (_transport == null) return;
    try {
      await _transport!.resume();
      _state = CastState.casting;
      notifyListeners();
    } catch (_) {}
  }

  /// `true` quand le foreground service « cast relais » est actif.
  bool _relayKeepAliveActive = false;

  /// Le telephone alimente-t-il la TV ? Alors il doit SURVIVRE a
  /// l'ecran eteint : foreground service + wakelock + wifilock (le
  /// meme PlaybackForegroundService que le mode « Ecouteurs », avec un
  /// libelle adapte). Sans relais (cast_proxy/direct : la TV tire le
  /// flux elle-meme), on s'assure au contraire que le service est coupe.
  void _updateRelayKeepAlive(String title) {
    if (_currentRelayUrl != null) {
      _relayKeepAliveActive = true;
      unawaited(PipService.instance.startBackgroundAudio(
        title,
        body: 'Diffusion sur la TV — garde le téléphone sur ce WiFi',
      ));
    } else {
      _stopRelayKeepAlive();
    }
  }

  void _stopRelayKeepAlive() {
    if (!_relayKeepAliveActive) return;
    _relayKeepAliveActive = false;
    unawaited(PipService.instance.stopBackgroundAudio());
  }

  Future<void> disconnect() async {
    _stopDlnaWatchdog();
    _stopRelayKeepAlive();
    try {
      await _transport?.stop();
    } catch (_) {}
    // Libère la session relay si on en avait une — évite de
    // garder un mapping orphelin en mémoire.
    if (_currentRelayUrl != null) {
      LocalCastServer.instance.clearRelay(_currentRelayUrl!);
      _currentRelayUrl = null;
    }
    _transport = null;
    _device = null;
    _selectedDevice = null;
    _currentTitle = null;
    _state = CastState.idle;
    _setProgress(CastProgress.idle);
  }

  // ============================================================
  //  Surveillance de session DLNA — reconnexion auto
  // ============================================================
  //  Équivalent RÉALISTE du « ne jamais geler » pour le DLNA. On NE peut
  //  pas bufferiser côté app (c'est la TV qui lit le flux). Ce qu'on PEUT
  //  faire : détecter une coupure et relancer la lecture sans que
  //  l'utilisateur ait à toucher quoi que ce soit.

  /// Démarre la surveillance après qu'une lecture DLNA a réellement démarré
  /// (PLAYING confirmé par `playStream`). Toutes les ~10 s on lit
  /// GetTransportInfo ; si l'état retombe en STOPPED/NO_MEDIA_PRESENT de
  /// façon inattendue (flux coupé côté serveur/réseau), on relance UNE fois
  /// SetAVTransportURI+Play sur la MÊME URL (cf. _dlnaAutoReconnect).
  void _startDlnaWatchdog(
    UpnpAvTransport transport,
    String url,
    String title,
    int mySeq, {
    String? relayFallbackUpstream,
    DlnaProfile? relayFallbackProfile,
  }) {
    _dlnaWatchdog?.cancel();
    _dlnaLiveUrl = url;
    _dlnaLiveTitle = title;
    _dlnaRelayFallbackUpstream = relayFallbackUpstream;
    _dlnaRelayFallbackProfile = relayFallbackProfile;
    _dlnaReconnects.clear();
    _dlnaReconnecting = false;
    _dlnaWatchdog =
        Timer.periodic(const Duration(seconds: 10), (Timer t) async {
      // Session changée (un nouveau cast a démarré) ou déconnecté → stop.
      if (mySeq != _sessionSeq || _transport == null) {
        t.cancel();
        if (identical(_dlnaWatchdog, t)) _dlnaWatchdog = null;
        return;
      }
      // On ne surveille QUE pendant une lecture active : ni pendant une
      // pause VOLONTAIRE de l'utilisateur (sinon on relancerait un flux
      // qu'il a mis en pause), ni pendant une reconnexion déjà en cours.
      if (_state != CastState.casting || _dlnaReconnecting) return;
      final String? st = await transport.currentTransportState();
      // null = la TV ne supporte pas GetTransportInfo → rien à surveiller.
      if (st == null) return;
      if (st == 'STOPPED' || st == 'NO_MEDIA_PRESENT') {
        await _dlnaAutoReconnect(transport, mySeq);
      }
    });
  }

  /// Relance la lecture sur la même URL, une fois, après un court délai.
  /// Rate-limité à 3 reconnexions par minute glissante pour ne JAMAIS
  /// partir en boucle si le serveur IPTV est définitivement coupé.
  Future<void> _dlnaAutoReconnect(
    UpnpAvTransport transport,
    int mySeq,
  ) async {
    final String? url = _dlnaLiveUrl;
    if (url == null) return;
    final DateTime now = DateTime.now();
    _dlnaReconnects
        .removeWhere((DateTime d) => now.difference(d) > const Duration(minutes: 1));
    if (_dlnaReconnects.length >= 3) {
      StructuredLogger.instance.warn(
        domain: 'cast',
        event: 'dlna.auto_reconnect_giveup',
        ctx: <String, Object?>{'windowReconnects': _dlnaReconnects.length},
      );
      return;
    }
    _dlnaReconnecting = true;
    _dlnaReconnects.add(now);
    StructuredLogger.instance.info(
      domain: 'cast',
      event: 'dlna.auto_reconnect',
      ctx: <String, Object?>{'attemptInWindow': _dlnaReconnects.length},
    );
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mySeq != _sessionSeq || _transport == null) return;
      await transport.playStream(
        streamUrl: url,
        title: _dlnaLiveTitle ?? '7 MOTION',
      );
    } on Exception catch (e) {
      StructuredLogger.instance.warn(
        domain: 'cast',
        event: 'dlna.auto_reconnect_fail',
        ctx: <String, Object?>{'error': e.toString()},
      );
      // REPLI RELAIS (2026-07-09) : le replay DIRECT est resté muet au
      // niveau CONNEXION alors que la TV jouait il y a ~10 s. Même
      // logique que le skip direct→relais du failover initial, mais
      // sans re-dérouler castTo : on registre le relais et on rejoue
      // UNE fois. En cas de succès, la session continue sur le relais
      // (keep-alive téléphone activé) au lieu de mourir en silence.
      await _dlnaReconnectViaRelay(transport, url, mySeq, directError: e);
    } finally {
      _dlnaReconnecting = false;
    }
  }

  /// Tente la reprise de session via le RELAIS du téléphone après un
  /// replay direct muet. Best-effort : toute erreur est journalisée et
  /// la main revient au tick suivant du watchdog (rate-limité 3/min).
  Future<void> _dlnaReconnectViaRelay(
    UpnpAvTransport transport,
    String failedUrl,
    int mySeq, {
    required Exception directError,
  }) async {
    final String? upstream = _dlnaRelayFallbackUpstream;
    final DlnaProfile? prof = _dlnaRelayFallbackProfile;
    if (!_looksLikeConnFailure(directError.toString())) return;
    if (upstream == null || prof == null) return;
    // Déjà sur le relais → rejouer la même URL au prochain tick suffit.
    if (failedUrl.contains('/relay/')) return;
    if (mySeq != _sessionSeq || _transport == null) return;
    try {
      final String? relayUrl = await LocalCastServer.instance.registerRelay(
        upstreamUrl: upstream,
        profile: prof,
        receiverHost: transport.device.host,
      );
      if (relayUrl == null) return;
      if (mySeq != _sessionSeq || _transport == null) {
        LocalCastServer.instance.clearRelay(relayUrl);
        return;
      }
      await transport.playStream(
        streamUrl: relayUrl,
        title: _dlnaLiveTitle ?? '7 MOTION',
      );
      _currentRelayUrl = relayUrl;
      _dlnaLiveUrl = relayUrl;
      // Le téléphone alimente désormais la TV : foreground service
      // (wakelock + wifilock) pour survivre à l'écran éteint.
      _updateRelayKeepAlive(_dlnaLiveTitle ?? '7 MOTION');
      StructuredLogger.instance.info(
        domain: 'cast',
        event: 'dlna.auto_reconnect_relay',
        ctx: <String, Object?>{'deviceName': transport.device.name},
      );
    } on Exception catch (e2) {
      StructuredLogger.instance.warn(
        domain: 'cast',
        event: 'dlna.auto_reconnect_relay_fail',
        ctx: <String, Object?>{'error': e2.toString()},
      );
    }
  }

  void _stopDlnaWatchdog() {
    _dlnaWatchdog?.cancel();
    _dlnaWatchdog = null;
    _dlnaReconnects.clear();
    _dlnaReconnecting = false;
    _dlnaLiveUrl = null;
    _dlnaLiveTitle = null;
    _dlnaRelayFallbackUpstream = null;
    _dlnaRelayFallbackProfile = null;
  }
}
