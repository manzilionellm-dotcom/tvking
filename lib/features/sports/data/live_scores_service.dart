// =========================================================
//  live_scores_service.dart — Les scores qui bougent tout seuls
// =========================================================
//  POURQUOI CE FICHIER EXISTE (23/08/2026).
//
//  Jusqu'ici le coin Sport affichait des HORAIRES. C'est un programme
//  télé : on le consulte une fois, et on n'y revient pas. Ce qui fait
//  qu'on rouvre une appli de sport dix fois dans une soirée, c'est le
//  score qui change pendant qu'on regarde.
//
//  L'offre gratuite de TheSportsDB ne pouvait PAS le faire, à aucun
//  prix : les scores en direct sont réservés aux comptes payants. La
//  clé achetée le 23/08 débloque une source rafraîchie toutes les
//  2 minutes — c'est la seule vraie nouveauté qu'elle apporte.
//
//  CE QUE CE SERVICE GARANTIT :
//
//   1. IL NE TOURNE QUE QUAND ON LE REGARDE. `start()` à l'ouverture de
//      l'écran, `stop()` à la fermeture. Un minuteur qui survivrait à
//      l'écran viderait la batterie pour des données que personne ne
//      lit — faute classique, et invisible en développement.
//
//   2. IL NE PERD JAMAIS CE QU'IL AVAIT. Une requête ratée (réseau
//      coupé, serveur muet) laisse les derniers scores connus à
//      l'écran. Remplacer « Manchester City 2-1 » par une liste vide
//      parce qu'un paquet s'est perdu serait pire que ne rien faire.
//
//   3. IL DIT QUAND IL NE PEUT PAS. Sans clé côté serveur, la route
//      répond `available:false` — l'écran écrit alors « indisponible »
//      au lieu d'un vide muet. C'est la leçon de la panne du 22/08 :
//      une liste vide et une panne se ressemblaient trop.
//
//   4. UNE SEULE REQUÊTE POUR TOUT LE MONDE. Le serveur garde la
//      réponse 45 s en cache : dix clients qui rafraîchissent en même
//      temps ne font pas dix appels chez le fournisseur.
//
//  LA SENTINELLE (06/09/2026) — demande du propriétaire : « configure
//  les alertes buts pour que je sois prévenu en direct ».
//
//  La garantie n° 1 (« ne tourne que quand on le regarde ») avait un
//  angle mort : un but ne prévient PERSONNE si le client est sur un
//  film. Or c'est précisément là qu'une alerte a de la valeur — sur
//  l'écran Sport, il voit déjà le score.
//
//  La sentinelle est un second minuteur, indépendant de l'écran, qui ne
//  se réveille que lorsqu'un match QUI COMPTE pour ce client (suivi un
//  par un, ou d'une équipe favorite) est en train de se jouer, ou sur le
//  point de commencer. Le reste du temps, elle ne fait AUCUNE requête :
//  elle relit toutes les 5 minutes, en mémoire, la liste des matchs
//  suivis pour savoir si une fenêtre s'ouvre. Un mardi matin sans match
//  suivi coûte donc zéro octet réseau — la garantie n° 1 tient toujours,
//  dans son esprit : on ne réveille le réseau que s'il y a quelque chose
//  à surveiller.
//
//  Ce qu'elle NE peut PAS faire, et il faut le dire honnêtement : un
//  minuteur Dart ne vit que tant que le processus de l'app vit. Sur
//  Android, une app en arrière-plan garde ses minuteurs quelques minutes
//  à quelques dizaines de minutes, puis le système la gèle. Une alerte
//  « app fermée depuis deux heures » demanderait des notifications
//  poussées depuis le serveur — ce n'est pas ce fichier.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/i18n/l10n_now.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/realtime/realtime_sync_service.dart'
    show AdminMessage, RealtimeSyncService;
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../domain/sport_models.dart';
import 'followed_matches_service.dart';
import 'sports_repository.dart';

