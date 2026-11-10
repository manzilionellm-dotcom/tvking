// =========================================================
//  remote_activation_watch.dart — Veille unique panel → box
// =========================================================
//  Trois chemins, un seul effet :
//    1. WebSocket (GET /api/box/ws). Le panel prévient tout de
//       suite. On relit les listes. Reconnexion toute seule.
//    2. Si la prise ne tient pas : canal long (GET /api/box/wait).
//       On accuse réception. Un numéro déjà vu n'est pas rejoué.
//    3. Si ce canal non plus (ancien Worker, 401, 429, Wi-Fi
//       coupé) : lecture courte de /api/status, 1 s pendant
//       l'attente, 2 s ensuite, jusqu'à 45 s si le réseau ne
//       répond plus. Fenêtre de 1 à 2 s sans le push.
//    L'interrupteur zuno.channel.legacy (coupé par défaut) saute
//    l'étape 1 et revient au comportement d'avant.
//
//  Quand le canal tient, on ne relit le statut qu'en filet
//  (25 s) pour ne pas doubler le trafic. Une coupure : on
//  reprend le canal avec le dernier numéro accusé.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app/repair_flags.dart';
import '../../../core/blackbox/black_box.dart';
import '../../../core/realtime/device_session.dart';
import '../../../core/update/update_service.dart';
import '../../about/data/force_update_checker.dart';
import '../../ads/data/startup_ad_repository.dart';
import '../../country_home/data/featured_repository.dart';
import '../../device/data/device_identity.dart';
import '../../device/data/device_secret.dart';
import '../../feedback/data/feedback_repository.dart';
import '../../playlists/data/box_reset.dart';
import '../../playlists/data/default_servers.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../pricing/data/pricing_repository.dart';
import '../../panel_board/data/promo_banner_repository.dart';
import '../../simple_home/data/announcement_repository.dart';
import '../../simple_home/data/home_layout_repository.dart';
import '../../theme/data/remote_theme_repository.dart';
import '../../tv/core/tv_activity.dart';
import '../domain/activation_pace.dart';
import '../domain/box_channel.dart';
import '../domain/box_signal.dart';
import '../domain/order_ack.dart';
import 'box_channel_session.dart';
import 'box_signal_client.dart';
import 'device_realtime_channel.dart';
import 'order_ack_client.dart';
import 'signal_inbox.dart';
import 'subscription_backend.dart';
import 'subscription_state.dart';

class RemoteActivationWatch {
  RemoteActivationWatch._();
  static final RemoteActivationWatch instance = RemoteActivationWatch._();

  Timer? _timer;
  bool _run = false;
  bool _tickBusy = false;
  bool _nudge = false;
  bool _allowSourceImport = true;
  bool _channelUp = false;
  int _failures = 0;
  int _signalFailures = 0;
  int? _lastSourceRev;
  int _generation = 0;
  int _boxCursor = 0;
  int _fleetCursor = 0;
  http.Client? _signalHttp;
  BoxChannelSession? _session;
  DeviceRealtimeChannel? _deviceSession;
  DateTime _lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  String _appVersion = '';
  bool _versionTried = false;
  final Set<int> _seenBox = <int>{};
  final Set<int> _seenFleet = <int>{};
  // Les listes restent ordonnées entre elles. Une longue importation ne doit
  // cependant pas retenir un gel, une activation ou un réglage indépendant.
  final Map<String, Future<bool>> _orderLanes = <String, Future<bool>>{};
  final Map<String, Future<bool>> _ordersInFlight = <String, Future<bool>>{};
  final Map<String, int> _legacyWakeCount = <String, int>{};

  /// Dernier corps reçu sur le canal (tests : pas de mot de passe).
  @visibleForTesting
  String lastSignalBody = '';

  /// Exerce le véritable traitement et les accusés avec un client HTTP de
  /// test, sans ouvrir les boucles permanentes de présence/WebSocket.
  @visibleForTesting
  Future<bool> applyOrdersForTesting(List<BoxOrder> orders) =>
      _applyOrders(orders, via: 'test');

  /// Présence panel pendant l'attente. Assez lent pour ne pas écrire
  /// en base à chaque lecture de statut.
  static const Duration _heartbeatWhileWaiting = Duration(seconds: 60);

  static const String _kBoxCursor = 'zuno.signal.box_after.v1';
  static const String _kFleetCursor = 'zuno.signal.fleet_after.v1';

