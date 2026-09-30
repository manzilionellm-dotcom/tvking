// =========================================================
//  remote_control.dart — Vie de la télécommande sur la box
// =========================================================
//  Ouvrir l'écran des Réglages → Télécommande démarre le serveur
//  (ou réaffiche le QR encore valide). Quitter l'écran NE coupe
//  PAS : le téléphone doit pouvoir changer de chaîne pendant le
//  film. « Couper » ou l'expiration arrêtent les commandes.
//
//  « Nouveau code » change le jeton tout de suite : l'ancien
//  téléphone ne commande plus, il faut rescaner.
// =========================================================

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/blackbox/black_box.dart';
import '../data/phone_remote_server.dart';
import '../domain/lan_ipv4.dart';
import 'remote_actions.dart';

enum RemotePhase { starting, ready, expired, stopped, noLan, error }

class RemoteView {
  const RemoteView({
    this.phase = RemotePhase.starting,
    this.url,
    this.paired = false,
    this.secondsLeft = 0,
  });

  final RemotePhase phase;
  final String? url;
  final bool paired;
  final int secondsLeft;
}

class RemoteControl {
  RemoteControl._();
  static final RemoteControl instance = RemoteControl._();

  RemoteView view = const RemoteView();
  PhoneRemoteServer? _server;

  /// L'utilisateur vient d'ouvrir l'écran. On garde le QR en cours
  /// s'il est encore valide (le téléphone déjà appairé continue).
  /// Sinon on en crée un nouveau — ouvrir l'écran est un geste
  /// volontaire, contrairement à un renouvellement tout seul.
  Future<void> onScreenOpened() async {
    final PhoneRemoteServer? server = _server;
    if (server != null && server.isRunning && !server.isExpired) {
      _publishReady();
      return;
    }
    await restart();
  }

  /// À appeler chaque seconde pendant que l'écran est visible,
  /// pour le compte à rebours et le passage « téléphone connecté ».
  /// N'allonge pas la session et n'en recrée pas une toute seule
  /// quand elle expire (le QR ne doit pas changer sans un appui).
  void poll() {
    final PhoneRemoteServer? server = _server;
    if (server == null || !server.isRunning) return;
    if (server.isExpired) {
      view = const RemoteView(phase: RemotePhase.expired);
      return;
    }
    _publishReady();
  }

  Future<void> restart() async {
    final String? ip = await _lanIp();
    if (ip == null) {
      await _server?.close();
      _server = null;
      view = const RemoteView(phase: RemotePhase.noLan);
      BlackBox.instance.info('REMOTE', 'pas de réseau local');
      return;
    }
    try {
      final PhoneRemoteServer? existing = _server;
      if (existing != null && existing.isRunning && existing.ip == ip) {
        existing.rotate();
        _publishReady();
        BlackBox.instance.info('REMOTE', 'nouveau code');
        return;
      }
      await existing?.close();
      final InternetAddress? addr = InternetAddress.tryParse(ip);
      if (addr == null) {
        view = const RemoteView(phase: RemotePhase.error);
        return;
      }
      // allowLoopback FALSE : un programme sur la box ne se fait pas
      // passer pour le téléphone via 127.0.0.1. Seule une adresse
      // privée (le Wi-Fi) est acceptée.
      _server = await PhoneRemoteServer.bind(
        addr,
        allowLoopback: false,
        onCommand: applyRemoteCommand,
      );
      _publishReady();
      BlackBox.instance.breadcrumb('Télécommande active');
    } catch (_) {
      view = const RemoteView(phase: RemotePhase.error);
      BlackBox.instance.warn('REMOTE', 'démarrage impossible');
    }
  }

  Future<void> userStop() async {
    await _server?.close();
    _server = null;
    view = const RemoteView(phase: RemotePhase.stopped);
    BlackBox.instance.info('REMOTE', 'coupée');
  }

  void _publishReady() {
    final PhoneRemoteServer? server = _server;
    if (server == null) return;
    view = RemoteView(
      phase: RemotePhase.ready,
      url: server.url,
      paired: server.isPaired,
      secondsLeft: server.secondsLeft,
    );
  }

  Future<String?> _lanIp() async {
    try {
      final List<NetworkInterface> list = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return pickLanIpv4(<LanIface>[
        for (final NetworkInterface n in list)
          LanIface(n.name, <String>[
            for (final InternetAddress a in n.addresses) a.address,
          ]),
      ]);
    } catch (_) {
      debugPrint('[remote] interfaces illisibles');
      return null;
    }
  }
}