class LiveScoresService {
  LiveScoresService._();
  static final LiveScoresService instance = LiveScoresService._();

  //  45 s — la source amont bouge toutes les 2 min et le serveur garde
  //  sa réponse 45 s. Descendre plus bas ne montrerait RIEN de plus au
  //  client : on ne ferait que réveiller le téléphone pour rien.
  static const Duration _period = Duration(seconds: 45);

  //  Court exprès. Les scores en direct sont un CONFORT : s'ils tardent,
  //  le reste de l'écran ne doit pas attendre avec eux.
  static const Duration _timeout = Duration(seconds: 7);

  Timer? _timer;
  int _watchers = 0;
  bool _inFlight = false;

  List<SportEvent> _live = const <SportEvent>[];
  bool _available = true;
  DateTime? _updatedAt;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  /// Les matchs en cours, du plus important au moins important (l'ordre
  /// vient du serveur : c'est lui qui décide, l'app ne reclasse pas).
  List<SportEvent> get live => List<SportEvent>.unmodifiable(_live);

  /// `false` quand le serveur n'a pas de clé payante. L'écran doit alors
  /// le DIRE, et surtout ne pas laisser croire qu'aucun match ne se joue.
  bool get available => _available;

  DateTime? get updatedAt => _updatedAt;

  /// Score en direct d'un match précis, s'il est en cours. Sert à faire
  /// vivre une affiche déjà à l'écran sans la reconstruire.
  SportEvent? forId(String id) {
    if (id.isEmpty) return null;
    for (final SportEvent e in _live) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Recopie une affiche en y injectant le score en direct s'il existe.
  /// L'affiche garde son heure, ses écussons et son niveau : on ne
  /// remplace QUE ce qui bouge.
  SportEvent enrich(SportEvent ev) {
    final SportEvent? l = forId(ev.id);
    if (l == null) return ev;
    return ev.copyWith(
      homeScore: l.homeScore,
      awayScore: l.awayScore,
      status: l.status,
      progress: l.progress,
    );
  }

  /// À appeler quand un écran commence à afficher des scores. Compté :
  /// deux écrans ouverts ne créent pas deux minuteurs, et le minuteur ne
  /// s'arrête que lorsque le DERNIER écran se ferme.
  void start() {
    _watchers++;
    if (_timer != null) return;
    unawaited(refresh());
    _timer = Timer.periodic(_period, (_) => unawaited(refresh()));
  }

  /// À appeler dans `dispose()`. Symétrique de [start].
  void stop() {
    if (_watchers > 0) _watchers--;
    if (_watchers == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  // =========================================================
  //  LA SENTINELLE — alertes de but même quand l'écran Sport est fermé
  // =========================================================

  /// Avant le coup d'envoi : on commence à écouter un peu avant, parce
  /// que l'horaire annoncé et le vrai coup d'envoi diffèrent souvent de
  /// quelques minutes.
  static const Duration kWindowBefore = Duration(minutes: 5);

  /// Après le coup d'envoi : un match de football dure ~2 h avec les
  /// arrêts de jeu ; une prolongation et des tirs au but, ~2 h 30. Trois
  /// heures couvrent tout, sans laisser la sentinelle tourner la nuit
  /// sur un match dont la source aurait oublié de dire « terminé ».
  static const Duration kWindowAfter = Duration(hours: 3);

  /// Hors fenêtre, on ne relit que la mémoire (aucune requête) à ce
  /// rythme, pour repérer une fenêtre qui s'ouvre. Cinq minutes : au
  /// pire, on rate les 5 premières minutes d'un match — et les
  /// abonnements aux changements (suivre un match, ajouter une équipe)
  /// réarment immédiatement, sans attendre ce tic.
  static const Duration kIdleRecheck = Duration(minutes: 5);

  Timer? _sentinelTimer;
  bool _sentinelOn = false;
  StreamSubscription<void>? _followSub;
  StreamSubscription<List<SportTeam>>? _favSub;
  StreamSubscription<void>? _favEventsSub;

  /// Branchement remplaçable dans les tests : la sentinelle appelle ceci
  /// au lieu de [refresh] (qui tape le réseau). Nul en production.
  @visibleForTesting
  Future<void> Function()? debugRefreshOverride;

  /// Horloge remplaçable dans les tests (fake_async n'avance PAS
  /// `DateTime.now()`, seulement les minuteurs). Nulle en production.
  @visibleForTesting
  DateTime Function()? debugClock;

  DateTime _now() => (debugClock ?? DateTime.now)();

  /// `true` tant que la sentinelle est armée (utile aux réglages pour
  /// écrire « veille active » plutôt que de laisser deviner).
  bool get sentinelOn => _sentinelOn;

  /// Démarre la veille app-wide. Idempotent. À appeler une fois au boot
  /// (téléphone ET TV) ; ne fait aucune requête tant qu'aucun match qui
  /// compte n'est dans sa fenêtre.
  void startSentinel() {
    if (_sentinelOn) return;
    _sentinelOn = true;
    // Les matchs suivis vivent dans les préférences : on les charge
    // d'abord, sinon la première évaluation croirait la liste vide.
    unawaited(FollowedMatchesService.instance.ensureLoaded().then((_) {
      if (_sentinelOn) _armSentinel();
    }));
    _followSub = FollowedMatchesService.instance.changes.listen((_) {
      if (_sentinelOn) _armSentinel();
    });
    _favSub = SportsRepository.instance.favoritesStream.listen((_) {
      if (_sentinelOn) _armSentinel();
    });
    _favEventsSub = SportsRepository.instance.changesStream.listen((_) {
      if (_sentinelOn) _armSentinel();
    });
  }

  /// Arrête la veille (tests, ou réglage « alertes de but » coupé).
  void stopSentinel() {
    _sentinelOn = false;
    _sentinelTimer?.cancel();
    _sentinelTimer = null;
    _followSub?.cancel();
    _followSub = null;
    _favSub?.cancel();
    _favSub = null;
    _favEventsSub?.cancel();
    _favEventsSub = null;
  }

  /// Programme le PROCHAIN tic. Une seule règle : fenêtre ouverte →
  /// rafraîchir dans [_period] ; fermée → relire la mémoire dans
  /// [kIdleRecheck]. Chaque tic réévalue, donc une fenêtre qui se ferme
  /// arrête d'elle-même les requêtes.
  void _armSentinel() {
    _sentinelTimer?.cancel();
    if (!_sentinelOn) return;
    final bool open = hasAlertWindow(_now());
    _sentinelTimer = Timer(open ? _period : kIdleRecheck, _sentinelTick);
    if (open) unawaited(_sentinelRefresh());
  }

  Future<void> _sentinelRefresh() async {
    // L'écran Sport rafraîchit déjà : inutile de doubler. `_inFlight`
    // protège aussi, mais autant ne pas créer la course du tout.
    if (_timer != null) return;
    final Future<void> Function()? o = debugRefreshOverride;
    await (o != null ? o() : refresh());
  }

  void _sentinelTick() {
    if (!_sentinelOn) return;
    _armSentinel();
  }

  /// Tous les matchs qui COMPTENT pour ce client : suivis un par un, et
  /// ceux des équipes favorites (derniers + prochains, tels que
  /// [SportsRepository] les connaît).
  List<SportEvent> _mattering() {
    final Map<String, SportEvent> byId = <String, SportEvent>{};
    for (final SportEvent e in FollowedMatchesService.instance.all) {
      if (e.id.isNotEmpty) byId[e.id] = e;
    }
    for (final SportTeam t in SportsRepository.instance.favorites) {
      final SportsEvents ev = SportsRepository.instance.eventsFor(t.id);
      for (final SportEvent e in <SportEvent>[...ev.next, ...ev.last]) {
        if (e.id.isNotEmpty) byId.putIfAbsent(e.id, () => e);
      }
    }
    return byId.values.toList(growable: false);
  }

  /// Y a-t-il, à l'instant [now], un match qui compte dans sa fenêtre ?
  /// Un match déjà vu EN DIRECT au dernier tour compte aussi, même si
  /// son horaire annoncé est dépassé : la source sait mieux que l'agenda.
  bool hasAlertWindow(DateTime now) {
    for (final SportEvent e in _mattering()) {
      if (inAlertWindow(e, now)) return true;
      final SportEvent? l = forId(e.id);
      if (l != null && l.isLive) return true;
    }
    return false;
  }

  /// Fonction PURE : ce match est-il dans [−kWindowBefore ; +kWindowAfter]
  /// autour de son coup d'envoi ? Sans horaire connu → non : on ne
  /// réveille pas le réseau pour un match qu'on ne sait pas dater.
  static bool inAlertWindow(SportEvent e, DateTime now) {
    final DateTime? k = e.startsAt;
    if (k == null) return false;
    return !now.isBefore(k.subtract(kWindowBefore)) &&
        !now.isAfter(k.add(kWindowAfter));
  }

  /// Fonction PURE : ce match mérite-t-il une alerte de but ?
  ///   - suivi un par un (choix explicite) ;
  ///   - OU l'un de ses deux camps est une équipe favorite, reconnue par
  ///     l'identifiant du match (si [SportsRepository] le connaît) ou par
  ///     le NOM de l'équipe — TheSportsDB écrit le même nom dans toutes
  ///     ses routes, mais on compare quand même sans la casse.
  static bool alertWorthy(
    SportEvent e, {
    required Set<String> followedIds,
    required Set<String> favoriteEventIds,
    required Set<String> favoriteNames,
  }) {
    if (e.id.isEmpty) return false;
    if (followedIds.contains(e.id)) return true;
    if (favoriteEventIds.contains(e.id)) return true;
    if (favoriteNames.isEmpty) return false;
    final String h = e.home.trim().toLowerCase();
    final String a = e.away.trim().toLowerCase();
    return (h.isNotEmpty && favoriteNames.contains(h)) ||
        (a.isNotEmpty && favoriteNames.contains(a));
  }

  bool _isAlertWorthy(SportEvent e) {
    final Set<String> favIds = <String>{};
    final Set<String> favNames = <String>{};
    for (final SportTeam t in SportsRepository.instance.favorites) {
      final String n = t.name.trim().toLowerCase();
      if (n.isNotEmpty) favNames.add(n);
      final SportsEvents ev = SportsRepository.instance.eventsFor(t.id);
      for (final SportEvent x in <SportEvent>[...ev.next, ...ev.last]) {
        if (x.id.isNotEmpty) favIds.add(x.id);
      }
    }
    return alertWorthy(
      e,
      followedIds: <String>{
        for (final SportEvent f in FollowedMatchesService.instance.all) f.id,
      },
      favoriteEventIds: favIds,
      favoriteNames: favNames,
    );
  }

  Future<void> refresh() async {
    // Deux rafraîchissements ne se chevauchent jamais : sur un réseau
    // lent, le minuteur repasserait avant la fin du précédent et on
    // empilerait les requêtes.
    if (_inFlight) return;
    _inFlight = true;
    try {
      final http.Response r = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/sports/live'),
              headers: const <String, String>{'Accept': 'application/json'})
          .timeout(_timeout);
      if (r.statusCode != 200) return; // on garde ce qu'on avait
      final Object? decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is! Map<String, dynamic>) return;

      final List<SportEvent> parsed = <SportEvent>[];
      final Object? list = decoded['live'];
      if (list is List) {
        for (final Object? raw in list) {
          if (raw is! Map<String, dynamic>) continue;
          final SportEvent ev = SportEvent.fromJson(raw);
          if (ev.id.isNotEmpty) parsed.add(ev);
        }
      }
      _detectGoals(parsed);
      _live = List<SportEvent>.unmodifiable(parsed);
      // `available` n'est PAS déduit de la liste : une liste vide un
      // mardi matin est parfaitement normale. Seul le serveur sait s'il
      // a pu interroger la source.
      _available = decoded['available'] != false;
      _updatedAt = DateTime.now();
      if (!_changes.isClosed) _changes.add(null);
    } catch (e) {
      // Panne réseau : on ne touche à RIEN. Les derniers scores connus
      // restent affichés, ce qui est toujours mieux qu'un écran qui se
      // vide parce qu'un paquet s'est perdu.
      if (kDebugMode) debugPrint('[LiveScores] KO: $e');
    } finally {
      _inFlight = false;
    }
  }

  // =========================================================
  //  LE « WOUAAAH » DE BUT
  // =========================================================
  //  Demande du propriétaire (23/08) : « si le but entre, il faut un
  //  petit son, comme les gens qui disent wouaouh ».
  //
  //  Le principe est simple — le score a augmenté depuis le dernier
  //  tour, donc quelqu'un a marqué. Ce sont les GARDE-FOUS qui font
  //  tout le travail, parce qu'une alerte sonore mal placée est la
  //  raison numéro un d'une désinstallation.
  //
  //   1. UNIQUEMENT LES MATCHS QUI COMPTENT. Il y a jusqu'à 60
  //      rencontres en direct simultanément. Sonner à chaque but de
  //      n'importe lequel, c'est un cri toutes les deux minutes un
  //      samedi après-midi. On ne sonne que pour ce que le client a
  //      choisi : un match suivi un par un, ou un match de l'une de ses
  //      équipes favorites (cf. [alertWorthy] — même définition que les
  //      alertes d'avant-match de MatchAlertsService, pour qu'un client
  //      n'ait pas deux notions de « mon match »).
  //
  //   2. JAMAIS AU PREMIER TOUR. Sans état antérieur, TOUS les matchs
  //      en cours paraissent venir de marquer : on ouvre l'app et on
  //      reçoit vingt cris d'un coup. Le premier passage ne fait
  //      qu'APPRENDRE les scores, en silence.
  //
  //   3. LE SCORE NE PEUT QUE MONTER. Une correction d'arbitrage, un
  //      but refusé après vidéo, ou simplement une donnée amont qui
  //      hoquette peuvent faire BAISSER un score. On mémorise alors la
  //      nouvelle valeur sans rien annoncer.
  //
  //   4. UN CRI À LA FOIS. Deux buts dans la même seconde sur deux
  //      matchs suivis feraient se chevaucher deux sons. On annonce le
  //      premier et on note les autres comme vus.
  final Map<String, int> _lastTotals = <String, int>{};
  bool _goalBaseline = false;

  int? _total(SportEvent e) {
    final int? h = int.tryParse(e.homeScore ?? '');
    final int? a = int.tryParse(e.awayScore ?? '');
    if (h == null || a == null) return null;
    return h + a;
  }

  /// Quels matchs viennent de voir leur score MONTER, et met à jour la
  /// mémoire au passage.
  ///
  /// Séparée du reste EXPRÈS : c'est ici que vit toute la logique
  /// délicate (premier tour, score qui baisse, score illisible), et
  /// elle est ainsi testable sans notification, sans réseau et sans
  /// aucun canal de plateforme. Le déclenchement du son, lui, n'est
  /// qu'un appel.
  List<SportEvent> _goalsIn(List<SportEvent> fresh) {
    final Map<String, int> totals = <String, int>{};
    final List<SportEvent> buts = <SportEvent>[];

    for (final SportEvent e in fresh) {
      final int? t = _total(e);
      if (t == null) continue; // score illisible : on ne devine pas
      totals[e.id] = t;
      final int? avant = _lastTotals[e.id];
      // `avant == null` : match encore jamais vu. On l'enregistre, on
      // ne crie pas — il a pu commencer pendant qu'on regardait
      // ailleurs, et son score de départ n'est pas un but.
      if (avant != null && t > avant) buts.add(e);
    }

    _lastTotals
      ..clear()
      ..addAll(totals);

    if (!_goalBaseline) {
      _goalBaseline = true; // premier passage : on a juste appris
      return const <SportEvent>[];
    }
    return buts;
  }

  void _detectGoals(List<SportEvent> fresh) {
    for (final SportEvent e in _goalsIn(fresh)) {
      if (!_isAlertWorthy(e)) continue;
      final String body = goalBody(e);
      unawaited(NotificationService.instance.notifyGoal(
        // Emplacement STABLE par match : un deuxième but REMPLACE la
        // notification du premier au lieu d'en empiler une seconde.
        // Le client veut le score du moment, pas un historique.
        id: 970000 + (e.id.hashCode.abs() % 1000),
        title: l10nNow.sportGoalTitle,
        body: body,
      ));
      // BANDEAU DANS L'APP, en plus de la notification système. Deux
      // raisons : (a) sur Android TV, les notifications système
      // n'apparaissent PAS à l'écran — elles vont dans un panneau que
      // personne n'ouvre ; le bandeau, lui, passe au-dessus du lecteur.
      // (b) sur téléphone, si l'app est au premier plan sur un film, le
      // bandeau se voit sans quitter le film. On réutilise la bannière
      // admin (déjà posée dans les deux entrées, au-dessus de tout).
      unawaited(_showGoalBanner(e, body));
      return; // un seul cri par tour (garde-fou 4)
    }
  }

  /// « Real Madrid 2–1 Chelsea · 67' » — le score du moment et, si la
  /// source la donne, la minute. Volontairement non traduit : un score
  /// se lit dans toutes les langues.
  static String goalBody(SportEvent e) {
    final String score =
        '${e.home} ${e.homeScore ?? ''}–${e.awayScore ?? ''} ${e.away}';
    final String minute = e.liveLabel.trim();
    return minute.isEmpty ? score : '$score · $minute';
  }

  Future<void> _showGoalBanner(SportEvent e, String body) async {
    // Même interrupteur que les alertes de match : quelqu'un qui a coupé
    // « alertes de match » dans les Réglages ne veut pas non plus d'un
    // bandeau qui surgit sur son film.
    if (!await NotificationService.instance.isEnabled(kPrefMatchesBanner)) {
      return;
    }
    RealtimeSyncService.instance.showAdminMessage(AdminMessage(
      // Identifiant STABLE par match, comme la notification : un second
      // but remplace le bandeau du premier.
      id: 'goal:${e.id}',
      title: l10nNow.sportGoalTitle,
      body: body,
      kind: 'success',
      durationSec: 8,
      translate: false,
    ));
  }

  /// Clé du réglage « alertes de match » (la même que
  /// `MatchAlertsService.prefMatches` — recopiée ici pour ne pas créer
  /// d'import croisé entre les deux services).
  static const String kPrefMatchesBanner = 'notif.matches.enabled';

  @visibleForTesting
  void debugSeed(List<SportEvent> events, {bool available = true}) {
    _live = List<SportEvent>.unmodifiable(events);
    _available = available;
  }

  /// Rejoue la détection de but sur une liste donnée, sans réseau ni
  /// notification. Renvoie les identifiants des matchs où un but vient
  /// d'être marqué — donc exactement ce qui déclencherait le son.
  @visibleForTesting
  List<String> debugGoals(List<SportEvent> events) =>
      _goalsIn(events).map((SportEvent e) => e.id).toList();

  @visibleForTesting
  void debugResetGoals() {
    _lastTotals.clear();
    _goalBaseline = false;
  }

  @visibleForTesting
  bool get debugBaselineDone => _goalBaseline;
}
