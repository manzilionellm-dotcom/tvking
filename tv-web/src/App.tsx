// =========================================================
//  App.tsx — Shell MVP : toggle M3U / Xtream + persistance + lecteur
// =========================================================
//  Evolution v0.2.0 vs v0.1.0 :
//    - Toggle entre 2 sources : URL M3U directe ou identifiants
//      Xtream Codes (URL serveur + user + pass).
//    - Sauvegarde auto de la derniere source utilisee + restauration
//      au boot (LocalStorage).
//    - Toggle "favori" sur chaque chaine + persistance.
//    - Reprend la derniere chaine jouee si dispo dans la nouvelle
//      liste.
//    - Logs structures aux transitions principales (boot, source
//      load, channel play).
//
//  Pas encore : D-pad nav, EPG, multi-piste, TMDB — Phase 3+.
// =========================================================

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Channel } from './core/models/channel.js';
import { parseM3u } from './core/parsers/m3u.js';
import {
  XtreamClient,
  XtreamError,
  type XtreamCredentials,
} from './core/clients/xtream.js';
import type {
  MediaPlayer,
  PlaybackState,
} from './core/player/player_interface.js';
import { WebMediaPlayer } from './core/player/web_media_player.js';
import {
  loadLastSource,
  saveLastSource,
  loadLastChannelId,
  saveLastChannelId,
  loadFavorites,
  toggleFavorite as storageToggleFavorite,
  type PlaylistSource,
} from './core/storage/storage.js';
import { logger } from './core/observability/structured_logger.js';
import { colors, spacing, radius, typography } from './branding/tokens.js';

type SourceMode = 'm3u' | 'xtream';

