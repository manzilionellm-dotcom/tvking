// =========================================================
//  tv_diagnostics_service.dart — Vérifications réseau ON-DEVICE partagées
// =========================================================
//  EXTRACTION (refactor 2026-07-10) : ces vérifications vivaient dans
//  tv_diagnostic_screen.dart (l'écran caché HAUT-HAUT-BAS-BAS). La Boîte
//  noire des Réglages (tv_black_box_screen.dart) a besoin des MÊMES
//  vérifications pour son « Diagnostiquer maintenant » → on les sort dans
//  ce service PARTAGÉ plutôt que dupliquer. L'écran caché consomme
//  désormais le service — comportement et textes STRICTEMENT identiques.
//
//  Chaque vérification est INDÉPENDANTE, en LECTURE seule (aucune écriture
//  réseau, aucune URL inventée), time-out borné (8 s), et renvoie un
//  (statut, détail) affichable tel quel. Aucune exception ne sort d'ici.
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:native_video_player/native_video_player.dart';

import '../../../core/playback/stream_slot.dart';
import '../../cast/data/stream_probe.dart';
import '../../device/data/device_identity.dart';
import '../../player/data/player_settings.dart';
import '../../player/data/stream_diagnostics.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;

/// Statut d'une vérification terminée (le « en cours » est un état d'UI,
/// il reste dans les écrans).
enum TvCheckStatus { ok, fail, timeout, unknown }

/// Résultat d'une vérification : statut + détail humain affichable tel quel.
class TvCheckResult {
  const TvCheckResult(this.status, this.detail);

  final TvCheckStatus status;
  final String detail;

  bool get isOk => status == TvCheckStatus.ok;
}

class TvDiagnosticsService {
  TvDiagnosticsService._();
  static final TvDiagnosticsService instance = TvDiagnosticsService._();

  /// Jeton de réclamation du créneau réseau pour les sondes de diagnostic :
  /// réclamer démonte (et attend) les consommateurs en cours — l'outil ne
  /// doit jamais se battre contre l'app qu'il diagnostique (audit 19/08).
  /// Pas de register : les sondes sont courtes et attendues, rien à démonter
  /// chez nous.
  final Object _slotToken = Object();

  /// Time-out commun à chaque vérification (~8 s : assez pour un serveur
  /// lent, assez court pour que le client voie l'écran avancer).
  static const Duration kCheckTimeout = Duration(seconds: 8);

  // ------------------------------------------------------------------
  // 1. Portail captif : un 204 « nu » = sortie Internet libre. Un 200 avec
  //    corps, un 302 ou un autre code = portail captif / interception.
  // ------------------------------------------------------------------
  Future<TvCheckResult> checkCaptivePortal() async {
    try {
      final http.Response r = await http
          .get(Uri.parse('http://connectivitycheck.gstatic.com/generate_204'))
          .timeout(kCheckTimeout);
      if (r.statusCode == 204 && r.body.isEmpty) {
        return const TvCheckResult(
            TvCheckStatus.ok, 'HTTP 204 (sortie Internet libre)');
      }
      return TvCheckResult(TvCheckStatus.fail,
          'HTTP ${r.statusCode} corps=${r.body.length}o → portail captif probable');
    } on TimeoutException {
      return const TvCheckResult(TvCheckStatus.timeout, 'pas de réponse en 8 s');
    } catch (e) {
      return TvCheckResult(TvCheckStatus.fail, _err(e));
    }
  }

  // ------------------------------------------------------------------
  // 2. DNS : résolution de l'hôte IPTV. Pas d'hôte = INCONNU.
  // ------------------------------------------------------------------
  Future<TvCheckResult> checkDns(String? host) async {
    if (host == null || host.isEmpty) {
      return const TvCheckResult(
          TvCheckStatus.unknown, 'aucune chaîne chargée → hôte INCONNU');
    }
    try {
      final List<InternetAddress> ips =
          await InternetAddress.lookup(host).timeout(kCheckTimeout);
      if (ips.isEmpty) {
        return TvCheckResult(TvCheckStatus.fail, '$host → aucune IP');
      }
      return TvCheckResult(TvCheckStatus.ok,
          '$host → ${ips.map((InternetAddress a) => a.address).join(', ')}');
    } on TimeoutException {
      return TvCheckResult(
          TvCheckStatus.timeout, '$host : pas de réponse DNS en 8 s');
    } catch (e) {
      return TvCheckResult(TvCheckStatus.fail, '$host : ${_err(e)}');
    }
  }

