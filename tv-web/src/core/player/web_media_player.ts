// =========================================================
//  web_media_player.ts — Implementation hls.js + <video> HTML5
// =========================================================
//  Cible : navigateur desktop, Electron, et la plupart des
//  WebViews TV (webOS, Tizen recent, Android TV en WebView). Pour
//  Tizen ancien qui plante sur hls.js, on fournira un fallback
//  TizenAvPlayer dans un fichier separe.
//
//  Strategie de selection de techno :
//    1. URL .m3u8 ET hls.js supporte (Source Buffer API) -> hls.js
//    2. URL .m3u8 ET Safari/Tizen avec HLS natif -> <video src>
//    3. Sinon -> <video src> direct (MP4, .ts brut sur certaines TVs)
//
//  Limites connues qu'on documente :
//    - Pas de selection de pistes pour les .ts bruts dans <video>
//      vanilla — la plupart des TVs n'exposent pas l'API.
//    - DASH n'est pas pris en charge dans cette implementation
//      (besoin Shaka Player — Phase 2 si demande).
// =========================================================

import Hls, { ErrorTypes, type ErrorData } from 'hls.js';
import type {
  MediaPlayer,
  MediaTrack,
  PlaybackState,
  PlayerError,
  StateListener,
} from './player_interface.js';

export class WebMediaPlayer implements MediaPlayer {
  private readonly video: HTMLVideoElement;
  private hls: Hls | null = null;
  private state: PlaybackState = 'idle';
  private readonly listeners = new Set<StateListener>();
  private disposed = false;

  /**
   * @param video Element <video> deja monte dans le DOM. Le caller
   *              garde la responsabilite du layout — on ne styling
   *              rien ici.
   */
  constructor(video: HTMLVideoElement) {
    this.video = video;
    this.attachVideoEvents();
  }

  // ===========================================================
  //  Open / Pause / Resume / Stop
  // ===========================================================

  async open(url: string, _hintMime?: string): Promise<void> {
    this.assertNotDisposed();
    this.stop().catch(() => {}); // best-effort cleanup avant re-open
    this.setState('loading');

    const lower = url.toLowerCase();
    const isHls = lower.includes('.m3u8');

    if (isHls && Hls.isSupported()) {
      // Navigateur moderne + Source Buffer -> on bosse avec hls.js
      const hls = new Hls({
        // Comportement LIVE par defaut : pas de barre infinie.
        liveDurationInfinity: true,
        // Tolerance reseau plus genereuse pour les TVs / IPTV
        // (segments qui prennent 3-4s sur Wi-Fi medioce).
        manifestLoadingMaxRetry: 4,
        manifestLoadingRetryDelay: 1000,
        manifestLoadingMaxRetryTimeout: 10000,
        levelLoadingMaxRetry: 4,
        fragLoadingMaxRetry: 6,
      });
      this.hls = hls;
      hls.on(Hls.Events.ERROR, this.onHlsError);
      hls.loadSource(url);
      hls.attachMedia(this.video);
      try {
        await this.video.play();
      } catch (err) {
        // Autoplay refuse par le navigateur (cas desktop sans
        // interaction utilisateur). L'UI doit gerer le tap-to-play.
        this.emitError({
          code: 'unknown',
          detail: `autoplay refuse: ${stringifyError(err)}`,
        });
      }
      return;
    }

    // Pas de HLS, ou HLS natif support (Safari, certaines TVs) — on
    // passe par <video src=...>
    this.video.src = url;
    try {
      await this.video.play();
    } catch (err) {
      this.emitError({
        code: 'unknown',
        detail: `play() rejected: ${stringifyError(err)}`,
      });
    }
  }

  async pause(): Promise<void> {
    this.assertNotDisposed();
    this.video.pause();
  }

  async resume(): Promise<void> {
    this.assertNotDisposed();
    try {
      await this.video.play();
    } catch (err) {
      this.emitError({
        code: 'unknown',
        detail: `resume() rejected: ${stringifyError(err)}`,
      });
    }
  }

  async stop(): Promise<void> {
    this.video.pause();
    this.video.removeAttribute('src');
    try {
      this.video.load();
    } catch {
      // ignore — certaines TVs anciennes throw sur load() apres dispose
    }
    if (this.hls) {
      try {
        this.hls.off(Hls.Events.ERROR, this.onHlsError);
        this.hls.destroy();
      } catch {
        // ignore
      }
      this.hls = null;
    }
    this.setState('idle');
  }

  // ===========================================================
  //  Position / duration / seek
  // ===========================================================

  currentTime(): number {
    return Number.isFinite(this.video.currentTime)
      ? this.video.currentTime
      : Number.NaN;
  }

