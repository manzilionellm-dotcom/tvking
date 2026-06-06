"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import ChannelLogo from "./ChannelLogo";
import { pushRecent, useFavorites } from "../lib/favorites";
import { nowNextFor } from "../lib/client-source";
import type { Channel } from "../lib/iptv-types";
import type { NowNextLite } from "../lib/view-types";

/*
 * NOVA+ live player — the heart of the TiViMate experience, TV-only.
 *
 * Remote (D-pad) behaviour, when no overlay is open:
 *   Up / Down ............ zap to previous / next channel (instant)
 *   OK / Enter ........... toggle the now/next info bar
 *   Left / Right / "L" ... open the channel-list overlay
 *   "F" .................. toggle favorite for the current channel
 *   Back / Esc ........... close overlay, else leave the player
 *
 * Playback uses hls.js for HLS (Android-TV WebView / Chromium have no native
 * HLS), native HLS where the browser supports it, and a direct <video src> for
 * progressive/TS streams.
 */

const INFO_TIMEOUT = 5000;

function progress(nn: NowNextLite | null): number {
  if (!nn || nn.stop <= nn.start) return 0;
  return Math.min(1, Math.max(0, (Date.now() - nn.start) / (nn.stop - nn.start)));
}
function hhmm(ms: number) {
  const d = new Date(ms);
  return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
}

