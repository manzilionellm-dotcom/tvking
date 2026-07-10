// =========================================================
//  stream_stability_monitor.dart — Cerveau de l'ABR maison du lecteur TV
// =========================================================
//  MISSION : « l'image ne gèle pas, la connexion reste — c'est la QUALITÉ
//  qui s'adapte » (comportement Netflix/YouTube), y compris sur les flux
//  IPTV mono-débit où l'ABR classique est impossible.
//
//  Cette machine à états PURE (zéro Flutter, zéro Timer, horodatages
//  injectés → testable à la seconde près, comme FreezeRecoveryPolicy)
//  observe deux capteurs :
//    • les REBUFFERS (image interrompue, spinner) et les pertes de
//      connexion upstream du relais — le mal déjà fait ;
//    • le DÉBIT D'INGESTION du relais (octets/s) comparé au débit nominal
//      appris du flux — le mal IMMINENT (le tuyau n'alimente plus assez
//      vite : le tampon se vide, le gel arrive dans quelques secondes).
//
//  Et rend des DÉCISIONS :
//    • downshift : basculer sur la déclinaison de qualité inférieure de la
//      même chaîne (cf. quality_ladder.dart) ;
//    • restore  : la connexion est redevenue stable depuis assez longtemps
//      → revenir à la chaîne d'origine.
//
//  ANTI YO-YO (le piège classique des ABR naïfs) :
//    • cooldown après chaque bascule : on laisse le nouveau flux s'installer
//      avant de re-juger ;
//    • la remontée exige une LONGUE période de calme (4 min), doublée à
//      chaque rechute (4 → 8 → 16 min) ;
//    • au bout de [maxRestores] rechutes, on ARRÊTE de remonter pour la
//      session : mieux vaut une image stable en HD qu'un yo-yo FHD/HD.
// =========================================================

/// Décision rendue par le moniteur à chaque échantillon.
enum StabilityAction {
  /// Rien à faire.
  none,

  /// Connexion trop faible pour la qualité courante → descendre d'un cran.
  downshift,

  /// Stable depuis assez longtemps → revenir à la qualité d'origine.
  restore,
}

/// Machine à états de l'adaptation de qualité. Une instance par écran
/// lecteur ; TOUTES les décisions passent par elle.
class StreamStabilityMonitor {
  StreamStabilityMonitor({
    this.eventWindow = const Duration(seconds: 90),
    this.eventsForDownshift = 3,
    this.deficitRatio = 0.65,
    this.deficitStreakForDownshift = 5,
    this.mixedDeficitStreak = 3,
    this.cooldown = const Duration(seconds: 45),
    this.stableForRestore = const Duration(minutes: 4),
    this.relapseWindow = const Duration(minutes: 3),
    this.maxRestores = 2,
  });

  /// Fenêtre de comptage des incidents (rebuffers + pertes upstream).
  final Duration eventWindow;

  /// Nombre d'incidents dans [eventWindow] qui déclenche la descente.
  final int eventsForDownshift;

  /// En dessous de `nominal × deficitRatio`, un échantillon de débit est
  /// « en déficit » (le tuyau n'alimente plus le débit du flux).
  final double deficitRatio;

  /// Échantillons de déficit CONSÉCUTIFS pour une descente PRÉVENTIVE
  /// (aucun gel encore visible — c'est la descente « avant l'écran figé »).
  final int deficitStreakForDownshift;

  /// Déficit consécutif suffisant quand il y a DÉJÀ eu au moins un incident
  /// dans la fenêtre (signal croisé : on ne traîne pas).
  final int mixedDeficitStreak;

  /// Silence radio après une bascule : le temps que le nouveau flux
  /// s'installe (tampon plein, débit nominal ré-appris).
  final Duration cooldown;

  /// Durée de calme exigée avant de remonter (doublée à chaque rechute).
  final Duration stableForRestore;

  /// Une descente si tôt après une remontée = rechute (yo-yo).
  final Duration relapseWindow;

  /// Nombre max de remontées par session de chaîne.
  final int maxRestores;

  // ----- État de session (remis à zéro par openChannel) -----
  final List<DateTime> _events = <DateTime>[];
  double? _smoothedRate;
  double _nominalRate = 0;
  int _deficitStreak = 0;
  DateTime? _quietUntil; // fin de cooldown après bascule
  DateTime? _lastIncident; // dernier événement OU déficit
  DateTime? _shiftedAt; // null = à la qualité d'origine
  DateTime? _restoredAt; // dernière remontée (détection de rechute)
  int _restores = 0;
  bool _restoreDisabled = false;
  bool _downshiftUnavailable = false;
  // `late` : un initialiseur de champ ne peut pas référencer un autre champ
  // d'instance ([stableForRestore]) sans lui. Ré-armé par openChannel.
  late Duration _requiredStability = stableForRestore;