  duration(): number {
    const d = this.video.duration;
    return Number.isFinite(d) ? d : Number.NaN;
  }

  async seek(seconds: number): Promise<void> {
    if (!Number.isFinite(seconds)) return;
    if (!Number.isFinite(this.video.duration)) {
      // LIVE — seek refuse par convention.
      return;
    }
    this.video.currentTime = Math.max(0, Math.min(seconds, this.video.duration));
  }

  // ===========================================================
  //  Tracks (best-effort selon la plateforme)
  // ===========================================================

  getAudioTracks(): readonly MediaTrack[] {
    if (!this.hls) return [];
    return this.hls.audioTracks.map((t) => ({
      id: String(t.id),
      language: t.lang ?? null,
      label: t.name ?? t.lang ?? `Audio ${t.id}`,
    }));
  }

  async setAudioTrack(id: string): Promise<void> {
    if (!this.hls) return;
    const idx = this.hls.audioTracks.findIndex((t) => String(t.id) === id);
    if (idx >= 0) {
      this.hls.audioTrack = idx;
    }
  }

  getSubtitleTracks(): readonly MediaTrack[] {
    if (!this.hls) return [];
    return this.hls.subtitleTracks.map((t) => ({
      id: String(t.id),
      language: t.lang ?? null,
      label: t.name ?? t.lang ?? `Sous-titre ${t.id}`,
    }));
  }

  async setSubtitleTrack(id: string | null): Promise<void> {
    if (!this.hls) return;
    if (id === null) {
      this.hls.subtitleTrack = -1;
      return;
    }
    const idx = this.hls.subtitleTracks.findIndex((t) => String(t.id) === id);
    if (idx >= 0) {
      this.hls.subtitleTrack = idx;
    }
  }

  // ===========================================================
  //  State + listeners
  // ===========================================================

  getState(): PlaybackState {
    return this.state;
  }

  onStateChange(listener: StateListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.detachVideoEvents();
    this.listeners.clear();
    void this.stop();
  }

  // ===========================================================
  //  Internals
  // ===========================================================

  private attachVideoEvents(): void {
    this.video.addEventListener('playing', this.onPlaying);
    this.video.addEventListener('pause', this.onPause);
    this.video.addEventListener('ended', this.onEnded);
    this.video.addEventListener('error', this.onVideoError);
    this.video.addEventListener('waiting', this.onWaiting);
  }

  private detachVideoEvents(): void {
    this.video.removeEventListener('playing', this.onPlaying);
    this.video.removeEventListener('pause', this.onPause);
    this.video.removeEventListener('ended', this.onEnded);
    this.video.removeEventListener('error', this.onVideoError);
    this.video.removeEventListener('waiting', this.onWaiting);
  }

  private readonly onPlaying = (): void => this.setState('playing');
  private readonly onPause = (): void => {
    // Si on est en train de stopper, pas la peine de remettre 'paused'
    if (this.state !== 'idle') this.setState('paused');
  };
  private readonly onEnded = (): void => this.setState('ended');
  private readonly onWaiting = (): void => {
    // 'waiting' = buffering. On reste en 'playing' pour l'UI car le
    // buffering est invisible sur la plupart des UX TV.
  };

  private readonly onVideoError = (): void => {
    const err = this.video.error;
    this.emitError({
      code: 'codec',
      detail: err ? `${err.code}: ${err.message}` : 'unknown video error',
    });
  };

  private readonly onHlsError = (
    _evt: unknown,
    data: ErrorData,
  ): void => {
    if (!data.fatal) return;
    const code: PlayerError['code'] =
      data.type === ErrorTypes.NETWORK_ERROR
        ? 'network'
        : data.type === ErrorTypes.MEDIA_ERROR
          ? 'codec'
          : 'unknown';
    this.emitError({
      code,
      detail: `${data.type}: ${data.details}`,
    });
  };

  private setState(next: PlaybackState, error?: PlayerError): void {
    this.state = next;
    for (const l of this.listeners) {
      try {
        l(next, error);
      } catch {
        // un listener defaillant ne doit pas bloquer les autres
      }
    }
  }

  private emitError(error: PlayerError): void {
    this.setState('error', error);
  }

  private assertNotDisposed(): void {
    if (this.disposed) {
      throw new Error('WebMediaPlayer used after dispose()');
    }
  }
}

function stringifyError(e: unknown): string {
  if (e instanceof Error) return e.message;
  if (typeof e === 'string') return e;
  try {
    return JSON.stringify(e);
  } catch {
    return 'unknown';
  }
}
