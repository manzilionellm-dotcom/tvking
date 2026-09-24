// =========================================================
//  admin_credentials.dart — Connexion au backend Worker
// =========================================================
//  Stockage local des credentials nécessaires pour piloter
//  notre backend Cloudflare Worker depuis le mode admin :
//
//    - PIN admin (4 chiffres) qui protège l'accès au dashboard
//      sur le téléphone admin
//    - URL du Worker (https://seven-motion-backend.X.workers.dev)
//    - Secret admin (envoyé en header X-Admin-Secret aux endpoints
//      /admin/* du Worker)
//
//  REMPLACE l'ancienne configuration GitHub Gist (gist ID + PAT)
//  qui demandait à l'utilisateur de comprendre des concepts geeks
//  (PAT scope `gist`, gist secret vs public, etc.).
//
//  SÉCURITÉ — note honnête :
//    Tout est dans SharedPreferences (XML chiffré par le Keystore
//    Android sur 9+, sinon clair). C'est l'appareil de l'admin
//    lui-même donc le modèle de menace est faible. Pour passer à
//    flutter_secure_storage (Android Keystore explicite), changer
//    juste l'impl de read/write sans toucher au reste.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminCredentials extends ChangeNotifier {
  AdminCredentials._();
  static final AdminCredentials instance = AdminCredentials._();

  static const String _kPinKey = 'admin.pin.v1';
  static const String _kWorkerUrlKey = 'admin.worker_url.v2';
  static const String _kAdminSecretKey = 'admin.secret.v2';

  // Legacy (gist) — lus uniquement pour migration au démarrage,
  // puis effacés.
  static const String _kLegacyPatKey = 'admin.github_pat.v1';
  static const String _kLegacyGistIdKey = 'admin.gist_id.v1';

  String? _pin;
  String? _workerUrl;
  String? _adminSecret;

  /// `true` quand un code PIN admin a déjà été défini.
  bool get hasPin => _pin != null && _pin!.isNotEmpty;

  /// `true` quand l'URL du Worker est configurée.
  bool get hasWorkerUrl => _workerUrl != null && _workerUrl!.isNotEmpty;

  /// `true` quand le secret admin est configuré.
  bool get hasAdminSecret =>
      _adminSecret != null && _adminSecret!.isNotEmpty;

  /// `true` quand on a tout pour lire/écrire le backend.
  bool get canWrite => hasWorkerUrl && hasAdminSecret;

  String? get workerUrl => _workerUrl;
  String? get adminSecret => _adminSecret;

  Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _pin = prefs.getString(_kPinKey);
    _workerUrl = prefs.getString(_kWorkerUrlKey);
    _adminSecret = prefs.getString(_kAdminSecretKey);

    // Migration : si on a encore des creds Gist legacy, on les
    // efface (ils ne servent plus à rien dans la nouvelle archi).
    final bool hadLegacy = prefs.containsKey(_kLegacyPatKey) ||
        prefs.containsKey(_kLegacyGistIdKey);
    if (hadLegacy) {
      await prefs.remove(_kLegacyPatKey);
      await prefs.remove(_kLegacyGistIdKey);
      if (kDebugMode) {
        debugPrint(
          '[Admin] Migration : creds Gist legacy effacés. '
          'Configure le Worker URL + secret dans la console admin.',
        );
      }
    }
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    _pin = pin;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinKey, pin);
    notifyListeners();
  }

  // ----- Anti-brute-force du PIN admin (P1-11) -----
  //  Le PIN fait 4 chiffres (10 000 combinaisons) → sans limite, il se force en
  //  quelques minutes. On VERROUILLE après [_kMaxFails] échecs, avec un backoff
  //  progressif. Défense indépendante du stockage (qui reste à migrer vers un
  //  hash + flutter_secure_storage — nécessite l'ajout du package `crypto`,
  //  donc un `pub get`, traité hors de ce correctif sans réseau).
  static const String _kFailCountKey = 'admin.pin.fails.v1';
  static const String _kLockUntilKey = 'admin.pin.lock_until.v1';
  static const int _kMaxFails = 5;

  Duration _lockRemaining = Duration.zero;

  /// Temps de verrouillage restant (0 = déverrouillé). À afficher dans l'UI
  /// admin (« Réessaie dans … ») après un appel à [verifyPin].
  Duration get lockRemaining => _lockRemaining;

  Future<bool> verifyPin(String input) async {
    if (_pin == null) return false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int now = DateTime.now().millisecondsSinceEpoch;

    // 1) Verrouillé ? On n'évalue même pas le PIN (anti-brute-force).
    final int lockUntil = prefs.getInt(_kLockUntilKey) ?? 0;
    if (now < lockUntil) {
      _lockRemaining = Duration(milliseconds: lockUntil - now);
      return false;
    }
    _lockRemaining = Duration.zero;

    // 2) Succès → on remet les compteurs à zéro.
    if (input == _pin) {
      await prefs.remove(_kFailCountKey);
      await prefs.remove(_kLockUntilKey);
      return true;
    }

    // 3) Échec → on incrémente et, au seuil, on verrouille avec backoff.
    final int fails = (prefs.getInt(_kFailCountKey) ?? 0) + 1;
    await prefs.setInt(_kFailCountKey, fails);
    if (fails >= _kMaxFails) {
      final Duration lock = _lockDurationFor(fails);
      await prefs.setInt(_kLockUntilKey, now + lock.inMilliseconds);
      _lockRemaining = lock;
    }
    return false;
  }

  /// Backoff progressif au-delà du seuil : 30 s → 1 min → 5 min → 15 min (cap).
  Duration _lockDurationFor(int fails) {
    final int over = fails - _kMaxFails; // 0, 1, 2, …
    const List<Duration> steps = <Duration>[
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 15),
    ];
    return steps[over.clamp(0, steps.length - 1)];
  }

  Future<void> setWorkerUrl(String url) async {
    // Normalisation : retire trailing slash pour éviter `//config/MAC`
    _workerUrl =
        url.trim().endsWith('/') ? url.trim().substring(0, url.trim().length - 1) : url.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWorkerUrlKey, _workerUrl!);
    notifyListeners();
  }

  Future<void> setAdminSecret(String secret) async {
    _adminSecret = secret.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAdminSecretKey, _adminSecret!);
    notifyListeners();
  }

  /// Construit l'URL publique `/config/:mac` que les clients
  /// utilisent pour récupérer leur playlist. Sert à pré-remplir
  /// automatiquement la section "Provisioning à distance" côté
  /// client (un seul `workerUrl` partagé pour tous).
  String? publicConfigUrlFor(String mac) {
    if (!hasWorkerUrl) return null;
    return '$_workerUrl/config/$mac';
  }

  Future<void> reset() async {
    _pin = null;
    _workerUrl = null;
    _adminSecret = null;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinKey);
    await prefs.remove(_kWorkerUrlKey);
    await prefs.remove(_kAdminSecretKey);
    notifyListeners();
    if (kDebugMode) debugPrint('[Admin] Credentials reset');
  }
}
