// =========================================================
//  stream_blocked_fallback.dart — Chaîne « échec → sonde → cascade »
// =========================================================
//  3e itération du bug terrain « la cascade ne s'exécute jamais »
//  (journaux des 2026-07-08 06:18, 11:37, 14:13) : la logique vivait
//  dans le widget VideoPlayerScreen (2 700 lignes), intestable de bout
//  en bout (libmpv indisponible sous test), avec DES SORTIES
//  SILENCIEUSES — les gardes `alreadyTried`/`inFlight` et les retours
//  « l'utilisateur a zappé » quittaient sans UNE ligne de journal :
//  sur le terrain, impossible de savoir où la chaîne se perdait.
//
//  Ce contrôleur possède désormais TOUTE la chaîne :
//
//    relais `definitiveFailures` → garde d'URL → diagnostic
//      → sonde multi-signatures de l'URL d'origine
//      → re-validation du format mémorisé
//      → CASCADE de variantes (XtreamCascadeProber)
//      → adoption (UA + format mémorisé) → réouverture
//
//  RÈGLES ABSOLUES (mission du 2026-07-08) :
//    1. CHAQUE sortie de la chaîne écrit POURQUOI dans StreamDiagnostics
//       — plus aucun `return` muet.
//    2. AUCUNE exception avalée : tout le diagnostic est sous un
//       catch-all qui journalise l'exception (stack comprise) puis
//       affiche l'erreur à l'utilisateur.
//    3. Le widget ne garde qu'une délégation d'une ligne : ce fichier
//       est testable avec le VRAI relais et la VRAIE sonde réseau
//       (cf. cascade_real_path_test.dart).
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../cast/data/stream_probe.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/source_link_utils.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/data/xtream_url_format_store.dart';
// Préfixé par cohérence avec le widget (media_kit y exporte aussi un
// type `Playlist`).
import '../../playlists/domain/playlist.dart' as pl;
import 'hls_preflight.dart';
import 'local_stream_relay.dart';
import 'player_settings.dart';
import 'stream_diagnostics.dart';
import 'xtream_cascade_prober.dart';
import 'xtream_url_variants.dart';

/// Message utilisateur quand une chaîne est vide/bloquée. Le rappel du
/// nombre de connexions est une SUGGESTION (cause fréquente), pas un
/// diagnostic.
const String kChannelBlockedMessage =
    'Chaîne indisponible : aucune vidéo reçue. Elle est vide ou bloquée '
    'par ta source — vérifie qu\'elle n\'est pas déjà ouverte sur un '
    'autre appareil, sinon essaie une autre chaîne.';

/// Message CLAIR quand le serveur renvoie HTTP 458 = LIMITE DE CONNEXIONS.
/// Ce n'est PAS un problème de format/signature : l'abonnement n'autorise
/// qu'un nombre limité de lectures simultanées et le(s) slot(s) sont pris.
const String kMaxConnectionsMessage =
    'Limite de connexions atteinte : ton abonnement n\'autorise qu\'un nombre '
    'limité de lectures en même temps, et un autre écran (ou la chaîne '
    'précédente) occupe encore le créneau. Ferme l\'autre lecture, patiente '
    'quelques secondes, puis réessaie.';

/// Message CLAIR quand le serveur du fournisseur renvoie une erreur 5xx
/// (500-599). Le 520-524 est typiquement un « origine derrière Cloudflare en
/// panne ». Ce n'est ni l'app ni la box du client.
String kServerErrorMessage(int code) =>
    'Le serveur de ton fournisseur est en panne (erreur $code). Ce n\'est pas '
    'l\'application ni ta box — réessaie dans un moment, ou contacte ton '
    'fournisseur si ça dure.';

/// Contrôleur du diagnostic « contenu bloqué » d'UN écran de lecture.
/// Toutes les liaisons vers le widget sont des callbacks : le
/// contrôleur ne connaît pas Flutter et se teste avec le vrai réseau.
class StreamBlockedFallback {
  StreamBlockedFallback({
    required this.getChannel,
    required this.getOverrideUrl,
    required this.getEffectiveUrl,
    required this.isAlive,
    required this.hasDecodedFrames,
    required this.getAdoptedAltUrl,
    required this.setAdoptedAltUrl,
    required this.resetWatchdogBudget,
    required this.reopen,
    required this.showBlocked,
    this.uaProbeTimeout = const Duration(milliseconds: 2500),
    this.retryBackoff = const Duration(seconds: 3),
    this.conn458Backoff = const Duration(milliseconds: 1100),
  });

