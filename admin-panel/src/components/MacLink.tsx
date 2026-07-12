// =========================================================
//  MacLink — une MAC cliquable PARTOUT → fiche 360° instantanée
// =========================================================
//  Objectif (demande owner) : « n'importe quelle MAC que je vois dans le
//  panel doit être cliquable et me donner TOUTES les infos ». Ce composant
//  rend la MAC en lien, et gère LUI-MÊME l'ouverture d'un tiroir de détail
//  (lecture seule) — on peut donc le poser sur toutes les pages sans
//  ajouter d'état : il suffit de remplacer le texte `{mac}` par
//  `<MacLink mac={mac} />`.
//
//  La fiche est chargée via `devicesApi.overview(mac)` : le backend
//  accepte désormais l'ID OU la MAC (deviceForActor), et renvoie la méta
//  appareil + abonnement + présence live (dernière connexion, IP, pays,
//  chaîne en cours) + sources poussées + inventaire réel sur l'appareil.
// =========================================================

import { useEffect, useState } from 'react';
import { ApiError, devicesApi } from '@/lib/api';
import type { DeviceOverview } from '@/lib/api';
import { cn, formatDateTime } from '@/lib/utils';

function ago(ts: number | null | undefined): string {
  if (!ts) return '';
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 60) return `il y a ${s}s`;
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  if (s < 86400) return `il y a ${Math.floor(s / 3600)} h`;
  return `il y a ${Math.floor(s / 86400)} j`;
}

/// La MAC en lien accent + tiroir de détail auto-géré.
export function MacLink({
  mac,
  className,
}: {
  mac: string | null | undefined;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  if (!mac) return <span className="text-ink-tertiary">—</span>;
  return (
    <>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setOpen(true);
        }}
        title="Voir la fiche complète"
        className={cn(
          'font-mono text-xs text-accent underline-offset-2 hover:underline',
          className,
        )}
      >
        {mac}
      </button>
      {open && <MacDetailDrawer mac={mac} onClose={() => setOpen(false)} />}
    </>
  );
}