export default function Player({
  channels,
  startId,
  initialNowNext,
}: {
  channels: Channel[];
  startId: string;
  initialNowNext: NowNextLite | null;
}) {
  const router = useRouter();
  const videoRef = useRef<HTMLVideoElement>(null);
  const { favoriteSet, toggle } = useFavorites();

  const startIndex = Math.max(0, channels.findIndex((c) => c.id === startId));
  const [index, setIndex] = useState(startIndex);
  const [showInfo, setShowInfo] = useState(true);
  const [showList, setShowList] = useState(false);
  const [loading, setLoading] = useState(true);
  const infoTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const channel = channels[index];

  // now/next is a pure sync read of the loaded EPG store — derive, don't store.
  const nn: NowNextLite | null = useMemo(
    () => (channel ? nowNextFor(channel.id) ?? initialNowNext : null),
    [channel, initialNowNext]
  );

  const flashInfo = useCallback(() => {
    setShowInfo(true);
    if (infoTimer.current) clearTimeout(infoTimer.current);
    infoTimer.current = setTimeout(() => setShowInfo(false), INFO_TIMEOUT);
  }, []);

  // Load the stream whenever the channel changes (hls.js with fallbacks).
  //
  // Réseaux difficiles (ex. connexions lentes ou instables) : on PRÉFÈRE le
  // RETARD à la COUPURE. On bufferise généreusement pour se constituer de
  // l'avance, on autorise le direct à prendre du retard (jusqu'à ~60 s) au lieu
  // de coller au bord et de caler, et on réessaie / restaure automatiquement
  // sur erreur réseau ou média. Résultat : l'image gèle un instant puis repart,
  // au lieu de "casser" — utilisable même là où la connexion est mauvaise.
  useEffect(() => {
    const video = videoRef.current;
    if (!video || !channel) return;
    setLoading(true);
    pushRecent(channel.id);

    let destroyed = false;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let hls: any = null;
    let recover = 0; // récupérations "dernier recours" en cours (borné)
    let srcTries = 0; // rechargements de la source en lecture native (borné)
    let retryTimer: ReturnType<typeof setTimeout> | null = null;
    const url = channel.url;
    const isHls = /\.m3u8(\?|$)/i.test(url);
    const canNative = video.canPlayType("application/vnd.apple.mpegurl") !== "";

    async function attach(el: HTMLVideoElement) {
      if (isHls && !canNative) {
        const mod = await import("hls.js");
        const Hls = mod.default;
        if (destroyed) return;
        if (Hls.isSupported()) {
          hls = new Hls({
            enableWorker: true,
            // On NE colle PAS au direct : la basse latence cale dès que ça faiblit.
            lowLatencyMode: false,
            // --- Buffer généreux : de l'avance pour absorber les coupures ---
            maxBufferLength: 60, // vise ~60 s d'avance quand le débit le permet
            maxMaxBufferLength: 120, // plafond dur
            backBufferLength: 30,
            // --- Direct : tolère de prendre du retard plutôt que de caler ---
            liveSyncDuration: 10, // démarre ~10 s derrière le bord du direct
            liveMaxLatencyDuration: 60, // tolère jusqu'à ~60 s de retard
            liveDurationInfinity: true,
            // --- Réessais réseau agressifs (fragments + playlists) ---
            fragLoadingMaxRetry: 8,
            fragLoadingRetryDelay: 1000,
            fragLoadingMaxRetryTimeout: 64000,
            manifestLoadingMaxRetry: 6,
            manifestLoadingRetryDelay: 1000,
            levelLoadingMaxRetry: 6,
            levelLoadingRetryDelay: 1000,
          });
          hls.loadSource(url);
          hls.attachMedia(el);
          hls.on(Hls.Events.MANIFEST_PARSED, () => el.play().catch(() => {}));
          // Un fragment vient d'être mis en buffer → on est reparti : on remet
          // le compteur de récupération à zéro.
          hls.on(Hls.Events.FRAG_BUFFERED, () => {
            recover = 0;
          });
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          hls.on(Hls.Events.ERROR, (_evt: unknown, data: any) => {
            if (destroyed || !data?.fatal) return; // non-fatal : hls gère seul
            if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
              // Playlist/segment injoignable : on relance le chargement (petit
              // délai) au lieu d'abandonner.
              if (retryTimer) clearTimeout(retryTimer);
              retryTimer = setTimeout(() => {
                if (!destroyed && hls) hls.startLoad();
              }, 1500);
            } else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
              hls.recoverMediaError();
            } else if (recover++ < 4) {
              // Dernier recours, borné + back-off : on recrée depuis la source.
              if (retryTimer) clearTimeout(retryTimer);
              retryTimer = setTimeout(() => {
                if (destroyed) return;
                try {
                  hls.destroy();
                } catch {
                  /* déjà détruit */
                }
                hls = null;
                void attach(el);
              }, 2000 * recover);
            }
          });
          return;
        }
      }
      // Lecture native (HLS Safari/iOS) ou flux progressif : on recharge la
      // source sur erreur transitoire, avec un nombre d'essais borné + back-off.
      el.src = url;
      el.play().catch(() => {});
      el.onerror = () => {
        if (destroyed || srcTries++ >= 4) return;
        if (retryTimer) clearTimeout(retryTimer);
        retryTimer = setTimeout(() => {
          if (destroyed) return;
          el.src = url;
          el.play().catch(() => {});
        }, 1500 * srcTries);
      };
    }
    attach(video);

    return () => {
      destroyed = true;
      if (retryTimer) clearTimeout(retryTimer);
      if (hls) hls.destroy();
      video.onerror = null;
      video.removeAttribute("src");
      video.load();
    };
  }, [channel]);

  const zap = useCallback(
    (delta: number) => {
      setIndex((i) => (i + delta + channels.length) % channels.length);
      flashInfo();
    },
    [channels.length, flashInfo]
  );

  const goTo = useCallback(
    (i: number) => {
      setIndex(i);
      setShowList(false);
      flashInfo();
    },
    [flashInfo]
  );

  // Remote key handling (capture phase so we can pre-empt the global SpatialNav
  // when zapping with no overlay open).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const overlayOpen = showList;
      switch (e.key) {
        case "ArrowUp":
          if (!overlayOpen) {
            e.preventDefault();
            e.stopImmediatePropagation();
            zap(-1);
          }
          break;
        case "ArrowDown":
          if (!overlayOpen) {
            e.preventDefault();
            e.stopImmediatePropagation();
            zap(1);
          }
          break;
        case "ArrowRight":
        case "ArrowLeft":
        case "l":
        case "L":
          if (!overlayOpen) {
            e.preventDefault();
            e.stopImmediatePropagation();
            setShowList(true);
          }
          break;
        case "Enter":
        case " ":
          if (!overlayOpen) {
            e.preventDefault();
            setShowInfo((s) => !s);
            flashInfo();
          }
          break;
        case "f":
        case "F":
          if (channel) toggle(channel.id);
          break;
        case "Backspace":
        case "Escape":
          e.preventDefault();
          if (showList) setShowList(false);
          else router.push("/");
          break;
      }
    }
    window.addEventListener("keydown", onKey, { capture: true });
    return () => window.removeEventListener("keydown", onKey, { capture: true });
  }, [showList, zap, flashInfo, toggle, channel, router]);

  // Show the info bar briefly on mount / channel change.
  useEffect(() => {
    flashInfo();
    return () => {
      if (infoTimer.current) clearTimeout(infoTimer.current);
    };
  }, [flashInfo]);

  if (!channel) {
    return (
      <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black text-[var(--text-medium)]">
        Chaîne introuvable.
      </div>
    );
  }

  const fav = favoriteSet.has(channel.id);
  const pct = progress(nn);

  return (
    <div className="fixed inset-0 z-[60] overflow-hidden bg-black">
      <video
        ref={videoRef}
        className="absolute inset-0 h-full w-full bg-black object-contain"
        autoPlay
        playsInline
        onPlaying={() => setLoading(false)}
        onWaiting={() => setLoading(true)}
      />

      {loading && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="h-[3rem] w-[3rem] animate-spin rounded-full border-[0.3rem] border-white/20 border-t-[var(--accent)]" />
        </div>
      )}

      {/* now/next info bar */}
      {showInfo && (
        <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/90 via-black/55 to-transparent px-[var(--safe-x)] pb-[var(--safe-y)] pt-[6rem]">
          <div className="flex items-end gap-[1.2rem]">
            <ChannelLogo src={channel.logo} name={channel.name} size="4.4rem" />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-[0.8rem]">
                <span className="rounded-[0.35rem] bg-[var(--live)] px-[0.5rem] py-[0.1rem] text-[0.85rem] font-bold tracking-wide text-white">
                  ● DIRECT
                </span>
                <span className="text-[1rem] font-bold tabular-nums text-[var(--text-medium)]">
                  {channel.number}
                </span>
                <h1 className="truncate text-[1.7rem] font-extrabold text-white">{channel.name}</h1>
                {fav && <span className="text-[1.2rem] text-[var(--accent-strong)]">★</span>}
              </div>
              {nn ? (
                <>
                  <p className="mt-[0.2rem] truncate text-[1.2rem] text-[var(--text-high)]">
                    {hhmm(nn.start)} · {nn.title}
                  </p>
                  <div className="mt-[0.5rem] h-[0.3rem] w-[min(40rem,60%)] overflow-hidden rounded-full bg-white/20">
                    <div className="h-full" style={{ width: `${pct * 100}%`, background: "var(--accent-grad)" }} />
                  </div>
                  {nn.nextTitle && (
                    <p className="mt-[0.4rem] truncate text-[1rem] text-[var(--text-medium)]">
                      À suivre · {nn.nextTitle}
                    </p>
                  )}
                </>
              ) : (
                <p className="mt-[0.2rem] text-[1.05rem] text-[var(--text-medium)]">{channel.group}</p>
              )}
            </div>
            <p className="hidden shrink-0 text-right text-[0.9rem] leading-relaxed text-[var(--text-disabled)] lg:block">
              ▲▼ Chaîne · ◀▶ Liste<br />
              OK Infos · F Favori · Retour Quitter
            </p>
          </div>
        </div>
      )}

      {/* Channel list overlay */}
      {showList && (
        <ChannelListOverlay
          channels={channels}
          currentIndex={index}
          favoriteSet={favoriteSet}
          onPick={goTo}
          onClose={() => setShowList(false)}
        />
      )}
    </div>
  );
}