  // ------------------------------------------------------------------
  // 2 bis. Joignabilité TCP du SERVEUR (sans parler HTTP) : distingue
  //  « le serveur du fournisseur est mort » (connexion refusée/timeout)
  //  de « le serveur répond mais refuse le flux » (vérif suivante).
  //  Utilisée par la Boîte noire (étape 3 du « Diagnostiquer maintenant »).
  // ------------------------------------------------------------------
  Future<TvCheckResult> checkServerReachable(String? host, {int port = 80}) async {
    if (host == null || host.isEmpty) {
      return const TvCheckResult(
          TvCheckStatus.unknown, 'hôte INCONNU → serveur non testé');
    }
    try {
      final Socket s =
          await Socket.connect(host, port).timeout(kCheckTimeout);
      s.destroy();
      return TvCheckResult(
          TvCheckStatus.ok, '$host:$port accepte la connexion');
    } on TimeoutException {
      return TvCheckResult(
          TvCheckStatus.timeout, '$host:$port ne répond pas en 8 s');
    } catch (e) {
      return TvCheckResult(TvCheckStatus.fail, '$host:$port : ${_err(e)}');
    }
  }

  // ------------------------------------------------------------------
  // 3. Joignabilité du flux : HEAD (léger) puis repli GET. On AFFICHE le
  //    code HTTP. 456 = blocage fournisseur (limite d'écrans / IP).
  // ------------------------------------------------------------------
  Future<TvCheckResult> checkStreamReachability(String? streamUrl) async {
    if (streamUrl == null || streamUrl.isEmpty) {
      return const TvCheckResult(
          TvCheckStatus.unknown, 'aucune chaîne chargée → URL INCONNUE');
    }
    final Uri uri = Uri.parse(streamUrl);
    try {
      int code;
      try {
        final http.Response h = await http.head(uri).timeout(kCheckTimeout);
        code = h.statusCode;
      } catch (_) {
        // Beaucoup de serveurs IPTV refusent HEAD → on retente en GET (sans
        // lire tout le flux : le code de statut arrive avec les en-têtes). On
        // ANNULE aussitôt le corps : sinon la connexion live resterait ouverte
        // et pourrait bloquer la sonde lecteur sur un abonnement 1 connexion.
        final http.Request req = http.Request('GET', uri);
        final http.StreamedResponse g =
            await req.send().timeout(kCheckTimeout);
        code = g.statusCode;
        // On ANNULE aussitôt le corps sans le lire. `onError`/`cancelOnError`
        // (correctif d'audit) : sans eux, une erreur émise sur ce court
        // intervalle devenait une erreur asynchrone NON GÉRÉE (remontée au
        // filet global). Ici on l'avale : le code de statut est déjà lu.
        await g.stream
            .listen((_) {}, onError: (_) {}, cancelOnError: true)
            .cancel();
      }
      if (code == 456) {
        return const TvCheckResult(
            TvCheckStatus.fail, 'HTTP 456 — fournisseur bloque cette IP');
      } else if (code >= 200 && code < 400) {
        return TvCheckResult(TvCheckStatus.ok, 'HTTP $code (flux joignable)');
      }
      return TvCheckResult(TvCheckStatus.fail, 'HTTP $code');
    } on TimeoutException {
      return const TvCheckResult(TvCheckStatus.timeout, 'pas de réponse en 8 s');
    } catch (e) {
      return TvCheckResult(TvCheckStatus.fail, _err(e));
    }
  }

  // ------------------------------------------------------------------
  // 4. Source poussée : GET /api/device-source/<MAC>. Lecture seule. On
  //    montre le code + si une source est assignée à cette box.
  // ------------------------------------------------------------------
  Future<TvCheckResult> checkPushedSource() async {
    String mac;
    try {
      mac = await DeviceIdentity.instance.mac;
    } catch (_) {
      mac = DeviceIdentity.instance.macSync;
    }
    if (!mac.startsWith('MK:')) {
      return TvCheckResult(TvCheckStatus.unknown, 'MAC INCONNUE ($mac)');
    }
    try {
      final http.Response r = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/device-source/$mac'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(kCheckTimeout);
      if (r.statusCode != 200) {
        return TvCheckResult(TvCheckStatus.fail, 'HTTP ${r.statusCode}');
      }
      // On ne fait que CONSTATER la présence d'une source (pas de parsing
      // métier ni de chargement : c'est un diagnostic, lecture seule).
      final String b = r.body;
      final bool hasSource =
          (b.contains('"source"') && !b.contains('"source":null')) ||
              (b.contains('"sources"') && b.contains('{'));
      return TvCheckResult(
          hasSource ? TvCheckStatus.ok : TvCheckStatus.fail,
          hasSource
              ? 'HTTP 200 — source assignée'
              : 'HTTP 200 — aucune source assignée');
    } on TimeoutException {
      return const TvCheckResult(TvCheckStatus.timeout, 'pas de réponse en 8 s');
    } catch (e) {
      return TvCheckResult(TvCheckStatus.fail, _err(e));
    }
  }

