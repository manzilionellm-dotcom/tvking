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
import 'dart:io' show Socket;

import 'package:flutter/foundation.dart';

import '../../../core/observability/structured_logger.dart';
import '../domain/cast_device.dart';
import 'cast_progress.dart';
import 'cast_session_diagnostic.dart';
import 'cast_transport.dart';
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
      case 'suspended':
        // Le SDK signale la fin de la session — on aligne notre etat.
        // ATTENTION : ne pas appeler disconnect() ici (eviterait une
        // boucle car notre disconnect() ferme aussi la session SDK).
        // On reset juste l'etat Dart.
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
      if (_state != CastState.discovering && !isCasting) {
        startDiscovery(timeout: const Duration(seconds: 3));
      }
    });
    _warmupTimer = Timer.periodic(interval, (_) {
      // On ne dérange jamais une session active ou une discovery en cours
      if (_state == CastState.discovering || isCasting) return;
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
      ).timeout(kCastTotalTimeout);
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
          'timeoutSeconds': kCastTotalTimeout.inSeconds,
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
          details: 'castTo timeout after ${kCastTotalTimeout.inSeconds}s',
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
    // Phase 1+/B5 (2026-06-01) — Capture ma seq des le start. Si une
    // autre castTo bumpe _sessionSeq pendant que je tourne, j'arrete.
    final int mySeq = ++_sessionSeq;
    _state = CastState.connecting;
    _device = device;
    _errorMessage = null;
    _currentRelayUrl = null;
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
          // Message contient "no route to host" → friendlyMessageFor le
          // route vers le hint réseau/AP-isolation dédié (Phase 1+/B4).
          throw Exception(
            'TV injoignable sur le réseau (${device.host}:${device.port}) '
            '— no route to host (pré-vol TCP)',
          );
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
        final Stopwatch sw = Stopwatch()..start();
        try {
          await _transport!.playStream(
            streamUrl: probe.finalUrl,
            title: title,
            imageUrl: imageUrl,
          );
          diag.attempts.add(AttemptResult(
            strategyIndex: 0,
            strategyName: 'direct',
            urlKind: 'direct',
            metadataMode: 'n/a',
            durationMs: sw.elapsedMilliseconds,
            success: true,
          ));
        } on Exception catch (e) {
          diag.attempts.add(AttemptResult(
            strategyIndex: 0,
            strategyName: 'direct',
            urlKind: 'direct',
            metadataMode: 'n/a',
            durationMs: sw.elapsedMilliseconds,
            success: false,
            errorMessage: e.toString(),
          ));
          rethrow;
        }
      }

      _currentTitle = title;
      _selectedDevice = device;
      _state = CastState.casting;
      _setProgress(CastProgress.live);
      diag.success = true;
    } on Exception catch (e) {
      _state = CastState.error;
      _errorMessage = e.toString();
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
    // RESTAURATION cast LG : on garde le profil D'ORIGINE (video/mp2t +
    // DLNA.ORG_PN). L'adaptation vers `video/vnd.dlna.mpeg-tts` (commit
    // e49be67) est annulée — elle avait cassé le cast LG.
    final DlnaProfile profile = DlnaProfiles.select(
      url: probe.finalUrl,
      finalMime: probe.mime,
      isLive: probe.isLive,
    );

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
    //   0 = direct + métadonnée DLNA complète (cas idéal, latence min)
    //   1 = direct + métadonnée minimale (juste MIME, pas de PN)
    //   2 = direct + AUCUNE métadonnée (URL nue → fallback ultime direct)
    //   3 = relay  + métadonnée DLNA complète (résout 95% des 500)
    //   4 = relay  + métadonnée minimale (sans PN, dernier recours)
    //
    // ATTENTION : on essaie TOUJOURS les 3 stratégies "direct" d'abord,
    // MÊME si le probe dit shouldUseRelay = true. Constaté empiriquement
    // sur la TV LG de l'utilisateur : le relay timeout systématiquement
    // (la TV ne joint pas notre serveur local — VLAN ou firewall) alors
    // que la TV elle-même a accès Internet et pourrait fetch Xtream
    // directement. Le probe est conservateur, mais ça n'aide pas pour
    // les TVs qui rejettent le relay.
    const int totalStrategies = 5;
    final int startStrategy = 0;
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
      final String strategyName = _strategyName(s);
      final String urlKind = s < 3 ? 'direct' : 'relay';
      final String metaName = (s == 1 || s == 4) ? 'minimal' : (s == 2 ? 'none' : 'full');

      try {
        _setProgress(
          CastProgress.connecting(attempt: displayAttempt, total: budget),
        );

        final String urlToCast;
        switch (s) {
          case 0:
            urlToCast = probe.finalUrl;
            transport.metadataMode = MetadataMode.full;
            break;
          case 1:
            urlToCast = probe.finalUrl;
            transport.metadataMode = MetadataMode.minimal;
            break;
          case 2:
            urlToCast = probe.finalUrl;
            transport.metadataMode = MetadataMode.none;
            break;
          case 3:
            urlToCast = await _ensureRelayUrl(
              upstreamUrl: probe.finalUrl,
              profile: profile,
              receiverHost: transport.device.host,
            );
            transport.metadataMode = MetadataMode.full;
            break;
          default: // 4
            urlToCast = await _ensureRelayUrl(
              upstreamUrl: probe.finalUrl,
              profile: profile,
              receiverHost: transport.device.host,
            );
            transport.metadataMode = MetadataMode.minimal;
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
        return 'unknown';
    }
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
  /// 2,5s = assez pour un LAN WiFi normal (RTT < 50ms, connexion en
  /// quelques ms), assez court pour ne pas faire patienter sur une TV
  /// réellement injoignable.
  Future<bool> _probeDeviceReachable(CastDevice device) async {
    try {
      final Socket socket = await Socket.connect(
        device.host,
        device.port,
        timeout: const Duration(milliseconds: 2500),
      );
      socket.destroy();
      return true;
    } on Exception {
      // SocketException (timeout, no route to host, connection refused)
      // → injoignable. On ne log pas ici : le caller throw un message
      // dédié qui sera archivé dans le diagnostic.
      return false;
    }
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

  Future<void> disconnect() async {
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
}