function ChannelListOverlay({
  channels,
  currentIndex,
  favoriteSet,
  onPick,
  onClose,
}: {
  channels: Channel[];
  currentIndex: number;
  favoriteSet: Set<string>;
  onPick: (i: number) => void;
  onClose: () => void;
}) {
  // Focus the current channel when the overlay opens.
  useEffect(() => {
    const el = document.getElementById(`ov-${currentIndex}`);
    el?.focus();
  }, [currentIndex]);

  return (
    <div className="absolute inset-y-0 left-0 z-10 flex w-[30rem] max-w-[80vw] flex-col bg-[var(--bg)]/96 py-[var(--safe-y)] pl-[var(--safe-x)] pr-[1rem] backdrop-blur">
      <div className="mb-[0.8rem] flex items-center justify-between pr-[0.4rem]">
        <h2 className="text-[1.2rem] font-bold text-[var(--text-high)]">Chaînes</h2>
        <span className="text-[0.9rem] text-[var(--text-disabled)]">{channels.length}</span>
      </div>
      <div className="no-scrollbar flex flex-1 flex-col gap-[0.25rem] overflow-y-auto pr-[0.4rem]">
        {channels.map((c, i) => (
          <button
            key={c.id}
            id={`ov-${i}`}
            data-focusable
            onClick={() => onPick(i)}
            onKeyDown={(e) => {
              if (e.key === "Backspace" || e.key === "Escape") {
                e.preventDefault();
                onClose();
              }
            }}
            className={`focusable flex items-center gap-[0.7rem] rounded-[var(--radius)] px-[0.7rem] py-[0.55rem] text-left ${
              i === currentIndex ? "bg-[rgba(61,169,252,0.14)]" : ""
            }`}
          >
            <span className="w-[2rem] shrink-0 text-right text-[0.9rem] font-bold tabular-nums text-[var(--text-disabled)]">
              {c.number}
            </span>
            <ChannelLogo src={c.logo} name={c.name} size="2.4rem" />
            <span className="min-w-0 flex-1 truncate text-[1.05rem] font-semibold text-[var(--text-high)]">
              {c.name}
            </span>
            {favoriteSet.has(c.id) && <span className="text-[0.95rem] text-[var(--accent-strong)]">★</span>}
          </button>
        ))}
      </div>
    </div>
  );
}
