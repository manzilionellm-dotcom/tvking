import { MacLink } from '@/components/MacLink';
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  onlineApi,
  devicesApi,
  type OnlineSnapshot,
  flagEmoji,
  ApiError,
} from '@/lib/api';
import { useLiveDevices, useRtEvent, sendCmd } from '@/lib/realtime';
import { toast } from '@/components/Toast';
import { cn } from '@/lib/utils';

/// Page « En ligne » (owner) — CENTRE DE SUPERVISION TEMPS RÉEL.
///
/// Source unique de vérité : union par MAC des appareils du hub temps réel
/// (WebSocket) et de la présence heartbeat /api/v1/online. Le WS gagne pour
/// la chaîne, la plateforme, le modèle, la version d'app et le « connecté à » ;
/// l'IP vient de /online. Le polling 30 s tourne TOUJOURS (source de « actifs
/// aujourd'hui », des IP, et des vieux APK sans WebSocket).
///
/// HONNÊTETÉ DES MÉTRIQUES : on n'affiche QUE des chiffres réels ou dérivés de
/// données réelles (sessions, versions, pays, chaînes, latence API mesurée,
/// qualité déduite du nom de chaîne). Les métriques d'INFRASTRUCTURE (CPU / RAM
/// / bande passante / ping serveur / débit par flux) n'ont PAS de source côté
/// serveur aujourd'hui : on ne fabrique JAMAIS de valeurs — la carte « Santé
/// serveurs » indique clairement ce qui reste à instrumenter.

// ---------------------------------------------------------------------------
//  Helpers d'affichage
// ---------------------------------------------------------------------------

function ago(ts: number): string {
  if (!ts) return '—';
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 60) return `il y a ${s}s`;
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  return `il y a ${Math.floor(s / 3600)} h`;
}

/// Durée compacte d'une session (ex. « 1 h 12 », « 8 min », « 42 s »).
function dur(ms: number): string {
  if (!ms || ms < 0) return '—';
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s} s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  return `${h} h ${String(m % 60).padStart(2, '0')}`;
}

/// Heure locale HH:MM d'un timestamp (heure de connexion).
function hhmm(ts?: number): string {
  if (!ts) return '—';
  const d = new Date(ts);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/// Libellé plateforme (connue seulement via le WS).
function platformLabel(p?: string): string {
  if (p === 'tv') return '📺 TV';
  if (p === 'mobile') return '📱 Mobile';
  if (p === 'windows') return '💻 Windows';
  return '—';
}

/// Sous-type d'un appareil TV DÉDUIT du modèle (heuristique honnête) :
/// Fire TV (Amazon « AFT… »), Google TV / Chromecast, Nvidia SHIELD, ou
/// « TV Box » (AOSP générique) par défaut.
function tvKind(platform?: string, model?: string): string | null {
  if (platform !== 'tv') return null;
  const m = (model || '').toLowerCase();
  if (/aft|fire/.test(m)) return 'Fire TV';
  if (/chromecast|google|sabrina|bravia/.test(m)) return 'Google TV';
  if (/shield|nvidia/.test(m)) return 'Nvidia SHIELD';
  if (/mibox|mi\s?tv|xiaomi/.test(m)) return 'Xiaomi';
  return 'TV Box';
}

/// Qualité DÉDUITE du nom de la chaîne (beaucoup de bouquets IPTV encodent
/// « 4K / UHD / FHD / HD / SD » dans le nom). Heuristique, jamais présentée
/// comme une mesure de flux réelle.
function qualityOf(channel?: string): '4K' | 'FHD' | 'HD' | 'SD' | 'Autre' {
  const c = (channel || '').toUpperCase();
  if (!c) return 'Autre';
  if (/(4K|UHD|2160)/.test(c)) return '4K';
  if (/(FHD|1080)/.test(c)) return 'FHD';
  if (/(\bHD\b|720)/.test(c)) return 'HD';
  if (/(\bSD\b|480|360)/.test(c)) return 'SD';
  return 'Autre';
}

/// Compare deux versions « x.y.z » → n° positif si a > b, négatif si a < b.
function cmpVersion(a: string, b: string): number {
  const pa = a.split('.').map((n) => parseInt(n, 10) || 0);
  const pb = b.split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d !== 0) return d;
  }
  return 0;
}

