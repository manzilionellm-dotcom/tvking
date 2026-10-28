import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../device/data/device_identity.dart';
import '../../device/data/device_secret.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../playlists/domain/playlist.dart';
import 'gold_trial_backend.dart';
import 'subscription_state.dart';

/// Un seul contrôleur vit dans l'accueil, même lorsque l'arrivée des
/// chaînes remplace l'écran vide. Un double clic ne crée jamais deux POST.
class GoldTrialController extends ChangeNotifier {
  GoldTrialController({
    GoldTrialBackend? backend,
    Future<GoldTrialIdentity> Function()? loadIdentity,
    Future<Map<String, String>> Function()? sourceHeaders,
    Future<RemoteSyncResult> Function()? importSource,
    bool Function()? hasSubscription,
    bool Function()? hasLoadedTrial,
    Listenable? subscriptionChanges,
    Listenable? sourceChanges,
    Future<List<Playlist>> Function()? loadPlaylists,
    Stream<List<Playlist>>? playlistChanges,
  })  : _backend = backend ?? GoldTrialBackend(),
        _sourceHeaders = sourceHeaders ?? DeviceSecret.instance.headers,
        _importSource = importSource ?? RemoteSourceRepository.sync,
        _hasSubscription = hasSubscription ?? _deviceHasSubscription,
        _hasLoadedTrial = hasLoadedTrial ?? _deviceHasTrial,
        _subscriptionChanges = subscriptionChanges ?? SubscriptionState.instance,
        _sourceChanges = sourceChanges ?? SubscriptionState.instance {
    _loadIdentity = loadIdentity ?? _deviceIdentity;
    _loadPlaylists = loadPlaylists ?? PlaylistRepository.instance.getAllPlaylists;
    _subscriptionChanges.addListener(_changed);
    _sourceChanges.addListener(_sourcePushed);
    _playlistSubscription = (playlistChanges ?? PlaylistRepository.instance.playlistsStream)
        .listen(_playlistsChanged);
  }

  final GoldTrialBackend _backend;
  late final Future<GoldTrialIdentity> Function() _loadIdentity;
  Future<void> Function()? _prepareDevice;
  final Future<Map<String, String>> Function() _sourceHeaders;
  final Future<RemoteSyncResult> Function() _importSource;
  final bool Function() _hasSubscription;
  final bool Function() _hasLoadedTrial;
  final Listenable _subscriptionChanges;
  final Listenable _sourceChanges;
  late final Future<List<Playlist>> Function() _loadPlaylists;
  late final StreamSubscription<List<Playlist>> _playlistSubscription;
  List<Playlist> _playlists = const <Playlist>[];
  bool _playlistsReady = false;
  int _playlistRevision = 0;
  GoldTrialIdentity? _identity;
  GoldTrialResult result = const GoldTrialResult(GoldTrialOutcome.idle);
  bool ready = false;
  bool requesting = false;
  bool waitingForSource = false;
  bool importing = false;
  bool sourceFailed = false;
  bool sourceLoaded = false;
  bool _activatedHere = false;
  bool _disposed = false;
  bool _checkingSource = false;
  int _generation = 0;
  Timer? _poll;
  Timer? _deadline;
  Stopwatch? _elapsed;

  bool get busy => requesting || waitingForSource || importing;
  // La licence du lecteur et la source IPTV sont deux états distincts.
  // Une liste déjà enregistrée (panel ou ajout manuel) suffit à masquer
  // l'offre, même hors ligne, désactivée ou sans chaînes dans le cache RAM.
  // Les radios et le sport gratuits n'utilisent pas ce dépôt de playlists.
  bool get visible => ready && _playlistsReady && _playlists.isEmpty && !_hasSubscription() &&
      result.outcome != GoldTrialOutcome.alreadyCustomer;
  bool get canRequest => visible && !busy &&
      result.outcome != GoldTrialOutcome.activated &&
      result.outcome != GoldTrialOutcome.alreadyUsed;
  // Un heartbeat peut confirmer la licence AVANT la réponse 201. Le
  // bouton disparaît, mais la confirmation de ce clic doit rester lisible.
  bool get showConfirmation => _activatedHere &&
      result.outcome == GoldTrialOutcome.activated &&
      !_hasCustomerSource;

