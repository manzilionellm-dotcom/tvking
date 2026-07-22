// =========================================================
//  crash_reporting.dart — Collecteur central des erreurs
// =========================================================
//  But : UN SEUL point d'entrée pour signaler une erreur, peu importe
//  d'où elle vient (filet global, plugin, lecteur vidéo, repo réseau…).
//
//  POURQUOI une abstraction et pas Crashlytics « en dur » partout :
//    - Le code applicatif ne dépend JAMAIS de Firebase directement → on
//      peut compiler/lancer l'app SANS configuration Firebase (dev, fork,
//      build sans secret). Crashlytics se branche derrière, en option.
//    - Si Firebase n'est pas configuré (pas de `google-services.json`),
//      l'init échoue PROPREMENT et on retombe sur un journal local : l'app
//      continue de tourner, elle n'a JAMAIS besoin de Firebase pour vivre.
//
//  Ce fichier (couche A) ne fait QUE du journal local : un anneau des N
//  derniers messages (consultable depuis un écran de diagnostic) + un
//  `debugPrint`. Le branchement Firebase Crashlytics est ajouté dans une
//  surcouche optionnelle (cf. `crash_reporting_firebase.dart`) qui se
//  contente d'appeler `attachBackend()` au démarrage si elle est présente.
// =========================================================
import 'dart:io' show ProcessInfo;

import 'package:flutter/foundation.dart';

import '../app/device_memory.dart';
import 'secret_redactor.dart';

/// Signature d'un « puits » d'erreurs distant (ex. Firebase Crashlytics).
/// On reste volontairement générique : la couche métier n'a aucune idée
/// de QUI consomme l'erreur.
typedef CrashBackend = void Function(
  Object error,
  StackTrace? stack, {
  String? context,
  bool fatal,
});

/// Collecteur unique. Singleton paresseux, sans dépendance lourde : il peut
/// être appelé AVANT même `runApp` (c'est le cas depuis le filet global).
class CrashReporting {
  CrashReporting._();
  static final CrashReporting instance = CrashReporting._();

  /// Anneau des derniers messages — utile pour un écran « Diagnostic » sans
  /// avoir à brancher un service distant. Borné pour ne pas fuir en mémoire.
  static const int _maxRing = 50;
  final List<String> _ring = <String>[];

  /// Puits distant optionnel (Crashlytics…). Null tant que rien n'est branché.
  CrashBackend? _backend;

  /// Auditeurs LOCAUX (boîte noire…) : reçoivent la même ligne que le
  /// ring. Plusieurs possibles, jamais lançants (erreurs avalées).
  final List<void Function(String line, {required bool fatal})>
      _localListeners = <void Function(String line, {required bool fatal})>[];

  /// Branche un auditeur local (ex. BlackBox). Contrairement à
  /// [attachBackend] (slot unique, réservé au puits distant), on peut
  /// en ajouter plusieurs.
  void addLocalListener(
    void Function(String line, {required bool fatal}) listener,
  ) =>
      _localListeners.add(listener);

  bool _ready = false;

  /// Init best-effort. Ne fait (volontairement) presque rien ici : la couche
  /// locale n'a rien à initialiser. La surcouche Firebase, si elle existe,
  /// appellera `attachBackend()` juste après. On garde la méthode `async`
  /// pour que le branchement Firebase (qui EST async) reste transparent.
  Future<void> initialize() async {
    _ready = true;
  }

  /// Branche un puits distant. Appelé par la surcouche Firebase si présente.
  /// Idempotent : un second appel remplace simplement le puits.
  void attachBackend(CrashBackend backend) {
    _backend = backend;
    debugPrint('[CrashReporting] backend distant branché.');
  }

