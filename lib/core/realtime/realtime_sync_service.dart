// =========================================================
//  realtime_sync_service.dart — Canal temps réel panel → app
// =========================================================
//  Couche WebSocket « en plus » du polling existant (heartbeat 6 h,
//  sync sources 5 min) — JAMAIS « à la place ». Voir le contrat
//  complet : docs/REALTIME-PROTOCOL.md (§3 et §6).
//
//  Rôle :
//    1. Ouvrir un WebSocket vers le backend (`/api/rt/device`) avec le
//       MAC virtuel de l'appareil — le panel voit alors l'appareil
//       « en ligne » en direct.
//    2. Recevoir les ordres `sync` (status / sources / config / all) et
//       relancer les fetchs HTTP EXISTANTS correspondants (aucune
//       nouvelle route, aucun credential ne transite sur le socket).
//    3. Recevoir les `message` admin → bannière in-app (AdminMessageBanner).
//    4. Confirmer chaque ordre reçu avec un `ack {id, ok}` → le panel
//       affiche « Appliqué sur l'appareil ✓ ».
//
//  FAIL-OPEN ABSOLU : si le WebSocket est indisponible (binding pas
//  déployé, réseau KO, plateforme sans dart:io…), l'app se comporte
//  exactement comme avant. Aucune exception ne sort de ce service.
//
//  Reconnexion : backoff 5 → 10 → 30 → 60 → 120 s (plafond), jitter
//  ±20 %, remise à zéro après 60 s de connexion stable. Sur
//  `bye{reason:'replaced'}` (un autre appareil a pris le même MAC),
//  on attend directement le backoff MAXIMUM pour ne pas se battre.
//
//  Aucune nouvelle dépendance : WebSocket de `dart:io` (l'app cible
//  Android / Android TV / Windows — pas de build web).
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/about/data/force_update_checker.dart';
import '../../features/ads/data/startup_ad_repository.dart';
import '../../features/country_home/data/featured_repository.dart';
import '../../features/device/data/device_identity.dart';
import '../../features/playlists/data/remote_source_repository.dart';
import '../../features/pricing/data/pricing_repository.dart';
import '../../features/simple_home/data/announcement_repository.dart';
import '../../features/simple_home/data/home_layout_repository.dart';
import '../../features/subscription/data/now_playing.dart';
import '../../features/subscription/data/subscription_state.dart';
import '../../features/theme/data/remote_theme_repository.dart';
import '../app/boot_guard.dart';
import '../app/build_info.dart';
import '../backend/backend_hosts.dart';
import 'device_message_repository.dart';

/// Message admin poussé par le panel (frame `message` du protocole).
/// Immuable : l'UI (AdminMessageBanner) le lit tel quel.
@immutable
class AdminMessage {
  const AdminMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.durationSec,
  });

  /// Identifiant de l'événement (sert à l'ack et à la dédup côté UI).
  final String id;

  /// Titre court ('' si absent).
  final String title;

  /// Corps du message ('' si absent).
  final String body;

  /// Catégorie visuelle : `'info'` | `'success'` | `'warning'`.
  /// Toute valeur inconnue est normalisée en `'info'` au parsing.
  final String kind;

  /// Durée d'affichage de la bannière (secondes). Défaut 15 s.
  final int durationSec;
}

/// Frame ENTRANTE (hub → appareil) déjà décodée et validée.
///
/// Le parsing est une FONCTION PURE (`RtEvent.parse`) : testable sans
/// socket ni réseau (cf. test/realtime_sync_service_test.dart).
@immutable
class RtEvent {
  const RtEvent._({
    required this.type,
    this.id,
    this.what,
    this.reason,
    this.message,
  });

  /// `'sync'` | `'message'` | `'bye'` (seuls types connus côté appareil).
  final String type;

  /// Identifiant d'événement (à renvoyer dans l'`ack`). `null` = pas d'ack.
  final String? id;