  /// Chaîne affichée à l'écran (change au zap).
  final Channel Function() getChannel;

  /// URL catch-up/replay (`widget.overrideUrl`) — jamais réécrite.
  final String? Function() getOverrideUrl;

  /// URL effectivement ouverte (variante adoptée > URL de la chaîne).
  final String Function() getEffectiveUrl;

  /// `mounted` du widget.
  final bool Function() isAlive;

  /// `true` UNIQUEMENT si au moins une frame a été DÉCODÉE pour la
  /// chaîne courante dans CETTE session de lecture (1re frame vidéo, ou
  /// position qui avance pour l'audio-only) — PAS « ouverture tentée »,
  /// PAS l'état `playing` de mpv (vrai dès l'ouverture, même sur un
  /// 404), PAS persisté entre chaînes ni entre lancements. Une coupure
  /// sur une chaîne qui décodait = problème réseau ; sinon = format /
  /// signature à diagnostiquer (cascade TOUJOURS).
  final bool Function() hasDecodedFrames;

  final String? Function() getAdoptedAltUrl;
  final void Function(String? url) setAdoptedAltUrl;

  /// Remet le budget de reconnexions du watchdog à zéro (nouvelle piste).
  final void Function() resetWatchdogBudget;

  /// Rouvre le lecteur sur cette URL (`_openMedia`).
  final void Function(String url) reopen;

  /// Affiche l'erreur bloquante à l'utilisateur.
  final void Function(String message) showBlocked;

  /// Timeout PAR signature de la sonde (court : 9 signatures ne doivent
  /// pas laisser l'écran muet une minute).
  final Duration uaProbeTimeout;

  /// BACKOFF 1-CONNEXION : attente avant le retry silencieux unique
  /// quand le premier refus ressemble à « le panel n'a pas encore
  /// libéré l'ancienne session » (403, ou EOF immédiat sans frame).
  /// 3 s sur le terrain ; injectable court dans les tests.
  final Duration retryBackoff;

  /// Premier délai d'attente sur un 458 — conservé pour compatibilité des
  /// appelants/tests ; le calendrier complet vit dans [_k458Schedule].
  final Duration conn458Backoff;