  bool get _hasCustomerSource =>
      _playlists.any((p) => !isGoldTrialPlaylist(p.name));

  void _playlistsChanged(List<Playlist> playlists) {
    if (_disposed) return;
    _playlistRevision++;
    _playlists = List<Playlist>.unmodifiable(playlists);
    _playlistsReady = true;
    if (_hasCustomerSource) _stopWaiting();
    _changed();
  }

  Future<void> _readPlaylists() async {
    final int revision = _playlistRevision;
    try {
      final List<Playlist> playlists = await _loadPlaylists();
      // Un import/suppression récent prime sur une lecture commencée avant.
      if (_disposed || revision != _playlistRevision) return;
      _playlists = List<Playlist>.unmodifiable(playlists);
      _playlistsReady = true;
    } catch (_) {
      // Une base pas encore lisible ne prouve pas l'absence d'abonnement.
      if (!_disposed && revision == _playlistRevision) _playlistsReady = false;
    }
  }

  static bool _deviceHasSubscription() {
    final SubscriptionState subscription = SubscriptionState.instance;
    // Attendre la lecture du cache évite d'offrir un essai à un abonné
    // pendant le tout premier rendu, y compris hors connexion.
    return !subscription.isLoaded || subscription.remote.paid ||
        subscription.status == SubscriptionStatus.paid ||
        subscription.status == SubscriptionStatus.banned ||
        subscription.status == SubscriptionStatus.frozen;
  }

  static bool _deviceHasTrial() =>
      PlaylistRepository.instance.currentPlaylists.any((p) =>
          isGoldTrialPlaylist(p.name) && p.channelCount > 0);

  Future<GoldTrialIdentity> _deviceIdentity() async {
    final String mac = await DeviceIdentity.instance.mac;
    final String androidId = await DeviceIdentity.instance.androidId();
    final PackageInfo package = await PackageInfo.fromPlatform();
    // Préparer l'identité ne doit pas ajouter de réseau au démarrage de la TV.
    // La preuve est réannoncée au clic, sous le loader, avant la création.
    _prepareDevice = () => DeviceSecret.instance.enroll(mac);
    return GoldTrialIdentity(
      mac: mac,
      androidId: androidId,
      // versionName Android : ni versionCode, ni numéro de build humain.
      appVersion: package.version,
      brand: package.packageName.contains('seven_tv') ? 'zuno' : '7motion',
    );
  }

  String get _cacheKey => 'gold_trial.${_identity!.mac}';