  /// Pour `sync` : `'status'` | `'sources'` | `'config'` | `'all'`.
  /// Une valeur absente/inconnue est normalisée en `'all'` (le plus sûr).
  final String? what;

  /// Pour `bye` : raison de la déconnexion (`'replaced'`…).
  final String? reason;

  /// Pour `message` : le message admin prêt à afficher.
  final AdminMessage? message;

  /// Valeurs acceptées pour `sync.what` (contrat §3).
  static const List<String> kSyncWhats = <String>[
    'status',
    'sources',
    'config',
    'all',
  ];

  /// Décode une frame texte du hub. Renvoie `null` pour TOUT ce qui
  /// n'est pas un objet JSON avec un `type` connu (frames non-JSON
  /// ignorées silencieusement — contrat §8). Ne throw jamais.
  static RtEvent? parse(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Object? type = decoded['type'];
      if (type is! String) return null;

      // Petit helper local : lit une chaîne, '' si absente/mauvais type.
      String str(String key) {
        final Object? v = decoded[key];
        return v is String ? v : '';
      }

      switch (type) {
        case 'sync':
          final String rawWhat = str('what');
          final String id = str('id');
          return RtEvent._(
            type: 'sync',
            id: id.isEmpty ? null : id,
            // Inconnu/absent → 'all' : on re-fetch tout, c'est idempotent
            // et ça ne peut pas rater un ordre du panel.
            what: kSyncWhats.contains(rawWhat) ? rawWhat : 'all',
          );
        case 'message':
          final String rawKind = str('kind');
          final Object? rawDur = decoded['durationSec'];
          // Durée bornée 3–120 s pour qu'un payload farfelu ne laisse
          // pas une bannière collée à l'écran (ni un flash illisible).
          final int durationSec =
              rawDur is num ? rawDur.toInt().clamp(3, 120).toInt() : 15;
          return RtEvent._(
            type: 'message',
            id: str('id').isEmpty ? null : str('id'),
            message: AdminMessage(
              id: str('id'),
              title: str('title'),
              body: str('body'),
              kind: const <String>['info', 'success', 'warning']
                      .contains(rawKind)
                  ? rawKind
                  : 'info',
              durationSec: durationSec,
            ),
          );
        case 'bye':
          return RtEvent._(type: 'bye', reason: str('reason'));
        default:
          return null; // type inconnu → ignoré (compat ascendante)
      }
    } catch (_) {
      return null; // JSON invalide → ignoré silencieusement
    }
  }
}

/// Service temps réel — singleton `RealtimeSyncService.instance`.
///
/// Cycle de vie :
///   - `start(platform: 'mobile'|'tv'|'windows')` UNE fois au boot
///     (idempotent, fire-and-forget, ne throw jamais) ;
///   - le service se reconnecte tout seul (backoff) tant que l'app vit ;
///   - `AppLifecycleState.resumed` → reconnexion immédiate + re-check
///     licence (comble le trou « aucun re-check au retour au 1er plan »).
///
/// L'UI écoute (`ChangeNotifier`) : `connected` (pastille éventuelle) et
/// `lastMessage` (bannière AdminMessageBanner).
class RealtimeSyncService extends ChangeNotifier with WidgetsBindingObserver {
  RealtimeSyncService._();

  /// Instance unique, partagée par tous les entrypoints.
  static final RealtimeSyncService instance = RealtimeSyncService._();

  // ============================================================
  //  Backoff — exposé en statique PUR pour être testable.
  // ============================================================

  /// Paliers de reconnexion (secondes) — contrat §6.
  static const List<int> kBackoffSeconds = <int>[5, 10, 30, 60, 120];

  /// Durée de connexion au-delà de laquelle on considère la liaison
  /// « stable » → le prochain incident repart au 1er palier (5 s).
  static const Duration kStableAfter = Duration(seconds: 60);