  /// Signale une erreur. JAMAIS bloquant, JAMAIS lançant : on enveloppe même
  /// l'appel au backend dans un try/catch pour qu'un puits défaillant ne
  /// devienne pas lui-même une source de crash.
  void recordError(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    // CAVIARDAGE (correctif de fuite d'identifiants) : le message d'erreur
    // brut contient très souvent l'URI d'une source IPTV, identifiants de
    // l'abonné inclus. On les masque AVANT de toucher le moindre puits
    // (ring, boîte noire disque, POST panel) — point d'étranglement unique.
    final String safeError = SecretRedactor.redact('$error');
    final String line = '${DateTime.now().toIso8601String()}'
        '${fatal ? ' [FATAL]' : ''}'
        '${context != null ? ' (${SecretRedactor.redact(context)})' : ''} '
        '$safeError';

    _ring.add(line);
    if (_ring.length > _maxRing) _ring.removeAt(0);

    debugPrint('[CrashReporting] $line');

    for (final void Function(String line, {required bool fatal}) l
        in _localListeners) {
      try {
        l(line, fatal: fatal);
      } catch (_) {
        // un auditeur défaillant ne doit pas devenir une source de crash
      }
    }

    final CrashBackend? backend = _backend;
    if (backend != null) {
      try {
        backend(error, stack, context: context, fatal: fatal);
      } catch (e) {
        // Un backend qui plante ne doit PAS faire planter l'app.
        debugPrint('[CrashReporting] backend distant en échec : $e');
      }
    }
  }

  /// Trace simple (fil d'Ariane), utile avant un point sensible.
  void log(String message) {
    debugPrint('[CrashReporting] $message');
  }

  // ============================================================
  //  BREADCRUMBS MÉMOIRE (diagnostic anti-OOM box faible RAM)
  // ============================================================
  //  But : localiser PRÉCISÉMENT la phase où la mémoire explose avant le kill
  //  natif (lowmemorykiller / signal 9). On pose un fil d'Ariane AVANT/APRÈS
  //  chaque étape lourde (fetch, décodage JSON, conversion, insertion SQLite,
  //  1er rendu…). À lire ensuite via `adb logcat | grep "\[mem\]"`.
  //
  //  La métrique clé est le **RSS du process** (mémoire résidente réellement
  //  occupée — c'est CELLE que l'OS regarde pour tuer l'app), via
  //  `ProcessInfo.currentRss` (pur Dart, aucune dépendance native). On y ajoute
  //  la classe de RAM de l'appareil (DeviceMemory). Best-effort, JAMAIS bloquant.

  /// Fil d'Ariane mémoire simple pour une [phase] donnée.
  void recordMemoryBreadcrumb(String phase) =>
      recordMemoryBreadcrumbWithCounts(phase);

  /// Variante avec compteurs (nb de [channels] traitées, taille en [bytes]).
  void recordMemoryBreadcrumbWithCounts(
    String phase, {
    int? channels,
    int? bytes,
  }) {
    try {
      // RSS = mémoire résidente du process (octets) → l'indicateur que l'OS
      // utilise pour décider de tuer l'app. C'est LE chiffre qui compte.
      int rssMb = 0;
      try {
        rssMb = (ProcessInfo.currentRss / (1024 * 1024)).round();
      } catch (_) {
        // currentRss indisponible sur certaines plateformes → on ignore.
      }
      final int totalMb = DeviceMemory.totalMb;
      final StringBuffer b = StringBuffer('[mem] $phase | rss=${rssMb}Mo');
      if (totalMb > 0) b.write(' | ramTotale=${totalMb}Mo');
      if (DeviceMemory.lowRam) b.write(' | lowRam');
      if (channels != null) b.write(' | chaines=$channels');
      if (bytes != null) {
        b.write(' | taille=${(bytes / (1024 * 1024)).toStringAsFixed(1)}Mo');
      }
      b.write(' | ${DateTime.now().toIso8601String()}');
      final String line = b.toString();
      _ring.add(line);
      if (_ring.length > _maxRing) _ring.removeAt(0);
      debugPrint('[CrashReporting] $line');
    } catch (_) {
      // Un breadcrumb ne doit JAMAIS faire planter l'app.
    }
  }

  /// Les derniers messages collectés (lecture seule) — pour un écran de diag.
  List<String> get recentErrors => List<String>.unmodifiable(_ring);

  bool get isReady => _ready;
}
