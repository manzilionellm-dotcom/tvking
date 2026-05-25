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
import 'cast_transport.dart';
import 'mdns_discovery.dart';
import 'ssdp_discovery.dart';

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
  }) async {
    stopDiscovery();
    _state = CastState.connecting;
    _device = device;
    _errorMessage = null;
    notifyListeners();

    try {
      _transport = CastTransport.forDevice(device);
      await _transport!.playStream(streamUrl: streamUrl, title: title);
      _currentStreamUrl = streamUrl;
      _currentTitle = title;
      _selectedDevice = device;
      _state = CastState.casting;
      notifyListeners();
    } on Exception catch (e) {
      _state = CastState.error;
      _errorMessage = e.toString();
      _transport = null;
      _device = null;
      notifyListeners();
      rethrow;
    }
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
    _transport = null;
    _device = null;
    _selectedDevice = null;
    _currentStreamUrl = null;
    _currentTitle = null;
    _state = CastState.idle;
    notifyListeners();
  }
}