  Future<void> initialize() async {
    // Le boot charge les chaînes en arrière-plan : lire aussi SQLite évite
    // qu'un ancien client voie l'offre avant le premier événement du dépôt.
    final Future<void> playlistsLoaded = _readPlaylists();
    try {
      _identity = await _loadIdentity();
      if (_disposed) return;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      if (prefs.getBool('$_cacheKey.customer') == true) {
        result = const GoldTrialResult(GoldTrialOutcome.alreadyCustomer);
      } else if (prefs.getInt('$_cacheKey.expire') case final int ms) {
        result = ms > DateTime.now().millisecondsSinceEpoch
            ? GoldTrialResult(GoldTrialOutcome.activated,
                expire: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true))
            : const GoldTrialResult(GoldTrialOutcome.alreadyUsed);
      } else if (prefs.getBool('$_cacheKey.used') == true) {
        result = const GoldTrialResult(GoldTrialOutcome.alreadyUsed);
      }
    } catch (_) {
      // La lecture de l'identité sera retentée au clic si nécessaire.
    }
    await playlistsLoaded;
    if (_disposed) return;
    ready = true;
    if (result.outcome == GoldTrialOutcome.activated) _startWaiting();
    _changed();
  }

  Future<void> request() async {
    if (!canRequest || _disposed) return;
    // Ce verrou est posé AVANT le premier await, pas après le POST.
    requesting = true;
    sourceFailed = false;
    _changed();
    try {
      _identity ??= await _loadIdentity();
      if (_disposed) return;
      // Revalider juste avant le POST si une source est arrivée pendant
      // l'attente d'identité, même avant son premier affichage à l'accueil.
      await _readPlaylists();
      if (_disposed || !visible) return;
      await _prepareDevice?.call();
      if (_disposed || !visible) return;
      final Map<String, String> headers = await _sourceHeaders();
      if (_disposed || !visible) return;
      result = await _backend.activate(_identity!, headers: headers);
      if (_disposed) return;
      _activatedHere = result.outcome == GoldTrialOutcome.activated;
      await _rememberResult();
      if (_disposed) return;
      if (result.outcome == GoldTrialOutcome.activated ||
          result.outcome == GoldTrialOutcome.inProgress) {
        _startWaiting();
      }
    } catch (_) {
      if (!_disposed) result = const GoldTrialResult(GoldTrialOutcome.error);
    } finally {
      requesting = false;
      _changed();
    }
  }

  Future<void> _rememberResult() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      switch (result.outcome) {
        case GoldTrialOutcome.alreadyCustomer:
          await prefs.setBool('$_cacheKey.customer', true);
          return;
        case GoldTrialOutcome.alreadyUsed:
          await prefs.setBool('$_cacheKey.used', true);
          return;
        case GoldTrialOutcome.activated:
          await prefs.setInt('$_cacheKey.expire', result.expire!.millisecondsSinceEpoch);
          return;
        default:
          break;
      }
    } catch (_) {
      // Une écriture locale impossible n'annule pas un essai confirmé.
    }
  }

  /// Reprend uniquement la lecture de la source, sans jamais recréer l'essai.
  void retrySource() {
    if (_disposed || busy || (result.outcome != GoldTrialOutcome.activated &&
        result.outcome != GoldTrialOutcome.inProgress)) {
      return;
    }
    _startWaiting();
    _changed();
  }

  void _startWaiting() {
    _stopWaiting();
    if (_hasCustomerSource) return;
    sourceFailed = false;
    sourceLoaded = _hasLoadedTrial();
    if (sourceLoaded) return;
    waitingForSource = true;
    _elapsed = Stopwatch()..start();
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _sourcePushed());
    _deadline = Timer(const Duration(seconds: 30), () {
      _stopWaiting();
      _backend.cancelPending();
      sourceFailed = true;
      _changed();
    });
    // Lire immédiatement après le 201 ; le timer sert uniquement de repli.
    _sourcePushed();
  }

  void _sourcePushed() {
    if (waitingForSource && !_checkingSource && !_disposed) {
      unawaited(_checkSource());
    }
  }

  Future<void> _checkSource() async {
    _checkingSource = true;
    final int generation = _generation;
    try {
      if (_hasLoadedTrial()) {
        _stopWaiting();
        sourceLoaded = true;
        return;
      }
      // La preuve existante est réutilisée, sans en exposer la valeur ni
      // modifier l'inscription de l'appareil au backend.
      final Map<String, String> headers = await _sourceHeaders()
          .timeout(const Duration(seconds: 2));
      if (_disposed || generation != _generation) return;
      final Duration remaining = const Duration(seconds: 30) - _elapsed!.elapsed;
      if (remaining <= Duration.zero) return;
      final bool assigned = await _backend.hasAssignedTrial(
        _identity!.mac,
        headers: headers,
        timeout: remaining < const Duration(seconds: 2)
            ? remaining : const Duration(seconds: 2),
      );
      if (!assigned || _disposed || generation != _generation) return;
      // Le synchroniseur existant sérialise les imports concurrents (push
      // box, démarrage, vérification manuelle). On garde cette unique voie.
      _stopWaiting();
      importing = true;
      _changed();
      await _importSource();
      if (_disposed) return;
      sourceLoaded = _hasLoadedTrial();
      sourceFailed = !sourceLoaded;
    } catch (_) {
      // Une panne de GET se retente au prochain tick, jusqu'à la limite.
      if (importing && !_disposed) sourceFailed = true;
    } finally {
      _checkingSource = false;
      importing = false;
      _changed();
    }
  }

  void _stopWaiting() {
    _generation++;
    waitingForSource = false;
    _poll?.cancel();
    _deadline?.cancel();
    _elapsed?.stop();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWaiting();
    _backend.cancelPending();
    _subscriptionChanges.removeListener(_changed);
    _sourceChanges.removeListener(_sourcePushed);
    unawaited(_playlistSubscription.cancel());
    super.dispose();
  }
}
