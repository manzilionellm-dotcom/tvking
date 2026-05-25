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
import 'ssdp_discovery.dart';
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
  UpnpAvTransport? _transport;
  String? _currentStreamUrl;
  String? _currentTitle;
  String? _errorMessage;

  // Liste des devices découverts pendant la session de discovery actuelle.
  final List<CastDevice> _discovered = <CastDevice>[];
  StreamSubscription<CastDevice>? _discoverySub;
  Timer? _discoveryTimer;

  // ----- Getters -----

  CastState get state => _state;
  CastDevice? get device => _device;
  String? get currentTitle => _currentTitle;
  String? get errorMessage => _errorMessage;
  List<CastDevice> get discoveredDevices =>
      List<CastDevice>.unmodifiable(_discovered);

  bool get isCasting =>
      _state == CastState.casting || _state == CastState.paused;

  // ----- Discovery -----

  /// Lance la découverte SSDP et expose les résultats dans
  /// [discoveredDevices]. Notifie ses listeners à chaque ajout.
  Future<void> startDiscovery({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_state == CastState.discovering) return;
    _discovered.clear();
    _state = CastState.discovering;
    notifyListeners();

    _discoverySub?.cancel();
    _discoveryTimer?.cancel();

    _discoverySub = SsdpDiscovery.instance
        .discover(timeout: timeout)
        .listen((CastDevice d) {
      // Double dédup : par id (UUID racine) ET par host+port pour
      // ne jamais lister la même TV plusieurs fois même si la
      // discovery SSDP renvoie des USN inconsistants.
      final bool already = _discovered.any((CastDevice e) =>
          e.id == d.id ||
          (e.host == d.host && e.port == d.port));
      if (already) return;
      _discovered.add(d);
      notifyListeners();
    });

    _discoveryTimer = Timer(timeout, () {
      if (_state == CastState.discovering) {
        _state = isCasting ? CastState.casting : CastState.idle;
        notifyListeners();
      }
    });
  }

  void stopDiscovery() {
    _discoverySub?.cancel();
    _discoveryTimer?.cancel();
    _discoverySub = null;
    _discoveryTimer = null;
    if (_state == CastState.discovering) {
      _state = isCasting ? CastState.casting : CastState.idle;
      notifyListeners();
    }
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
      _transport = UpnpAvTransport(device);
      await _transport!.playStream(streamUrl: streamUrl, title: title);
      _currentStreamUrl = streamUrl;
      _currentTitle = title;
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
    _currentStreamUrl = null;
    _currentTitle = null;
    _state = CastState.idle;
    notifyListeners();
  }
}
