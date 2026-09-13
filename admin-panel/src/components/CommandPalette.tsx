// =========================================================
//  CommandPalette — Cmd+K / Ctrl+K (Vague A cockpit)
// =========================================================
//  Recherche globale : MAC, label, note, client (GET /devices?q= déjà
//  cloisonné revendeur) + pages nav (caps) + actions rapides Radar /
//  Devices / Activate. Pas de nouvel endpoint : on réutilise la liste.
// =========================================================

import { createContext, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { devicesApi, getCurrentUser, isOwnerRole, userCan, type Device } from '@/lib/api';
import { applyNew } from '@/components/NewBadge';
import { useDeviceSheet } from '@/components/DeviceSheet';
import { getVisibleNavPages } from '@/components/Sidebar';
import { useT } from '@/lib/i18n';
import { AboChip } from '@/components/DeviceOps';
import { cn, formatMacAsYouType } from '@/lib/utils';

const CmdkCtx = createContext<{ toggle: () => void } | null>(null);

type Hit =
  | { kind: 'action'; id: string; label: string; hint: string; run: () => void }
  | { kind: 'page'; id: string; label: string; hint: string; run: () => void }
  | { kind: 'device'; id: string; label: string; hint: string; device: Device; run: () => void };

export function CommandPaletteHost({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <CmdkCtx.Provider value={{ toggle: () => setOpen((v) => !v) }}>
      {children}
      <CommandPalette open={open} setOpen={setOpen} />
    </CmdkCtx.Provider>
  );
}

function CommandPalette({
  open,
  setOpen,
}: {
  open: boolean;
  setOpen: (v: boolean | ((p: boolean) => boolean)) => void;
}) {
  const [q, setQ] = useState('');
  const [hits, setHits] = useState<Device[]>([]);
  const [loading, setLoading] = useState(false);
  const [cursor, setCursor] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const nav = useNavigate();
  const sheet = useDeviceSheet();
  const t = useT();
  const user = getCurrentUser();
  const owner = isOwnerRole(user?.role);
  const canDevices = owner || userCan(user, 'devices');
  const canActivate = owner || userCan(user, 'activate');

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const isK = e.key === 'k' || e.key === 'K';
      if ((e.metaKey || e.ctrlKey) && isK) {
        e.preventDefault();
        setOpen((v) => !v);
      }
      if (e.key === 'Escape' && open) {
        e.preventDefault();
        setOpen(false);
      }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    setQ('');
    setHits([]);
    setCursor(0);
    const id = window.setTimeout(() => inputRef.current?.focus(), 30);
    return () => window.clearTimeout(id);
  }, [open]);

  useEffect(() => {
    if (!open || !canDevices) return;
    const term = q.trim();
    if (term.length < 2) {
      setHits([]);
      return;
    }
    let alive = true;
    const timer = window.setTimeout(() => {
      setLoading(true);
      devicesApi.list(term)
        .then((r) => { if (alive) setHits(r.items || []); })
        .catch(() => { if (alive) setHits([]); })
        .finally(() => { if (alive) setLoading(false); });
    }, 180);
    return () => { alive = false; window.clearTimeout(timer); };
  }, [q, open, canDevices]);

  function go(path: string) {
    setOpen(false);
    nav(path);
  }

  function openMac(mac: string, seed?: Device) {
    setOpen(false);
    sheet.open(mac, seed);
  }

  const pages = useMemo(() => getVisibleNavPages(), [open, user?.id, user?.role]);

  const rows: Hit[] = useMemo(() => {
    const term = q.trim().toLowerCase();
    const out: Hit[] = [];

    const actions: Hit[] = [];
    if (canDevices) {
      actions.push({
        kind: 'action',
        id: 'go-devices',
        label: 'Aller à Appareils',
        hint: 'Liste MAC',
        run: () => go('/devices'),
      });
    }
    if (owner) {
      actions.push({
        kind: 'action',
        id: 'go-radar',
        label: 'Aller au Radar',
        hint: 'Expirations',
        run: () => go('/radar'),
      });
    }
    if (canActivate) {
      actions.push({
        kind: 'action',
        id: 'go-activate',
        label: 'Aller à Activer',
        hint: 'Poser un abo',
        run: () => go('/activate'),
      });
    }
    for (const a of actions) {
      if (!term || a.label.toLowerCase().includes(term) || a.hint.toLowerCase().includes(term)) {
        out.push(a);
      }
    }

    for (const p of pages) {
      const label = t(p.key);
      if (term && !label.toLowerCase().includes(term) && !p.to.toLowerCase().includes(term)) continue;
      out.push({
        kind: 'page',
        id: `page-${p.to}`,
        label,
        hint: p.to,
        run: () => go(p.to),
      });
    }

    for (const d of hits) {
      out.push({
        kind: 'device',
        id: d.id,
        label: d.mac,
        hint: [d.customer_name, d.label, d.admin_note].filter(Boolean).join(' · ') || 'Ouvrir la fiche',
        device: d,
        run: () => openMac(d.mac, d),
      });
    }
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, hits, pages, owner, canDevices, canActivate]);

  useEffect(() => { setCursor(0); }, [rows.length, q]);

  function pick(i: number) {
    const row = rows[i];
    if (row) row.run();
  }

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-[80] flex items-start justify-center bg-black/55 px-3 pt-[12vh]"
      onClick={() => setOpen(false)}
    >
      <div
        {...applyNew('cmdk-palette', 'w-full max-w-xl overflow-hidden rounded-2xl border bg-midnight shadow-2xl')}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 border-b border-white/5 px-4 py-3">
          <span className="text-[10px] font-bold uppercase tracking-widest text-ink-tertiary">
            Cmd+K
          </span>
          <input
            ref={inputRef}
            value={q}
            onChange={(e) => setQ(formatMacAsYouType(e.target.value))}
            onKeyDown={(e) => {
              if (e.key === 'ArrowDown') {
                e.preventDefault();
                setCursor((c) => Math.min(c + 1, Math.max(0, rows.length - 1)));
              } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                setCursor((c) => Math.max(0, c - 1));
              } else if (e.key === 'Enter') {
                e.preventDefault();
                pick(cursor);
              }
            }}
            placeholder="MAC, client, note, page…"
            className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-ink-tertiary"
          />
          {loading && <span className="text-[10px] text-ink-tertiary">…</span>}
        </div>
        <ul className="max-h-[50vh] overflow-y-auto py-1">
          {rows.length === 0 && (
            <li className="px-4 py-6 text-center text-xs text-ink-tertiary">
              {q.trim().length < 2 && canDevices
                ? 'Tape au moins 2 caractères pour chercher une MAC / un client.'
                : 'Aucun résultat.'}
            </li>
          )}
          {rows.map((row, i) => (
            <li key={row.id}>
              <button
                type="button"
                onMouseEnter={() => setCursor(i)}
                onClick={() => pick(i)}
                className={cn(
                  'flex w-full items-center justify-between gap-3 px-4 py-2 text-left text-sm',
                  i === cursor ? 'bg-white/8 text-ink-primary' : 'text-ink-secondary hover:bg-white/[0.04]',
                )}
              >
                <span className="min-w-0">
                  <span className={cn('block truncate', row.kind === 'device' && 'font-mono text-xs text-accent')}>
                    {row.label}
                  </span>
                  <span className="block truncate text-[11px] text-ink-tertiary">{row.hint}</span>
                </span>
                <span className="shrink-0 text-[10px] uppercase tracking-widest text-ink-tertiary">
                  {row.kind === 'device' ? (
                    <AboChip license={row.device.license} />
                  ) : row.kind === 'action' ? (
                    'Action'
                  ) : (
                    'Page'
                  )}
                </span>
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

/// Bouton topbar — même ouverture que le raccourci clavier.
export function CommandPaletteTrigger() {
  const ctx = useContext(CmdkCtx);
  return (
    <button
      type="button"
      onClick={() => ctx?.toggle()}
      title="Recherche rapide (Cmd+K / Ctrl+K)"
      {...applyNew(
        'cmdk-trigger',
        'flex items-center gap-1.5 rounded-md border px-2 py-1.5 text-xs font-medium',
      )}
    >
      <span>Rechercher</span>
      <kbd className="rounded border border-white/10 px-1 py-0.5 text-[10px] text-ink-tertiary">
        ⌘K
      </kbd>
    </button>
  );
}