  /// CALENDRIER DE RECONNEXION SUR 458 (photo client du 19/08 : « limite de
  /// connexions atteinte » sur TF1, juste après avoir quitté une autre
  /// lecture). Trois essais à 1,1 s couvraient à peine 3 secondes — or un
  /// panel Xtream ne libère PAS le créneau à la milliseconde où la socket se
  /// ferme : il attend l'expiration de SA propre session, souvent 15 à 60 s.
  /// L'app abandonnait donc juste avant que le slot ne se libère.
  ///
  /// On étale maintenant les essais sur ~45 s, en espaçant progressivement
  /// (on ne martèle pas le fournisseur). Pendant tout ce temps l'écran reste
  /// en « reconnexion » : pour le client, la chaîne finit par s'ouvrir toute
  /// seule au lieu de lui jeter une erreur à la figure.
  static const List<Duration> _k458Schedule = <Duration>[
    Duration(milliseconds: 1100),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 12),
    Duration(seconds: 14),
  ];

  /// Idem pour un 5xx (serveur fournisseur en panne) : on retente un peu (le
  /// serveur peut revenir), plus espacé que le 458, puis message clair.
  static const int _kMax5xxRetries = 2;
  static const Duration _k5xxBackoff = Duration(milliseconds: 2000);

  String? _attemptedForChannelId;
  String? _backoffConsumedForChannelId;
  // Compteur de retries 458 pour la CHAÎNE COURANTE (réinitialisé au zap).
  String? _conn458ChannelId;
  int _conn458Count = 0;
  // Compteur de retries 5xx pour la CHAÎNE COURANTE (réinitialisé au zap).
  String? _conn5xxChannelId;
  int _conn5xxCount = 0;
  bool _inFlight = false;
  StreamSubscription<RelayFailure>? _relaySub;

  static void _log(String message, {String level = 'info'}) =>
      StreamDiagnostics.instance
          .recordEvent('fallback', message, level: level);

  // ---------------------------------------------------------------
  //  Abonnement au relais
  // ---------------------------------------------------------------

  /// Branche le déclencheur FIABLE : l'événement « échec définitif »
  /// du relais (4xx dès la 1re réponse / serveur muet jamais diffusé).
  void attach() {
    _relaySub =
        LocalStreamRelay.instance.definitiveFailures.listen(_onRelayFailure);
    _log('Abonné aux échecs définitifs du relais');
  }

  void detach() {
    _relaySub?.cancel();
    _relaySub = null;
  }

  /// À appeler quand une IMAGE RÉELLE vient d'être décodée (lecture saine).
  /// RÉARME les gardes anti-boucle (correctif d'audit) : sans ça, un
  /// aller-retour de zap vers une chaîne déjà diagnostiquée dans la même
  /// session d'écran partait DIRECTEMENT en « bloquée » sans re-sonder, et le
  /// backoff 1-connexion ne se rejouait jamais — alors que le créneau peut
  /// désormais être libre. Une lecture réussie prouve que l'incident précédent
  /// est résolu : le prochain échec mérite un diagnostic neuf.
  void noteFramesDecoded() {
    _attemptedForChannelId = null;
    _backoffConsumedForChannelId = null;
  }

  void _onRelayFailure(RelayFailure failure) {
    if (!isAlive()) return; // écran fermé : rien à faire ni à journaliser
    final String failedUrl = failure.url;
    final String current = getEffectiveUrl();
    if (failedUrl != current) {
      _log(
        'Événement relais ignoré : URL ≠ lecture en cours '
            '(${StreamDiagnostics.maskCredentials(failedUrl)} vs '
            '${StreamDiagnostics.maskCredentials(current)})',
        level: 'warn',
      );
      return;
    }
    _log('Relais : échec définitif signalé '
        '(HTTP ${failure.status ?? '— (réseau)'}) → décision immédiate');
    // HTTP 458 = LIMITE DE CONNEXIONS (mission terrain 2026-07-19). Ce n'est
    // JAMAIS un problème de format/signature : sonder 8 UA + cascader 4
    // variantes ne fait qu'ouvrir autant de connexions REFUSÉES pareil, ça
    // martèle le fournisseur et ça n'aide jamais. Le bon geste : quelques
    // RETRIES RAPIDES (le slot se libère quand la lecture précédente ferme sa
    // socket), puis un message CLAIR. On zappe vite → on repart vite.
    if (failure.status == 458) {
      if (_try458Retry()) return;
      _log('[458] limite de connexions confirmée après '
          '${_k458Schedule.length} essais étalés sur ~45 s '
          '→ message clair (pas de sonde/cascade)');
      showBlocked(kMaxConnectionsMessage);
      return;
    }
    // HTTP 5xx = ERREUR SERVEUR du fournisseur (500-599 ; 520-524 = le serveur
    // d'origine derrière Cloudflare est en panne). Sonder/cascader n'aide pas
    // (toutes les variantes tapent le MÊME serveur en panne). Quelques retries
    // (ça peut revenir), puis un message CLAIR — ce n'est ni l'app ni la box.
    final int? st0 = failure.status;
    if (st0 != null && st0 >= 500 && st0 <= 599) {
      if (_try5xxRetry()) return;
      _log('[5xx] serveur fournisseur en panne (HTTP $st0) après '
          '$_kMax5xxRetries retries → message clair (pas de sonde/cascade)');
      showBlocked(kServerErrorMessage(st0));
      return;
    }
    // RÈGLE DE DÉCISION (mission 2026-07-08 14:43) : la branche
    // « coupure réseau » ne s'applique QUE si la lecture avait
    // réellement démarré (≥ 1 frame décodée). Sinon — et notamment sur
    // un HTTP définitif 404/403 — le diagnostic tourne TOUJOURS. La
    // valeur du drapeau est journalisée AU MOMENT de la décision.
    final bool frames = hasDecodedFrames();
    _log('frames décodées: ${frames ? '≥1' : '0'} → décision: '
        '${frames ? 'erreur directe (coupure réseau)' : 'diagnostic'}');
    if (frames) {
      showBlocked('Flux interrompu. Vérifie ta connexion puis réessaie.');
      return;
    }
    // BACKOFF 1-CONNEXION (mission 2026-07-08 17:07) : un 403 dès la
    // 1re réponse sur une chaîne jamais décodée = très probablement le
    // slot de connexion encore occupé par la lecture qu'on vient de
    // quitter (le panel le libère en ~1 s). Sonder/cascader tout de
    // suite AGGRAVERAIT le problème (chaque sonde = une connexion de
    // plus). On attend, on retente UNE fois en silence — le diagnostic
    // complet ne part que si le retry échoue aussi. Un 404, lui, est
    // déterministe (mauvais format d'URL) → cascade directe.
    if ((failure.status == 403 || failure.status == 429) &&
        _tryScheduleBackoffRetry(
            'HTTP ${failure.status} dès la 1re réponse (slot 1-connexion '
            'probablement encore occupé)')) {
      return;
    }
    // ÉLARGISSEMENT (terrain 2026-07-16, enchaînement d'épisodes) :
    // beaucoup de panels ne renvoient PAS un 403 propre quand le slot
    // est occupé — ils servent un 200 VIDE ou coupent la socket (EOF
    // immédiat, status null). Ce cas partait directement en cascade de
    // sondes (chaque sonde = une connexion de plus pendant que le slot
    // est encore pris) → échec garanti → « Chaîne vide ou bloquée ».
    // Même parade que le 403 : UN retry silencieux après backoff. Seuls
    // les échecs DÉTERMINISTES (404/410/401 : mauvaise URL ou compte
    // refusé — réessayer ne changera rien) partent en cascade directe.
    final int? st = failure.status;
    final bool deterministic = st == 404 || st == 410 || st == 401;
    if (!deterministic &&
        _tryScheduleBackoffRetry(
            'échec sans frame (HTTP ${st ?? '— (réseau/EOF)'}) — slot '
            '1-connexion probablement encore occupé')) {
      return;
    }
    // Fire-and-forget VOLONTAIRE : run() a son propre catch-all — aucune
    // exception ne peut se perdre dans la zone async du listener.
    run();
  }

  /// Déclenché par le lecteur quand mpv refuse le flux AVANT toute frame
  /// (« Error when loading first segment », EOF immédiat…). Même parade
  /// 1-connexion que pour le 403 du relais : UN retry silencieux après
  /// [retryBackoff], puis le diagnostic complet si ça échoue encore.
  void onPlaybackRefused(String reason) {
    if (!hasDecodedFrames() && _tryScheduleBackoffRetry(reason)) return;
    // Fire-and-forget : run() a son propre catch-all.
    run();
  }

  /// Nouvel essai sur un 458 (limite de connexions). Renvoie `false` quand le
  /// calendrier [_k458Schedule] est épuisé (→ message clair). Le compteur se
  /// réinitialise dès qu'on change de chaîne (zap).
  /// « CONTENEUR NON RECONNU » (ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
  /// code 3003) sur une chaîne qui n'a JAMAIS affiché d'image.
  ///
  /// Journal de vol du client, 19/08 : « None of the available extractors
  /// (TsExtractor, FlvExtractor…) » sur TF1, 44 chaînes en échec en 24 h,
  /// ligne à UNE connexion. Aucun extracteur ne reconnaît ces octets — donc
  /// ce ne sont PAS des octets vidéo. Un panel Xtream dont le créneau est
  /// déjà pris ne renvoie pas toujours un 458 propre : beaucoup servent une
  /// page HTML d'erreur, ou un corps vide, avec un HTTP 200. ExoPlayer reçoit
  /// du texte, cherche un conteneur, n'en trouve pas, et l'app concluait
  /// « format non géré » — puis lançait la CASCADE de sondes multi-signatures.
  /// Sur une ligne 1-connexion, ces sondes consomment le créneau qu'on
  /// attend : le diagnostic empirait la panne qu'il devait expliquer.
  ///
  /// On traite donc ce cas comme un créneau occupé : mêmes essais espacés que
  /// le 458, aucune sonde. Renvoie `true` si un essai est programmé (l'écran
  /// reste en reconnexion), `false` s'il faut passer au diagnostic normal —
  /// une image DÉJÀ affichée, elle, signe un vrai souci de format.
  bool onContainerUnsupported() {
    if (hasDecodedFrames()) return false;
    if (_try458Retry()) return true;
    _log('[conteneur] toujours rien de lisible après '
        '${_k458Schedule.length} essais → message clair (pas de sonde)');
    showBlocked(kMaxConnectionsMessage);
    return true;
  }

  bool _try458Retry() {
    final Channel channel = getChannel();
    if (_conn458ChannelId != channel.id) {
      _conn458ChannelId = channel.id;
      _conn458Count = 0;
    }
    if (_conn458Count >= _k458Schedule.length) return false;
    // Premier 458 de cette chaîne : on va lire les compteurs RÉELS du compte
    // (max_connections / active_cons) pour que le message final dise la
    // vérité au lieu de « (?/?) » — photo client du 19/08.
    if (_conn458Count == 0) unawaited(_probeAccountLimits());
    final Duration wait = _k458Schedule[_conn458Count];
    _conn458Count++;
    _log('[458] limite de connexions — nouvel essai '
        '$_conn458Count/${_k458Schedule.length} dans ${wait.inMilliseconds} ms '
        '(le panel libère le créneau à l\'expiration de SA session, '
        'pas à la fermeture de la socket)');
    Future<void>.delayed(wait).then((_) {
      if (!isAlive() || channel.id != getChannel().id) {
        _log('[458] retry abandonné (zap ou écran fermé pendant l\'attente)');
        return;
      }
      resetWatchdogBudget();
      _log('[458] retry silencieux → réouverture de '
          '${StreamDiagnostics.maskCredentials(getEffectiveUrl())}');
      reopen(getEffectiveUrl());
    });
    return true;
  }

  /// Lit les compteurs RÉELS du compte Xtream (max_connections /
  /// active_cons) pour que le message de limite dise « 1/1 » au lieu de
  /// « (?/?) » — photo client du 19/08, où le message n'apprenait rien.
  ///
  /// Best-effort ABSOLU : c'est du confort de diagnostic. Un échec (pas une
  /// source Xtream, réseau coupé, panel qui ne renvoie pas ces champs) ne
  /// doit rien changer au déroulement des essais.
  ///
  /// `player_api.php` est une requête d'API, pas un flux : elle ne consomme
  /// pas le créneau de lecture qu'on est justement en train d'attendre.
  Future<void> _probeAccountLimits() async {
    try {
      final pl.Playlist? src = xtreamPlaylistFor(getChannel());
      if (src == null ||
          src.xtreamServer == null ||
          src.xtreamUsername == null ||
          src.xtreamPassword == null) {
        return;
      }
      final XtreamClient client = XtreamClient(
        serverUrl: src.xtreamServer!,
        username: src.xtreamUsername!,
        password: src.xtreamPassword!,
        timeout: const Duration(seconds: 8),
      );
      // `fetchAccountInfo` alimente lui-même StreamDiagnostics : le message
      // affiché à la fin des essais reprendra ces chiffres.
      await client.fetchAccountInfo();
    } catch (e) {
      _log('[458] compteurs du compte illisibles ($e) — sans conséquence');
    }
  }

  /// Retry sur un 5xx (serveur fournisseur en panne). Renvoie `false` quand les
  /// [_kMax5xxRetries] retries de la chaîne sont épuisés (→ message clair). Le
  /// compteur se réinitialise dès qu'on change de chaîne (zap).
  bool _try5xxRetry() {
    final Channel channel = getChannel();
    if (_conn5xxChannelId != channel.id) {
      _conn5xxChannelId = channel.id;
      _conn5xxCount = 0;
    }
    if (_conn5xxCount >= _kMax5xxRetries) return false;
    _conn5xxCount++;
    _log('[5xx] serveur fournisseur en panne — retry '
        '$_conn5xxCount/$_kMax5xxRetries dans ${_k5xxBackoff.inMilliseconds} '
        'ms (le serveur peut revenir)');
    Future<void>.delayed(_k5xxBackoff).then((_) {
      if (!isAlive() || channel.id != getChannel().id) {
        _log('[5xx] retry abandonné (zap ou écran fermé pendant l\'attente)');
        return;
      }
      resetWatchdogBudget();
      _log('[5xx] retry silencieux → réouverture de '
          '${StreamDiagnostics.maskCredentials(getEffectiveUrl())}');
      reopen(getEffectiveUrl());
    });
    return true;
  }

  /// Programme le retry silencieux unique du backoff 1-connexion.
  /// Renvoie `false` si le backoff a DÉJÀ été consommé pour cette chaîne
  /// (le prochain échec doit partir en diagnostic complet).
  bool _tryScheduleBackoffRetry(String reason) {
    final Channel channel = getChannel();
    if (_backoffConsumedForChannelId == channel.id) {
      _log('[backoff] déjà consommé pour « ${channel.cleanName} » → '
          'place au diagnostic complet');
      return false;
    }
    _backoffConsumedForChannelId = channel.id;
    _log('[backoff] $reason → attente de '
        '${retryBackoff.inMilliseconds} ms (le panel libère l\'ancienne '
        'session) puis UN retry automatique et silencieux');
    Future<void>.delayed(retryBackoff).then((_) {
      if (!isAlive() || channel.id != getChannel().id) {
        _log('[backoff] retry abandonné (zap ou écran fermé pendant '
            'l\'attente)');
        return;
      }
      resetWatchdogBudget();
      _log('[backoff] retry silencieux → réouverture de '
          '${StreamDiagnostics.maskCredentials(getEffectiveUrl())}');
      reopen(getEffectiveUrl());
    });
    return true;
  }

  // ---------------------------------------------------------------
  //  Diagnostic complet
  // ---------------------------------------------------------------

  /// Diagnostic « contenu jamais lu » : sonde l'URL d'origine avec
  /// toutes les signatures, re-valide le format mémorisé, puis déroule
  /// la CASCADE de variantes. Appelé par l'événement relais, l'erreur
  /// mpv, le timeout de démarrage et le watchdog.
  Future<void> run() async {
    final Channel channel = getChannel();
    // ----- Gardes (JOURNALISÉES — c'étaient les sorties muettes) -----
    if (_inFlight) {
      _log('Diagnostic déjà EN COURS pour cette chaîne — appel ignoré '
          '(l\'issue arrivera au journal)');
      return;
    }
    if (_attemptedForChannelId == channel.id) {
      _log(
        'Diagnostic déjà TENTÉ pour « ${channel.cleanName} » — pas de '
            'nouvelle sonde (anti-boucle), erreur affichée',
        level: 'warn',
      );
      showBlocked(kChannelBlockedMessage);
      return;
    }
    _attemptedForChannelId = channel.id;
    _inFlight = true;
    try {
      await _runInner(channel);
    } catch (e, st) {
      // RÈGLE 2 : aucune exception avalée sans trace. C'est le genre de
      // trou noir qui a rendu ce bug indiagnosticable pendant 3 journaux.
      _log('EXCEPTION pendant le diagnostic : $e', level: 'error');
      if (kDebugMode) debugPrint('[Fallback] $e\n$st');
      if (isAlive() && channel.id == getChannel().id) {
        showBlocked(kChannelBlockedMessage);
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _runInner(Channel channel) async {
    bool stillCurrent() => isAlive() && channel.id == getChannel().id;

    // Diagnostic HLS SUR ÉCHEC uniquement (séquentiel — la sonde ne
    // tourne plus EN MÊME TEMPS que la lecture : sur un abonnement
    // 1-connexion elle comptait comme une connexion de plus, journal
    // terrain « 4/1 »). La lecture est déjà morte ici : on peut sonder.
    final String effective = getEffectiveUrl();
    if (HlsPreflight.isHlsUrl(effective)) {
      await HlsPreflight.run(effective);
      if (!stillCurrent()) {
        _log('Diagnostic abandonné pendant la sonde HLS (zap)');
        return;
      }
    }

    final String currentUa = PlayerSettings.instance.userAgent;
    final pl.Playlist? src = xtreamPlaylistFor(channel);
    final XtreamContentType contentType = contentTypeOf(channel);

    // LIGNE À 1 CONNEXION (journal terrain du 19/08 23:38 : la salve
    // multi-signatures s'est déclenchée sur une ligne 1-connexion — seule
    // une panne DNS l'a empêchée d'ouvrir ses connexions) : chaque sonde
    // est une connexion ouverte/fermée sur LE créneau unique, pile pendant
    // qu'on attend qu'il se libère. On réduit donc la salve à la SEULE
    // signature courante (1 connexion), et la cascade de formats — qui
    // reste indispensable pour trouver le bon conteneur — n'essaie elle
    // aussi qu'avec cette signature (≤ 4 connexions séquentielles au lieu
    // de variantes × 9 signatures). Comptes multi-connexions : inchangé.
    final bool singleConn = StreamDiagnostics.instance.singleConnectionLine;
    final List<String> uaCandidates = singleConn
        ? <String>[currentUa]
        : <String>[currentUa, ...PlayerSettings.userAgentPresets.values];
    if (singleConn) {
      _log('[1-connexion] compte à connexion unique → sonde limitée à la '
          'signature courante et cascade mono-signature (pas de salve '
          'multi-signatures sur le créneau qu\'on attend)');
    }

    // ----- 1. Sonde de l'URL D'ORIGINE (multi-signatures si le compte
    // l'autorise, signature courante seule sur une ligne 1-connexion) -----
    _log('Contenu jamais lu → sonde de l\'URL d\'origine '
        '(${StreamDiagnostics.maskCredentials(channel.streamUrl)})…');
    final UserAgentProbeResult probe = await StreamProbe.instance
        .probeUserAgents(
      channel.streamUrl,
      candidates: uaCandidates,
      timeout: uaProbeTimeout,
    );
    _recordProbeAttempts(probe);
    if (!stillCurrent()) {
      _log('Diagnostic abandonné : zap ou écran fermé pendant la sonde');
      return;
    }

    // ----- 2. L'origine répond → bascule UA et/ou retour à l'origine --
    final bool altWasApplied = getAdoptedAltUrl() != null;
    if (probe.workingUserAgent != null &&
        (probe.workingUserAgent != currentUa || altWasApplied)) {
      if (probe.workingUserAgent != currentUa) {
        _log('Signature "$currentUa" refusée mais '
            '"${probe.workingUserAgent}" acceptée → bascule + relance');
        await PlayerSettings.instance.setUserAgent(probe.workingUserAgent!);
        if (!stillCurrent()) {
          _log('Diagnostic abandonné après bascule de signature (zap)');
          return;
        }
      }
      if (altWasApplied) {
        setAdoptedAltUrl(null);
        if (src?.id != null) {
          final bool forgot = await XtreamUrlFormatStore.instance
              .clearWinningFormat(src!.id!, contentType);
          if (forgot) {
            _log(
              'Le format mémorisé ne répond plus mais l\'URL d\'origine '
                  'oui → format oublié, retour à l\'origine',
              level: 'warn',
            );
          }
          if (!stillCurrent()) {
            _log('Diagnostic abandonné après l\'oubli du format (zap)');
            return;
          }
        }
      }
      resetWatchdogBudget();
      reopen(getOverrideUrl() ?? channel.streamUrl);
      return; // pas d'erreur affichée : on retente silencieusement
    }

    // ----- 3. CASCADE de variantes (gate journalisé) -----
    if (getOverrideUrl() != null) {
      _log(
        '[cascade] catch-up/replay (overrideUrl) → URL laissée intacte, '
            'pas de variantes',
        level: 'warn',
      );
    } else if (src == null) {
      _log(
        '[cascade] source non-Xtream ou introuvable '
            '(playlistId=${channel.playlistId ?? '—'}, '
            'host=${Uri.tryParse(channel.streamUrl)?.host ?? '?'}) '
            '→ URL laissée intacte, pas de variantes',
        level: 'error',
      );
    } else {
      final CascadeWin? win = await XtreamCascadeProber.findWorkingVariant(
        channel.streamUrl, // URL BRUTE (identifiants réels)
        contentType,
        // Même liste que la sonde : réduite à la signature courante sur une
        // ligne 1-connexion (cf. garde [1-connexion] ci-dessus).
        uaCandidates: uaCandidates,
        isCancelled: () => !stillCurrent(),
      );
      if (!stillCurrent()) {
        _log('Diagnostic abandonné pendant la cascade (zap)');
        return;
      }
      if (win != null) {
        if (win.userAgent != currentUa) {
          _log('[cascade] la variante gagnante exige la signature '
              '"${win.userAgent}" → adoptée');
          await PlayerSettings.instance.setUserAgent(win.userAgent);
          if (!stillCurrent()) {
            _log('Diagnostic abandonné après adoption de la signature (zap)');
            return;
          }
        }
        setAdoptedAltUrl(win.url);
        if (src.id != null) {
          await XtreamUrlFormatStore.instance
              .saveWinningFormat(src.id!, contentType, win.formatCode);
          _log('[cascade] format « ${win.formatCode} » mémorisé pour la '
              'source « ${src.name} » (${contentType.name}) — les '
              'prochains contenus l\'utiliseront directement');
          if (!stillCurrent()) {
            _log('Diagnostic abandonné après mémorisation (zap)');
            return;
          }
        }
        resetWatchdogBudget();
        _log('[cascade] réouverture du lecteur sur la variante gagnante '
            '${StreamDiagnostics.maskCredentials(win.url)}');
        reopen(win.url);
        return; // pas d'erreur affichée : la variante a de vraies chances
      }
    }

    // ----- 4. Échec total → oubli du format mémorisé + erreur claire --
    if (src?.id != null) {
      final bool forgot = await XtreamUrlFormatStore.instance
          .clearWinningFormat(src!.id!, contentType);
      if (forgot) {
        _log('Format mémorisé oublié (plus aucune variante ne répond)',
            level: 'warn');
      }
      if (!stillCurrent()) {
        _log('Diagnostic abandonné à l\'oubli final du format (zap)');
        return;
      }
    }
    _log(
      probe.isLikelyNetworkBlocked
          ? 'Aucune signature ne passe — échecs de niveau RÉSEAU '
              '(DNS/timeout) : blocage FAI probable'
          : 'Aucune signature ni variante de format ne débloque ce flux',
      level: 'error',
    );
    if (!stillCurrent()) return;
    showBlocked(
      probe.isLikelyNetworkBlocked
          ? '$kChannelBlockedMessage\n\nÇa ressemble à un blocage réseau '
              '(FAI ou DNS) plutôt qu\'à un problème de l\'app — un VPN '
              'peut aider si cette chaîne fonctionne ailleurs.'
          : kChannelBlockedMessage,
    );
  }

  /// Verse le détail d'une sonde multi-signatures dans la boîte noire :
  /// une ligne par User-Agent essayé (statut HTTP ou raison d'échec).
  /// Le statut de la signature ACTIVE alimente aussi l'instantané HTTP
  /// (utile pour la VOD, qui ne passe pas par le relais).
  void _recordProbeAttempts(UserAgentProbeResult probe, {String? label}) {
    final StreamDiagnostics d = StreamDiagnostics.instance;
    final String prefix = label == null ? '' : '[$label] ';
    probe.attempts.forEach((String ua, StreamProbeResult r) {
      final String verdict = r.success
          ? 'OK (HTTP 2xx${r.mime == null ? '' : ' · ${r.mime}'})'
          : (r.errorCode != null
              ? 'HTTP ${r.errorCode} — ${r.errorReason ?? 'refusé'}'
              : (r.errorReason ?? 'échec'));
      d.recordEvent('probe', '${prefix}UA "$ua" → $verdict',
          level: r.success ? 'info' : 'warn');
    });
    final StreamProbeResult? currentAttempt =
        probe.attempts[PlayerSettings.instance.userAgent];
    if (currentAttempt != null && d.httpStatus == null) {
      d.recordHttp(
        status:
            currentAttempt.errorCode ?? (currentAttempt.success ? 200 : null),
        finalUrl: currentAttempt.finalUrl,
        mime: currentAttempt.mime,
        source: 'probe',
      );
    }
  }

  // ---------------------------------------------------------------
  //  Résolution source / type (déplacées depuis le widget)
  // ---------------------------------------------------------------

  /// Playlist XTREAM d'où vient ce contenu, ou `null` (source M3U
  /// générique, fichier local, inconnu). Par `playlistId` quand la
  /// chaîne vient de la base ; par host:port sinon (Channels VOD
  /// ad-hoc sans playlistId).
  static pl.Playlist? xtreamPlaylistFor(Channel channel) {
    final List<pl.Playlist> all = PlaylistRepository.instance.currentPlaylists;
    final int? pid = channel.playlistId;
    if (pid != null) {
      for (final pl.Playlist p in all) {
        if (p.id == pid) {
          return p.type == pl.PlaylistType.xtream ? p : null;
        }
      }
      return null;
    }
    final Uri? u = Uri.tryParse(channel.streamUrl);
    if (u == null || !u.hasAuthority) return null; // fichier local, etc.
    for (final pl.Playlist p in all) {
      if (p.type != pl.PlaylistType.xtream) continue;
      final Uri? server = Uri.tryParse(
          SourceLinkUtils.sanitizeXtreamServer(p.xtreamServer ?? ''));
      if (server != null &&
          server.host.isNotEmpty &&
          server.host == u.host &&
          server.port == u.port) {
        return p;
      }
    }
    return null;
  }

  /// Type de contenu Xtream : le PRÉFIXE de l'URL fait foi, sinon
  /// `isLive` de la chaîne (URL nue non-live = film ; nos épisodes de
  /// séries sont toujours préfixés `/series/` par XtreamClient).
  static XtreamContentType contentTypeOf(Channel channel) {
    final XtreamContentType? fromUrl =
        XtreamUrlVariants.detectType(channel.streamUrl);
    if (fromUrl != null) return fromUrl;
    return channel.isLive ? XtreamContentType.live : XtreamContentType.movie;
  }
}