  /// « Activation express » — filet UNIVERSEL (téléphone + TV) qui rend
  /// l'activation quasi instantanée MÊME si le WebSocket n'est pas
  /// disponible (binding pas déployé, réseau capricieux, hub occupé).
  ///
  /// Tant que l'appareil n'est pas encore ACTIVÉ (pas payant), et qu'il
  /// est au premier plan, on interroge le backend toutes les
  /// [kActivationInterval] pendant [kActivationFastTicks] cycles
  /// (≈ 3 min par session). Dès que le revendeur valide le code sur le
  /// panel, l'app le voit en quelques secondes au lieu d'attendre le
  /// heartbeat (6 h) ou la synchro sources (5 min). Coût : un petit GET
  /// JSON par cycle, borné dans le temps, arrêté net dès l'activation.
  static const Duration kActivationInterval = Duration(seconds: 8);
  static const int kActivationFastTicks = 22; // ~3 min à 8 s

  /// Calcule le délai avant la tentative n° [attempt] (0 = première
  /// re-tentative). [jitter] ∈ [-0.2, +0.2] (±20 %) — passé en paramètre
  /// pour rester une fonction PURE (le tirage aléatoire est fait par
  /// l'appelant). Toute valeur hors bornes est ramenée dans [-0.2, 0.2].
  static Duration computeBackoff(int attempt, {double jitter = 0}) {
    final int idx = attempt < 0
        ? 0
        : (attempt >= kBackoffSeconds.length
            ? kBackoffSeconds.length - 1
            : attempt);
    final double j = jitter.clamp(-0.2, 0.2).toDouble();
    final int ms = (kBackoffSeconds[idx] * 1000 * (1 + j)).round();
    return Duration(milliseconds: ms);
  }

  // ============================================================
  //  État interne
  // ============================================================

  bool _started = false;
  String _platform = 'mobile';
  WebSocket? _socket;
  bool _connecting = false;
  bool _connected = false;
  int _attempt = 0; // index du prochain palier de backoff
  Timer? _reconnectTimer;
  Timer? _pingTimer; // 'ping' texte toutes les 45 s (keepalive NAT)
  Timer? _watchTimer; // surveille NowPlaying (voir _onWatchTick)
  Timer? _stableTimer; // après 60 s stables → _attempt = 0
  Timer? _activationTimer; // fenêtre « activation express » (voir plus bas)
  int _activationTicksLeft = 0;
  String _lastSentChannel = '';
  DateTime _lastWatchingAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Random _random = Random();

  AdminMessage? _lastMessage;

  /// `true` quand le socket est ouvert et le `hello` envoyé.
  bool get connected => _connected;

  /// Dernier message admin reçu, `null` si aucun (ou déjà fermé).
  AdminMessage? get lastMessage => _lastMessage;

  /// Affiche un message admin construit AILLEURS (ex. boîte de réception
  /// persistante relevée au boot / au resume par DeviceMessageRepository).
  /// Réutilise la MÊME bannière (AdminMessageBanner écoute `lastMessage`).
  void showAdminMessage(AdminMessage msg) {
    _lastMessage = msg;
    notifyListeners();
  }

  /// L'UI a fermé la bannière (croix ou auto-dismiss).
  void dismissMessage() {
    if (_lastMessage == null) return;
    _lastMessage = null;
    notifyListeners();
  }

  // ============================================================
  //  Démarrage / reconnexion
  // ============================================================

