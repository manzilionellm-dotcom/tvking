// =========================================================
//  player_interface.ts — Abstraction lecteur (interface commune)
// =========================================================
//  Cahier des charges §3 : "creer une couche d'abstraction lecteur
//  avec une implementation par plateforme derriere. Le reste de
//  l'app ne parle qu'a cette interface."
//
//  Implementations prevues :
//    - WebMediaPlayer  : <video> HTML5 + hls.js (Desktop, webOS, Tizen <video>)
//    - TizenAvPlayer   : API AVPlay native (Tizen, quand <video> ne suffit pas)
//    - ExoPlayerBridge : Android TV natif via JS bridge (Phase 2+)
//
//  L'abstraction reste minimaliste : on n'expose QUE les operations
//  reellement partagees par les 4 cibles. Tout ce qui est specifique
//  (drm Widevine, profil DLNA, etc.) reste dans l'implementation.
// =========================================================

/** Etat de lecture observable par l'UI. */
export type PlaybackState =
  | 'idle' // pas de media charge
  | 'loading' // open() en cours, premiere frame pas encore decode
  | 'playing' // lecture active
  | 'paused' // pause manuelle ou buffering
  | 'ended' // VOD finie
  | 'error'; // erreur fatale (codec, reseau, drm)

/** Resume d'une piste audio ou sous-titre. */
export interface MediaTrack {
  /** Identifiant opaque dependant de l'implementation (index, langue, etc.). */
  readonly id: string;
  /** Code de langue ISO 639-1/2 si disponible ("fr", "en", "spa"). */
  readonly language: string | null;
  /** Libelle affichable ("Français", "VO sous-titrée", etc.). */
  readonly label: string;
}

/** Erreur normalisee, pour que l'UI affiche un message homogene. */
export interface PlayerError {
  /**
   * Code court machine-friendly :
   *   - 'network'  : echec reseau (timeout, DNS, 4xx/5xx upstream)
   *   - 'codec'    : format non supporte par la plateforme
   *   - 'drm'      : licence refusee
   *   - 'unknown'  : non classifie
   */
  readonly code: 'network' | 'codec' | 'drm' | 'unknown';
  /** Detail technique non destine a l'utilisateur (logs / diagnostic). */
  readonly detail: string;
}

/** Callback abonne aux transitions d'etat. */
export type StateListener = (
  state: PlaybackState,
  error?: PlayerError,
) => void;

/**
 * Contrat minimal. Toutes les operations sont asynchrones et best-effort :
 * si la plateforme ne supporte pas une feature (pas de selection de piste
 * audio sur Tizen <video> par ex.), la methode resout sans erreur ET
 * un appel ulterieur a `getAudioTracks()` retournera une liste vide.
 */
export interface MediaPlayer {
  /**
   * Charge et demarre la lecture d'un flux.
   *
   * @param url       URL HTTP/HTTPS, peut etre .m3u8 / .ts / .mp4 / .mpd
   * @param hintMime  MIME indicatif optionnel ("application/x-mpegURL")
   */
  open(url: string, hintMime?: string): Promise<void>;

  /** Met en pause sans liberer le buffer. */
  pause(): Promise<void>;

  /** Reprend une lecture en pause. No-op si deja playing. */
  resume(): Promise<void>;

  /** Stop + dispose des ressources (revient en idle). */
  stop(): Promise<void>;

  /** Position courante en secondes. NaN si idle ou indeterminable. */
  currentTime(): number;

  /** Duree totale en secondes. NaN pour les flux LIVE sans fin connue. */
  duration(): number;

  /** Saut absolu — no-op sur LIVE. */
  seek(seconds: number): Promise<void>;

  /** Liste des pistes audio dispo. Tableau vide si non supporte. */
  getAudioTracks(): readonly MediaTrack[];

  /** Selectionne une piste audio par id. No-op si id inconnu. */
  setAudioTrack(id: string): Promise<void>;

  /** Liste des sous-titres dispo. Tableau vide si non supporte. */
  getSubtitleTracks(): readonly MediaTrack[];

  /** Selectionne un sous-titre par id, ou null pour les masquer. */
  setSubtitleTrack(id: string | null): Promise<void>;

  /** Etat de lecture courant. */
  getState(): PlaybackState;

  /**
   * Abonne un listener aux transitions d'etat. Retourne une fonction
   * a appeler pour se desabonner (pattern standard React useEffect).
   */
  onStateChange(listener: StateListener): () => void;

  /** Libere TOUTES les ressources. A appeler quand l'UI est demontee. */
  dispose(): void;
}