  // ------------------------------------------------------------------
  // 5. Signatures de lecteur (multi-User-Agent) : beaucoup de fournisseurs
  //    whitelistent UNE signature (VLC, IBO, Smarters…). Même sonde que le
  //    lecteur (_declareChannelBlocked) — ici en LECTURE seule : on ne
  //    change PAS la signature persistée, on CONSTATE.
  // ------------------------------------------------------------------
  Future<TvCheckResult> checkUserAgentSignatures(String? streamUrl) async {
    if (streamUrl == null || streamUrl.isEmpty) {
      return const TvCheckResult(
          TvCheckStatus.unknown, 'aucune chaîne chargée → URL INCONNUE');
    }
    try {
      // CRÉNEAU (audit 19/08) : ces sondes sont de vraies connexions au
      // flux — on démonte (et on ATTEND) les consommateurs en cours
      // (aperçu, téléchargements) au lieu de sonder par-dessus eux : sur
      // une ligne 1-connexion, l'outil concluait « le fournisseur refuse »
      // alors qu'il se battait contre l'app elle-même.
      await StreamSlot.instance.claim(_slotToken);
      final String current = PlayerSettings.instance.userAgent;
      // Ligne 1-connexion : une seule signature (chaque sonde de plus est
      // une connexion de plus sur le créneau unique) — même règle que le
      // diagnostic du lecteur (stream_blocked_fallback).
      final UserAgentProbeResult probe =
          await StreamProbe.instance.probeUserAgents(
        streamUrl,
        candidates: StreamDiagnostics.instance.singleConnectionLine
            ? <String>[current]
            : <String>[
                current,
                ...PlayerSettings.userAgentPresets.values,
              ],
      );
      final String? working = probe.workingUserAgent;
      if (working != null) {
        final bool isCurrent = working == current;
        return TvCheckResult(
          TvCheckStatus.ok,
          isCurrent
              ? 'la signature actuelle est acceptée par le serveur'
              : 'une AUTRE signature passe (« ${_shorten(working)} ») — le '
                  'lecteur l\'adoptera tout seul à la prochaine lecture',
        );
      }
      if (probe.isLikelyNetworkBlocked) {
        return TvCheckResult(
          TvCheckStatus.fail,
          '${probe.attempts.length} signatures testées, toutes bloquées au '
              'niveau RÉSEAU (DNS/timeout) — un VPN peut aider',
        );
      }
      return TvCheckResult(
        TvCheckStatus.fail,
        '${probe.attempts.length} signatures testées, aucune acceptée — le '
            'fournisseur refuse ce flux',
      );
    } catch (e) {
      return TvCheckResult(TvCheckStatus.fail, _err(e));
    }
  }

  // ------------------------------------------------------------------
  // 6. Sonde lecteur : mini NativeVideoView (Media3/ExoPlayer, même moteur
  //    que la prod) sur l'URL, 1re image (OK) ou erreur (FAIL).
  //    [onProbeController] : l'écran appelant doit MONTER la vue native
  //    (setState) quand on lui passe un contrôleur, et la démonter quand on
  //    lui repasse null — sans vue attachée, le lecteur natif ne démarre pas.
  // ------------------------------------------------------------------
  Future<TvCheckResult> probePlayer(
    String? streamUrl, {
    required void Function(NativeVideoController? controller) onProbeController,
  }) async {
    if (streamUrl == null || streamUrl.isEmpty) {
      return const TvCheckResult(
          TvCheckStatus.unknown, 'aucune chaîne chargée → URL INCONNUE');
    }
    // CRÉNEAU (audit 19/08) : la sonde lecteur est une vraie connexion au
    // flux — on démonte et on attend les consommateurs en cours d'abord.
    await StreamSlot.instance.claim(_slotToken);
    final Completer<TvCheckStatus> c = Completer<TvCheckStatus>();
    final NativeVideoController ctrl =
        NativeVideoController(initialUrl: streamUrl);
    void listener() {
      if (c.isCompleted) return;
      if (ctrl.firstFrame) {
        c.complete(TvCheckStatus.ok);
      } else if (ctrl.hasError) {
        c.complete(TvCheckStatus.fail);
      }
    }

    ctrl.addListener(listener);
    onProbeController(ctrl); // monte la vue → attach → play
    try {
      final TvCheckStatus s = await c.future.timeout(kCheckTimeout);
      return TvCheckResult(
          s,
          s == TvCheckStatus.ok
              ? '1re image décodée et affichée'
              : 'ExoPlayer a renvoyé une erreur');
    } on TimeoutException {
      return const TvCheckResult(TvCheckStatus.timeout, 'aucune image en 8 s');
    } catch (e) {
      return TvCheckResult(TvCheckStatus.fail, _err(e));
    } finally {
      ctrl.removeListener(listener);
      ctrl.dispose();
      onProbeController(null);
    }
  }

  /// Erreur tronquée à ~80 caractères (même règle que l'écran historique :
  /// une ligne lisible à 3 m, pas une stacktrace).
  static String _err(Object e) {
    final String s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  static String _shorten(String s) =>
      s.length > 40 ? '${s.substring(0, 40)}…' : s;
}
