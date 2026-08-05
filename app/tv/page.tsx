"use client";

import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import Player from "../components/Player";
import type { Art, MediaItem } from "../lib/data";
import { groupChannels, parseM3U, verifyUrl, type Channel } from "../lib/m3u";
import { loadPlaylist, savePlaylist, withChannels } from "../lib/playlist";

/*
 * "TV en direct" — the IPTV heart of the app. No content ships with TV King
 * (per the CGU): the user pastes their own M3U playlist. Every link is
 * verified before it is offered for playback — a bad link is flagged with a
 * reason, never sent to the player, so nothing can ever hang on it.
 */

/* Rotating gradient swatches for channel art (no binary assets, like data.ts). */
const PALETTE: Art[] = [
  { from: "#1f3a5f", to: "#0c1622" },
  { from: "#3a2b5f", to: "#140f24" },
  { from: "#244a3a", to: "#0c1a14" },
  { from: "#5f3a2b", to: "#241310" },
  { from: "#5f2b3a", to: "#241019" },
  { from: "#244a4a", to: "#0c1a1a" },
];

const DEMO_M3U = `#EXTM3U
#EXTINF:-1 group-title="Test",Chaîne Test
https://demo.tvking.app/test/index.m3u8
#EXTINF:-1 group-title="Sport",Sport Royal 1
https://demo.tvking.app/sport1/index.m3u8
#EXTINF:-1 group-title="Sport",Sport Royal 2
https://demo.tvking.app/sport2/index.m3u8
#EXTINF:-1 group-title="Cinéma",Ciné Couronne
https://demo.tvking.app/cine/index.m3u8
#EXTINF:-1 group-title="Découverte",Monde & Nature
https://demo.tvking.app/nature/index.m3u8`;

/* The playlist store only changes through this page, never underneath it. */
const noSubscription = () => () => {};

function channelAsItem(ch: Channel, index: number): MediaItem {
  return {
    id: ch.id,
    title: ch.name,
    art: PALETTE[index % PALETTE.length],
    live: "live",
    league: ch.group,
  };
}

function ImportForm({ onLoad }: { onLoad: (channels: Channel[]) => void }) {
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);

  const load = (source: string) => {
    const channels = parseM3U(source);
    if (channels.length === 0) {
      setError("Aucune chaîne trouvée dans ce texte. Collez une playlist au format M3U (#EXTM3U / #EXTINF).");
      return;
    }
    onLoad(channels);
  };

  return (
    <section className="max-w-[46rem]">
      <p className="mb-[1rem] text-[1.25rem] text-[var(--text-medium)]">
        TV King ne fournit aucune chaîne : collez votre propre playlist M3U ci-dessous.
        Chaque lien sera vérifié avant lecture — un lien invalide est signalé, jamais
        d&apos;attente sans fin.
      </p>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        data-focusable
        rows={8}
        spellCheck={false}
        placeholder={"#EXTM3U\n#EXTINF:-1 group-title=\"Sport\",Ma chaîne\nhttps://exemple.com/flux.m3u8"}
        className="focusable mb-[1rem] w-full rounded-[var(--radius)] bg-[var(--surface-2)] p-[1rem] font-mono text-[1rem] text-[var(--text-high)] placeholder:text-[var(--text-disabled)]"
        aria-label="Playlist M3U"
      />
      {error && (
        <p className="mb-[1rem] rounded-[var(--radius)] bg-[var(--live)]/15 px-[1rem] py-[0.7rem] text-[1.05rem] font-semibold text-[var(--live)]">
          {error}
        </p>
      )}
      <div className="flex flex-wrap gap-[0.9rem]">
        <button
          data-focusable
          data-focus-default
          onClick={() => load(text)}
          className="focusable rounded-[var(--radius)] px-[1.5rem] py-[0.8rem] text-[1.2rem] font-bold text-black"
          style={{ background: "var(--gold-grad)" }}
        >
          Charger ma playlist
        </button>
        <button
          data-focusable
          onClick={() => load(DEMO_M3U)}
          className="focusable rounded-[var(--radius)] bg-white/12 px-[1.4rem] py-[0.8rem] text-[1.15rem] font-semibold text-[var(--text-high)]"
        >
          Essayer avec la playlist de démonstration
        </button>
      </div>
    </section>
  );
}

function ChannelCard({
  channel,
  index,
  onPlay,
}: {
  channel: Channel;
  index: number;
  onPlay: () => void;
}) {
  const check = verifyUrl(channel.url);
  const art = PALETTE[index % PALETTE.length];

  return (
    <button
      data-focusable
      onClick={check.ok ? onPlay : undefined}
      disabled={!check.ok}
      className="card focusable group relative block w-[20rem] shrink-0 cursor-pointer text-left disabled:cursor-not-allowed disabled:opacity-60"
      aria-label={channel.name}
    >
      <div
        className="relative aspect-video w-full overflow-hidden rounded-[var(--radius)] ring-1 ring-[var(--hairline)]"
        style={{ background: `linear-gradient(140deg, ${art.from}, ${art.to})` }}
      >
        <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-white/12 to-transparent opacity-60" />
        <div className="absolute inset-0 flex items-center justify-center px-[1rem] text-center text-[1.2rem] font-bold text-white">
          {channel.name}
        </div>
        {/* Link verification badge — the promised pre-playback check. */}
        <div className="absolute left-[0.6rem] top-[0.6rem]">
          {check.ok ? (
            <span className="rounded-md bg-[var(--sport)]/90 px-[0.6rem] py-[0.2rem] text-[0.8rem] font-bold uppercase tracking-wider text-black">
              ✓ Lien vérifié
            </span>
          ) : (
            <span className="rounded-md bg-[var(--live)]/90 px-[0.6rem] py-[0.2rem] text-[0.8rem] font-bold uppercase tracking-wider text-white">
              ✕ {check.reason}
            </span>
          )}
        </div>
      </div>
      <div className="mt-[0.6rem] px-[0.1rem]">
        <h3 className="truncate text-[1.05rem] font-semibold text-[var(--text-high)]">{channel.name}</h3>
        <p className="mt-[0.2rem] truncate text-[0.85rem] text-[var(--text-medium)]">
          {check.ok ? "Prêt à lire — démarrage immédiat" : "Lecture bloquée : corrigez le lien"}
        </p>
      </div>
    </button>
  );
}

