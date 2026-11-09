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
    this.onConnectionChanged,
    this.onReceived,
  });

  final String mac;
  final Future<void> Function(BoxChannelFrame frame) onFrame;
  final bool Function() alive;

  /// Réveille le filet HTTP dès qu'une prise tombe, sans attendre que
  /// l'autre boucle réseau constate indirectement la coupure.
  final void Function(bool open)? onConnectionChanged;

  /// Accusé rapide à l'arrivée, indépendant d'un import déjà en cours.
  /// Le traitement métier reste ordonné par la file ci-dessous.
  final void Function(BoxChannelFrame frame)? onReceived;

  /// Dernier numéro appliqué. Un signal déjà vu ne se rejoue pas.
  int seq = 0;

  /// Vrai tant que la prise est ouverte. La veille s'en sert
  /// pour ne pas doubler avec l'attente longue.
  bool open = false;

  void _setOpen(bool value) {
    if (open == value) return;
    open = value;
    onConnectionChanged?.call(value);
  }

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
    // Le socket continue de lire pendant un import : sinon les ordres suivants
    // restent dans son tampon et leur accusé « reçu » peut attendre une minute.
    // Une seule file applique les effets, y compris après une reconnexion.
    Future<void> pending = Future<void>.value();
    while (_going()) {
      Timer? hello;
      try {
        final Uri uri = boxChannelUri(kSubscriptionBaseUrl, mac);
        final WebSocket socket = await WebSocket.connect(uri.toString())
            .timeout(const Duration(seconds: 8));
        _socket = socket;
        if (!_going()) break;
        _setOpen(true);
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
          try {
            onReceived?.call(frame);
          } catch (e) {
            if (kDebugMode) debugPrint('[Canal] accusé : ${e.runtimeType}');
          }
          pending = pending.then((_) async {
            if (!_going()) return;
            try {
              await onFrame(frame);
            } catch (e) {
              // Une erreur métier ne bloque ni la réception ni les ordres
              // suivants ; les accusés APPLIED/FAILED restent à la veille.
              if (kDebugMode)
                debugPrint('[Canal] traitement : ${e.runtimeType}');
            }
          });
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Canal] $e');
      } finally {
        hello?.cancel();
        _setOpen(false);
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