// ---------------------------------------------------------------------------
//  Ligne fusionnée du tableau (WS ∪ /online, par MAC)
// ---------------------------------------------------------------------------

type OnlineRow = {
  mac: string;
  country: string;
  channel: string;
  lastSeen: number;
  ip?: string;
  platform?: string;
  model?: string;
  appVersion?: string;
  connectedAt?: number;
  live: boolean; // connecté au hub temps réel en ce moment
};

type Severity = 'red' | 'orange';
type Alert = { id: string; sev: Severity; icon: string; text: string };

// ---------------------------------------------------------------------------
//  Petits composants d'affichage (locaux à l'écran « En ligne »)
// ---------------------------------------------------------------------------

function Kpi({
  label,
  value,
  tone = 'default',
  hint,
}: {
  label: string;
  value: ReactNode;
  tone?: 'default' | 'success' | 'accent' | 'warning';
  hint?: string;
}) {
  const border =
    tone === 'success'
      ? 'border-success/20 bg-success/[0.06]'
      : tone === 'accent'
        ? 'border-accent/20 bg-accent/[0.06]'
        : tone === 'warning'
          ? 'border-warning/20 bg-warning/[0.06]'
          : 'border-white/5 bg-midnight';
  const color =
    tone === 'success'
      ? 'text-success'
      : tone === 'accent'
        ? 'text-accent-bright'
        : tone === 'warning'
          ? 'text-warning-bright'
          : 'text-ink-primary';
  return (
    <div className={cn('rounded-xl border p-4', border)}>
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</div>
      <div className={cn('mt-1 text-3xl font-bold', color)}>{value}</div>
      {hint && <div className="mt-0.5 text-[11px] text-ink-tertiary">{hint}</div>}
    </div>
  );
}

/// Barre horizontale « libellé · valeur » avec remplissage proportionnel.
function Bar({
  label,
  value,
  max,
  tone = 'accent',
}: {
  label: ReactNode;
  value: number;
  max: number;
  tone?: 'accent' | 'success' | 'warning' | 'champagne';
}) {
  const pct = max > 0 ? Math.max(3, Math.round((value / max) * 100)) : 0;
  const fill =
    tone === 'success'
      ? 'bg-success'
      : tone === 'warning'
        ? 'bg-warning'
        : tone === 'champagne'
          ? 'bg-champagne'
          : 'bg-accent';
  return (
    <div className="flex items-center gap-3">
      <div className="w-40 shrink-0 truncate text-xs text-ink-secondary">{label}</div>
      <div className="h-2 flex-1 overflow-hidden rounded-full bg-white/5">
        <div className={cn('h-full rounded-full', fill)} style={{ width: `${pct}%` }} />
      </div>
      <div className="w-8 shrink-0 text-right text-xs font-bold text-ink-primary">{value}</div>
    </div>
  );
}

/// Mini-graphe temps réel (sparkline SVG) — utilisateurs par minute.
function Sparkline({ points }: { points: number[] }) {
  const w = 260;
  const h = 46;
  if (points.length < 2) {
    return <div className="text-xs text-ink-tertiary">Collecte en cours…</div>;
  }
  const max = Math.max(1, ...points);
  const step = w / (points.length - 1);
  const path = points
    .map((p, i) => `${i === 0 ? 'M' : 'L'}${(i * step).toFixed(1)},${(h - (p / max) * (h - 6) - 3).toFixed(1)}`)
    .join(' ');
  const area = `${path} L${w},${h} L0,${h} Z`;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="h-12 w-full" preserveAspectRatio="none">
      <path d={area} fill="url(#spark)" opacity="0.25" />
      <path d={path} fill="none" stroke="currentColor" strokeWidth="1.5" className="text-success" />
      <defs>
        <linearGradient id="spark" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#5BC97E" />
          <stop offset="100%" stopColor="#5BC97E" stopOpacity="0" />
        </linearGradient>
      </defs>
    </svg>
  );
}