  /// Démarre le service (idempotent — les appels suivants sont no-op).
  /// [platform] : `'mobile'` | `'tv'` | `'windows'` selon l'entrypoint.
  /// Ne throw JAMAIS : tout échec est loggé puis retenté (backoff).
  Future<void> start({required String platform}) async {
    if (_started) return;
    _started = true;
    _platform = platform;
    // Hook cycle de vie : au retour au premier plan on reconnecte tout
    // de suite ET on re-vérifie la licence (l'admin a pu agir pendant
    // que l'app était en arrière-plan). Best-effort si le binding
    // n'est pas encore prêt (impossible en pratique : start() est
    // appelé après WidgetsFlutterBinding.ensureInitialized()).
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] addObserver: $e');
    }
    // Filet d'activation express AVANT le connect : un 1er contrôle part
    // tout de suite, sans attendre l'établissement du socket.
    _armActivationFastSync();
    // Boîte de réception persistante : relève les messages déposés depuis
    // le panel (livrés même si l'appareil était hors ligne à l'envoi).
    unawaited(DeviceMessageRepository.fetchAndShow());
    await _connect();
  }

  // ============================================================
  //  Activation express — filet universel (voir kActivationInterval)
  // ============================================================

  /// `true` quand l'appareil est ACTIVÉ (payant confirmé par le serveur)
  /// → plus besoin d'interroger vite : le filet express peut s'arrêter.
  bool get _activationSettled {
    final r = SubscriptionState.instance.remote;
    return r.exists && r.paid;
  }

  /// (Re)démarre la fenêtre d'activation express. Idempotent : annule la
  /// fenêtre en cours et repart pour [kActivationFastTicks] cycles. No-op
  /// si l'appareil est déjà activé. Appelé au boot et à chaque `resumed`.
  void _armActivationFastSync() {
    _activationTimer?.cancel();
    _activationTimer = null;
    if (_activationSettled) return;
    _activationTicksLeft = kActivationFastTicks;
    unawaited(_pollActivationOnce()); // contrôle immédiat
    _activationTimer = Timer.periodic(kActivationInterval, (_) {
      if (_activationSettled || _activationTicksLeft <= 0) {
        _activationTimer?.cancel();
        _activationTimer = null;
        return;
      }
      _activationTicksLeft--;
      unawaited(_pollActivationOnce());
    });
  }

  /// Un contrôle d'activation : statut d'abonnement + source poussée
  /// (mêmes fetchs HTTP existants que le heartbeat). Ne throw jamais.
  Future<void> _pollActivationOnce() async {
    try {
      await SubscriptionState.instance.syncWithBackend();
      if (!BootGuard.instance.safeMode) {
        await RemoteSourceRepository.sync();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] activation poll: $e');
    }
  }

  /// Ferme la connexion courante (si besoin) et reconnecte SANS attendre
  /// le backoff. Utilisé au `resumed` et disponible pour un bouton
  /// « réessayer » éventuel. Ne throw jamais.
  Future<void> forceReconnect() async {
    if (!_started) return;
    _attempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // On détache le socket AVANT de le fermer : ainsi le onDone de
    // l'ancien socket (_onClosed) voit `_socket == null` et ne
    // programme pas une reconnexion concurrente.
    final WebSocket? old = _socket;
    _socket = null;
    _stopTimers();
    if (old != null) {
      try {
        await old.close();
      } catch (_) {}
    }
    if (_connected) {
      _connected = false;
      notifyListeners();
    }
    await _connect();
  }

  /// Tentative de connexion unique. En cas d'échec → backoff.
  Future<void> _connect() async {
    if (_connecting || _socket != null) return;
    _connecting = true;
    try {
      // Identité + méta de l'appareil (mêmes sources que le heartbeat).
      final String mac = await DeviceIdentity.instance.mac;
      final Map<String, String> info =
          await DeviceIdentity.instance.deviceInfo();
      final String model = info['model'] ?? '';
      final String version = await _appVersion();

      // URL wss dérivée de l'hôte HTTP courant (failover inclus : si le
      // heartbeat a basculé sur l'adresse de secours, on la suit).
      final String base = BackendHosts.current
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      // `Uri.replace(queryParameters:)` encode tout proprement
      // (les ':' du MAC deviennent %3A, comme attendu par le worker).
      final Uri uri = Uri.parse('$base/api/rt/device').replace(
        queryParameters: <String, String>{
          'mac': mac,
          'platform': _platform,
          'v': version,
          'b': '$kBuildTs',
          'model': model,
        },
      );

      // ATTENTION : `Future.timeout` n'ANNULE PAS le connect sous-jacent.
      // Sans le `onTimeout` ci-dessous, un connect qui aboutit à 12 s
      // (timeout à 10 s) laisserait un socket fantôme : jamais assigné,
      // jamais écouté, jamais fermé — et l'appareil apparaîtrait « en
      // ligne » en double sur le hub jusqu'au bye{replaced}. On garde la
      // Future d'origine pour FERMER proprement ce socket retardataire.
      final Future<WebSocket> pending = WebSocket.connect(uri.toString());
      final WebSocket ws = await pending.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          unawaited(pending
              .then((WebSocket late) => late.close(1000, 'connect timeout'))
              .catchError((Object _) {}));
          throw TimeoutException('connexion WebSocket > 10 s');
        },
      );
      _socket = ws;
      _connected = true;
      _connecting = false;
      notifyListeners();
      if (kDebugMode) debugPrint('[Realtime] connecté ($_platform)');

      // Après 60 s sans incident, la liaison est jugée stable → le
      // prochain souci repartira au 1er palier (5 s).
      _stableTimer?.cancel();
      _stableTimer = Timer(kStableAfter, () => _attempt = 0);

      // 1re frame obligatoire : `hello` (contrat §3).
      _sendJson(<String, Object?>{
        'type': 'hello',
        'mac': mac,
        'platform': _platform,
        'appVersion': version,
        'appBuild': '$kBuildTs',
        'model': model,
        'channel': NowPlaying.instance.current,
      });
      _lastSentChannel = NowPlaying.instance.current;
      _lastWatchingAt = DateTime.now();
      _startTimers();

      ws.listen(
        _onFrame,
        onDone: _onClosed,
        onError: (Object e) {
          if (kDebugMode) debugPrint('[Realtime] socket error: $e');
          _onClosed();
        },
        cancelOnError: true,
      );
    } catch (e) {
      // Réseau KO, binding rt absent (503), plateforme sans dart:io…
      // → on retentera au prochain palier. JAMAIS d'exception sortante.
      if (kDebugMode) debugPrint('[Realtime] connect: $e');
      _connecting = false;
      _socket = null;
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  /// Le socket vient de se fermer (serveur, réseau, hibernation…).
  void _onClosed() {
    // `forceReconnect` a déjà détaché ce socket → rien à faire ici.
    if (_socket == null) return;
    _socket = null;
    _stopTimers();
    _stableTimer?.cancel(); // (déjà tiré si la liaison était stable)
    if (_connected) {
      _connected = false;
      notifyListeners();
    }
    if (kDebugMode) debugPrint('[Realtime] déconnecté');
    _scheduleReconnect();
  }

  /// Programme la prochaine tentative selon le backoff (+ jitter ±20 %
  /// pour ne pas synchroniser toutes les box sur le même instant après
  /// un incident serveur).
  void _scheduleReconnect() {
    if (_reconnectTimer != null) return; // déjà programmée
    final double jitter = _random.nextDouble() * 0.4 - 0.2;
    final Duration delay = computeBackoff(_attempt, jitter: jitter);
    if (_attempt < kBackoffSeconds.length - 1) _attempt++;
    if (kDebugMode) {
      debugPrint('[Realtime] reconnexion dans ${delay.inSeconds}s');
    }
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  // ============================================================
  //  Timers keepalive + « watching »
  // ============================================================

  void _startTimers() {
    _stopTimers();
    // Keepalive : frame TEXTE littérale 'ping' toutes les 45 s. Le hub
    // répond 'pong' sans même se réveiller (setWebSocketAutoResponse).
    _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      try {
        _socket?.add('ping');
      } catch (e) {
        if (kDebugMode) debugPrint('[Realtime] ping: $e');
      }
    });
    // NowPlaying n'est PAS observable (simple porte-état, pas de
    // notifier) → on le SONDE toutes les 5 s : envoi immédiat au
    // changement de chaîne, et ré-envoi au moins toutes les 60 s tant
    // qu'une lecture est en cours (contrat §3). Coût nul : une lecture
    // de String et, au pire, une petite frame JSON par minute.
    _watchTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _onWatchTick();
    });
  }

  void _stopTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  void _onWatchTick() {
    try {
      final String now = NowPlaying.instance.current;
      final bool changed = now != _lastSentChannel;
      final bool refresh = now.isNotEmpty &&
          DateTime.now().difference(_lastWatchingAt) >=
              const Duration(seconds: 60);
      if (!changed && !refresh) return;
      _sendJson(<String, Object?>{'type': 'watching', 'channel': now});
      _lastSentChannel = now;
      _lastWatchingAt = DateTime.now();
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] watching: $e');
    }
  }

  // ============================================================
  //  Frames entrantes
  // ============================================================

  void _onFrame(dynamic data) {
    try {
      if (data is! String) return; // frames binaires : hors contrat
      if (data == 'pong') return; // réponse au keepalive
      final RtEvent? event = RtEvent.parse(data);
      if (event == null) return; // non-JSON / type inconnu → silencieux
      switch (event.type) {
        case 'sync':
          // Async : on ack quand les re-fetchs sont terminés (le panel
          // mesure ainsi une vraie latence d'application).
          unawaited(_handleSync(event));
          break;
        case 'message':
          final AdminMessage? msg = event.message;
          if (msg != null) {
            _lastMessage = msg;
            notifyListeners(); // la bannière s'affiche
          }
          // Ack immédiat : le message est « livré » dès qu'il est stocké.
          final String? id = event.id;
          if (id != null) _sendAck(id, ok: true);
          break;
        case 'bye':
          // Le serveur nous congédie (typiquement : un autre appareil a
          // pris notre place avec le même MAC). On NE se bat pas : la
          // prochaine reconnexion attendra le backoff MAXIMUM.
          if (event.reason == 'replaced') {
            _stableTimer?.cancel();
            _attempt = kBackoffSeconds.length - 1;
          }
          // Le serveur ferme juste après → _onClosed programmera la
          // reconnexion avec ce backoff.
          break;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] onFrame: $e');
    }
  }

  /// Applique un ordre `sync` puis ack. Ne throw jamais.
  Future<void> _handleSync(RtEvent event) async {
    bool ok = true;
    String? error;
    try {
      await _runSyncActions(event.what ?? 'all');
    } catch (e) {
      ok = false;
      error = '$e';
      if (kDebugMode) debugPrint('[Realtime] sync ${event.what}: $e');
    }
    final String? id = event.id;
    if (id != null) _sendAck(id, ok: ok, error: error);
  }

  /// Mapping `sync.what` → fetchs HTTP EXISTANTS (contrat §3). Rien de
  /// nouveau ne transite par le socket : il ne fait que déclencher.
  Future<void> _runSyncActions(String what) async {
    switch (what) {
      case 'status':
        await SubscriptionState.instance.syncWithBackend();
        break;
      case 'sources':
        // Même garde que le timer 5 min de main.dart : en MODE SANS
        // ÉCHEC (boucle de crash détectée), pas de ré-import distant
        // (fetch+parse = suspect OOM n°1).
        if (!BootGuard.instance.safeMode) {
          await RemoteSourceRepository.sync();
        }
        break;
      case 'config':
        await _refreshRemoteConfig();
        break;
      case 'all':
        await SubscriptionState.instance.syncWithBackend();
        if (!BootGuard.instance.safeMode) {
          await RemoteSourceRepository.sync();
        }
        await _refreshRemoteConfig();
        break;
    }
  }

  /// Re-fetch de la config distante pilotée par le panel — mêmes appels
  /// que le bootstrap de main.dart. Chaque brique est isolée dans son
  /// try/catch : une qui échoue n'empêche pas les autres.
  Future<void> _refreshRemoteConfig() async {
    // Thème (nom de l'app + accent) — s'applique et rebuild tout seul.
    try {
      await RemoteThemeRepository.fetchAndApply();
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] config thème: $e');
    }
    // Tarifs (bloc « Nos offres ») — PricingRepository.notifier notifie.
    try {
      await PricingRepository.fetch();
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] config tarifs: $e');
    }
    // Disposition de l'accueil (sections on/off + ordre).
    try {
      await HomeLayoutRepository.instance.refresh();
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] config layout: $e');
    }
    // Sélection « À la une » de l'accueil pays.
    try {
      await FeaturedRepository.instance.refresh();
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] config featured: $e');
    }
    // Pub vidéo de démarrage : on rafraîchit la CONFIG seulement (elle
    // sera jouée au prochain lancement — on n'interrompt pas le client).
    try {
      await StartupAdRepository.instance.fetch();
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] config pub: $e');
    }
    // Annonces : la bannière d'accueil écoute ce signal et re-fetch
    // aussitôt — une annonce publiée depuis le panel apparaît EN DIRECT
    // (et une annonce retirée disparaît en direct).
    try {
      AnnouncementRepository.notifyChanged();
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] config annonce: $e');
    }
    // Mise à jour forcée : _AppEntry écoute ce signal et relance
    // mustUpdate() — un « Forcer la mise à jour » du panel bloque les
    // apps obsolètes immédiatement, sans attendre leur redémarrage.
    try {
      ForceUpdateChecker.instance.requestRecheck();
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] config maj forcée: $e');
    }
  }

  // ============================================================
  //  Envois sortants
  // ============================================================

  void _sendAck(String id, {required bool ok, String? error}) {
    _sendJson(<String, Object?>{
      'type': 'ack',
      'id': id,
      'ok': ok,
      if (error != null) 'error': error,
    });
  }

  /// Sérialise et envoie une frame JSON. Best-effort : un socket mort
  /// sera détecté par onDone/onError, pas ici.
  void _sendJson(Map<String, Object?> frame) {
    try {
      _socket?.add(jsonEncode(frame));
    } catch (e) {
      if (kDebugMode) debugPrint('[Realtime] send: $e');
    }
  }

  // ============================================================
  //  Cycle de vie de l'app
  // ============================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Retour au premier plan : reconnexion immédiate (Android a pu
      // tuer le socket en arrière-plan) + re-check licence — l'admin a
      // pu activer/geler pendant l'absence (comble le trou du polling).
      unawaited(forceReconnect());
      unawaited(SubscriptionState.instance.syncWithBackend());
      // Relance la fenêtre d'activation express : si le revendeur a agi
      // pendant que l'app était en arrière-plan, on le voit en quelques
      // secondes au retour à l'écran (filet universel, phone + TV).
      _armActivationFastSync();
      // Relève aussi la boîte de messages (un mot déposé pendant l'absence
      // s'affiche au retour à l'écran).
      unawaited(DeviceMessageRepository.fetchAndShow());
      // (les timers repartent dans _connect(), via forceReconnect)
    } else if (state == AppLifecycleState.paused) {
      // Arrière-plan : on GARDE le socket (l'OS le tuera peut-être — la
      // reconnexion au resume rattrape ce cas) mais on ARRÊTE les timers
      // de sondage : rien à « regarder » quand l'app n'est pas visible,
      // et ~17 000 réveils/jour économisés sur un boîtier TV allumé H24.
      _stopTimers();
      // La fenêtre d'activation express n'a pas de sens hors écran : on
      // la coupe (elle repartira au prochain `resumed`).
      _activationTimer?.cancel();
      _activationTimer = null;
    }
  }

  // Version lisible de l'app (« 0.3.1 »), mise en cache. Best-effort.
  String? _appVersionCache;
  Future<String> _appVersion() async {
    if (_appVersionCache != null) return _appVersionCache!;
    try {
      final PackageInfo pkg = await PackageInfo.fromPlatform();
      _appVersionCache = pkg.version;
    } catch (_) {
      _appVersionCache = '';
    }
    return _appVersionCache!;
  }
}
