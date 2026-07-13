// =========================================================
//  remote_error_reporter.dart — Remontée des erreurs vers le panel
// =========================================================
//  Branche un « puits » sur CrashReporting (via addLocalListener) qui envoie
//  les erreurs de l'appareil au backend (POST /api/error-log). Le revendeur
//  les voit alors dans « Journaux d'erreurs » du panel : il diagnostique un
//  client SANS le harceler de questions.
//
//  RÈGLES D'OR (ne JAMAIS nuire à l'app) :
//    - Best-effort total : toute erreur d'envoi est avalée.
//    - Anti-spam : au plus 1 envoi / 60 s ; on n'envoie que la DERNIÈRE erreur
//      en attente (les autres sont résumées par un compteur), jamais une rafale.
//    - RELEASE uniquement (kDebugMode → no-op) : le développement ne pollue pas
//      la base de production.
//    - Aucune donnée sensible : juste le message d'erreur + version + MAC.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../app/app_platform.dart';
import '../backend/backend_hosts.dart';
import '../../features/device/data/device_identity.dart';
import 'crash_reporting.dart';

class RemoteErrorReporter {
  RemoteErrorReporter._();
  static final RemoteErrorReporter instance = RemoteErrorReporter._();

  /// Intervalle mini entre deux envois (anti-spam réseau + base).
  static const Duration _minInterval = Duration(seconds: 60);

  bool _attached = false;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pendingFlush;

  // Dernière erreur en attente + nombre d'erreurs « avalées » depuis le
  // dernier envoi (résumé, pour ne pas perdre l'info sans spammer).
  String? _pendingLine;
  bool _pendingFatal = false;
  int _suppressed = 0;

  String? _appVersion;
  String? _appBuild;

  /// Branche le puits sur CrashReporting. À appeler une fois au démarrage,
  /// APRÈS `CrashReporting.instance.initialize()`. No-op en debug.
  void attach() {
    if (_attached || kDebugMode) return;
    _attached = true;
    CrashReporting.instance.addLocalListener(_onLine);
  }

  void _onLine(String line, {required bool fatal}) {
    // Un fil d'Ariane mémoire n'est pas une erreur : on ne remonte pas ça.
    if (line.contains('[mem]')) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastSent) >= _minInterval) {
      _send(line, fatal);
      return;
    }
    // Trop tôt : on garde la plus récente et on planifie un envoi à l'échéance.
    if (_pendingLine != null) _suppressed++;
    _pendingLine = line;
    _pendingFatal = _pendingFatal || fatal;
    _pendingFlush ??= Timer(
      _minInterval - now.difference(_lastSent),
      _flushPending,
    );
  }

  void _flushPending() {
    _pendingFlush = null;
    final String? line = _pendingLine;
    if (line == null) return;
    final bool fatal = _pendingFatal;
    final int extra = _suppressed;
    _pendingLine = null;
    _pendingFatal = false;
    _suppressed = 0;
    final String suffix = extra > 0 ? ' (+$extra autres erreurs)' : '';
    _send('$line$suffix', fatal);
  }

  Future<void> _send(String message, bool fatal) async {
    _lastSent = DateTime.now();
    try {
      if (_appVersion == null) {
        try {
          final PackageInfo pkg = await PackageInfo.fromPlatform();
          _appVersion = pkg.version;
          _appBuild = pkg.buildNumber;
        } catch (_) {
          _appVersion = '';
          _appBuild = '';
        }
      }
      final String mac = DeviceIdentity.instance.macSync;
      final Map<String, String> payload = <String, String>{
        'mac': mac,
        'level': fatal ? 'fatal' : 'error',
        'tag': 'app',
        'message': message.length > 2000 ? message.substring(0, 2000) : message,
        'app_version': _appVersion ?? '',
        'app_build': _appBuild ?? '',
        'platform': AppPlatform.isTv ? 'tv' : 'mobile',
      };
      await http
          .post(
            Uri.parse('${BackendHosts.current}/api/error-log'),
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort : une remontée d'erreur ne doit JAMAIS créer d'erreur.
    }
  }
}
