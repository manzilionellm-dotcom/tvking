// =========================================================
//  App.tsx — Ecran unique MVP : input M3U + liste + lecteur
// =========================================================
//  Vue minimale fonctionnelle pour valider la chaine complete :
//
//    1. L'utilisateur colle une URL M3U (ou un blob direct .ts/.m3u8).
//    2. On fetch + parse via parseM3u().
//    3. On affiche la liste des chaines (focusable D-pad — Phase 2).
//    4. Au clic sur une chaine, on instancie WebMediaPlayer et on
//       joue dans le <video>.
//
//  Pas de Xtream Codes, pas d'EPG, pas de TMDB ici — ces briques
//  arrivent en Phase 2+ (cf. tv-web/README.md). On valide la
//  fondation (parser + abstraction + lecture HLS/TS) avant d'empiler.
// =========================================================

import { useEffect, useMemo, useRef, useState } from 'react';
import type { Channel } from './core/models/channel.js';
import { parseM3u } from './core/parsers/m3u.js';
import type { MediaPlayer, PlaybackState } from './core/player/player_interface.js';
import { WebMediaPlayer } from './core/player/web_media_player.js';
import { colors, spacing, radius, typography } from './branding/tokens.js';

export function App(): JSX.Element {
  const [playlistInput, setPlaylistInput] = useState('');
  const [channels, setChannels] = useState<Channel[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [activeChannelId, setActiveChannelId] = useState<string | null>(null);
  const [playbackState, setPlaybackState] = useState<PlaybackState>('idle');

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const playerRef = useRef<MediaPlayer | null>(null);

  // Construit le player une fois le <video> monte. Le dispose() est
  // appele a l'unmount pour fermer hls.js proprement (sinon fuite
  // memoire connue de la lib).
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const player = new WebMediaPlayer(video);
    playerRef.current = player;
    const unsubscribe = player.onStateChange((state) =>
      setPlaybackState(state),
    );
    return () => {
      unsubscribe();
      player.dispose();
      playerRef.current = null;
    };
  }, []);

  const activeChannel = useMemo(
    () => channels.find((c) => c.id === activeChannelId) ?? null,
    [channels, activeChannelId],
  );

  // ---------- Handlers ----------

  async function handleLoadPlaylist(): Promise<void> {
    const url = playlistInput.trim();
    if (url.length === 0) {
      setLoadError('Colle une URL de playlist M3U.');
      return;
    }
    setLoading(true);
    setLoadError(null);
    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status} ${response.statusText}`);
      }
      const text = await response.text();
      const parsed = parseM3u(text);
      if (parsed.length === 0) {
        setLoadError(
          'Playlist vide ou format M3U non reconnu (entete #EXTM3U manquante ?)',
        );
        setChannels([]);
        return;
      }
      setChannels(parsed);
    } catch (e) {
      setLoadError(
        e instanceof Error
          ? `Echec du chargement : ${e.message}`
          : 'Echec du chargement de la playlist.',
      );
      setChannels([]);
    } finally {
      setLoading(false);
    }
  }

  async function handlePlay(channel: Channel): Promise<void> {
    setActiveChannelId(channel.id);
    const player = playerRef.current;
    if (!player) return;
    await player.open(channel.url);
  }

  // ---------- Render ----------

  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: 'minmax(320px, 28%) 1fr',
        height: '100vh',
        background: colors.background,
      }}
    >
      {/* COLONNE GAUCHE — input + liste */}
      <aside
        style={{
          background: colors.surface,
          borderRight: `1px solid ${colors.border}`,
          padding: spacing.lg,
          overflowY: 'auto',
          display: 'flex',
          flexDirection: 'column',
          gap: spacing.md,
        }}
      >
        <h1
          style={{
            margin: 0,
            color: colors.accent,
            fontSize: typography.size.heading,
            fontWeight: typography.weight.bold,
            letterSpacing: 2,
          }}
        >
          7 MOTION
        </h1>
        <p
          style={{
            margin: 0,
            color: colors.textMuted,
            fontSize: typography.size.caption,
          }}
        >
          MVP TV — v0.1.0. Colle ton URL M3U / M3U8 pour charger ta playlist.
        </p>

        <div style={{ display: 'flex', gap: spacing.sm }}>
          <input
            type="text"
            placeholder="https://exemple.com/playlist.m3u"
            value={playlistInput}
            onChange={(e) => setPlaylistInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') void handleLoadPlaylist();
            }}
            style={{
              flex: 1,
              padding: `${spacing.sm}px ${spacing.md}px`,
              borderRadius: radius.md,
              border: `1px solid ${colors.border}`,
              background: colors.background,
              color: colors.textPrimary,
              fontSize: typography.size.body,
            }}
          />
          <button
            onClick={() => void handleLoadPlaylist()}
            disabled={loading}
            style={{
              padding: `${spacing.sm}px ${spacing.md}px`,
              borderRadius: radius.md,
              border: 'none',
              background: colors.accent,
              color: colors.textPrimary,
              fontSize: typography.size.body,
              fontWeight: typography.weight.semibold,
              cursor: loading ? 'wait' : 'pointer',
            }}
          >
            {loading ? '…' : 'Charger'}
          </button>
        </div>

        {loadError && (
          <div
            style={{
              padding: spacing.sm,
              borderRadius: radius.md,
              background: 'rgba(232, 55, 64, 0.15)',
              color: colors.live,
              fontSize: typography.size.caption,
            }}
          >
            {loadError}
          </div>
        )}

        <div
          style={{
            color: colors.textSecondary,
            fontSize: typography.size.caption,
            textTransform: 'uppercase',
            letterSpacing: 1,
          }}
        >
          {channels.length} chaîne{channels.length > 1 ? 's' : ''}
        </div>

        <ChannelList
          channels={channels}
          activeId={activeChannelId}
          onPlay={(c) => void handlePlay(c)}
        />
      </aside>

      {/* COLONNE DROITE — player */}
      <main
        style={{
          background: '#000',
          position: 'relative',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <video
          ref={videoRef}
          controls
          playsInline
          autoPlay
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'contain',
          }}
        />
        {!activeChannel && (
          <div
            style={{
              position: 'absolute',
              color: colors.textMuted,
              fontSize: typography.size.body,
              pointerEvents: 'none',
            }}
          >
            Sélectionne une chaîne pour lancer la lecture
          </div>
        )}
        {activeChannel && (
          <div
            style={{
              position: 'absolute',
              top: spacing.md,
              left: spacing.md,
              padding: `${spacing.xs}px ${spacing.sm}px`,
              borderRadius: radius.md,
              background: 'rgba(10, 10, 12, 0.7)',
              color: colors.textPrimary,
              fontSize: typography.size.caption,
            }}
          >
            {activeChannel.name} · état: {playbackState}
          </div>
        )}
      </main>
    </div>
  );
}

interface ChannelListProps {
  channels: Channel[];
  activeId: string | null;
  onPlay: (channel: Channel) => void;
}

function ChannelList({
  channels,
  activeId,
  onPlay,
}: ChannelListProps): JSX.Element {
  if (channels.length === 0) {
    return (
      <div
        style={{
          color: colors.textMuted,
          fontSize: typography.size.caption,
          padding: spacing.md,
          textAlign: 'center',
        }}
      >
        Aucune chaîne chargée.
      </div>
    );
  }
  return (
    <ul
      style={{
        listStyle: 'none',
        padding: 0,
        margin: 0,
        display: 'flex',
        flexDirection: 'column',
        gap: spacing.xs,
      }}
    >
      {channels.map((c) => {
        const isActive = c.id === activeId;
        return (
          <li key={c.id}>
            <button
              onClick={() => onPlay(c)}
              style={{
                width: '100%',
                textAlign: 'left',
                padding: `${spacing.sm}px ${spacing.md}px`,
                borderRadius: radius.md,
                border: `1px solid ${
                  isActive ? colors.accent : 'transparent'
                }`,
                background: isActive ? colors.surfaceHigh : 'transparent',
                color: colors.textPrimary,
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: spacing.sm,
                fontSize: typography.size.body,
              }}
            >
              {c.logoUrl ? (
                <img
                  src={c.logoUrl}
                  alt=""
                  width={36}
                  height={36}
                  style={{ objectFit: 'contain' }}
                  onError={(e) => {
                    e.currentTarget.style.visibility = 'hidden';
                  }}
                />
              ) : (
                <div
                  style={{
                    width: 36,
                    height: 36,
                    borderRadius: radius.sm,
                    background: colors.surfaceHigh,
                  }}
                />
              )}
              <div
                style={{
                  flex: 1,
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}
              >
                {c.name}
              </div>
              {c.group && (
                <span
                  style={{
                    fontSize: typography.size.caption,
                    color: colors.textMuted,
                  }}
                >
                  {c.group}
                </span>
              )}
            </button>
          </li>
        );
      })}
    </ul>
  );
}
