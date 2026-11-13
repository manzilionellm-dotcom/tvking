// =========================================================
//  feedback_repository.dart — Avis clients (invitation + envoi)
// =========================================================
//  Lit l'invitation posée par le panel (`GET /api/feedback-prompt`) et
//  envoie l'avis du client (`POST /api/feedback`). On ne re-demande pas
//  tant que le client a déjà répondu au MÊME message (clé liée au texte
//  → un nouveau message du panel re-pose la question). Zéro cast.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_backend.dart';

class FeedbackRepository extends ChangeNotifier {
  FeedbackRepository._();
  static final FeedbackRepository instance = FeedbackRepository._();

  bool _enabled = false;
  String _message = '';
  bool _initialized = false;
  int _request = 0;

  String get message => _message;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _fetch();
  }

  /// Relit l'invitation. Appelé quand le panel vient d'en poser une,
  /// sans attendre le prochain démarrage de l'app.
  Future<void> reload({bool strict = false}) async {
    _initialized = true;
    await _fetch(strict: strict);
  }

  Future<void> _fetch({bool strict = false}) async {
    final request = ++_request;
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/feedback-prompt'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) throw StateError('Invitation non confirmée');
      if (request != _request) throw StateError('Invitation remplacée');
      final Object? d = jsonDecode(resp.body);
      if (d is! Map || d['enabled'] is! bool || d['message'] is! String) {
        throw const FormatException('Invitation invalide');
      }
      _enabled = d['enabled'] == true;
      _message = (d['message'] ?? '').toString();
      notifyListeners();
    } catch (e) {
      if (strict) rethrow;
      if (kDebugMode) debugPrint('[Feedback] ${e.runtimeType}');
    }
  }

  String _keyFor(String message) => 'fb_done_${message.hashCode}';
  String get _key => _keyFor(_message);

  /// Faut-il inviter le client maintenant ? (activé + message non vide +
  /// pas déjà répondu à ce message)
  Future<bool> shouldPrompt() async {
    if (!_enabled || _message.trim().isEmpty) return false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_key) ?? false);
    } catch (_) {
      return true;
    }
  }

  Future<void> markDone({String? prompt}) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyFor(prompt ?? _message), true);
      notifyListeners();
    } catch (_) {}
  }

  /// Envoie seulement sur action du client. Un échec reste réessayable ;
  /// une invitation arrivée pendant la requête ne doit pas être acquittée.
  Future<bool> submit(
      {required String text, int rating = 0, String? prompt}) async {
    final value = text.trim();
    if (value.isEmpty || value.length > 2000 || rating < 0 || rating > 5) {
      return false;
    }
    final answeredPrompt = prompt ?? _message;
    try {
      final String mac = await DeviceIdentity.instance.mac;
      final http.Response resp = await http
          .post(
            Uri.parse('$kSubscriptionBaseUrl/api/feedback'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'mac': mac,
              'rating': rating,
              'message': value,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return false;
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map || decoded['ok'] != true) return false;
      await markDone(prompt: answeredPrompt);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Feedback submit] $e');
      return false;
    }
  }
}
