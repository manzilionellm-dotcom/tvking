// =========================================================
//  phone_remote_bus.dart — File des ordres du téléphone
// =========================================================
//  Le mini-serveur dépose un ordre. Le lecteur, s'il est
//  ouvert et si la fonction est allumée, le lit. Personne
//  d'autre n'agit : un ordre sans lecteur est simplement
//  oublié. Ça ne démarre pas un flux tout seul.
// =========================================================

import 'dart:async';

import '../domain/remote_command.dart';

class PhoneRemoteBus {
  PhoneRemoteBus._();
  static final PhoneRemoteBus instance = PhoneRemoteBus._();

  final StreamController<RemoteCommand> _controller =
      StreamController<RemoteCommand>.broadcast();

  Stream<RemoteCommand> get stream => _controller.stream;

  void add(RemoteCommand command) {
    if (_controller.isClosed) return;
    _controller.add(command);
  }
}
