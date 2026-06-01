// =========================================================
//  channel.ts — Modele de chaine IPTV
// =========================================================
//  Resultat du parsing M3U / Xtream. Immuable. Le minimum pour
//  qu'une chaine soit utilisable :
//    - url    : flux a jouer (.ts brut, .m3u8 HLS, .mp4...)
//    - name   : libelle affichable
//    - id     : identifiant stable (clef de cache, favoris)
//
//  Le reste est optionnel — beaucoup de playlists M3U publiques
//  manquent de logo ou de tvg-id.
// =========================================================

export interface Channel {
  /** Identifiant stable. M3U: tvg-id ou hash(url). Xtream: stream_id. */
  readonly id: string;

  /** Nom affichable. */
  readonly name: string;

  /** URL du flux (HTTP[S], .ts/.m3u8/.mp4). */
  readonly url: string;

  /** URL du logo, ou null si absent. */
  readonly logoUrl: string | null;

  /**
   * Categorie / groupe ("Sport", "Adulte", "Films FR"...). null si
   * la playlist n'en fournit pas. NE PAS confondre avec [genre] qui
   * serait deduit du nom dans un futur curator.
   */
  readonly group: string | null;

  /**
   * tvg-id (M3U) ou epg_channel_id (Xtream) — clef pour lier la
   * chaine a sa grille EPG XMLTV. null si pas d'EPG associee.
   */
  readonly epgId: string | null;

  /**
   * Position d'origine dans la playlist M3U. Utile pour preserver
   * l'ordre voulu par le fournisseur (chaines premium en tete, etc.).
   * 0-indexed.
   */
  readonly orderIndex: number;
}
