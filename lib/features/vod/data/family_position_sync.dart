// =========================================================
//  family_position_sync.dart — « Chacun reprend son film », en famille
// =========================================================
//  Netflix sur une ligne à UNE connexion : chaque membre a son profil et
//  retrouve son film là où il l'a laissé, sur la TV du salon comme sur son
//  téléphone. Les positions de reprise (PlaybackPositionRepository, locales
//  par profil) sont ici POUSSÉES au serveur et RÉCUPÉRÉES à chaque
//  changement de profil / démarrage, via /api/family/positions.
//
//  RÈGLES
//    • Jamais d'URL de flux dans ce qui part (elle porte les identifiants du
//      compte). L'autre appareil retrouve le contenu par sa clé (`vod-…`,
//      `ep-…`) dans son propre catalogue ; sa position s'applique quand il
//      l'ouvre. Une entrée reçue sans URL locale n'apparaît pas dans la
//      rangée « Continuer » (rien à relancer), mais sa barre de progression
//      et sa reprise, elles, marchent.
//    • Fusion « le plus récent gagne », des deux côtés ; « terminé » se
//      propage (tombstone).
//    • Envoi DIFFÉRÉ (8 s après la dernière modification) : le lecteur
//      sauvegarde toutes les 4 s ; on n'envoie qu'une fois par pause de
//      l'activité, jamais à chaque tick.
//    • Mode Bouclier « télémétrie minimale » : RIEN ne part et rien n'est
//      lu — le client a choisi que ses films ne quittent pas sa box.
//    • Tout est best-effort : réseau muet = on garde le local, sans erreur.
// =========================================================
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../../core/privacy/privacy_shield.dart';
import '../../../core/profiles/profiles_repository.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/family_backend.dart';
import 'playback_position_repository.dart';

/// Accès réseau injectable (tests : aucun HTTP).
abstract class FamilyPositionTransport {
  Future<List<Map<String, dynamic>>?> fetch(String mac, String profile);
  Future<bool> push(String mac, String profile, List<Map<String, Object?>> items);
}

class _HttpTransport implements FamilyPositionTransport {
  const _HttpTransport();
  @override
  Future<List<Map<String, dynamic>>?> fetch(String mac, String profile) =>
      FamilyBackend.positions(mac, profile);
  @override
  Future<bool> push(
          String mac, String profile, List<Map<String, Object?>> items) =>
      FamilyBackend.pushPositions(mac, profile, items);
}

class FamilyPositionSync {
  FamilyPositionSync._();
  static final FamilyPositionSync instance = FamilyPositionSync._();

  /// Délai entre la dernière modification locale et l'envoi.
  static const Duration pushDelay = Duration(seconds: 8);

  @visibleForTesting
  FamilyPositionTransport transport = const _HttpTransport();

  /// Identité et profil injectables (tests).
  @visibleForTesting
  Future<String> Function() macProvider = () => DeviceIdentity.instance.mac;
  @visibleForTesting
  String Function() profileProvider =
      () => ProfilesRepository.instance.active.id;

  /// Interrupteur global. ÉTEINT sous `flutter test` (variable d'environnement
  /// `FLUTTER_TEST` posée par l'outil) : aucun test unitaire ne doit parler
  /// au vrai serveur parce qu'un dépôt a appelé `load()`. Les tests de CE
  /// module le rallument avec un transport factice.
  @visibleForTesting
  bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  Timer? _pushTimer;
  bool _pushing = false;
  bool _pullInFlight = false;

  /// Contenus marqués « terminé » localement depuis le dernier envoi : ils
  /// n'existent plus dans le dépôt, on les pousse comme tombstones.
  final Map<String, DateTime> _finished = <String, DateTime>{};

  /// Dernier envoi réussi : on ne renvoie que ce qui a changé depuis.
  DateTime _lastPushedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _allowed =>
      enabled && !PrivacyShield.instance.minimalTelemetryActive;

