// =========================================================
//  cast_url_resolver.dart — URL de cast alignée sur le lecteur
// =========================================================
//  TERRAIN (2026-07-10, panel thekung) : le lecteur du téléphone
//  applique le « format mémorisé » Xtream (p.ex. `live:ts` →
//  ré-écriture `host/U/P/ID.ts` → `host/live/U/P/ID.ts`) AVANT
//  d'ouvrir le flux — mais le chemin CAST partait avec l'URL BRUTE de
//  la playlist. Sur les panels qui exigent le préfixe `/live/`, le
//  pré-vol du cast répondait 404 (page HTML) et les 8/8 casts
//  échouaient alors que la même chaîne jouait très bien sur le
//  téléphone.
//
//  Ce résolveur reproduit la logique du lecteur (video_player_screen) :
//    - format gagnant mémorisé par source (XtreamUrlFormatStore),
//    - garde anti-saturation : un format HLS mémorisé pour du LIVE est
//      ignoré (multi-connexions → écran noir sur les comptes
//      « 1 connexion », terrain 2026-07-09).
//  Le cœur est PUR (resolveWith) pour être testable sans base ni
//  repository ; resolve(Channel) fait la plomberie singletons.
//
//  Le repli « cascade de variantes quand le pré-vol échoue » vit, lui,
//  dans CastManager._castToInner : il couvre AUSSI les entrées sans
//  Channel (picker « flux maintenant »).
// =========================================================

import '../../channels/domain/channel.dart';
import '../../player/data/stream_blocked_fallback.dart';
import '../../player/data/xtream_url_variants.dart';
import '../../playlists/data/xtream_url_format_store.dart';
import '../../playlists/domain/playlist.dart' as pl;

class CastUrlResolver {
  /// URL à donner au CastManager pour [channel] : le format Xtream
  /// mémorisé de sa source, appliqué comme le fait le lecteur. Sans
  /// source Xtream identifiable ou sans format mémorisé, l'URL brute
  /// part telle quelle (la cascade de secours du CastManager tranchera).
  static Future<String> resolve(Channel channel) async {
    final pl.Playlist? src = StreamBlockedFallback.xtreamPlaylistFor(channel);
    final int? playlistId = src?.id;
    if (playlistId == null) return channel.streamUrl;
    final XtreamContentType type =
        StreamBlockedFallback.contentTypeOf(channel);
    final String? code = await XtreamUrlFormatStore.instance
        .winningFormat(playlistId, type);
    return resolveWith(
      rawUrl: channel.streamUrl,
      type: type,
      memorizedCode: code,
    );
  }

  /// Cœur PUR : applique [memorizedCode] à [rawUrl] avec les mêmes
  /// gardes que le lecteur. Renvoie [rawUrl] si rien n'est applicable.
  static String resolveWith({
    required String rawUrl,
    required XtreamContentType type,
    required String? memorizedCode,
  }) {
    if (memorizedCode == null) return rawUrl;
    // AUTO-CORRECTIF (terrain 2026-07-09) : un format HLS mémorisé pour
    // du LIVE ouvre plusieurs connexions (playlist repollée + segments)
    // et sature les comptes « max 1 connexion » — on l'ignore, comme le
    // lecteur.
    final bool hlsLiveMemorized =
        type == XtreamContentType.live && memorizedCode.contains('m3u8');
    if (hlsLiveMemorized) return rawUrl;
    return XtreamUrlVariants.applyFormat(rawUrl, memorizedCode) ?? rawUrl;
  }
}
