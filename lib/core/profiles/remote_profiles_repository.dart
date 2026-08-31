// =========================================================
//  remote_profiles_repository.dart — Les profils viennent du panel
// =========================================================
//  POURQUOI CE FICHIER EXISTE (30/08/2026).
//
//  Demande du propriétaire : une seule source M3U collée dans le panel,
//  et le système génère CINQ profils indépendants — papa, maman, trois
//  enfants — chacun avec son PIN, sa liste de chaînes, son historique,
//  activable ou désactivable À DISTANCE, avec contrôle parental par
//  profil.
//
//  « À distance » est le mot qui décide de tout : les profils ne peuvent
//  donc pas vivre uniquement sur l'appareil. Ils suivent exactement le
//  chemin déjà éprouvé de la source M3U :
//
//     panel  →  D1  →  GET /api/device-profiles/:mac  →  app
//                 └→  poussée temps réel (WebSocket)
//
//  On réutilise cette plomberie plutôt que d'en inventer une : elle a
//  déjà son cache, son repli par poll, son acquittement et ses tests.
//
//  ---------------------------------------------------------
//  TROIS RÈGLES QUI ÉVITENT DES PANNES CLIENT
//  ---------------------------------------------------------
//   1. UN ÉCHEC RÉSEAU NE CHANGE RIEN. Si le serveur ne répond pas, on
//      garde les profils déjà en mémoire. Une coupure Wi-Fi ne doit pas
//      faire disparaître les profils de la famille au démarrage.
//
//   2. UNE RÉPONSE VIDE NE VIDE PAS. Le serveur qui répond « aucun
//      profil » (client sans configuration) laisse l'appareil tel quel.
//      Seule une liste NON VIDE remplace la précédente. Sans cette
//      règle, un incident serveur d'une minute effacerait les PIN de
//      toutes les box.
//
//   3. RIEN N'EST BLOQUANT AU DÉMARRAGE. La synchronisation part en
//      arrière-plan ; l'app s'ouvre avec ce qu'elle a en cache.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/device/data/device_identity.dart';
import '../../features/subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../observability/structured_logger.dart';
import '../update/build_flags.dart';
import 'profiles_repository.dart';

class RemoteProfilesRepository {
  RemoteProfilesRepository._();
  static final RemoteProfilesRepository instance = RemoteProfilesRepository._();

  /// Court : les profils sont un petit JSON, et l'app peut s'ouvrir sans.
  /// Mieux vaut renoncer vite et réessayer que retarder l'affichage.
  static const Duration _timeout = Duration(seconds: 6);

  bool _inFlight = false;
  DateTime? _lastOk;

  DateTime? get lastSyncAt => _lastOk;

  /// Point d'entrée normal : résout la MAC tout seul.
  ///
  ///  DEUX GARDES, LES MÊMES QUE POUR LA SOURCE POUSSÉE :
  ///
  ///   • BUILD STORE. Une app publiée sur un store n'a pas de panel
  ///     derrière : personne ne lui pousse de profils. On n'appelle donc
  ///     même pas le serveur — ça évite un aller-retour inutile à chaque
  ///     démarrage sur des dizaines de milliers d'appareils.
  ///
  ///   • MAC NON RECONNUE. `DeviceIdentity` préfixe les identifiants
  ///     qu'il a vraiment calculés par « MK: ». Sans ce préfixe, on
  ///     interrogerait le serveur avec une clé qui ne désigne personne.
  Future<bool> syncSelf() async {
    // `kIsPlayBuild` directement, et non `RemoteSourceRepository.storeBuild`
    // (qui est @visibleForTesting) : lire un membre réservé aux tests depuis
    // du code de production, c'est se donner rendez-vous avec une surprise
    // le jour où quelqu'un le bascule dans un test.
    if (kIsPlayBuild) return false;
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return false;
      return await sync(mac);
    } catch (_) {
      return false; // règle 1 : on ne touche à rien
    }
  }

  /// Récupère les profils du panel pour cette [mac] et les applique.
  ///
  /// Renvoie `true` si la liste locale a CHANGÉ — l'appelant peut alors
  /// rafraîchir l'écran sans le faire à chaque passage.
  Future<bool> sync(String mac) async {
    if (mac.isEmpty) return false;
    // Deux synchronisations ne se chevauchent jamais : la poussée temps
    // réel et le poll périodique peuvent tomber à la même seconde.
    if (_inFlight) return false;
    _inFlight = true;
    try {
      final Uri url = Uri.parse(
        '$kSubscriptionBaseUrl/api/device-profiles/${Uri.encodeComponent(mac)}',
      );
      final http.Response r = await http
          .get(url, headers: const <String, String>{'Accept': 'application/json'})
          .timeout(_timeout);
      if (r.statusCode != 200) return false; // règle 1 : on ne touche à rien
      final Object? decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is! Map<String, dynamic>) return false;

      final Object? list = decoded['profiles'];
      if (list is! List || list.isEmpty) {
        // Règle 2 : « aucun profil » n'efface pas ce qu'on a déjà.
        return false;
      }
      final List<TvProfile> parsed = list
          .map(TvProfile.fromJson)
          .whereType<TvProfile>()
          .toList(growable: false);
      if (parsed.isEmpty) return false; // que des lignes illisibles

      final bool changed =
          await ProfilesRepository.instance.applyRemote(parsed);
      _lastOk = DateTime.now();
      if (changed) {
        StructuredLogger.instance.info(
          domain: 'profiles',
          event: 'remote.applied',
          ctx: <String, Object?>{
            'count': parsed.length,
            'disabled': parsed.where((TvProfile p) => !p.enabled).length,
            'withPin': parsed.where((TvProfile p) => p.pin != null).length,
          },
        );
      }
      return changed;
    } catch (e) {
      // Règle 1 : réseau muet → on garde ce qu'on a. On le NOTE, pour
      // pouvoir répondre « le panel n'était pas joignable » au lieu de
      // chercher un bug dans l'app.
      if (kDebugMode) debugPrint('[Profils] sync KO: $e');
      StructuredLogger.instance.warn(
        domain: 'profiles',
        event: 'remote.sync_fail',
        ctx: <String, Object?>{'error': e.toString()},
      );
      return false;
    } finally {
      _inFlight = false;
    }
  }
}