function SectionTitle({ children }: { children: ReactNode }) {
  return (
    <div className="mb-2 mt-6 text-[10px] uppercase tracking-widest text-ink-tertiary">
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
//  Page
// ---------------------------------------------------------------------------

const VISIBLE_CAP = 300; // borne d'affichage du tableau (perf sur grosses flottes)

export function OnlinePage({ onLogout }: { onLogout: () => void }) {
  const [data, setData] = useState<OnlineSnapshot | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [apiMs, setApiMs] = useState<number | null>(null);
  const [query, setQuery] = useState('');
  const { devices: live, connected } = useLiveDevices();

  // Séries temps réel (échantillonnées) — utilisateurs par minute.
  const [series, setSeries] = useState<number[]>([]);
  const onlineCountRef = useRef(0);

  // Suivi par MAC pour les ALERTES (persistant entre les rendus).
  const countryByMac = useRef<Map<string, string>>(new Map());
  // Changements de pays récents (mac → {from,to,at}) → alerte « voyage » / VPN.
  const countryChanges = useRef<Map<string, { from: string; to: string; at: number }>>(new Map());
  const reconnects = useRef<Map<string, number>>(new Map());
  const zaps = useRef<Map<string, number>>(new Map()); // changements de chaîne
  const [alertTick, setAlertTick] = useState(0); // force le recalcul des alertes

  const load = useCallback(() => {
    const t0 = performance.now();
    onlineApi
      .get()
      .then((d) => {
        setApiMs(Math.round(performance.now() - t0));
        setData(d);
        setErr(null);
      })
      .catch((e: any) => {
        if (e instanceof ApiError && e.status === 401) {
          onLogout();
          return;
        }
        setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      })
      .finally(() => setLoading(false));
  }, [onLogout]);

  // Le polling 30 s tourne TOUJOURS (même WS connecté).
  useEffect(() => {
    load();
    const t = setInterval(load, 30000);
    return () => clearInterval(t);
  }, [load]);

  // Échantillonnage « utilisateurs par minute » toutes les 5 s (30 points ≈ 2,5 min).
  useEffect(() => {
    const t = setInterval(() => {
      setSeries((prev) => {
        const next = [...prev, onlineCountRef.current];
        return next.length > 40 ? next.slice(next.length - 40) : next;
      });
    }, 5000);
    return () => clearInterval(t);
  }, []);

  // Compteurs d'ALERTES alimentés par les évènements temps réel bruts.
  useRtEvent('device_online', (e: any) => {
    const mac = e?.device?.mac;
    if (!mac) return;
    reconnects.current.set(mac, (reconnects.current.get(mac) || 0) + 1);
    setAlertTick((n) => n + 1);
  });
  useRtEvent('watching', (e: any) => {
    const mac = e?.mac;
    if (!mac) return;
    zaps.current.set(mac, (zaps.current.get(mac) || 0) + 1);
  });

  // Union par MAC : /online d'abord, puis le WS écrase les champs qu'il connaît.
  const rows = useMemo<OnlineRow[]>(() => {
    const map = new Map<string, OnlineRow>();
    for (const d of data?.items ?? []) {
      map.set(d.mac, {
        mac: d.mac,
        country: d.country || '',
        channel: d.channel ?? '',
        lastSeen: d.lastSeen,
        ip: d.ip || undefined,
        live: false,
      });
    }
    for (const d of live) {
      const prev = map.get(d.mac);
      map.set(d.mac, {
        mac: d.mac,
        country: d.country || prev?.country || '',
        channel: d.channel ?? '',
        lastSeen: d.lastSeen ?? d.connectedAt ?? prev?.lastSeen ?? 0,
        ip: prev?.ip,
        platform: d.platform,
        model: d.model,
        appVersion: d.appVersion,
        connectedAt: d.connectedAt,
        live: true,
      });
    }
    return Array.from(map.values()).sort((a, b) => b.lastSeen - a.lastSeen);
  }, [data, live]);

  const onlineCount = rows.length;
  useEffect(() => {
    onlineCountRef.current = onlineCount;
  }, [onlineCount]);

  // Suivi des changements de PAYS par MAC (pour l'alerte « changement de pays »).
  useEffect(() => {
    for (const r of rows) {
      if (!r.country) continue;
      const prev = countryByMac.current.get(r.mac);
      if (prev && prev !== r.country) {
        countryChanges.current.set(r.mac, { from: prev, to: r.country, at: Date.now() });
        setAlertTick((n) => n + 1);
      }
      countryByMac.current.set(r.mac, r.country);
    }
  }, [rows]);

  // ------- Agrégats (tous dérivés de données RÉELLES) -----------------------

  const watching = useMemo(() => rows.filter((r) => r.channel).length, [rows]);

  const avgSession = useMemo(() => {
    const withStart = rows.filter((r) => r.connectedAt);
    if (!withStart.length) return 0;
    const now = Date.now();
    const sum = withStart.reduce((a, r) => a + (now - (r.connectedAt || now)), 0);
    return sum / withStart.length;
  }, [rows]);

  const byCountry = useMemo(() => {
    const acc: Record<string, number> = {};
    for (const r of rows) acc[r.country || '??'] = (acc[r.country || '??'] || 0) + 1;
    return Object.entries(acc).sort((a, b) => b[1] - a[1]);
  }, [rows]);

  const byPlatform = useMemo(() => {
    const acc: Record<string, number> = {};
    for (const r of rows) {
      const k = tvKind(r.platform, r.model) || platformLabel(r.platform);
      acc[k] = (acc[k] || 0) + 1;
    }
    return Object.entries(acc).sort((a, b) => b[1] - a[1]);
  }, [rows]);

  const byChannel = useMemo(() => {
    const acc: Record<string, number> = {};
    for (const r of rows) if (r.channel) acc[r.channel] = (acc[r.channel] || 0) + 1;
    return Object.entries(acc).sort((a, b) => b[1] - a[1]).slice(0, 8);
  }, [rows]);

  const quality = useMemo(() => {
    const acc: Record<string, number> = { '4K': 0, FHD: 0, HD: 0, SD: 0, Autre: 0 };
    for (const r of rows) if (r.channel) acc[qualityOf(r.channel)]++;
    return acc;
  }, [rows]);

  // Version d'app « de référence » = la plus élevée observée en ligne.
  const latestVersion = useMemo(() => {
    let best = '';
    for (const r of rows) {
      if (r.appVersion && (!best || cmpVersion(r.appVersion, best) > 0)) best = r.appVersion;
    }
    return best;
  }, [rows]);

  const outdatedCount = useMemo(() => {
    if (!latestVersion) return 0;
    return rows.filter((r) => r.appVersion && cmpVersion(r.appVersion, latestVersion) < 0).length;
  }, [rows, latestVersion]);

  // ------- ALERTES INTELLIGENTES (détection sur données réelles) ------------

  const alerts = useMemo<Alert[]>(() => {
    void alertTick; // dépendance : recalcul quand les compteurs bougent
    const out: Alert[] = [];

    // 1) Plusieurs appareils DIFFÉRENTS sur la même IP (partage de compte / NAT).
    const macsByIp = new Map<string, Set<string>>();
    for (const r of rows) {
      if (!r.ip) continue;
      if (!macsByIp.has(r.ip)) macsByIp.set(r.ip, new Set());
      macsByIp.get(r.ip)!.add(r.mac);
    }
    for (const [ip, macs] of macsByIp) {
      if (macs.size >= 3) {
        out.push({
          id: `ip-${ip}`,
          sev: 'orange',
          icon: '👥',
          text: `${macs.size} appareils sur la même IP (${ip}) — partage de compte possible.`,
        });
      }
    }

    // 2) Trop de reconnexions récentes (churn) — instabilité réseau/serveur.
    for (const [mac, n] of reconnects.current) {
      if (n >= 5) {
        out.push({
          id: `re-${mac}`,
          sev: 'orange',
          icon: '🔁',
          text: `${mac} : ${n} reconnexions — flux instable ou coupures répétées.`,
        });
      }
    }

    // 3) Zapping anormalement élevé (flux instable / erreurs de lecture).
    for (const [mac, n] of zaps.current) {
      if (n >= 25) {
        out.push({
          id: `zap-${mac}`,
          sev: 'orange',
          icon: '📶',
          text: `${mac} : ${n} changements de chaîne — lecture peut-être instable.`,
        });
      }
    }

    // 3b) Changement de pays récent (< 15 min) — voyage réel ou VPN/partage.
    const now = Date.now();
    for (const [mac, ch] of countryChanges.current) {
      if (now - ch.at < 15 * 60 * 1000) {
        out.push({
          id: `geo-${mac}`,
          sev: 'orange',
          icon: '🌍',
          text: `${mac} : changement de pays ${ch.from} → ${ch.to} (VPN ou partage possible).`,
        });
      }
    }

    // 4) Versions d'app obsolètes.
    if (outdatedCount > 0) {
      out.push({
        id: 'outdated',
        sev: 'orange',
        icon: '⬆️',
        text: `${outdatedCount} appareil(s) sur une version d'app antérieure à ${latestVersion}.`,
      });
    }

    // 5) Saturation apparente (beaucoup de monde, latence API dégradée).
    if (apiMs != null && apiMs > 1500 && onlineCount > 50) {
      out.push({
        id: 'sat',
        sev: 'red',
        icon: '🔥',
        text: `API lente (${apiMs} ms) sous forte charge (${onlineCount} en ligne) — surveiller la saturation.`,
      });
    }

    return out.slice(0, 12);
  }, [rows, outdatedCount, latestVersion, apiMs, onlineCount, alertTick]);

  // ------- Recherche avancée (MAC / IP / pays / chaîne / plateforme / version)
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((r) => {
      const hay = [
        r.mac,
        r.ip || '',
        r.country,
        r.channel,
        r.appVersion || '',
        tvKind(r.platform, r.model) || r.platform || '',
        r.model || '',
      ]
        .join(' ')
        .toLowerCase();
      return hay.includes(q);
    });
  }, [rows, query]);

  const visible = filtered.slice(0, VISIBLE_CAP);

  // ------- Actions rapides par ligne ---------------------------------------

  function copy(text: string, what: string) {
    navigator.clipboard?.writeText(text).then(
      () => toast(`${what} copié`, 'success'),
      () => toast('Copie impossible', 'error'),
    );
  }

  function notify(mac: string) {
    const body = window.prompt(`Message à envoyer à ${mac} :`, '');
    if (body == null) return;
    const text = body.trim();
    if (!text) return;
    devicesApi.sendMessage(mac, { title: '7 MOTION', body: text }).then(
      () => toast('Notification déposée', 'success'),
      () => toast('Envoi impossible', 'error'),
    );
  }

  function restartStream(mac: string) {
    // Pas de « kill » brutal côté hub : on force une RE-SYNCHRO de l'appareil
    // (il ré-ouvre sa source / relit son flux). C'est l'action réelle la plus
    // proche d'un « redémarrage du flux » disponible aujourd'hui.
    sendCmd(mac, 'sync', { scope: 'all' });
    toast('Re-synchronisation envoyée', 'success');
  }

  const apiTone = apiMs == null ? 'default' : apiMs < 400 ? 'success' : apiMs < 1200 ? 'warning' : 'accent';

  return (
    <AppLayout
      title="En ligne"
      subtitle={
        connected
          ? "Centre de supervision — flux temps réel (WebSocket), mise à jour automatique"
          : "Qui utilise l'app en ce moment (mise à jour auto ; temps réel indisponible)"
      }
      onLogout={onLogout}
      actions={
        connected ? (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-success/30 bg-success/10 px-3 py-1 text-xs font-semibold text-success">
            Direct <span className="animate-pulse">●</span>
          </span>
        ) : (
          <span className="inline-flex items-center gap-1.5 rounded-full border border-white/10 bg-midnight px-3 py-1 text-xs font-semibold text-ink-tertiary">
            Hors temps réel
          </span>
        )
      }
    >
      {err && (
        <div className="mb-4 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
          {err}
        </div>
      )}

      {loading && !data && !connected ? (
        <div className="text-sm text-ink-tertiary">Chargement…</div>
      ) : (
        <>
          {/* ============ INDICATEURS GLOBAUX ============ */}
          <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
            <Kpi label="En ligne maintenant" value={onlineCount} tone="success" />
            <Kpi label="Actifs aujourd'hui" value={data?.todayCount ?? 0} />
            <Kpi label="Flux actifs" value={watching} tone="accent" hint="en lecture" />
            <Kpi label="Pays en ligne" value={byCountry.length} />
            <Kpi label="Session moyenne" value={dur(avgSession)} hint="appareils temps réel" />
            <Kpi
              label="Temps réponse API"
              value={apiMs == null ? '—' : `${apiMs} ms`}
              tone={apiTone}
            />
          </div>

          {/* ============ STATISTIQUES LIVE ============ */}
          <SectionTitle>Statistiques live</SectionTitle>
          <div className="grid gap-3 lg:grid-cols-2">
            {/* Utilisateurs par minute */}
            <div className="rounded-xl border border-white/5 bg-midnight p-4 text-success">
              <div className="mb-1 flex items-center justify-between">
                <span className="text-[11px] uppercase tracking-widest text-ink-tertiary">
                  Utilisateurs (temps réel)
                </span>
                <span className="text-sm font-bold text-ink-primary">{onlineCount}</span>
              </div>
              <Sparkline points={series} />
            </div>

            {/* Répartition plateformes */}
            <div className="rounded-xl border border-white/5 bg-midnight p-4">
              <div className="mb-3 text-[11px] uppercase tracking-widest text-ink-tertiary">
                Répartition des appareils
              </div>
              <div className="space-y-2">
                {byPlatform.length === 0 && (
                  <div className="text-xs text-ink-tertiary">Aucun appareil temps réel.</div>
                )}
                {byPlatform.map(([k, n]) => (
                  <Bar key={k} label={k} value={n} max={byPlatform[0][1]} tone="champagne" />
                ))}
              </div>
            </div>

            {/* Chaînes les plus regardées */}
            <div className="rounded-xl border border-white/5 bg-midnight p-4">
              <div className="mb-3 text-[11px] uppercase tracking-widest text-ink-tertiary">
                Chaînes les plus regardées
              </div>
              <div className="space-y-2">
                {byChannel.length === 0 && (
                  <div className="text-xs text-ink-tertiary">Personne ne regarde pour l'instant.</div>
                )}
                {byChannel.map(([name, n]) => (
                  <Bar key={name} label={`▶ ${name}`} value={n} max={byChannel[0][1]} tone="accent" />
                ))}
              </div>
            </div>

            {/* Qualité du streaming (déduite du nom de chaîne) */}
            <div className="rounded-xl border border-white/5 bg-midnight p-4">
              <div className="mb-3 flex items-center justify-between">
                <span className="text-[11px] uppercase tracking-widest text-ink-tertiary">
                  Qualité du streaming
                </span>
                <span className="text-[10px] text-ink-muted">estimée d'après le nom de chaîne</span>
              </div>
              <div className="grid grid-cols-5 gap-2 text-center">
                {(['4K', 'FHD', 'HD', 'SD', 'Autre'] as const).map((q) => (
                  <div key={q} className="rounded-lg border border-white/5 bg-obsidian p-2">
                    <div className="text-lg font-bold text-ink-primary">{quality[q]}</div>
                    <div className="text-[10px] uppercase tracking-wider text-ink-tertiary">{q}</div>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* ============ CARTE DES CONNEXIONS PAR PAYS ============ */}
          {byCountry.length > 0 && (
            <>
              <SectionTitle>Connexions par pays</SectionTitle>
              <div className="rounded-xl border border-white/5 bg-midnight p-4">
                <div className="grid gap-x-6 gap-y-2 sm:grid-cols-2">
                  {byCountry.map(([code, n]) => (
                    <Bar
                      key={code}
                      label={
                        <span className="flex items-center gap-1.5">
                          <span className="text-base">{flagEmoji(code)}</span>
                          {code}
                        </span>
                      }
                      value={n}
                      max={byCountry[0][1]}
                      tone="success"
                    />
                  ))}
                </div>
              </div>
            </>
          )}

          {/* ============ ALERTES INTELLIGENTES ============ */}
          <SectionTitle>Alertes intelligentes</SectionTitle>
          <div className="space-y-2">
            {alerts.length === 0 ? (
              <div className="rounded-xl border border-success/20 bg-success/[0.05] px-4 py-3 text-sm text-success">
                ✓ Aucune anomalie détectée.
              </div>
            ) : (
              alerts.map((a) => (
                <div
                  key={a.id}
                  className={cn(
                    'flex items-center gap-3 rounded-xl border px-4 py-2.5 text-sm',
                    a.sev === 'red'
                      ? 'border-accent/30 bg-accent/[0.07] text-accent-bright'
                      : 'border-warning/25 bg-warning/[0.06] text-warning-bright',
                  )}
                >
                  <span className="text-base">{a.icon}</span>
                  <span className="text-ink-secondary">{a.text}</span>
                </div>
              ))
            )}
          </div>

          {/* ============ SANTÉ DES SERVEURS (honnête) ============ */}
          <SectionTitle>Santé des serveurs & réseau</SectionTitle>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <div className="rounded-xl border border-white/5 bg-midnight p-4">
              <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                API temps réel
              </div>
              <div
                className={cn(
                  'mt-1 text-2xl font-bold',
                  apiTone === 'success'
                    ? 'text-success'
                    : apiTone === 'warning'
                      ? 'text-warning-bright'
                      : apiTone === 'accent'
                        ? 'text-accent-bright'
                        : 'text-ink-primary',
                )}
              >
                {apiMs == null ? '—' : `${apiMs} ms`}
              </div>
              <div className="mt-1 flex items-center gap-1.5 text-[11px] text-ink-tertiary">
                <span
                  className={cn(
                    'inline-block h-2 w-2 rounded-full',
                    apiTone === 'success'
                      ? 'bg-success'
                      : apiTone === 'warning'
                        ? 'bg-warning'
                        : apiTone === 'accent'
                          ? 'bg-accent'
                          : 'bg-ink-muted',
                  )}
                />
                {connected ? 'WebSocket connecté' : 'WebSocket indisponible'}
              </div>
            </div>
            {/* Métriques d'infra non instrumentées → honnêteté (pas de faux chiffres). */}
            {[
              { k: 'CPU serveur', why: 'agent serveur requis' },
              { k: 'RAM serveur', why: 'agent serveur requis' },
              { k: 'Bande passante', why: 'métrique passerelle requise' },
            ].map((m) => (
              <div key={m.k} className="rounded-xl border border-dashed border-white/10 bg-obsidian p-4">
                <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{m.k}</div>
                <div className="mt-1 text-2xl font-bold text-ink-muted">—</div>
                <div className="mt-1 text-[11px] text-ink-tertiary">Non instrumenté · {m.why}</div>
              </div>
            ))}
          </div>

          {/* ============ RECHERCHE AVANCÉE ============ */}
          <SectionTitle>Activité utilisateur</SectionTitle>
          <div className="mb-3 flex flex-wrap items-center gap-2">
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Rechercher : MAC, IP, pays, chaîne, appareil, version…"
              className="min-w-[240px] flex-1 rounded-lg border border-white/10 bg-obsidian px-3 py-2 text-sm text-ink-primary outline-none placeholder:text-ink-muted focus:border-accent/50"
            />
            <span className="text-xs text-ink-tertiary">
              {filtered.length} résultat{filtered.length > 1 ? 's' : ''}
              {filtered.length > VISIBLE_CAP ? ` · ${VISIBLE_CAP} affichés` : ''}
            </span>
          </div>

          {/* ============ TABLEAU ACTIVITÉ UTILISATEUR ============ */}
          <div className="overflow-x-auto rounded-xl border border-white/5">
            <table className="w-full text-left text-sm">
              <thead className="bg-midnight text-[10px] uppercase tracking-widest text-ink-tertiary">
                <tr>
                  <th className="px-4 py-2.5">Pays</th>
                  <th className="px-4 py-2.5">Appareil</th>
                  <th className="px-4 py-2.5">App</th>
                  <th className="px-4 py-2.5">IP</th>
                  <th className="px-4 py-2.5">MAC</th>
                  <th className="px-4 py-2.5">Regarde</th>
                  <th className="px-4 py-2.5">Session</th>
                  <th className="px-4 py-2.5">Connecté</th>
                  <th className="px-4 py-2.5">Vu</th>
                  <th className="px-4 py-2.5 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((r) => {
                  const kind = tvKind(r.platform, r.model);
                  return (
                    <tr key={r.mac} className="border-t border-white/5">
                      <td className="whitespace-nowrap px-4 py-2.5">
                        {r.live && (
                          <span className="mr-1.5 inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-success align-middle" />
                        )}
                        <span className="mr-1.5">{flagEmoji(r.country)}</span>
                        {r.country || '—'}
                      </td>
                      <td className="whitespace-nowrap px-4 py-2.5 text-xs text-ink-secondary">
                        {kind ? `📺 ${kind}` : platformLabel(r.platform)}
                        {r.model ? <span className="ml-1.5 text-ink-tertiary">{r.model}</span> : null}
                      </td>
                      <td className="whitespace-nowrap px-4 py-2.5 font-mono text-xs text-ink-secondary">
                        {r.appVersion || '—'}
                      </td>
                      <td className="whitespace-nowrap px-4 py-2.5 font-mono text-xs text-ink-secondary">
                        {r.ip || '—'}
                      </td>
                      <td className="px-4 py-2.5 text-xs">
                        <MacLink mac={r.mac} />
                      </td>
                      <td className="px-4 py-2.5 text-xs">
                        {r.channel ? (
                          <span className="inline-flex items-center gap-1 text-accent-bright">▶ {r.channel}</span>
                        ) : (
                          <span className="text-ink-tertiary">—</span>
                        )}
                      </td>
                      <td className="whitespace-nowrap px-4 py-2.5 text-xs text-ink-secondary">
                        {r.connectedAt ? dur(Date.now() - r.connectedAt) : '—'}
                      </td>
                      <td className="whitespace-nowrap px-4 py-2.5 text-xs text-ink-tertiary">
                        {hhmm(r.connectedAt)}
                      </td>
                      <td className="whitespace-nowrap px-4 py-2.5 text-xs text-ink-tertiary">
                        {ago(r.lastSeen)}
                      </td>
                      <td className="whitespace-nowrap px-4 py-2.5 text-right">
                        <div className="inline-flex items-center gap-1">
                          <ActionBtn title="Copier la MAC" onClick={() => copy(r.mac, 'MAC')}>
                            ⧉
                          </ActionBtn>
                          {r.ip && (
                            <ActionBtn title="Copier l'IP" onClick={() => copy(r.ip!, 'IP')}>
                              IP
                            </ActionBtn>
                          )}
                          <ActionBtn title="Envoyer une notification" onClick={() => notify(r.mac)}>
                            ✉
                          </ActionBtn>
                          {r.live && (
                            <ActionBtn
                              title="Redémarrer le flux (re-sync)"
                              onClick={() => restartStream(r.mac)}
                            >
                              ↻
                            </ActionBtn>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
                {visible.length === 0 && (
                  <tr>
                    <td colSpan={10} className="px-4 py-6 text-center text-xs text-ink-tertiary">
                      {query
                        ? 'Aucun résultat pour cette recherche.'
                        : 'Personne en ligne dans les 15 dernières minutes.'}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          <p className="mt-3 text-[11px] text-ink-tertiary">
            Astuce : clique sur une MAC pour la fiche 360° (profil, abonnement, historique). Les
            métriques d'infrastructure (CPU / RAM / bande passante / débit par flux) nécessitent un
            agent côté serveurs de streaming — elles sont volontairement laissées vides plutôt que
            simulées.
          </p>
        </>
      )}
    </AppLayout>
  );
}

/// Petit bouton d'action de ligne (icône), style cohérent avec le panel.
function ActionBtn({
  children,
  title,
  onClick,
}: {
  children: ReactNode;
  title: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      title={title}
      onClick={onClick}
      className="inline-flex h-7 min-w-7 items-center justify-center rounded-md border border-white/10 bg-obsidian px-1.5 text-xs text-ink-secondary transition hover:border-accent/40 hover:text-accent-bright"
    >
      {children}
    </button>
  );
}