  /// À appeler une fois le boot lancé. [allowSourceImport] est faux
  /// en mode sans échec : on lit quand même la licence (la box peut
  /// s'ouvrir), mais on ne retélécharge pas une grosse liste.
  void start({
    bool allowSourceImport = true,
    Future<DeviceRealtimeCredentials?> Function()? deviceCredentials,
  }) {
    _allowSourceImport = allowSourceImport;
    if (_run) return;
    _run = true;
    // Prépare le libellé hors du chemin critique du premier accusé.
    unawaited(_version());
    // Le démarrage vient de faire un heartbeat. On ne le double pas.
    _lastHeartbeat = DateTime.now();
    _arm(ActivationPace.fast);
    _generation++;
    final int generation = _generation;
    unawaited(_signalLoop(generation));
    // WebSocket d'abord. S'il ne tient pas, l'attente longue
    // (déjà dans _signalLoop) prend le relais. L'interrupteur
    // de repli, coupé par défaut, saute cette prise.
    unawaited(_socketLoop(generation));
    unawaited(_deviceSocketLoop(
      generation,
      deviceCredentials ?? DeviceSession.instance.credentials,
    ));
  }

  /// « J'ai payé — Vérifier », ou juste après un changement de
  /// licence : on regarde tout de suite, sans attendre le délai.
  void nudge() {
    _nudge = true;
    if (_tickBusy) return;
    _timer?.cancel();
    _arm(Duration.zero);
  }

  void _setChannelUp(bool value) {
    if (_channelUp == value) return;
    _channelUp = value;
    // Une perte du canal ne doit pas attendre le filet garé à 25 s.
    // Le garde empêche un ancien appel réseau de relancer une veille arrêtée.
    if (!value && _run) nudge();
  }

  /// Arrête la veille (téléphone passé en arrière-plan). [start] la
  /// relance ; les ordres envoyés pendant la pause attendent sur le serveur
  /// et sont lus à la reprise (curseur gardé).
  void stop() => stopForTesting();

  @visibleForTesting
  void stopForTesting() {
    _run = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _tickBusy = false;
    _nudge = false;
    _failures = 0;
    _signalFailures = 0;
    _channelUp = false;
    _lastSourceRev = null;
    _session?.stop();
    _session = null;
    _deviceSession?.stop();
    _deviceSession = null;
    _signalHttp?.close();
    _signalHttp = null;
  }

