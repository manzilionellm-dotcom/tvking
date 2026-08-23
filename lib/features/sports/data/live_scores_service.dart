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
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/i18n/l10n_now.dart';
import '../../../core/notifications/notification_service.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../domain/sport_models.dart';
import 'followed_matches_service.dart';

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
  //   1. UNIQUEMENT LES MATCHS SUIVIS. Il y a jusqu'à 60 rencontres en
  //      direct simultanément. Sonner à chaque but de n'importe lequel,
  //      c'est un cri toutes les deux minutes un samedi après-midi.
  //      On ne sonne que pour ce que le client a EXPLICITEMENT choisi
  //      de suivre.
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
      if (!FollowedMatchesService.instance.isFollowed(e.id)) continue;
      unawaited(NotificationService.instance.notifyGoal(
        // Emplacement STABLE par match : un deuxième but REMPLACE la
        // notification du premier au lieu d'en empiler une seconde.
        // Le client veut le score du moment, pas un historique.
        id: 970000 + (e.id.hashCode.abs() % 1000),
        title: l10nNow.sportGoalTitle,
        body: '${e.home} ${e.homeScore ?? ''}–${e.awayScore ?? ''} ${e.away}',
      ));
      return; // un seul cri par tour (garde-fou 4)
    }
  }

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
