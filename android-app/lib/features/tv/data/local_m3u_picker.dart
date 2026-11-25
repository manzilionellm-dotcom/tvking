// =========================================================
//  local_m3u_picker.dart — Choisir un .m3u sur la box
// =========================================================
//  Ouvre le sélecteur de documents Android. Beaucoup de
//  boîtiers n'en ont pas : on répond « indisponible » et
//  l'écran propose de coller un lien. Aucun identifiant
//  n'est écrit ici.
// =========================================================

import 'package:flutter/services.dart';

enum LocalM3uPickStatus { ok, cancelled, unavailable, empty, tooBig }

class LocalM3uPick {
  const LocalM3uPick(this.status, {this.path});

  final LocalM3uPickStatus status;
  final String? path;

  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/device');

  static Future<LocalM3uPick> ask() async {
    try {
      final Object? raw = await _channel.invokeMethod<Object?>('pickLocalM3u');
      if (raw is! Map) return const LocalM3uPick(LocalM3uPickStatus.unavailable);
      final String status = (raw['status'] as String?) ?? 'unavailable';
      final String path = ((raw['path'] as String?) ?? '').trim();
      switch (status) {
        case 'ok':
          if (path.isEmpty) {
            return const LocalM3uPick(LocalM3uPickStatus.empty);
          }
          return LocalM3uPick(LocalM3uPickStatus.ok, path: path);
        case 'cancelled':
          return const LocalM3uPick(LocalM3uPickStatus.cancelled);
        case 'empty':
          return const LocalM3uPick(LocalM3uPickStatus.empty);
        case 'too_big':
          return const LocalM3uPick(LocalM3uPickStatus.tooBig);
        default:
          return const LocalM3uPick(LocalM3uPickStatus.unavailable);
      }
    } catch (_) {
      return const LocalM3uPick(LocalM3uPickStatus.unavailable);
    }
  }
}