export function App(): JSX.Element {
  // ---------- Mode + inputs ----------
  const [mode, setMode] = useState<SourceMode>('m3u');
  const [m3uUrl, setM3uUrl] = useState('');
  const [xtServer, setXtServer] = useState('');
  const [xtUser, setXtUser] = useState('');
  const [xtPass, setXtPass] = useState('');

  // ---------- Etat ----------
  const [channels, setChannels] = useState<Channel[]>([]);
  const [favorites, setFavorites] = useState<readonly string[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loadInfo, setLoadInfo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [activeChannelId, setActiveChannelId] = useState<string | null>(null);
  const [playbackState, setPlaybackState] = useState<PlaybackState>('idle');

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const playerRef = useRef<MediaPlayer | null>(null);

  // ---------- Boot : restore last source ----------
  useEffect(() => {
    const last = loadLastSource();
    setFavorites(loadFavorites());
    logger.info('tv', 'app.boot', { hasLastSource: last !== null });
    if (last === null) return;
    if (last.kind === 'm3u') {
      setMode('m3u');
      setM3uUrl(last.url);
    } else {
      setMode('xtream');
      setXtServer(last.serverUrl);
      setXtUser(last.username);
      setXtPass(last.password);
    }
    // On NE charge PAS automatiquement la playlist au boot — l'utilisateur
    // garde le controle (peut vouloir changer de source). C'est juste
    // pre-rempli.
  }, []);

  // ---------- Player lifecycle ----------
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

  const handleLoad = useCallback(async (): Promise<void> => {
    setLoadError(null);
    setLoadInfo(null);
    setLoading(true);
    try {
      let parsed: Channel[];
      let source: PlaylistSource;
      if (mode === 'm3u') {
        const url = m3uUrl.trim();
        if (url.length === 0) {
          setLoadError('Colle une URL de playlist M3U.');
          return;
        }
        const response = await fetch(url);
        if (!response.ok) {
          throw new Error(`HTTP ${response.status} ${response.statusText}`);
        }
        const text = await response.text();
        parsed = parseM3u(text);
        if (parsed.length === 0) {
          setLoadError(
            "Playlist vide ou format non reconnu (entête #EXTM3U manquante ?)",
          );
          setChannels([]);
          return;
        }
        source = { kind: 'm3u', url };
      } else {
        const creds: XtreamCredentials = {
          serverUrl: xtServer.trim(),
          username: xtUser.trim(),
          password: xtPass,
        };
        if (
          creds.serverUrl.length === 0 ||
          creds.username.length === 0 ||
          creds.password.length === 0
        ) {
          setLoadError('Remplis les 3 champs (serveur, utilisateur, mot de passe).');
          return;
        }
        const client = new XtreamClient(creds);
        // 1) authenticate -> verifie credentials + recupere meta
        const auth = await client.authenticate();
        setLoadInfo(
          auth.isTrial
            ? `Compte d'essai · ${auth.status}`
            : `Compte ${auth.status}`,
        );
        // 2) on tire toutes les chaines Live (pas de filtrage Phase 2)
        parsed = await client.getLiveStreams();
        if (parsed.length === 0) {
          setLoadError(
            'Le serveur ne renvoie aucune chaîne Live. Vérifie ton abonnement.',
          );
          setChannels([]);
          return;
        }
        source = {
          kind: 'xtream',
          serverUrl: creds.serverUrl,
          username: creds.username,
          password: creds.password,
        };
      }
      setChannels(parsed);
      saveLastSource(source);
      logger.info('tv', 'playlist.loaded', {
        source: source.kind,
        channelCount: parsed.length,
      });

      // Reprise auto de la derniere chaine si elle est dans la liste
      const lastId = loadLastChannelId();
      if (lastId !== null && parsed.some((c) => c.id === lastId)) {
        const target = parsed.find((c) => c.id === lastId);
        if (target) {
          void handlePlay(target);
        }
      }
    } catch (e) {
      const message = errorToUserMessage(e);
      setLoadError(message);
      logger.warn('tv', 'playlist.load_failed', {
        source: mode,
        message,
      });
      setChannels([]);
    } finally {
      setLoading(false);
    }
    // handlePlay change a chaque render -> on l'exclut du deps (stable
    // grace au ref-pattern dans handlePlay lui-meme).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode, m3uUrl, xtServer, xtUser, xtPass]);

  const handlePlay = useCallback(async (channel: Channel): Promise<void> => {
    setActiveChannelId(channel.id);
    saveLastChannelId(channel.id);
    logger.info('tv', 'channel.play', {
      id: channel.id,
      name: channel.name,
    });
    const player = playerRef.current;
    if (!player) return;
    await player.open(channel.url);
  }, []);

  const handleToggleFavorite = useCallback((id: string): void => {
    const next = storageToggleFavorite(id);
    setFavorites(next);
    logger.info('tv', 'favorite.toggle', {
      id,
      nowFavorite: next.includes(id),
    });
  }, []);

  // ---------- Render ----------

  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: 'minmax(360px, 30%) 1fr',
        height: '100vh',
        background: colors.background,
      }}
    >
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
        <header style={{ display: 'flex', alignItems: 'baseline', gap: spacing.sm }}>
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
          <span
            style={{ color: colors.textMuted, fontSize: typography.size.caption }}
          >
            TV · v0.2.0
          </span>
        </header>

        <SourceToggle mode={mode} onChange={setMode} />

        {mode === 'm3u' ? (
          <M3uForm
            url={m3uUrl}
            setUrl={setM3uUrl}
            loading={loading}
            onSubmit={() => void handleLoad()}
          />
        ) : (
          <XtreamForm
            server={xtServer}
            user={xtUser}
            pass={xtPass}
            setServer={setXtServer}
            setUser={setXtUser}
            setPass={setXtPass}
            loading={loading}
            onSubmit={() => void handleLoad()}
          />
        )}

        {loadError && <Alert kind="error">{loadError}</Alert>}
        {loadInfo && !loadError && <Alert kind="info">{loadInfo}</Alert>}

        <div
          style={{
            color: colors.textSecondary,
            fontSize: typography.size.caption,
            textTransform: 'uppercase',
            letterSpacing: 1,
          }}
        >
          {channels.length} chaîne{channels.length > 1 ? 's' : ''}
          {favorites.length > 0 && ` · ${favorites.length} favori${favorites.length > 1 ? 's' : ''}`}
        </div>

        <ChannelList
          channels={channels}
          favorites={favorites}
          activeId={activeChannelId}
          onPlay={(c) => void handlePlay(c)}
          onToggleFavorite={handleToggleFavorite}
        />
      </aside>

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
          style={{ width: '100%', height: '100%', objectFit: 'contain' }}
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

// ===========================================================
//  Sous-composants
// ===========================================================

interface SourceToggleProps {
  mode: SourceMode;
  onChange: (m: SourceMode) => void;
}

function SourceToggle({ mode, onChange }: SourceToggleProps): JSX.Element {
  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: '1fr 1fr',
        background: colors.background,
        borderRadius: radius.md,
        padding: 4,
        border: `1px solid ${colors.border}`,
      }}
    >
      {(['m3u', 'xtream'] as const).map((value) => {
        const active = mode === value;
        return (
          <button
            key={value}
            onClick={() => onChange(value)}
            style={{
              padding: spacing.sm,
              background: active ? colors.surfaceHigh : 'transparent',
              border: 'none',
              borderRadius: radius.sm,
              color: active ? colors.textPrimary : colors.textSecondary,
              fontSize: typography.size.caption,
              fontWeight: active
                ? typography.weight.semibold
                : typography.weight.regular,
              cursor: 'pointer',
              letterSpacing: 1,
              textTransform: 'uppercase',
            }}
          >
            {value === 'm3u' ? 'URL M3U' : 'Xtream Codes'}
          </button>
        );
      })}
    </div>
  );
}

interface M3uFormProps {
  url: string;
  setUrl: (v: string) => void;
  loading: boolean;
  onSubmit: () => void;
}

function M3uForm({ url, setUrl, loading, onSubmit }: M3uFormProps): JSX.Element {
  return (
    <div style={{ display: 'flex', gap: spacing.sm }}>
      <input
        type="text"
        placeholder="https://exemple.com/playlist.m3u"
        value={url}
        onChange={(e) => setUrl(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') onSubmit();
        }}
        style={inputStyle()}
      />
      <PrimaryButton loading={loading} onClick={onSubmit}>
        Charger
      </PrimaryButton>
    </div>
  );
}