  /// `true` si on joue actuellement une déclinaison DÉGRADÉE.
  bool get isShifted => _shiftedAt != null;

  /// Débit nominal appris (octets/s) — diagnostic.
  double get nominalRate => _nominalRate;

  Duration get _stabilityNeeded => _requiredStability;

  // ----- API -----

  /// Nouvelle chaîne choisie PAR L'UTILISATEUR (zap manuel, numéro, OK) :
  /// tout repart de zéro — la session d'adaptation précédente est close.
  void openChannel(DateTime now) {
    _events.clear();
    _smoothedRate = null;
    _nominalRate = 0;
    _deficitStreak = 0;
    _quietUntil = null;
    _lastIncident = null;
    _shiftedAt = null;
    _restoredAt = null;
    _restores = 0;
    _restoreDisabled = false;
    _downshiftUnavailable = false;
    _requiredStability = stableForRestore;
  }

  /// Un REBUFFER visible (spinner en cours de lecture) ou une perte de
  /// connexion upstream signalée par le relais.
  void onIncident(DateTime now) {
    _events.add(now);
    _lastIncident = now;
    _evict(now);
  }

  /// Échantillon périodique (tick du watchdog, ~4 s) avec le débit
  /// d'ingestion mesuré par le relais (`null` = pas de mesure : lecture
  /// directe HLS, session pas encore établie…). Renvoie la décision.
  StabilityAction onSample(DateTime now, {double? ingestBytesPerSecond}) {
    _evict(now);

    // ----- Apprentissage du débit nominal + détection de déficit -----
    if (ingestBytesPerSecond != null && ingestBytesPerSecond > 0) {
      final double s = _smoothedRate == null
          ? ingestBytesPerSecond
          : _smoothedRate! * 0.7 + ingestBytesPerSecond * 0.3;
      _smoothedRate = s;
      if (s > _nominalRate) _nominalRate = s;
      final bool deficit =
          _nominalRate > 0 && s < _nominalRate * deficitRatio;
      if (deficit) {
        _deficitStreak++;
        _lastIncident = now;
      } else {
        _deficitStreak = 0;
      }
    }

    // ----- Cooldown après bascule : on observe, on ne décide pas -----
    final DateTime? quiet = _quietUntil;
    if (quiet != null && now.isBefore(quiet)) return StabilityAction.none;

    // ----- Descente ? -----
    final bool tooManyEvents = _events.length >= eventsForDownshift;
    final bool sustainedDeficit = _deficitStreak >= deficitStreakForDownshift;
    final bool mixedSignal =
        _events.isNotEmpty && _deficitStreak >= mixedDeficitStreak;
    if (!_downshiftUnavailable &&
        (tooManyEvents || sustainedDeficit || mixedSignal)) {
      return StabilityAction.downshift;
    }

    // ----- Remontée ? -----
    if (_shiftedAt != null && !_restoreDisabled) {
      final DateTime calmSince = _latest(
        _lastIncident,
        _latest(_shiftedAt, _quietUntil),
      )!;
      if (now.difference(calmSince) >= _stabilityNeeded) {
        return StabilityAction.restore;
      }
    }
    return StabilityAction.none;
  }

  /// Le lecteur A EFFECTIVEMENT basculé sur la déclinaison inférieure.
  void noteShifted(DateTime now) {
    _shiftedAt ??= now;
    // Rechute juste après une remontée → yo-yo : la prochaine remontée
    // devra prouver une stabilité DOUBLE ; au bout de [maxRestores], on
    // reste en bas pour de bon (image stable > qualité instable).
    final DateTime? restored = _restoredAt;
    if (restored != null && now.difference(restored) <= relapseWindow) {
      _requiredStability *= 2;
      if (_restores >= maxRestores) _restoreDisabled = true;
    }
    _afterShift(now);
  }

  /// Le lecteur est REVENU à la qualité d'origine.
  void noteRestored(DateTime now) {
    _shiftedAt = null;
    _restoredAt = now;
    _restores++;
    _afterShift(now);
  }

  /// Aucune déclinaison inférieure disponible : on arrête de proposer la
  /// descente pour cette session (le tampon et les reconnexions du relais
  /// restent seuls en première ligne).
  void noteDownshiftUnavailable() {
    _downshiftUnavailable = true;
  }

  // ----- interne -----

  void _afterShift(DateTime now) {
    _quietUntil = now.add(cooldown);
    _events.clear();
    _deficitStreak = 0;
    // Nouveau flux = nouveau débit nominal (celui de l'ancien ne veut
    // plus rien dire — c'est précisément ce qu'on vient de changer).
    _smoothedRate = null;
    _nominalRate = 0;
  }

  void _evict(DateTime now) {
    final DateTime cutoff = now.subtract(eventWindow);
    while (_events.isNotEmpty && _events.first.isBefore(cutoff)) {
      _events.removeAt(0);
    }
  }

  static DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}