  void _arm(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      await _tick();
      if (!_run) return;
      if (_nudge) {
        _nudge = false;
        _arm(Duration.zero);
        return;
      }
      _arm(
        signalPace(
          channelUp: _channelUp,
          waiting: _isWaiting,
          failures: _failures,
        ),
      );
    });
  }

  /// Vrai tant que l'accueil ne peut pas s'ouvrir, ou qu'il s'ouvre
  /// mais qu'aucune chaîne n'est encore en cache.
  bool get _isWaiting {
    final SubscriptionStatus s = SubscriptionState.instance.status;
    final bool open =
        s == SubscriptionStatus.paid || s == SubscriptionStatus.trialActive;
    final bool has = PlaylistRepository.instance.currentChannels.isNotEmpty;
    return !open || !has;
  }

  /// [sourceOrdered] : un ordre « source » / « source_clear » vient
  /// d'arriver du panel. Les listes sont relues tout de suite, même
  /// si une chaîne joue (sauf repli `zuno.source.order_waits_idle`).
  Future<bool> _tick({bool sourceOrdered = false}) async {
    if (_tickBusy) return false;
    _tickBusy = true;
    try {
      final bool waiting = _isWaiting;
      final bool heartbeatDue = waiting &&
          DateTime.now().difference(_lastHeartbeat) >= _heartbeatWhileWaiting;
      final RemoteSyncOutcome outcome = await _freshStatus(
        heartbeat: heartbeatDue,
      );
      if (heartbeatDue && outcome == RemoteSyncOutcome.applied) {
        _lastHeartbeat = DateTime.now();
      }
      if (outcome != RemoteSyncOutcome.applied) {
        _failures++;
        return false;
      }
      _failures = 0;
      // Remise à neuf demandée depuis le panel (« Réinitialiser la box ») :
      // tout est effacé AVANT de relire les listes, qui sont alors vides.
      if (await BoxReset.maybeApply(snapOf().resetAt)) {
        _lastSourceRev = null;
        sourceOrdered = true;
      }
      // Tombstones du statut : on efface même si le lecteur est
      // ouvert (on n'importe pas une grosse liste à ce moment-là).
      if (snapOf().revoked.isNotEmpty) {
        await RemoteSourceRepository.applyRevocations(snapOf().revoked);
      }
      await _maybeImportSource(ordered: sourceOrdered);
      return true;
    } finally {
      _tickBusy = false;
    }
  }

  /// Une lecture commencée avant l'ordre ne prouve pas son application.
  /// Le heartbeat peut appartenir à un autre écran : on attend sa fin, puis
  /// on exige notre propre lecture, sans attendre l'import des chaînes.
  Future<RemoteSyncOutcome> _freshStatus({bool heartbeat = false}) async {
    final int generation = _generation;
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
    bool first = true;
    while (generation == _generation) {
      final RemoteSyncOutcome outcome = heartbeat && first
          ? await SubscriptionState.instance.syncWithBackend()
          : await SubscriptionState.instance.refreshRemote();
      if (generation != _generation) return RemoteSyncOutcome.busy;
      first = false;
      if (outcome != RemoteSyncOutcome.busy) return outcome;
      if (DateTime.now().isAfter(deadline)) return RemoteSyncOutcome.busy;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return RemoteSyncOutcome.busy;
  }

  RemoteSubscriptionStatus snapOf() => SubscriptionState.instance.remote;

  /// Télécharge la source si la décision pure dit oui. Un échec
  /// réseau ne mémorise pas le numéro : on réessaiera au prochain
  /// tour, sans couper ce qui joue déjà.
  Future<void> _maybeImportSource({bool ordered = false}) async {
    if (!_allowSourceImport) return;
    final RemoteSubscriptionStatus snap = SubscriptionState.instance.remote;
    final bool has = PlaylistRepository.instance.currentChannels.isNotEmpty;
    final bool busy = TvActivity.isBusy;
    final bool fetch = SourceFetchDecision.shouldFetch(
      networkOk: true,
      playbackBusy: busy,
      sourceRevKnown: snap.sourceRev != null,
      sourceRev: snap.sourceRev,
      lastFetchedRev: _lastSourceRev,
      hasChannels: has,
      ordered: ordered,
      orderWaitsIdle: RepairFlags.sourceOrderWaitsIdle,
    );
    if (!fetch) {
      if (ordered) {
        // Repli allumé : on le dit, pour que la boîte noire explique
        // pourquoi la liste n'arrive qu'au retour à l'accueil.
        BlackBox.instance.info(
          'PANEL',
          'ordre liste reçu, import différé : lecture en cours, repli allumé',
        );
      }
      return;
    }
    if (ordered && busy && has) {
      BlackBox.instance.info(
        'PANEL',
        'ordre liste reçu pendant la lecture : import tout de suite',
      );
    }
    // Ordre du panel : les listes mises de côté après un refus sont
    // retentées tout de suite (le revendeur vient peut-être de corriger
    // le mot de passe).
    // Ordre « liste » du panel = renvoi explicite : une liste du panel
    // supprimée sur la télé AVANT cet ordre peut revenir (le panel reste
    // le maître). Voir tv_delete.dart.
    if (ordered) RemoteSourceRepository.notePanelResend();
    final RemoteSyncResult result = await RemoteSourceRepository.sync(
      force: ordered,
    );
    if (result == RemoteSyncResult.networkError ||
        result == RemoteSyncResult.superseded) {
      return;
    }
    if (snap.sourceRev != null) _lastSourceRev = snap.sourceRev;
    // Ordre du panel appliqué : on remonte l'inventaire tout de suite
    // (heartbeat), au lieu d'attendre le prochain heartbeat régulier. Le
    // panel (bouton « Envoi instantané ») voit alors « Liste sur la TV
    // après N s » à la seconde. Repli : zuno.heartbeat.after_import_off.
    if (ordered &&
        result == RemoteSyncResult.loaded &&
        !RepairFlags.heartbeatAfterImportOff) {
      final RemoteSyncOutcome hb =
          await SubscriptionState.instance.syncWithBackend();
      if (hb == RemoteSyncOutcome.applied) _lastHeartbeat = DateTime.now();
      BlackBox.instance.info(
        'PANEL',
        'inventaire envoyé au panel après la liste (${hb.name})',
      );
    }
  }

  /// Prise WebSocket. Tant qu'elle est ouverte, [_signalLoop]
  /// n'ouvre pas l'attente longue. Si le repli est allumé, on
  /// ne tente même pas la prise.
  Future<void> _socketLoop(int generation) async {
    if (RepairFlags.realtimeLegacy) return;
    while (_run && generation == _generation) {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) {
        await _pause(const Duration(seconds: 5), generation);
        continue;
      }
      if (!_run || generation != _generation) return;
      final BoxChannelSession session = BoxChannelSession(
        mac: mac,
        alive: () => _run && generation == _generation,
        onConnectionChanged: (bool connected) {
          if (_run && generation == _generation) _setChannelUp(connected);
        },
        onReceived: (BoxChannelFrame frame) {
          if (!_run || generation != _generation) {
            return;
          }
          if (_cursorsLoaded &&
              frameAlreadyHandled(seq: frame.seq, cursor: _boxCursor)) {
            return;
          }
          _legacyWakeCount[frame.type] =
              (_legacyWakeCount[frame.type] ?? 0) + 1;
          // La réception n'attend ni la playlist précédente ni son analyse.
          // Le serveur conserve le premier RECEIVED ; l'accusé final continue
          // de décrire le résultat réel, après application de l'ordre.
          if (frame.orderId.isNotEmpty) {
            unawaited(OrderAckClient.send(mac, <Map<String, Object?>>[
              ackPayload(
                orderId: frame.orderId,
                state: 'received',
                traceId: frame.traceId,
                appVersion: _appVersion,
                receivedAtMs: DateTime.now().millisecondsSinceEpoch,
              ),
            ]));
          }
          // L'effet léger commence dès la réception. onFrame attendra la
          // même opération : les curseurs restent enregistrés dans l'ordre,
          // jamais au-delà d'une playlist encore en cours d'application.
          if (!refreshesFor(frame.type).contains(SignalRefresh.source) ||
              _priorityRemoval(frame.type)) {
            unawaited(_applyFastFrame(frame, generation));
          } else if (frame.type == 'source') {
            unawaited(_preflightSourceReplacement());
          }
        },
        onFrame: (BoxChannelFrame frame) async {
          // Le Durable Object renvoie le DERNIER ordre à chaque ouverture
          // de la prise. Même numéro que l'attente longue : on lit le
          // numéro gardé (entre deux démarrages) et on ignore un ordre
          // déjà traité. Repli `zuno.realtime.ws_replay_legacy`.
          if (!RepairFlags.wsReplayLegacy) {
            if (!_cursorsLoaded) await _loadCursors();
            if (frameAlreadyHandled(seq: frame.seq, cursor: _boxCursor)) {
              BlackBox.instance.info(
                'PANEL',
                'ordre ${frame.type} n°${frame.seq} déjà traité : ignoré (renvoyé à la reconnexion)',
              );
              return;
            }
          }
          // Le statut, l'annonce, le thème : la veille les connaît
          // déjà par le nom d'ordre. Un ordre de liste relit les
          // listes tout de suite dans _applyOrders (le numéro de
          // source du statut peut ne pas bouger sur le Worker de
          // production) : même chemin que l'attente longue, une
          // seule lecture de /api/device-source par ordre.
          final bool applied = await _applyOrders(<BoxOrder>[
            BoxOrder(
              id: frame.seq,
              kind: frame.type,
              fleet: false,
              orderId: frame.orderId,
              traceId: frame.traceId,
            ),
          ], via: 'ws');
          if (applied &&
              !RepairFlags.wsReplayLegacy &&
              frame.seq > _boxCursor) {
            _boxCursor = frame.seq;
            await _saveCursors();
          }
        },
      );
      _session = session;
      await session.run();
      if (identical(_session, session)) _session = null;
    }
  }

  Future<void> _applyFastFrame(BoxChannelFrame frame, int generation) async {
    if (!_cursorsLoaded) await _loadCursors();
    if (!_run || generation != _generation) return;
    if (!RepairFlags.wsReplayLegacy &&
        frameAlreadyHandled(seq: frame.seq, cursor: _boxCursor)) {
      return;
    }
    await _applyOrders(<BoxOrder>[
      BoxOrder(
        id: frame.seq,
        kind: frame.type,
        fleet: false,
        orderId: frame.orderId,
        traceId: frame.traceId,
      ),
    ], via: 'ws');
  }

  Future<void> _deviceSocketLoop(
    int generation,
    Future<DeviceRealtimeCredentials?> Function() credentials,
  ) async {
    if (RepairFlags.realtimeLegacy) return;
    final String mac = await DeviceIdentity.instance.mac;
    if (!_run || generation != _generation || !mac.startsWith('MK:')) return;
    final session = DeviceRealtimeChannel(
      mac: mac,
      credentialProvider: credentials,
      alive: () => _run && generation == _generation,
      onWake: (DeviceRealtimeWake wake) => _applyDeviceWake(wake, generation),
    );
    _deviceSession = session;
    await session.run();
    if (identical(_deviceSession, session)) _deviceSession = null;
  }

  // Le canal actuel diffuse les réglages globaux ici, pas dans le socket
  // historique. Il ne fournit pas d'order_id : aucun faux ACK n'est créé.
  static const Set<String> _configurationKinds = <String>{
    'message',
    'theme',
    'home',
    'force_update',
    'featured',
    'ad',
    'pricing',
    'feedback',
    'servers',
    'banner',
  };

  Future<void> _applyDeviceWake(DeviceRealtimeWake wake, int generation) async {
    if (!_run || generation != _generation) return;
    final kinds = <String>{
      ...wake.kinds,
      if (wake.resync) ..._configurationKinds,
    };
    if (wake.resync) nudge();
    await Future.wait<bool>(<Future<bool>>[
      for (final String kind in kinds)
        if (_configurationKinds.contains(kind))
          _runOrderLane(_orderLane(kind), () async {
            final bool refreshed = await _sideEffect(kind);
            if (refreshed && _run && generation == _generation) {
              SignalInbox.instance.note(kind);
            }
            return refreshed;
          })
        else
          _applyDeviceTargetWake(kind, generation),
    ]);
  }

  Future<bool> _applyDeviceTargetWake(String kind, int generation) async {
    if (_session?.open == true) {
      final int before = _legacyWakeCount[kind] ?? 0;
      // Le Worker envoie d'abord le réveil v2, puis l'ordre historique suivi.
      // On le laisse arriver, sans confondre une prise TCP ouverte avec une
      // livraison effective. Si elle est devenue muette, v2 prend le relais.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if ((_legacyWakeCount[kind] ?? 0) > before) return true;
    }
    if (!_run || generation != _generation) return false;
    if (kind == 'source') await _preflightSourceReplacement();
    if (_priorityRemoval(kind)) {
      final result = await _readPriorityRemoval(kind);
      if (!result.statusRead) return false;
      final OrderOutcome? removed = result.outcome;
      if (removed != null) {
        if (removed.applied) SignalInbox.instance.note(kind);
        return removed.applied;
      }
      // Attendre une relecture complète ne doit pas retenir un autre
      // retrait confirmé arrivé après cette demande sans preuve.
      return _runOrderLane('source', () => _applySourceOrder(true));
    }
    return _runOrderLane(_orderLane(kind), () async {
      if (refreshesFor(kind).contains(SignalRefresh.source)) {
        return _applySourceOrder(true);
      }
      final bool refreshed = await _freshStatus() == RemoteSyncOutcome.applied;
      if (refreshed && _run && generation == _generation) {
        if (snapOf().revoked.isNotEmpty) {
          await RemoteSourceRepository.applyRevocations(snapOf().revoked);
        }
        SignalInbox.instance.note(kind);
        nudge();
      }
      return refreshed;
    });
  }

  Future<void> _signalLoop(int generation) async {
    final http.Client client = http.Client();
    _signalHttp = client;
    try {
      await _loadCursors();
      while (_run && generation == _generation) {
        // Prise ouverte : on ne double pas avec l'attente longue.
        // Elle reprend toute seule dès que la prise tombe.
        if (_session?.open == true) {
          _setChannelUp(true);
          await _pause(const Duration(seconds: 2), generation);
          continue;
        }
        final String mac = await DeviceIdentity.instance.mac;
        if (!mac.startsWith('MK:')) {
          await _pause(const Duration(seconds: 5), generation);
          continue;
        }
        await DeviceSecret.instance.enroll(mac);
        if (!_run || generation != _generation) return;
        final BoxWaitResult result = await BoxSignalClient.wait(
          client: client,
          mac: mac,
          after: _boxCursor,
          fleetAfter: _fleetCursor,
          version: await _version(),
          build: '0',
        );
        if (!_run || generation != _generation) return;
        if (result.unauthorized || result.rateLimited) {
          // Ancien Worker, secret refusé, ou trop d'ouvertures :
          // la lecture courte continue. On réessaie le canal plus tard.
          // L'attente HTTP peut avoir commencé avant l'ouverture du push.
          // Son refus tardif ne signifie pas que la prise WebSocket est tombée.
          _setChannelUp(_session?.open == true);
          await _pause(const Duration(seconds: 30), generation);
          continue;
        }
        if (result.offline) {
          // Reprise courte : 1 s, puis 2, 4… plafonné à 30 s.
          // On ne martèle pas le réseau, et un retour de Wi-Fi
          // n'attend pas le plafond de 45 s de la lecture courte.
          _setChannelUp(_session?.open == true);
          _signalFailures++;
          final int shift = _signalFailures > 5 ? 5 : _signalFailures;
          final int seconds = 1 << (shift - 1);
          await _pause(
            Duration(seconds: seconds > 30 ? 30 : seconds),
            generation,
          );
          continue;
        }
        _setChannelUp(true);
        _signalFailures = 0;
        lastSignalBody = result.raw;
        if (result.orders.isEmpty) continue;
        final bool applied = await _applyOrders(result.orders, via: 'attente');
        if (!applied) {
          await _pause(const Duration(seconds: 2), generation);
          continue;
        }
        final List<int> boxIds = <int>[
          for (final BoxOrder o in result.orders)
            if (!o.fleet) o.id,
        ];
        final List<int> fleetIds = <int>[
          for (final BoxOrder o in result.orders)
            if (o.fleet) o.id,
        ];
        final bool acked = await BoxSignalClient.ack(
          client: client,
          mac: mac,
          boxIds: boxIds,
          fleetIds: fleetIds,
        );
        if (!acked) continue;
        if (boxIds.isNotEmpty) {
          _boxCursor = boxIds.reduce((int a, int b) => a > b ? a : b);
        }
        if (fleetIds.isNotEmpty) {
          _fleetCursor = fleetIds.reduce((int a, int b) => a > b ? a : b);
        }
        await _saveCursors();
      }
    } finally {
      client.close();
      if (identical(_signalHttp, client)) _signalHttp = null;
    }
  }

  Future<void> _pause(Duration delay, int generation) async {
    final DateTime end = DateTime.now().add(delay);
    while (_run && generation == _generation && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Applique les ordres nouveaux. `false` = le statut n'a pas pu
  /// être lu : on n'accuse pas, on réessaiera les mêmes numéros.
  /// [via] dit par quel chemin l'ordre est arrivé (« ws » ou
  /// « attente ») : la boîte noire horodate la réception, ce qui
  /// permet de mesurer le délai clic du panel → box.
  Future<bool> _applyOrders(List<BoxOrder> orders, {String via = ''}) async {
    final List<bool> results = await Future.wait<bool>(<Future<bool>>[
      for (final BoxOrder order in orders) _dispatchOrder(order, via: via),
    ]);
    return results.every((bool applied) => applied);
  }

  Future<bool> _dispatchOrder(BoxOrder order, {required String via}) {
    final String key = '${order.fleet ? 'fleet' : 'box'}:${order.id}';
    final Future<bool>? running = _ordersInFlight[key];
    if (running != null) return running;
    if ((order.fleet ? _seenFleet : _seenBox).contains(order.id)) {
      return Future<bool>.value(true);
    }
    if (order.kind == 'source' && via != 'ws') {
      unawaited(_preflightSourceReplacement());
    }
    late final Future<bool> operation;
    operation = (_priorityRemoval(order.kind)
            ? _applyOrder(<BoxOrder>[order], via: via)
            : _runOrderLane(
                _orderLane(order.kind),
                () => _applyOrder(<BoxOrder>[order], via: via),
              ))
        .whenComplete(() {
      if (identical(_ordersInFlight[key], operation)) {
        _ordersInFlight.remove(key);
      }
    });
    _ordersInFlight[key] = operation;
    return operation;
  }

  String _orderLane(String kind) {
    if (_priorityRemoval(kind)) return 'removal';
    final Set<SignalRefresh> plan = refreshesFor(kind);
    return plan.contains(SignalRefresh.source)
        ? 'source'
        : (plan.contains(SignalRefresh.status)
            ? 'status'
            : plan.map((SignalRefresh refresh) => refresh.name).join(':'));
  }

  Future<bool> _runOrderLane(String lane, Future<bool> Function() action) {
    final int generation = _generation;
    final Future<bool> previous = _orderLanes[lane] ?? Future<bool>.value(true);
    late final Future<bool> operation;
    operation = previous.catchError((Object _) => false).then((_) async {
      if (generation != _generation) return false;
      return action();
    }).whenComplete(() {
      if (identical(_orderLanes[lane], operation)) _orderLanes.remove(lane);
    });
    _orderLanes[lane] = operation;
    return operation;
  }

  bool _priorityRemoval(String kind) =>
      kind == 'source_clear' || kind == 'reset';

  Future<bool> _preflightSourceReplacement() =>
      _runOrderLane('removal', () async {
        try {
          if (await _freshStatus() != RemoteSyncOutcome.applied) return false;
          final revoked = snapOf().revoked;
          if (!RemoteSourceRepository.supersedeRevokedPanelImport(revoked)) {
            return false;
          }
          await RemoteSourceRepository.applyRevocations(revoked);
          return true;
        } catch (_) {
          // Le traitement ordonné relira le statut et produira son ACK réel.
          return false;
        }
      });

  Future<({bool statusRead, OrderOutcome? outcome})> _readPriorityRemoval(
    String kind,
  ) async {
    bool statusRead = false;
    OrderOutcome? outcome;
    await _runOrderLane('removal', () async {
      statusRead = await _freshStatus() == RemoteSyncOutcome.applied;
      if (statusRead) outcome = await _confirmedRemoval(kind, snapOf());
      return statusRead;
    });
    return (statusRead: statusRead, outcome: outcome);
  }

  /// Le nom de l'ordre n'autorise aucun effacement. Seuls les tombstones ou
  /// un reset_at frais du serveur permettent de dépasser un téléchargement.
  /// Le résultat est propre à cet ordre, jamais le rapport global de l'import.
  Future<OrderOutcome?> _confirmedRemoval(
    String kind,
    RemoteSubscriptionStatus snapshot,
  ) async {
    try {
      if (kind == 'source_clear' && snapshot.revoked.isNotEmpty) {
        RemoteSourceRepository.supersedePendingPanelImports();
        await RemoteSourceRepository.applyRevocations(snapshot.revoked);
        return OrderOutcome(
          applied: true,
          result: 'revoked',
          configRev: snapshot.sourceRev,
        );
      }
      if (kind == 'reset' && !RepairFlags.remoteResetOff) {
        final preferences = await SharedPreferences.getInstance();
        if (!BoxReset.shouldApply(
          resetAt: snapshot.resetAt,
          appliedAt: preferences.getInt(BoxReset.appliedKey) ?? 0,
        )) {
          return null;
        }
        final bool wiped =
            await BoxReset.maybeApply(snapshot.resetAt, strict: true);
        if (!wiped) return null;
        _lastSourceRev = null;
        return OrderOutcome(
          applied: true,
          result: 'reset',
          configRev: snapshot.sourceRev,
        );
      }
      return null;
    } catch (_) {
      return const OrderOutcome(
        applied: false,
        result: 'removal_failed',
        errorCode: 'removal_failed',
        errorMessage: 'effacement local non confirmé',
      );
    }
  }

  Future<bool> _applyOrder(List<BoxOrder> orders, {String via = ''}) async {
    final List<Map<String, Object?>> boxMaps = <Map<String, Object?>>[
      for (final BoxOrder o in orders)
        if (!o.fleet) <String, Object?>{'id': o.id, 'kind': o.kind},
    ];
    final List<Map<String, Object?>> fleetMaps = <Map<String, Object?>>[
      for (final BoxOrder o in orders)
        if (o.fleet) <String, Object?>{'id': o.id, 'kind': o.kind},
    ];
    final List<Map<String, Object?>> freshBox = freshCommands(
      boxMaps,
      _seenBox,
    );
    final List<Map<String, Object?>> freshFleet = freshCommands(
      fleetMaps,
      _seenFleet,
    );
    final List<String> kinds = <String>[
      for (final Map<String, Object?> m in freshBox) m['kind']! as String,
      for (final Map<String, Object?> m in freshFleet) m['kind']! as String,
    ];
    // Accusé RECEIVED dès la réception (avant tout travail) : le serveur
    // distingue « envoyé » de « reçu ». La trace du panel suit dans la
    // boîte noire et dans l'accusé.
    final int receivedAt = DateTime.now().millisecondsSinceEpoch;
    final Set<int> freshIds = <int>{
      for (final Map<String, Object?> m in freshBox) m['id']! as int,
    };
    final List<BoxOrder> tracked = <BoxOrder>[
      for (final BoxOrder o in orders)
        if (!o.fleet && o.orderId.isNotEmpty && freshIds.contains(o.id)) o,
    ];
    for (final BoxOrder o in orders) {
      if (o.fleet || !freshIds.contains(o.id)) continue;
      BlackBox.instance.info(
        'PANEL',
        'ordre ${o.kind} n°${o.id} reçu'
            '${via.isEmpty ? '' : ' ($via)'}'
            '${o.traceId.isEmpty ? '' : ' trace=${o.traceId}'}',
      );
    }
    final String appVersion = await _version();
    final String ackMac = await DeviceIdentity.instance.mac;
    if (tracked.isNotEmpty) {
      unawaited(
        OrderAckClient.send(ackMac, <Map<String, Object?>>[
          for (final BoxOrder o in tracked)
            ackPayload(
              orderId: o.orderId,
              state: 'received',
              traceId: o.traceId,
              appVersion: appVersion,
              receivedAtMs: receivedAt,
            ),
        ]),
      );
    }
    final bool needStatus = kinds.any(kindNeedsStatus);
    final bool sourceOrdered = kinds.any(channelRefreshesSources);
    final bool needsSource = kinds.any(
      (String kind) => refreshesFor(kind).contains(SignalRefresh.source),
    );
    final bool priorityRemoval =
        kinds.length == 1 && _priorityRemoval(kinds.single);
    OrderOutcome? removalOutcome;
    bool statusRead = !needStatus;
    if (priorityRemoval) {
      final result = await _readPriorityRemoval(kinds.single);
      statusRead = result.statusRead;
      if (!statusRead) return false;
      removalOutcome = result.outcome;
    }
    if (removalOutcome != null) {
      // L'effacement confirmé ne dépend pas de la fin du réseau fournisseur.
    } else if (needStatus && !needsSource) {
      statusRead = await _freshStatus() == RemoteSyncOutcome.applied;
      if (!statusRead) return false;
      if (await BoxReset.maybeApply(snapOf().resetAt)) _lastSourceRev = null;
      if (snapOf().revoked.isNotEmpty) {
        await RemoteSourceRepository.applyRevocations(snapOf().revoked);
      }
      // L'activation garde sa vérification de source, mais son affichage et
      // son ACK n'attendent pas le téléchargement de cette source.
      if (_run) nudge();
    } else if (needStatus) {
      // Une lecture déjà en vol a pu partir AVANT l'ordre. On la
      // laisse finir, puis on relit : l'accusé ne part qu'avec
      // l'état d'après le clic.
      statusRead = priorityRemoval
          ? await _runOrderLane(
              'source', () => _applySourceOrder(sourceOrdered))
          : await _applySourceOrder(sourceOrdered);
      if (!statusRead) return false;
    }
    final Map<String, bool> sideOk = <String, bool>{};
    for (final String kind in kinds) {
      sideOk[kind] = removalOutcome?.applied ?? await _sideEffect(kind);
      if (sideOk[kind] == true) SignalInbox.instance.note(kind);
    }
    // Issue RÉELLE de chaque ordre suivi : APPLIED ou FAILED, avec le
    // résultat, l'erreur et la révision de listes effectivement appliquée.
    if (tracked.isNotEmpty) {
      final int doneAt = DateTime.now().millisecondsSinceEpoch;
      final List<Map<String, Object?>> finals = <Map<String, Object?>>[];
      for (final BoxOrder o in tracked) {
        final OrderOutcome out = removalOutcome ??
            orderOutcome(
              kind: o.kind,
              receivedAtMs: receivedAt,
              statusRead: statusRead,
              sideEffectOk: sideOk[o.kind] ?? true,
              report: RemoteSourceRepository.lastReport,
            );
        BlackBox.instance.info(
          'PANEL',
          'ordre ${o.kind} n°${o.id} ${out.applied ? 'appliqué' : 'en échec'} : ${out.result}'
              '${out.configRev == null ? '' : ' (révision ${out.configRev})'}'
              '${o.traceId.isEmpty ? '' : ' trace=${o.traceId}'}',
        );
        finals.add(
          ackPayload(
            orderId: o.orderId,
            state: out.state,
            traceId: o.traceId,
            appVersion: appVersion,
            receivedAtMs: receivedAt,
            appliedAtMs: doneAt,
            outcome: out,
          ),
        );
      }
      unawaited(OrderAckClient.send(ackMac, finals));
    }
    for (final Map<String, Object?> m in freshBox) {
      _seenBox.add(m['id']! as int);
    }
    for (final Map<String, Object?> m in freshFleet) {
      _seenFleet.add(m['id']! as int);
    }
    return true;
  }

  Future<bool> _applySourceOrder(bool sourceOrdered) async {
    final int generation = _generation;
    while (_tickBusy && _run && generation == _generation) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (generation != _generation) return false;
    _timer?.cancel();
    try {
      return await _tick(sourceOrdered: sourceOrdered);
    } finally {
      if (_run && generation == _generation) {
        _arm(_nudge
            ? Duration.zero
            : signalPace(
                channelUp: _channelUp,
                waiting: _isWaiting,
                failures: _failures,
              ));
      }
    }
  }

  /// Rend faux si la relecture a échoué (l'accusé de l'ordre le dira).
  Future<bool> _sideEffect(String kind) async {
    final Set<SignalRefresh> plan = refreshesFor(kind);
    try {
      if (plan.contains(SignalRefresh.announcement)) {
        await AnnouncementRepository.fetchLatest(strict: true);
      }
      if (plan.contains(SignalRefresh.theme)) {
        await RemoteThemeRepository.fetchAndApply(strict: true);
      }
      if (plan.contains(SignalRefresh.home)) {
        await HomeLayoutRepository.instance.refresh(strict: true);
      }
      if (plan.contains(SignalRefresh.forceUpdate)) {
        final bool must = await ForceUpdateChecker.instance.mustUpdate(
          strict: true,
        );
        SignalInbox.instance.setForceBlocked(must);
        // Le panel vient de publier une version : la box la télécharge
        // et ouvre l'installateur sans attendre le prochain tour (30 min).
        unawaited(
          UpdateService.instance.autoUpdate(busy: () => TvActivity.isBusy),
        );
      }
      if (plan.contains(SignalRefresh.featured)) {
        await FeaturedRepository.instance.refresh(strict: true);
      }
      if (plan.contains(SignalRefresh.ad)) {
        await StartupAdRepository.instance.fetch(strict: true);
      }
      if (plan.contains(SignalRefresh.pricing)) {
        await PricingRepository.fetch(strict: true);
      }
      if (plan.contains(SignalRefresh.feedback)) {
        await FeedbackRepository.instance.reload(strict: true);
      }
      if (plan.contains(SignalRefresh.servers)) {
        await DefaultServersApi.fetch(forceRefresh: true, strict: true);
      }
      if (plan.contains(SignalRefresh.banner)) {
        await PromoBannerRepository.instance.refresh(strict: true);
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Signal] effet $kind : ${e.runtimeType}');
      BlackBox.instance.warn('PANEL', 'ordre $kind : relecture en échec');
      return false;
    }
  }

  Future<String> _version() async {
    if (_versionTried) return _appVersion;
    _versionTried = true;
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {
      _appVersion = '';
    }
    return _appVersion;
  }

  /// Vrai une fois les numéros relus (la prise WebSocket peut recevoir
  /// une trame avant que l'attente longue ne les ait chargés).
  bool _cursorsLoaded = false;

  Future<void> _loadCursors() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _boxCursor = prefs.getInt(_kBoxCursor) ?? 0;
      _fleetCursor = prefs.getInt(_kFleetCursor) ?? 0;
    } catch (_) {
      _boxCursor = 0;
      _fleetCursor = 0;
    }
    _cursorsLoaded = true;
  }

  Future<void> _saveCursors() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBoxCursor, _boxCursor);
      await prefs.setInt(_kFleetCursor, _fleetCursor);
    } catch (_) {
      // Le numéro reste en mémoire jusqu'au prochain redémarrage.
    }
  }
}
