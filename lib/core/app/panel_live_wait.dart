// =========================================================
//  panel_live_wait.dart — le panel joint le téléphone À L'INSTANT
// =========================================================
//  POURQUOI CE FICHIER EXISTE (06/10/2026).
//
//  Mesuré par le propriétaire sur son téléphone (MK:30:70:0E:D7:5B) :
//  « Effacer les listes » dans le panel → le serveur ne sert plus aucune
//  liste (0/3), mais le téléphone garde ses listes. Ajouter une liste →
//  « Pas encore de chaînes ». Le téléphone ne lisait le panel qu'à
//  l'ouverture, au réveil (foreground_sync.dart) et toutes les 60 s :
//  rien n'était instantané.
//
//  La box, elle, écoute le serveur en direct. Ici, le même canal en sa
//  forme la plus simple : l'ATTENTE LONGUE du Worker
//    GET /api/box/wait/<MAC>?after=<dernier numéro>&timeout=25000
//  Le serveur garde la requête ouverte jusqu'à 25 s et répond DÈS qu'un
//  ordre part pour cette MAC (liste ajoutée, retirée, éteinte, effacée,
//  activation…). Le téléphone relit alors ses listes et sa licence tout
//  de suite, par le chemin habituel (RemoteSourceRepository.sync, qui
//  porte aussi les ordres et l'effacement du panel).
//
//  Règles :
//    • seulement app au premier plan (batterie, données) ;
//    • une seule relecture à la fois ; un ordre qui arrive pendant une
//      relecture en relance UNE après (rien n'est perdu, pas de rafale) ;
//    • serveur sans canal (404) → on s'arrête, le minuteur de 60 s reste ;
//    • panne réseau → réessai après 2, 4, 8… 30 s ;
//    • aucun secret dans la requête ni dans le journal (MAC + numéro).
//  Repli : préférence `zuno.mobile.live_wait_off` = vrai → pas d'écoute.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/device/data/device_identity.dart';
import '../../features/playlists/data/remote_source_repository.dart';
import '../../features/subscription/data/subscription_backend.dart';
import '../../features/subscription/data/subscription_state.dart';

/// Préférence de repli : vrai = pas d'écoute en direct (ancien comportement).
const String kLiveWaitOffKey = 'zuno.mobile.live_wait_off';

/// Dernier numéro d'ordre déjà traité (survit à la fermeture de l'app).
const String kLiveWaitCursorKey = 'zuno.mobile.live_wait_cursor.v1';

/// Ce que le téléphone retient d'une réponse de l'attente longue.
@immutable
class LiveWaitStep {
  const LiveWaitStep({required this.cursor, required this.changed});

  /// Nouveau curseur (plus grand numéro vu, jamais en recul).
  final int cursor;

  /// Vrai si au moins un ordre NOUVEAU est arrivé → relire tout de suite.
  final bool changed;
}

/// Règle pure (testée) : lit le corps de `/api/box/wait` et dit s'il faut
/// relire. Un corps illisible ne change rien (pas de relecture inutile).
LiveWaitStep readLiveWait(Object? body, int cursor) {
  if (body is! Map) return LiveWaitStep(cursor: cursor, changed: false);
  final Object? box = body['box'];
  if (box is! List) return LiveWaitStep(cursor: cursor, changed: false);
  int next = cursor;
  bool changed = false;
  for (final Object? item in box) {
    if (item is! Map) continue;
    final num? id = item['id'] is num ? item['id'] as num : num.tryParse('${item['id']}');
    if (id == null) continue;
    if (id.toInt() > cursor) changed = true;
    if (id.toInt() > next) next = id.toInt();
  }
  return LiveWaitStep(cursor: next, changed: changed);
}

/// Délai avant de réessayer après [failures] échecs d'affilée.
Duration liveWaitBackoff(int failures) {
  if (failures <= 0) return Duration.zero;
  final int s = 1 << (failures.clamp(1, 5)); // 2, 4, 8, 16, 32
  return Duration(seconds: s > 30 ? 30 : s);
}

class PanelLiveWait with WidgetsBindingObserver {
  PanelLiveWait._();
  static final PanelLiveWait instance = PanelLiveWait._();

  /// Remplaçables par les tests.
  @visibleForTesting
  Future<void> Function() onChange = _defaultOnChange;
  @visibleForTesting
  http.Client Function() clientFactory = http.Client.new;

  static Future<void> _defaultOnChange() async {
    await RemoteSourceRepository.sync();
    await SubscriptionState.instance.syncIfStale(force: true);
  }

  bool _installed = false;
  bool _running = false;
  int _generation = 0;
  http.Client? _client;

  bool _syncing = false;
  bool _again = false;

  /// À appeler une fois au démarrage du téléphone.
  Future<void> install() async {
    if (_installed) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(kLiveWaitOffKey) ?? false) return;
    } catch (_) {}
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      stop();
    }
  }

  void start() {
    if (_running) return;
    _running = true;
    final int gen = ++_generation;
    unawaited(_loop(gen));
  }

  void stop() {
    _running = false;
    _generation++;
    _client?.close();
    _client = null;
  }

  /// Relecture unique : un ordre pendant une relecture en relance une
  /// seule après, jamais deux en parallèle.
  @visibleForTesting
  Future<void> trigger() async {
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _again = false;
        await onChange();
      } while (_again);
    } catch (e) {
      if (kDebugMode) debugPrint('[PanelLiveWait] relecture : $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _loop(int gen) async {
    int failures = 0;
    int cursor = 0;
    try {
      cursor = (await SharedPreferences.getInstance()).getInt(kLiveWaitCursorKey) ?? 0;
    } catch (_) {}
    while (_running && gen == _generation) {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return;
      final http.Client client = clientFactory();
      _client = client;
      try {
        final Uri uri = Uri.parse(
            '$kSubscriptionBaseUrl/api/box/wait/$mac?after=$cursor&timeout=25000');
        final http.Response resp = await client
            .get(uri, headers: const <String, String>{'Accept': 'application/json'})
            .timeout(const Duration(seconds: 40));
        if (gen != _generation) return;
        if (resp.statusCode == 404) {
          // Serveur sans canal : le minuteur de 60 s reste le filet.
          if (kDebugMode) debugPrint('[PanelLiveWait] pas de canal (404)');
          _running = false;
          return;
        }
        if (resp.statusCode != 200) throw StateError('HTTP ${resp.statusCode}');
        final LiveWaitStep step = readLiveWait(jsonDecode(resp.body), cursor);
        failures = 0;
        if (step.cursor != cursor) {
          cursor = step.cursor;
          try {
            await (await SharedPreferences.getInstance()).setInt(kLiveWaitCursorKey, cursor);
          } catch (_) {}
        }
        if (step.changed) unawaited(trigger());
      } catch (e) {
        if (gen != _generation) return;
        failures++;
        if (kDebugMode) debugPrint('[PanelLiveWait] attente : $e');
        await Future<void>.delayed(liveWaitBackoff(failures));
      } finally {
        client.close();
        if (identical(_client, client)) _client = null;
      }
    }
  }
}
