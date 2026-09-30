// =========================================================
//  remote_command.dart — Ordres que le téléphone peut envoyer
// =========================================================
//  Liste fermée. Un mot inconnu est ignoré : le téléphone ne
//  peut pas inventer une commande qui ouvrirait un flux.
// =========================================================

enum RemoteCommand { up, down, left, right, ok, back, playPause }

abstract final class RemoteCommands {
  static RemoteCommand? parse(String? raw) {
    switch (raw) {
      case 'up':
        return RemoteCommand.up;
      case 'down':
        return RemoteCommand.down;
      case 'left':
        return RemoteCommand.left;
      case 'right':
        return RemoteCommand.right;
      case 'ok':
        return RemoteCommand.ok;
      case 'back':
        return RemoteCommand.back;
      case 'play':
        return RemoteCommand.playPause;
      default:
        return null;
    }
  }
}
