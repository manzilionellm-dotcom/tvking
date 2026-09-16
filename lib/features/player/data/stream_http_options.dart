// =========================================================
//  stream_http_options.dart — En-têtes HTTP portés par le M3U
// =========================================================
//  Certaines playlists (VLC / Kodi) collent User-Agent, Referer et
//  Cookie sur la chaîne via `#EXTVLCOPT:` / `#KODIPROP:`. Sans ces
//  en-têtes, le serveur sert une page d'erreur et l'écran reste noir.
//
//  On ne les met PAS sur [Channel] : ça ripple SQLite (nouvelle
//  colonne, migration, tous les SELECT). Ce singleton les mémorise
//  par URL de flux, en mémoire, pour la session. Le parseur M3U
//  appelle [remember] ; le lecteur (plus tard) lira [headersFor].
// =========================================================

import 'package:flutter/foundation.dart';

/// Dépôt des en-têtes HTTP optionnels d'un flux, indexés par URL.
class StreamHttpOptions {
  StreamHttpOptions._();
  static final StreamHttpOptions instance = StreamHttpOptions._();

  final Map<String, Map<String, String>> _byUrl =
      <String, Map<String, String>>{};

  /// Mémorise [headers] pour [streamUrl]. Écrase une entrée précédente
  /// (même URL vue deux fois dans la playlist : la dernière gagne).
  void remember(String streamUrl, Map<String, String> headers) {
    final String url = streamUrl.trim();
    if (url.isEmpty || headers.isEmpty) return;
    _byUrl[url] = Map<String, String>.unmodifiable(
      Map<String, String>.from(headers),
    );
  }

  /// En-têtes connus pour [streamUrl], ou `null` s'il n'y en a pas.
  Map<String, String>? headersFor(String streamUrl) =>
      _byUrl[streamUrl.trim()];

  /// Rapatrie un lot (retour d'isolate [M3uParser.parseInBackground]).
  void importAll(Map<String, Map<String, String>> headers) {
    headers.forEach(remember);
  }

  /// Instantané (passage isolate → isolate principal).
  Map<String, Map<String, String>> exportAll() =>
      Map<String, Map<String, String>>.from(_byUrl);

  @visibleForTesting
  void forgetAll() => _byUrl.clear();
}