export default function TvPage() {
  // Hydration-safe read of the persisted playlist (server snapshot: null raw).
  const persisted = useSyncExternalStore(
    noSubscription,
    () => (typeof window === "undefined" ? null : window.localStorage.getItem("tvking.v1.playlist")),
    () => null
  );
  const [session, setSession] = useState<Channel[] | null>(null);
  const [nowPlaying, setNowPlaying] = useState<{ ch: Channel; index: number } | null>(null);
  /* True when opening the player pushed a history entry (see openPlayer). */
  const pushedHistoryRef = useRef(false);

  const channels = useMemo(
    () => session ?? (persisted !== null ? loadPlaylist().channels : []),
    [session, persisted]
  );
  const hasPlaylist = channels.length > 0;
  const playerOpen = nowPlaying !== null;

  /*
   * Sur un box TV, la touche Retour de la télécommande déclenche history.back()
   * du WebView. Le lecteur n'étant qu'une surcouche (aucune navigation), sans
   * entrée d'historique à consommer, ce back ferme l'application Android
   * elle-même — c'était la fermeture systématique au changement de chaîne.
   * On pousse donc une entrée à l'ouverture (en dupliquant l'état courant du
   * routeur Next pour ne pas le dérégler), et popstate referme le lecteur.
   */
  const openPlayer = (ch: Channel, index: number) => {
    if (!playerOpen) {
      pushedHistoryRef.current = false;
      try {
        window.history.pushState(window.history.state, "");
        pushedHistoryRef.current = true;
      } catch {
        // pushState indisponible : le lecteur s'ouvre quand même, la touche
        // Retour retombera sur le comportement natif.
      }
    }
    setNowPlaying({ ch, index });
  };

  useEffect(() => {
    if (!playerOpen) return;
    const onPop = () => setNowPlaying(null);
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, [playerOpen]);

  const exitPlayer = useCallback(() => {
    // Consume the entry we pushed so history stays balanced; popstate then
    // closes the player. Without a pushed entry, close directly.
    if (pushedHistoryRef.current) {
      pushedHistoryRef.current = false;
      window.history.back();
    } else {
      setNowPlaying(null);
    }
  }, []);

  /* CH+/CH- : zap vers la chaîne lisible suivante/précédente, en boucle. */
  const zap = useCallback(
    (delta: 1 | -1) => {
      setNowPlaying((cur) => {
        if (!cur) return cur;
        const playable = channels.filter((c) => verifyUrl(c.url).ok);
        if (playable.length < 2) return cur;
        const i = playable.findIndex((c) => c.id === cur.ch.id);
        const nextCh = playable[(i + delta + playable.length) % playable.length];
        return { ch: nextCh, index: channels.indexOf(nextCh) };
      });
    },
    [channels]
  );

  const load = (chs: Channel[]) => {
    savePlaylist(withChannels(chs));
    setSession(chs);
  };
  const clear = () => {
    savePlaylist(withChannels([]));
    setSession([]);
    setNowPlaying(null);
  };

  const readyCount = channels.filter((c) => verifyUrl(c.url).ok).length;

  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[0.4rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        TV en direct
      </h1>
      <p className="mb-[2rem] text-[1.3rem] text-[var(--text-medium)]">
        {hasPlaylist
          ? `${channels.length} chaînes · ${readyCount} liens vérifiés et prêts`
          : "Votre télévision, vos chaînes, vos liens."}
      </p>

      {!hasPlaylist && <ImportForm onLoad={load} />}

      {hasPlaylist && (
        <>
          {groupChannels(channels).map(({ group, channels: chs }) => (
            <section key={group} className="relative z-[2] mb-[2.4rem]">
              <h2 className="font-display mb-[0.9rem] flex items-center gap-[0.8rem] text-[1.7rem] font-bold text-[var(--text-high)]">
                <span className="inline-block h-[1.3rem] w-[0.28rem] rounded-full" style={{ background: "var(--gold-grad)" }} />
                {group}
              </h2>
              <div className="no-scrollbar flex gap-[1.2rem] overflow-x-auto overflow-y-visible py-[0.5rem]">
                {chs.map((ch) => {
                  const index = channels.indexOf(ch);
                  return (
                    <ChannelCard
                      key={ch.id}
                      channel={ch}
                      index={index}
                      onPlay={() => openPlayer(ch, index)}
                    />
                  );
                })}
              </div>
            </section>
          ))}

          <button
            data-focusable
            onClick={clear}
            className="focusable rounded-[var(--radius)] bg-white/10 px-[1.4rem] py-[0.8rem] text-[1.15rem] font-semibold text-[var(--text-medium)]"
          >
            Remplacer la playlist
          </button>
        </>
      )}

      {nowPlaying && (
        <Player
          /* key: le changement de chaîne remonte un lecteur neuf (position,
             lecture) au lieu de garder l'état de la chaîne précédente. */
          key={nowPlaying.ch.id}
          item={channelAsItem(nowPlaying.ch, nowPlaying.index)}
          next={null}
          onExit={exitPlayer}
          onZap={zap}
        />
      )}
    </div>
  );
}
