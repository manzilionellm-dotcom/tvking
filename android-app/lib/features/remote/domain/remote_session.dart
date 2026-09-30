// =========================================================
//  remote_session.dart — Un appairage, un téléphone, une fin
// =========================================================
//  Règles (toutes testées) :
//    1. Tant que personne n'a appairé, les commandes sont refusées.
//    2. Le PREMIER téléphone qui appairé gagne. Le suivant est refusé
//       jusqu'au prochain QR (qui change le jeton).
//    3. À l'heure d'expiration, même le bon téléphone est refusé.
//       Envoyer des touches ne recule pas l'heure.
// =========================================================

import 'remote_token.dart';

class RemoteSession {
  RemoteSession({
    required this.token,
    required DateTime createdAt,
    required DateTime Function() clock,
    this.ttl = kRemoteSessionTtl,
  })  : _createdAt = createdAt,
        _clock = clock;

  /// Nouvelle session : nouveau jeton, aucun téléphone.
  factory RemoteSession.issue({
    required DateTime Function() clock,
    Duration ttl = kRemoteSessionTtl,
    String Function()? tokenFactory,
  }) {
    return RemoteSession(
      token: (tokenFactory ?? newRemoteToken)(),
      createdAt: clock(),
      clock: clock,
      ttl: ttl,
    );
  }

  final String token;
  final Duration ttl;
  final DateTime _createdAt;
  final DateTime Function() _clock;

  String? _phone;

  DateTime get expiresAt => _createdAt.add(ttl);

  bool get isExpired => !_clock().isBefore(expiresAt);

  int get secondsLeft {
    final int s = expiresAt.difference(_clock()).inSeconds;
    return s < 0 ? 0 : s;
  }

  /// Vrai seulement après un [pairNewPhone] réussi et non expiré.
  bool get isPaired => _phone != null && !isExpired;

  /// Le cookie présenté est-il celui du téléphone appairé ?
  bool matches(String? presented) {
    final String? phone = _phone;
    if (phone == null || presented == null || isExpired) return false;
    return constantTimeEquals(phone, presented);
  }

  /// Appairage. Renvoie le secret à mettre dans le cookie, ou null
  /// si la session est morte OU si un téléphone est déjà là.
  ///
  /// À appeler SANS `await` entre le test et l'écriture : Dart exécute
  /// une seule chose à la fois tant qu'on n'attend pas, donc deux
  /// téléphones ne peuvent pas gagner ensemble.
  String? pairNewPhone(String secret) {
    if (isExpired || _phone != null) return null;
    if (secret.isEmpty) return null;
    _phone = secret;
    return secret;
  }
}
