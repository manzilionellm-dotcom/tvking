// =========================================================
//  admin_credentials.dart — Code PIN admin + token GitHub
// =========================================================
//  Stockage local des credentials nécessaires pour piloter le
//  gist GitHub (lecture/écriture) depuis le mode admin de l'app :
//
//    - PIN admin (4-8 chiffres) qui protège l'accès au dashboard
//    - GitHub Personal Access Token (scope `gist`) pour écrire
//    - ID du gist (extrait automatiquement de l'URL Raw configurée
//      dans Réglages → Provisioning à distance)
//
//  SÉCURITÉ — note honnête :
//    Tout est dans SharedPreferences (XML chiffré par le Keystore
//    Android sur 9+, sinon clair). C'est l'appareil de l'admin
//    lui-même donc le modèle de menace est faible. Pour passer à
//    flutter_secure_storage (Android Keystore explicite) il
//    suffira de remplacer ce repo sans toucher au reste.
//
//    Le PIN est stocké en clair — la "sécurité" du mode admin
//    est principalement par obscurité (le bouton n'est pas
//    annoncé). Un PIN haché n'apporte rien si l'attaquant a
//    déjà accès aux SharedPreferences.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminCredentials extends ChangeNotifier {
  AdminCredentials._();
  static final AdminCredentials instance = AdminCredentials._();

  static const String _kPinKey = 'admin.pin.v1';
  static const String _kPatKey = 'admin.github_pat.v1';
  static const String _kGistIdKey = 'admin.gist_id.v1';

  String? _pin;
  String? _pat;
  String? _gistId;

  /// `true` quand un code PIN admin a déjà été défini.
  bool get hasPin => _pin != null && _pin!.isNotEmpty;

  /// `true` quand un GitHub PAT est configuré (donc on peut écrire).
  bool get hasPat => _pat != null && _pat!.isNotEmpty;

  /// `true` quand on a tout pour écrire (PAT + gist ID).
  bool get canWrite => hasPat && hasGistId;

  bool get hasGistId => _gistId != null && _gistId!.isNotEmpty;

  String? get pat => _pat;
  String? get gistId => _gistId;

  Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _pin = prefs.getString(_kPinKey);
    _pat = prefs.getString(_kPatKey);
    _gistId = prefs.getString(_kGistIdKey);
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    _pin = pin;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinKey, pin);
    notifyListeners();
  }

  Future<bool> verifyPin(String input) async {
    if (_pin == null) return false;
    return input == _pin;
  }

  Future<void> setPat(String pat) async {
    _pat = pat.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPatKey, _pat!);
    notifyListeners();
  }

  Future<void> setGistId(String gistId) async {
    _gistId = gistId.trim();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGistIdKey, _gistId!);
    notifyListeners();
  }

  /// Extrait l'ID du gist depuis n'importe quelle URL gist GitHub :
  ///   https://gist.githubusercontent.com/USER/abc123/raw/...
  ///   https://gist.github.com/USER/abc123
  ///   https://api.github.com/gists/abc123
  ///   abc123 (déjà l'ID brut)
  ///
  /// Renvoie `null` si rien ne match.
  static String? extractGistIdFromUrl(String url) {
    if (url.trim().isEmpty) return null;
    final String trimmed = url.trim();

    // URL contenant /gist*.../USER/<ID>/...
    final RegExp gistUrlPattern =
        RegExp(r'gist(?:hubusercontent)?\.github\.com/[^/]+/([a-f0-9]+)');
    final RegExpMatch? m1 = gistUrlPattern.firstMatch(trimmed);
    if (m1 != null) return m1.group(1);

    // URL API : api.github.com/gists/<ID>
    final RegExp apiPattern =
        RegExp(r'api\.github\.com/gists/([a-f0-9]+)');
    final RegExpMatch? m2 = apiPattern.firstMatch(trimmed);
    if (m2 != null) return m2.group(1);

    // ID brut (40 caractères hex typiques d'un gist)
    if (RegExp(r'^[a-f0-9]{20,40}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  Future<void> reset() async {
    _pin = null;
    _pat = null;
    _gistId = null;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinKey);
    await prefs.remove(_kPatKey);
    await prefs.remove(_kGistIdKey);
    notifyListeners();
    if (kDebugMode) debugPrint('[Admin] Credentials reset');
  }
}
