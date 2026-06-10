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

class FeedbackRepository {
  FeedbackRepository._();
  static final FeedbackRepository instance = FeedbackRepository._();

  bool _enabled = false;
  String _message = '';
  bool _initialized = false;

  String get message => _message;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/feedback-prompt'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return;
      final Object? d = jsonDecode(resp.body);
      if (d is! Map) return;
      _enabled = d['enabled'] == true;
      _message = (d['message'] ?? '').toString();
    } catch (e) {
      if (kDebugMode) debugPrint('[Feedback] $e');
    }
  }

  String get _key => 'fb_done_${_message.hashCode}';

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

  Future<void> markDone() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {}
  }

  /// Envoie l'avis. Marque comme répondu (qu'on retente ou non).
  Future<bool> submit({required String text, int rating = 0}) async {
    await markDone();
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
              'message': text,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return resp.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('[Feedback submit] $e');
      return false;
    }
  }
}
