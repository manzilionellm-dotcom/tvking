// =========================================================
//  remote_activation_watch.dart — Veille unique panel → box
// =========================================================
//  Trois chemins, un seul effet :
//    1. WebSocket (GET /api/box/ws). Le panel prévient tout de
//       suite. On relit les listes. Reconnexion toute seule.
//    2. Si la prise ne tient pas : canal long (GET /api/box/wait).
//       On accuse réception. Un numéro déjà vu n'est pas rejoué.
//    3. Si ce canal non plus (ancien Worker, 401, 429, Wi-Fi
//       coupé) : lecture courte de /api/status, 3 s pendant
//       l'attente, 4 s ensuite, jusqu'à 45 s si le réseau ne
//       répond plus. C'est le rythme de la version 103.
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
  DateTime _lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  String _appVersion = '';
  bool _versionTried = false;
  final Set<int> _seenBox = <int>{};
  final Set<int> _seenFleet = <int>{};

  /// Dernier corps reçu sur le canal (tests : pas de mot de passe).
  @visibleForTesting
  String lastSignalBody = '';

  /// Présence panel pendant l'attente. Assez lent pour ne pas écrire
  /// en base à chaque lecture de statut.
  static const Duration _heartbeatWhileWaiting = Duration(seconds: 60);

  static const String _kBoxCursor = 'zuno.signal.box_after.v1';
  static const String _kFleetCursor = 'zuno.signal.fleet_after.v1';

  /// À appeler une fois le boot lancé. [allowSourceImport] est faux
  /// en mode sans échec : on lit quand même la licence (la box peut
  /// s'ouvrir), mais on ne retélécharge pas une grosse liste.
  void start({bool allowSourceImport = true}) {
    _allowSourceImport = allowSourceImport;
    if (_run) return;
    _run = true;
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
  }

  /// « J'ai payé — Vérifier », ou juste après un changement de
  /// licence : on regarde tout de suite, sans attendre le délai.
  void nudge() {
    _nudge = true;
    if (_tickBusy) return;
    _timer?.cancel();
    _arm(Duration.zero);
  }

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
      _arm(signalPace(
        channelUp: _channelUp,
        waiting: _isWaiting,
        failures: _failures,
      ));
    });
  }

  /// Vrai tant que l'accueil ne peut pas s'ouvrir, ou qu'il s'ouvre
  /// mais qu'aucune chaîne n'est encore en cache.
  bool get _isWaiting {
    final SubscriptionStatus s = SubscriptionState.instance.status;
    final bool open = s == SubscriptionStatus.paid ||
        s == SubscriptionStatus.trialActive;
    final bool has = PlaylistRepository.instance.currentChannels.isNotEmpty;
    return !open || !has;
  }

  /// [sourceOrdered] : un ordre « source » / « source_clear » vient
  /// d'arriver du panel. Les listes sont relues tout de suite, même
  /// si une chaîne joue (sauf repli `zuno.source.order_waits_idle`).
  Future<void> _tick({bool sourceOrdered = false}) async {
    if (_tickBusy) return;
    _tickBusy = true;
    try {
      final bool waiting = _isWaiting;
      final bool heartbeatDue = waiting &&
          DateTime.now().difference(_lastHeartbeat) >= _heartbeatWhileWaiting;
      final RemoteSyncOutcome outcome = heartbeatDue
          ? await SubscriptionState.instance.syncWithBackend()
          : await SubscriptionState.instance.refreshRemote();
      if (outcome == RemoteSyncOutcome.busy) return;
      if (heartbeatDue && outcome == RemoteSyncOutcome.applied) {
        _lastHeartbeat = DateTime.now();
      }
      if (outcome != RemoteSyncOutcome.applied) {
        _failures++;
        return;
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
    } finally {
      _tickBusy = false;
    }
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
    final RemoteSyncResult result =
        await RemoteSourceRepository.sync(force: ordered);
    if (result == RemoteSyncResult.networkError) return;
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
        onFrame: (BoxChannelFrame frame) async {
          // Le statut, l'annonce, le thème : la veille les connaît
          // déjà par le nom d'ordre. Un ordre de liste relit les
          // listes tout de suite dans _applyOrders (le numéro de
          // source du statut peut ne pas bouger sur le Worker de
          // production) : même chemin que l'attente longue, une
          // seule lecture de /api/device-source par ordre.
          await _applyOrders(<BoxOrder>[
            BoxOrder(
              id: frame.seq,
              kind: frame.type,
              fleet: false,
              orderId: frame.orderId,
              traceId: frame.traceId,
            ),
          ], via: 'ws');
        },
      );
      _session = session;
      await session.run();
      if (identical(_session, session)) _session = null;
    }
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
          _channelUp = true;
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
          _channelUp = false;
          await _pause(const Duration(seconds: 30), generation);
          continue;
        }
        if (result.offline) {
          // Reprise courte : 1 s, puis 2, 4… plafonné à 30 s.
          // On ne martèle pas le réseau, et un retour de Wi-Fi
          // n'attend pas le plafond de 45 s de la lecture courte.
          _channelUp = false;
          _signalFailures++;
          final int shift = _signalFailures > 5 ? 5 : _signalFailures;
          final int seconds = 1 << (shift - 1);
          await _pause(
            Duration(seconds: seconds > 30 ? 30 : seconds),
            generation,
          );
          continue;
        }
        _channelUp = true;
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
    final List<Map<String, Object?>> boxMaps = <Map<String, Object?>>[
      for (final BoxOrder o in orders)
        if (!o.fleet) <String, Object?>{'id': o.id, 'kind': o.kind},
    ];
    final List<Map<String, Object?>> fleetMaps = <Map<String, Object?>>[
      for (final BoxOrder o in orders)
        if (o.fleet) <String, Object?>{'id': o.id, 'kind': o.kind},
    ];
    final List<Map<String, Object?>> freshBox =
        freshCommands(boxMaps, _seenBox);
    final List<Map<String, Object?>> freshFleet =
        freshCommands(fleetMaps, _seenFleet);
    final List<String> kinds = <String>[
      for (final Map<String, Object?> m in freshBox) m['kind']! as String,
      for (final Map<String, Object?> m in freshFleet) m['kind']! as String,
    ];
    // Accusé RECEIVED dès la réception (avant tout travail) : le serveur
    // distingue « envoyé » de « reçu ». La trace du panel suit dans la
    // boîte noire et dans l'accusé.
    final int receivedAt = DateTime.now().millisecondsSinceEpoch;
    final Set<int> freshIds = <int>{for (final Map<String, Object?> m in freshBox) m['id']! as int};
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
      unawaited(OrderAckClient.send(ackMac, <Map<String, Object?>>[
        for (final BoxOrder o in tracked)
          ackPayload(
            orderId: o.orderId,
            state: 'received',
            traceId: o.traceId,
            appVersion: appVersion,
            receivedAtMs: receivedAt,
          ),
      ]));
    }
    final bool needStatus = kinds.any(kindNeedsStatus);
    final bool sourceOrdered = kinds.any(channelRefreshesSources);
    if (needStatus) {
      // Une lecture déjà en vol a pu partir AVANT l'ordre. On la
      // laisse finir, puis on relit : l'accusé ne part qu'avec
      // l'état d'après le clic.
      while (_tickBusy && _run) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      _timer?.cancel();
      await _tick(sourceOrdered: sourceOrdered);
      if (SubscriptionState.instance.syncHint == 'offline') return false;
    }
    final Map<String, bool> sideOk = <String, bool>{};
    for (final String kind in kinds) {
      sideOk[kind] = await _sideEffect(kind);
      SignalInbox.instance.note(kind);
    }
    // Issue RÉELLE de chaque ordre suivi : APPLIED ou FAILED, avec le
    // résultat, l'erreur et la révision de listes effectivement appliquée.
    if (tracked.isNotEmpty) {
      final bool statusRead = SubscriptionState.instance.syncHint != 'offline';
      final int doneAt = DateTime.now().millisecondsSinceEpoch;
      final List<Map<String, Object?>> finals = <Map<String, Object?>>[];
      for (final BoxOrder o in tracked) {
        final OrderOutcome out = orderOutcome(
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
        finals.add(ackPayload(
          orderId: o.orderId,
          state: out.state,
          traceId: o.traceId,
          appVersion: appVersion,
          receivedAtMs: receivedAt,
          appliedAtMs: doneAt,
          outcome: out,
        ));
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

  /// Rend faux si la relecture a échoué (l'accusé de l'ordre le dira).
  Future<bool> _sideEffect(String kind) async {
    final Set<SignalRefresh> plan = refreshesFor(kind);
    try {
      if (plan.contains(SignalRefresh.announcement)) {
        await AnnouncementRepository.fetchLatest();
      }
      if (plan.contains(SignalRefresh.theme)) {
        await RemoteThemeRepository.fetchAndApply();
      }
      if (plan.contains(SignalRefresh.home)) {
        await HomeLayoutRepository.instance.refresh();
      }
      if (plan.contains(SignalRefresh.forceUpdate)) {
        final bool must = await ForceUpdateChecker.instance.mustUpdate();
        SignalInbox.instance.setForceBlocked(must);
        // Le panel vient de publier une version : la box la télécharge
        // et ouvre l'installateur sans attendre le prochain tour (30 min).
        unawaited(
          UpdateService.instance.autoUpdate(busy: () => TvActivity.isBusy),
        );
      }
      if (plan.contains(SignalRefresh.featured)) {
        await FeaturedRepository.instance.refresh();
      }
      if (plan.contains(SignalRefresh.ad)) {
        await StartupAdRepository.instance.fetch();
      }
      if (plan.contains(SignalRefresh.pricing)) {
        await PricingRepository.fetch();
      }
      if (plan.contains(SignalRefresh.feedback)) {
        await FeedbackRepository.instance.reload();
      }
      if (plan.contains(SignalRefresh.servers)) {
        await DefaultServersApi.fetch(forceRefresh: true);
      }
      if (plan.contains(SignalRefresh.banner)) {
        await PromoBannerRepository.instance.refresh();
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Signal] effet $kind : $e');
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

  Future<void> _loadCursors() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _boxCursor = prefs.getInt(_kBoxCursor) ?? 0;
      _fleetCursor = prefs.getInt(_kFleetCursor) ?? 0;
    } catch (_) {
      _boxCursor = 0;
      _fleetCursor = 0;
    }
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