  /// Le dépôt local a changé (position enregistrée) → envoi différé.
  void noteChanged() {
    if (!_allowed) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDelay, () => unawaited(pushNow()));
  }

  /// Un contenu vient d'être marqué terminé localement.
  void noteFinished(String key, {DateTime? at}) {
    if (!_allowed) return;
    _finished[key] = at ?? DateTime.now();
    noteChanged();
  }

  /// Envoie MAINTENANT ce qui a changé depuis le dernier envoi réussi.
  Future<void> pushNow() async {
    _pushTimer?.cancel();
    _pushTimer = null;
    if (!_allowed || _pushing) return;
    _pushing = true;
    try {
      final PlaybackPositionRepository repo = PlaybackPositionRepository.instance;
      final List<Map<String, Object?>> items = <Map<String, Object?>>[
        for (final PlaybackPosition e in repo.allEntries)
          if (e.updatedAt.isAfter(_lastPushedAt))
            <String, Object?>{
              'key': e.key,
              'position_ms': e.positionMs,
              'duration_ms': e.durationMs,
              'finished': false,
              'updated_at': e.updatedAt.millisecondsSinceEpoch,
              'name': e.name,
              'poster_url': e.posterUrl,
              'is_episode': e.isEpisode,
            },
        for (final MapEntry<String, DateTime> f in _finished.entries)
          <String, Object?>{
            'key': f.key,
            'finished': true,
            'updated_at': f.value.millisecondsSinceEpoch,
          },
      ];
      if (items.isEmpty) return;
      final String mac = await macProvider();
      if (mac.isEmpty) return;
      final DateTime stamp = DateTime.now();
      final bool ok = await transport.push(mac, profileProvider(), items);
      if (ok) {
        _lastPushedAt = stamp;
        _finished.clear();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FamilyPos] push: $e');
    } finally {
      _pushing = false;
    }
  }

  /// Récupère les positions du profil actif et les FUSIONNE dans le dépôt
  /// local (le plus récent gagne). Renvoie le nombre d'entrées appliquées.
  Future<int> pullNow() async {
    if (!_allowed || _pullInFlight) return 0;
    _pullInFlight = true;
    try {
      final String mac = await macProvider();
      if (mac.isEmpty) return 0;
      final String profile = profileProvider();
      final List<Map<String, dynamic>>? remote =
          await transport.fetch(mac, profile);
      if (remote == null || remote.isEmpty) return 0;
      // Le profil a pu changer pendant l'attente réseau : on n'applique
      // jamais les films de papa dans la liste de maman.
      if (profileProvider() != profile) return 0;
      final List<PlaybackPosition> incoming = <PlaybackPosition>[];
      final Map<String, DateTime> finished = <String, DateTime>{};
      for (final Map<String, dynamic> j in remote) {
        final String key = '${j['key'] ?? ''}';
        final int updatedMs = (j['updated_at'] as num?)?.toInt() ?? 0;
        if (key.isEmpty || updatedMs <= 0) continue;
        final DateTime at = DateTime.fromMillisecondsSinceEpoch(updatedMs);
        if (j['finished'] == true) {
          finished[key] = at;
          continue;
        }
        final int pos = (j['position_ms'] as num?)?.toInt() ?? 0;
        final int dur = (j['duration_ms'] as num?)?.toInt() ?? 0;
        if (dur <= 0) continue;
        incoming.add(PlaybackPosition(
          key: key,
          positionMs: pos,
          durationMs: dur,
          updatedAt: at,
          name: '${j['name'] ?? ''}',
          // Pas d'URL côté serveur : le dépôt garde celle qu'il connaît déjà
          // pour ce contenu, sinon vide (reprise OK, rangée « Continuer » non).
          streamUrl: '',
          posterUrl: j['poster_url'] as String?,
          isEpisode: j['is_episode'] == true,
        ));
      }
      return PlaybackPositionRepository.instance
          .mergeRemote(incoming, finished: finished);
    } catch (e) {
      if (kDebugMode) debugPrint('[FamilyPos] pull: $e');
      return 0;
    } finally {
      _pullInFlight = false;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _pushing = false;
    _pullInFlight = false;
    _finished.clear();
    _lastPushedAt = DateTime.fromMillisecondsSinceEpoch(0);
    enabled = !Platform.environment.containsKey('FLUTTER_TEST');
    transport = const _HttpTransport();
    macProvider = () => DeviceIdentity.instance.mac;
    profileProvider = () => ProfilesRepository.instance.active.id;
  }
}
