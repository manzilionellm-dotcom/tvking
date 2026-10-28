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
    this.onConnected,
    this.headers,
    this.baseUrl,
    this.pingInterval = const Duration(seconds: 10),
    this.retryDelay = const Duration(seconds: 1),
  });

  final String mac;
  final Future<bool> Function(BoxChannelFrame frame) onFrame;
  final bool Function() alive;
  final void Function()? onConnected;
  final Future<Map<String, String>> Function()? headers;
  final String? baseUrl;
  final Duration pingInterval;
  final Duration retryDelay;

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
        final Uri uri = boxChannelUri(baseUrl ?? kSubscriptionBaseUrl, mac, after: seq);
        final Future<WebSocket> pending = WebSocket.connect(uri.toString(),
            headers: await headers?.call());
        final WebSocket socket = await pending.timeout(const Duration(seconds: 8),
          onTimeout: () {
            // timeout ne ferme pas une connexion qui aboutit plus tard.
            unawaited(pending.then((WebSocket lateSocket) => lateSocket.close()).catchError((Object _) {}));
            throw TimeoutException('canal indisponible');
          });
        _socket = socket;
        if (!_going()) {
          await socket.close();
          break;
        }
        // Ping protocolaire : Cloudflare répond même pendant l'hibernation.
        // Une prise devenue muette est fermée au lieu de masquer le repli.
        socket.pingInterval = pingInterval;
        open = true;
        onConnected?.call();
        socket.add('{"v":1,"type":"hello"}');
        hello = Timer.periodic(const Duration(seconds: 10), (_) {
          try {
            _socket?.add('{"v":1,"type":"hello"}');
          } catch (_) {
            // La prise est déjà fermée : la boucle reconnecte.
          }
        });
        await for (final dynamic message in socket) {
          if (!_going()) break;
          // Une réponse du serveur valide aussi une connexion sans ordre.
          delaySeconds = 1;
          final BoxChannelFrame? frame = parseBoxChannelFrame('$message');
          if (frame == null || frame.seq <= seq) continue;
          if (frame.mac != mac) continue;
          if (!await onFrame(frame)) {
            // La réception seule n'autorise pas à avancer le curseur : une
            // relecture en échec doit pouvoir reprendre le même ordre.
            throw StateError('ordre non appliqué, reprise nécessaire');
          }
          seq = frame.seq;
          delaySeconds = 1;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Canal] connexion interrompue');
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
      await _pause(retryDelay * delaySeconds);
      delaySeconds = (delaySeconds * 2).clamp(1, 30).toInt();
    }
  }

  Future<void> _pause(Duration delay) async {
    final DateTime end = DateTime.now().add(delay);
    while (_going() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}
