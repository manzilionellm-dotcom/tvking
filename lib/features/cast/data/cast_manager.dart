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

import 'package:flutter/foundation.dart';

import '../domain/cast_device.dart';
import 'cast_progress.dart';
import 'cast_session_diagnostic.dart';
import 'cast_transport.dart';
import 'dlna_capabilities.dart';
import 'dlna_profiles.dart';
import 'local_cast_server.dart';
import 'mdns_discovery.dart';
import 'ssdp_discovery.dart';
import 'stream_probe.dart';
import 'upnp_av_transport.dart';

enum CastState {
  idle,
  discovering,
  connecting,
  casting,
  paused,
  error,
}

class CastManager extends ChangeNotifier {
  CastManager._();
  static final CastManager instance = CastManager._();

  CastState _state = CastState.idle;
  CastDevice? _device;
  CastTransport? _transport;
  String? _currentStreamUrl;
  String? _currentTitle;
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
  }) async {
    stopDiscovery();
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
      // (1) Pré-vol : on vérifie l'URL avant de la pousser au récepteur.
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
      _transport = CastTransport.forDevice(device);
      if (device.kind == CastDeviceKind.dlna) {
        await _castDlnaWithFailover(
          transport: _transport! as UpnpAvTransport,
          probe: probe,
          title: title,
          diag: diag,
        );
      } else {
        _setProgress(CastProgress.connecting());
        final Stopwatch sw = Stopwatch()..start();
        try {
          await _transport!.playStream(
            streamUrl: probe.finalUrl,
            title: title,
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

      _currentStreamUrl = streamUrl;
      _currentTitle = title;
      _selectedDevice = device;
      _state = CastState.casting;
      _setProgress(CastProgress.live);
      diag.success = true;
    } on Exception catch (e) {
      _state = CastState.error;
      _errorMessage = e.toString();
      _setProgress(
        CastProgress.failure(
          _friendlyMessageFor(e),
          details: e.toString(),
        ),
      );
      diag.finalErrorMessage = e.toString();
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
  }) async {
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

    // Échelle de stratégies en gradient :
    //   0 = direct + métadonnée DLNA complète (cas idéal, latence min)
    //   1 = relay  + métadonnée DLNA complète (résout 95% des 500)
    //   2 = relay  + métadonnée minimale (sans PN, dernier recours)
    //
    // Si le probe nous a déjà dit "passe par la relay" (redirects, auth,
    // MIME ambigu...), on saute la stratégie 0 d'emblée.
    final int startStrategy = probe.shouldUseRelay ? 1 : 0;
    const int totalStrategies = 3;
    final int budget = totalStrategies - startStrategy;

    Exception? lastError;
    for (int s = startStrategy; s < totalStrategies; s++) {
      final int displayAttempt = s - startStrategy + 1;
      final Stopwatch attemptSw = Stopwatch()..start();
      final String strategyName = _strategyName(s);
      final String urlKind = s == 0 ? 'direct' : 'relay';
      final String metaName = s == 2 ? 'minimal' : 'full';

      try {
        _setProgress(
          CastProgress.connecting(attempt: displayAttempt, total: budget),
        );

        final String urlToCast;
        if (s == 0) {
          urlToCast = probe.finalUrl;
          transport.metadataMode = MetadataMode.full;
        } else if (s == 1) {
          urlToCast = await _ensureRelayUrl(
            upstreamUrl: probe.finalUrl,
            profile: profile,
            receiverHost: transport.device.host,
          );
          transport.metadataMode = MetadataMode.full;
        } else {
          urlToCast = await _ensureRelayUrl(
            upstreamUrl: probe.finalUrl,
            profile: profile,
            receiverHost: transport.device.host,
          );
          transport.metadataMode = MetadataMode.minimal;
        }

        await transport.playStream(streamUrl: urlToCast, title: title);
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
        return 'relay+full';
      case 2:
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

  /// Convertit une Exception interne en message court pour l'UI.
  /// Les libellés évitent tout jargon technique.
  String _friendlyMessageFor(Exception e) {
    final String s = e.toString().toLowerCase();
    if (s.contains('timeout') || s.contains('ne répond pas')) {
      return 'La TV ne répond pas. Vérifie le WiFi.';
    }
    if (s.contains('auth') || s.contains('401') || s.contains('403')) {
      return 'Accès au flux refusé — ton abonnement a peut-être expiré.';
    }
    if (s.contains('refusé') || s.contains('500') || s.contains('stopped')) {
      return 'Cette TV n\'a pas accepté ce flux. Essaie une autre chaîne ou le mode QR code.';
    }
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
    _currentStreamUrl = null;
    _currentTitle = null;
    _state = CastState.idle;
    _setProgress(CastProgress.idle);
  }
}
