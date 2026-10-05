// =========================================================
//  box_channel_session.dart — WebSocket de la box
// =========================================================
//  La box ouvre wss://…/api/box/ws?mac=… et attend un signal.
//  Dès qu'il arrive, on le donne à la veille, qui relit les
//  listes. Si la prise ne s'ouvre pas, on rend la main : la
//  veille reprend l'attente longue (GET /api/box/wait), puis
//  la lecture courte.
//
//  Reconnexion : 1 s, 2 s, 4 s… plafonné à 30 s.
//  Un « hello » toutes les 25 s garde le chemin ouvert.
//  Aucun mot de passe n'est écrit dans l'adresse ni dans hello.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/box_channel.dart';
import 'subscription_backend.dart';

class BoxChannelSession {
  BoxChannelSession({
    required this.mac,
    required this.onFrame,
    required this.alive,
  });

  final String mac;
  final Future<void> Function(BoxChannelFrame frame) onFrame;
  final bool Function() alive;

  /// Dernier numéro appliqué. Un signal déjà vu ne se rejoue pas.
  int seq = 0;

  /// Vrai tant que la prise est ouverte. La veille s'en sert
  /// pour ne pas doubler avec l'attente longue.
  bool open = false;

  bool _stopped = false;
  WebSocket? _socket;

  /// Coupe la prise tout de suite (arrêt de la veille, test).
  void stop() {
    _stopped = true;
    try {
      _socket?.close();
    } catch (_) {
      // Déjà fermée.
    }
  }

  bool _going() => !_stopped && alive();

  /// Boucle jusqu'à ce que [alive] soit faux.
  Future<void> run() async {
    var delaySeconds = 1;
    while (_going()) {
      Timer? hello;
      try {
        final Uri uri = boxChannelUri(kSubscriptionBaseUrl, mac);
        final WebSocket socket = await WebSocket.connect(uri.toString())
            .timeout(const Duration(seconds: 8));
        _socket = socket;
        if (!_going()) break;
        open = true;
        delaySeconds = 1;
        hello = Timer.periodic(const Duration(seconds: 25), (_) {
          try {
            _socket?.add('{"v":1,"type":"hello"}');
          } catch (_) {
            // La prise est déjà fermée : la boucle reconnecte.
          }
        });
        await for (final dynamic message in socket) {
          if (!_going()) break;
          final BoxChannelFrame? frame = parseBoxChannelFrame('$message');
          if (frame == null || frame.seq <= seq) continue;
          if (frame.mac != mac) continue;
          seq = frame.seq;
          await onFrame(frame);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Canal] $e');
      } finally {
        hello?.cancel();
        open = false;
        try {
          await _socket?.close();
        } catch (_) {
          // Déjà fermée.
        }
        _socket = null;
      }
      if (!_going()) return;
      await _pause(Duration(seconds: delaySeconds));
      if (delaySeconds < 30) delaySeconds *= 2;
    }
  }

  Future<void> _pause(Duration delay) async {
    final DateTime end = DateTime.now().add(delay);
    while (_going() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}