interface XtreamFormProps {
  server: string;
  user: string;
  pass: string;
  setServer: (v: string) => void;
  setUser: (v: string) => void;
  setPass: (v: string) => void;
  loading: boolean;
  onSubmit: () => void;
}

function XtreamForm({
  server,
  user,
  pass,
  setServer,
  setUser,
  setPass,
  loading,
  onSubmit,
}: XtreamFormProps): JSX.Element {
  const submitOnEnter = (e: React.KeyboardEvent<HTMLInputElement>): void => {
    if (e.key === 'Enter') onSubmit();
  };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: spacing.sm }}>
      <input
        type="text"
        placeholder="http://serveur.com:8080"
        value={server}
        onChange={(e) => setServer(e.target.value)}
        onKeyDown={submitOnEnter}
        style={inputStyle()}
      />
      <input
        type="text"
        placeholder="Nom d'utilisateur"
        value={user}
        onChange={(e) => setUser(e.target.value)}
        onKeyDown={submitOnEnter}
        autoComplete="username"
        style={inputStyle()}
      />
      <input
        type="password"
        placeholder="Mot de passe"
        value={pass}
        onChange={(e) => setPass(e.target.value)}
        onKeyDown={submitOnEnter}
        autoComplete="current-password"
        style={inputStyle()}
      />
      <PrimaryButton loading={loading} onClick={onSubmit}>
        Connecter
      </PrimaryButton>
    </div>
  );
}

interface ChannelListProps {
  channels: Channel[];
  favorites: readonly string[];
  activeId: string | null;
  onPlay: (channel: Channel) => void;
  onToggleFavorite: (id: string) => void;
}

function ChannelList({
  channels,
  favorites,
  activeId,
  onPlay,
  onToggleFavorite,
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
  const favSet = new Set(favorites);
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
        const isFav = favSet.has(c.id);
        return (
          <li key={c.id} style={{ display: 'flex', alignItems: 'stretch', gap: 4 }}>
            <button
              onClick={() => onPlay(c)}
              style={{
                flex: 1,
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
            <button
              onClick={() => onToggleFavorite(c.id)}
              title={isFav ? 'Retirer des favoris' : 'Ajouter aux favoris'}
              aria-label={isFav ? 'Retirer des favoris' : 'Ajouter aux favoris'}
              style={{
                width: 40,
                border: `1px solid transparent`,
                borderRadius: radius.md,
                background: 'transparent',
                color: isFav ? colors.accent : colors.textMuted,
                cursor: 'pointer',
                fontSize: 18,
              }}
            >
              {isFav ? '★' : '☆'}
            </button>
          </li>
        );
      })}
    </ul>
  );
}

interface AlertProps {
  kind: 'error' | 'info';
  children: React.ReactNode;
}

function Alert({ kind, children }: AlertProps): JSX.Element {
  const bg = kind === 'error' ? 'rgba(232, 55, 64, 0.15)' : 'rgba(63, 164, 91, 0.15)';
  const fg = kind === 'error' ? colors.live : colors.success;
  return (
    <div
      style={{
        padding: spacing.sm,
        borderRadius: radius.md,
        background: bg,
        color: fg,
        fontSize: typography.size.caption,
      }}
    >
      {children}
    </div>
  );
}

interface PrimaryButtonProps {
  loading: boolean;
  onClick: () => void;
  children: React.ReactNode;
}

function PrimaryButton({
  loading,
  onClick,
  children,
}: PrimaryButtonProps): JSX.Element {
  return (
    <button
      onClick={onClick}
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
      {loading ? '…' : children}
    </button>
  );
}

// ===========================================================
//  Helpers locaux
// ===========================================================

function inputStyle(): React.CSSProperties {
  return {
    flex: 1,
    padding: `${spacing.sm}px ${spacing.md}px`,
    borderRadius: radius.md,
    border: `1px solid ${colors.border}`,
    background: colors.background,
    color: colors.textPrimary,
    fontSize: typography.size.body,
  };
}

/**
 * Mappe une exception en message UX clair. Inspiree de
 * `friendlyMessageFor` du CastManager phone.
 */
function errorToUserMessage(e: unknown): string {
  if (e instanceof XtreamError) {
    switch (e.code) {
      case 'auth_failed':
        return 'Identifiants Xtream refusés. Vérifie ton login/mot de passe.';
      case 'network':
        return 'Connexion impossible au serveur. Vérifie ton internet et l\'URL.';
      case 'invalid_response':
        return 'Réponse inattendue du serveur (pas un JSON Xtream valide).';
      case 'unknown':
        return `Erreur Xtream : ${e.message}`;
    }
  }
  if (e instanceof Error) {
    return `Échec du chargement : ${e.message}`;
  }
  return 'Échec du chargement de la playlist.';
}