/// Tiroir de détail (lecture seule) — tout ce qu'on sait de la MAC.
function MacDetailDrawer({ mac, onClose }: { mac: string; onClose: () => void }) {
  const [ov, setOv] = useState<DeviceOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    devicesApi
      .overview(mac)
      .then((r) => {
        if (alive) {
          setOv(r);
          setErr(null);
        }
      })
      .catch((e) => {
        if (alive) {
          setErr(
            e instanceof ApiError
              ? e.status === 404
                ? "Cette MAC n'est pas encore enregistrée (aucun démarrage de l'app)."
                : e.message
              : 'Échec du chargement.',
          );
        }
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [mac]);

  const d = ov?.device ?? null;
  const p = ov?.presence ?? null;
  const lic = ov?.license ?? null;
  const sources = ov?.sources ?? [];
  const localSources = ov?.localSources ?? [];
  const lastSeen = p?.last_seen || d?.last_seen_at || 0;
  const st = d?.block_status || 'active';

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/60 px-4 py-10"
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold tracking-tight">Fiche appareil</h2>
            <p className="mt-0.5 font-mono text-xs text-accent">{mac}</p>
          </div>
          <span
            className={cn(
              'rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide',
              st === 'banned'
                ? 'bg-red-500/15 text-red-300'
                : st === 'frozen'
                  ? 'bg-amber-500/15 text-amber-300'
                  : 'bg-emerald-500/15 text-emerald-300',
            )}
          >
            {st === 'banned' ? 'Banni' : st === 'frozen' ? 'Gelé' : 'Actif'}
          </span>
        </div>

        {loading && <div className="h-40 animate-pulse rounded-lg bg-white/5" />}
        {err && (
          <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
            {err}
          </div>
        )}

        {!loading && !err && (
          <div className="space-y-4">
            {/* Connexion (live) */}
            <Section title="Connexion">
              <Row label="En ligne">
                <span className="inline-flex items-center gap-1.5">
                  <span
                    className={cn(
                      'inline-block h-2 w-2 rounded-full',
                      p?.online ? 'bg-emerald-400 shadow-[0_0_8px] shadow-emerald-400' : 'bg-ink-tertiary',
                    )}
                  />
                  {p?.online ? 'Oui' : 'Non'}
                </span>
              </Row>
              <Row label="Dernière connexion">
                {lastSeen ? `${formatDateTime(lastSeen)} · ${ago(lastSeen)}` : '—'}
              </Row>
              <Row label="Adresse IP" mono>
                {p?.ip || '—'}
              </Row>
              <Row label="Pays">{p?.country || '—'}</Row>
              <Row label="Chaîne en cours">{p?.channel || '—'}</Row>
            </Section>

            {/* Abonnement */}
            <Section title="Abonnement">
              <Row label="Statut">{lic ? lic.status : '—'}</Row>
              <Row label="Offre">{lic?.plan || '—'}</Row>
              <Row label="Expire le">
                {lic
                  ? lic.expires_at
                    ? formatDateTime(lic.expires_at)
                    : 'À vie'
                  : '—'}
              </Row>
            </Section>

            {/* Appareil */}
            <Section title="Appareil">
              <Row label="Client">{d?.customer_name || d?.label || '—'}</Row>
              <Row label="Plateforme">
                {d?.platform === 'tv'
                  ? '📺 TV'
                  : d?.platform === 'mobile'
                    ? '📱 Mobile'
                    : d?.platform || '—'}
              </Row>
              <Row label="Modèle">{d?.device_model || '—'}</Row>
              <Row label="Android">
                {d?.android_release ? `Android ${d.android_release}` : '—'}
              </Row>
              <Row label="Version app">
                {d?.app_version || (d?.app_build != null ? String(d.app_build) : '—')}
              </Row>
              <Row label="Première vue">
                {d?.first_seen_at ? formatDateTime(d.first_seen_at) : '—'}
              </Row>
              <Row label="Revendeur">{d?.reseller_id || '—'}</Row>
            </Section>

            {/* Sources poussées (M-Trio) */}
            <Section title={`Sources poussées · ${sources.length}`}>
              {sources.length === 0 ? (
                <p className="text-xs text-ink-tertiary">Aucune source poussée depuis le panel.</p>
              ) : (
                sources.map((s, i) => (
                  <div
                    key={i}
                    className="mb-1.5 rounded-lg border border-white/5 bg-obsidian px-3 py-2 text-xs"
                  >
                    <div className="font-semibold text-ink-secondary">
                      {(s.type || '?').toUpperCase()}
                      {s.label ? ` · ${s.label}` : ''}
                    </div>
                    {s.server_url && (
                      <div className="mt-0.5 break-all font-mono text-[11px] text-ink-tertiary">
                        {s.server_url}
                      </div>
                    )}
                    {s.username && (
                      <div className="font-mono text-[11px] text-ink-tertiary">
                        👤 {s.username}
                      </div>
                    )}
                    {s.m3u_url && (
                      <div className="mt-0.5 break-all font-mono text-[11px] text-ink-tertiary">
                        {s.m3u_url}
                      </div>
                    )}
                  </div>
                ))
              )}
            </Section>

            {/* Inventaire réel sur l'appareil */}
            {localSources.length > 0 && (
              <Section title={`Sur l'appareil du client · ${localSources.length}`}>
                {localSources.map((s, i) => (
                  <div
                    key={i}
                    className="mb-1.5 rounded-lg border border-white/5 bg-obsidian px-3 py-2 text-xs"
                  >
                    <div className="font-semibold text-ink-secondary">
                      {(s.type || '?').toUpperCase()} · {s.name || '—'}
                      {s.active ? ' · ✓ active' : ''}
                    </div>
                    {s.server && (
                      <div className="mt-0.5 break-all font-mono text-[11px] text-ink-tertiary">
                        {s.server}
                      </div>
                    )}
                    {s.username && (
                      <div className="font-mono text-[11px] text-ink-tertiary">👤 {s.username}</div>
                    )}
                    <div className="text-[11px] text-ink-tertiary">{s.channels} chaînes</div>
                  </div>
                ))}
              </Section>
            )}
          </div>
        )}

        <div className="flex justify-end pt-5">
          <button
            type="button"
            onClick={onClose}
            className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary"
          >
            Fermer
          </button>
        </div>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-white/5 bg-obsidian/40 p-3">
      <h3 className="mb-2 text-[10px] font-bold uppercase tracking-widest text-ink-tertiary">
        {title}
      </h3>
      <div className="space-y-1">{children}</div>
    </div>
  );
}

function Row({
  label,
  children,
  mono,
}: {
  label: string;
  children: React.ReactNode;
  mono?: boolean;
}) {
  return (
    <div className="flex items-start justify-between gap-3 text-sm">
      <span className="text-ink-tertiary">{label}</span>
      <span className={cn('text-right font-medium text-ink-primary', mono && 'font-mono text-xs')}>
        {children}
      </span>
    </div>
  );
}
