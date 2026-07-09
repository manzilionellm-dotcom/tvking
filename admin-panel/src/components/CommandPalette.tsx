import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  customersApi, devicesApi, getCurrentUser, isOwnerRole, userCan,
  type Customer, type Device,
} from '@/lib/api';

/// PALETTE DE COMMANDES (Ctrl+K / ⌘K) — recherche globale du panel.
///  • Navigation : tape le nom d'une page ("sources", "produits"…)
///  • MAC : tape/colle une MAC → activer, pousser des sources, voir la fiche
///  • Recherche live : appareils (MAC/label/client) et clients (nom/email)
/// Clavier : ↑/↓ pour choisir, Entrée pour ouvrir, Échap pour fermer.

type Item = {
  id: string;
  group: 'Actions' | 'Pages' | 'Appareils' | 'Clients';
  label: string;
  hint?: string;
  to: string;
};

/// Pages navigables (owner) — les revendeurs n'ont que leurs entrées.
const OWNER_PAGES: { label: string; to: string; keywords: string }[] = [
  { label: 'Tableau de bord', to: '/', keywords: 'dashboard accueil stats' },
  { label: 'Activer un appareil', to: '/activate', keywords: 'activation licence abonnement mac' },
  { label: 'Sources M3U / Xtream', to: '/sources', keywords: 'playlist m3u xtream source pousser' },
  { label: 'Réseau & localisation', to: '/network', keywords: 'ip proxy pays voyage sortie localisation bloque' },
  { label: 'Serveurs', to: '/servers', keywords: 'serveur iptv defaut' },
  { label: 'Activations', to: '/activations', keywords: 'licences abonnements' },
  { label: 'Clients', to: '/customers', keywords: 'customers acheteurs' },
  { label: 'Appareils', to: '/devices', keywords: 'devices mac tv box' },
  { label: 'Revendeurs', to: '/resellers', keywords: 'resellers credits' },
  { label: 'Famille', to: '/families', keywords: 'family partage' },
  { label: 'Transférer', to: '/transfer', keywords: 'transfert changement appareil' },
  { label: 'Références', to: '/references', keywords: 'carnet usernames' },
  { label: 'Annonces', to: '/notifications', keywords: 'nouveautes notifications broadcast info promo' },
  { label: 'Produits & publications', to: '/products', keywords: 'produit offre publier' },
  { label: 'Favori du jour', to: '/featured', keywords: 'chaine vedette' },
  { label: 'Accueil de l\'app', to: '/home-manager', keywords: 'home sections layout' },
  { label: 'Thème', to: '/theme', keywords: 'couleur nom app branding' },
  { label: 'Centre de contrôle', to: '/control-center', keywords: 'control modules' },
  { label: 'Avis clients', to: '/reviews', keywords: 'feedback notes etoiles' },
  { label: 'Tarifs', to: '/tarifs', keywords: 'prix pricing essai promo' },
  { label: 'Pub vidéo', to: '/ad', keywords: 'publicite ads video' },
  { label: 'En ligne', to: '/online', keywords: 'presence live pays ip' },
  { label: 'Accès à l\'app', to: '/app-access', keywords: 'maintenance verrouille kill switch' },
  { label: 'Mise à jour forcée', to: '/force-update', keywords: 'update version build' },
  { label: 'API & intégrations', to: '/integrations', keywords: 'api cles webhooks integration' },
  { label: 'Applications', to: '/apps', keywords: 'apps produit package' },
  { label: 'Historique', to: '/history', keywords: 'audit journal logs' },
  { label: 'Mon compte', to: '/account', keywords: 'mot de passe 2fa langue' },
];

const RESELLER_PAGES: { label: string; to: string; keywords: string; cap?: string }[] = [
  { label: 'Tableau de bord', to: '/', keywords: 'dashboard' },
  { label: 'Activer un appareil', to: '/activate', keywords: 'activation mac', cap: 'activate' },
  { label: 'Sources M3U / Xtream', to: '/sources', keywords: 'playlist m3u xtream', cap: 'sources' },
  { label: 'Mes appareils', to: '/devices', keywords: 'devices mac', cap: 'devices' },
  { label: 'Mes activations', to: '/activations', keywords: 'licences', cap: 'activations' },
  { label: 'Mon compte', to: '/account', keywords: 'mot de passe' },
];

/// Extrait une MAC (avec ou sans préfixe MK:, séparateurs libres).
function parseMac(q: string): string | null {
  const hex = q.toUpperCase().replace(/^MK[:\s]*/, '').replace(/[^0-9A-F]/g, '');
  if (hex.length !== 10) return null;
  return 'MK:' + (hex.match(/.{2}/g) || []).join(':');
}

export function CommandPalette() {
  const nav = useNavigate();
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState('');
  const [sel, setSel] = useState(0);
  const [devices, setDevices] = useState<Device[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);
  const debounceRef = useRef<number | undefined>(undefined);

  const user = getCurrentUser();
  const owner = isOwnerRole(user?.role);

  // Raccourci global Ctrl+K / ⌘K (+ Échap pour fermer).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setOpen((o) => !o);
      } else if (e.key === 'Escape') {
        setOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => {
    if (open) {
      setQ(''); setSel(0); setDevices([]); setCustomers([]);
      // Focus après le rendu du modal.
      window.setTimeout(() => inputRef.current?.focus(), 30);
    }
  }, [open]);

  // Recherche live (débouncée) sur appareils + clients.
  useEffect(() => {
    window.clearTimeout(debounceRef.current);
    const query = q.trim();
    if (query.length < 2 || parseMac(query)) {
      setDevices([]); setCustomers([]);
      return;
    }
    debounceRef.current = window.setTimeout(() => {
      devicesApi.list(query).then((r) => setDevices(r.items.slice(0, 5))).catch(() => {});
      if (owner) {
        customersApi.list(query).then((r) => setCustomers(r.items.slice(0, 5))).catch(() => {});
      }
    }, 250);
    return () => window.clearTimeout(debounceRef.current);
  }, [q, owner]);

  const items = useMemo<Item[]>(() => {
    const out: Item[] = [];
    const query = q.trim().toLowerCase();
    const mac = parseMac(q.trim());

    if (mac) {
      // Une MAC collée = les 3 gestes du quotidien, directement.
      if (userCan(user, 'activate')) {
        out.push({ id: 'act', group: 'Actions', label: `Activer ${mac}`, hint: 'licence', to: `/activate?mac=${encodeURIComponent(mac)}` });
      }
      if (userCan(user, 'sources')) {
        out.push({ id: 'src', group: 'Actions', label: `Pousser des sources sur ${mac}`, hint: 'M3U / Xtream', to: `/sources?mac=${encodeURIComponent(mac)}` });
        out.push({ id: 'net', group: 'Actions', label: `Changer l'IP de ${mac}`, hint: 'réseau / voyage', to: `/network?mac=${encodeURIComponent(mac)}` });
      }
      out.push({ id: 'dev', group: 'Actions', label: `Voir la fiche de ${mac}`, hint: 'appareil', to: `/devices?q=${encodeURIComponent(mac)}` });
      return out;
    }

    const pages = owner
      ? OWNER_PAGES
      : RESELLER_PAGES.filter((p) => !p.cap || userCan(user, p.cap));
    for (const p of pages) {
      if (!query || p.label.toLowerCase().includes(query) || p.keywords.includes(query)) {
        out.push({ id: 'pg:' + p.to, group: 'Pages', label: p.label, to: p.to });
      }
    }
    for (const d of devices) {
      out.push({
        id: 'dv:' + d.id,
        group: 'Appareils',
        label: d.mac,
        hint: [d.label, d.customer_name].filter(Boolean).join(' · ') || undefined,
        to: `/devices?q=${encodeURIComponent(d.mac)}`,
      });
    }
    for (const c of customers) {
      out.push({
        id: 'cu:' + c.id,
        group: 'Clients',
        label: c.name || c.email || c.id,
        hint: c.email || undefined,
        to: `/customers?q=${encodeURIComponent(c.name || c.email || '')}`,
      });
    }
    return out.slice(0, 14);
  }, [q, devices, customers, owner, user]);

  const go = useCallback((item: Item | undefined) => {
    if (!item) return;
    setOpen(false);
    nav(item.to);
  }, [nav]);

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        title="Recherche globale (Ctrl+K)"
        className="hidden items-center gap-2 rounded-md border border-white/10 px-3 py-1.5 text-xs text-ink-tertiary transition hover:border-accent/40 hover:text-ink-secondary sm:flex"
      >
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <circle cx="11" cy="11" r="7" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
        Rechercher…
        <kbd className="rounded bg-white/5 px-1.5 py-0.5 font-mono text-[10px]">Ctrl K</kbd>
      </button>
    );
  }

  let lastGroup = '';
  return (
    <>
      {/* Le bouton reste rendu pour garder la topbar stable */}
      <button className="hidden sm:flex items-center gap-2 rounded-md border border-white/10 px-3 py-1.5 text-xs text-ink-tertiary" aria-hidden>
        Rechercher…
      </button>
      <div className="fixed inset-0 z-[60]" role="dialog" aria-modal>
        <div className="absolute inset-0 bg-black/70" onClick={() => setOpen(false)} />
        <div className="absolute left-1/2 top-24 w-full max-w-lg -translate-x-1/2 px-4">
          <div className="overflow-hidden rounded-xl border border-white/10 bg-midnight shadow-2xl">
            <input
              ref={inputRef}
              value={q}
              onChange={(e) => { setQ(e.target.value); setSel(0); }}
              onKeyDown={(e) => {
                if (e.key === 'ArrowDown') { e.preventDefault(); setSel((s) => Math.min(s + 1, items.length - 1)); }
                else if (e.key === 'ArrowUp') { e.preventDefault(); setSel((s) => Math.max(s - 1, 0)); }
                else if (e.key === 'Enter') { e.preventDefault(); go(items[sel]); }
              }}
              placeholder="Page, MAC, client, action…"
              className="w-full border-b border-white/5 bg-transparent px-4 py-3.5 text-sm outline-none placeholder:text-ink-muted"
            />
            <div className="max-h-80 overflow-y-auto py-1.5">
              {items.length === 0 && (
                <p className="px-4 py-6 text-center text-sm text-ink-tertiary">
                  Aucun résultat. Colle une MAC pour agir directement dessus.
                </p>
              )}
              {items.map((it, i) => {
                const showGroup = it.group !== lastGroup;
                lastGroup = it.group;
                return (
                  <div key={it.id}>
                    {showGroup && (
                      <div className="px-4 pb-1 pt-2 text-[10px] font-semibold uppercase tracking-widest text-ink-muted">
                        {it.group}
                      </div>
                    )}
                    <button
                      onMouseEnter={() => setSel(i)}
                      onClick={() => go(it)}
                      className={
                        'flex w-full items-center justify-between gap-3 px-4 py-2 text-left text-sm transition ' +
                        (i === sel ? 'bg-accent/10 text-ink-primary' : 'text-ink-secondary')
                      }
                    >
                      <span className={it.group === 'Appareils' ? 'font-mono text-xs' : ''}>{it.label}</span>
                      {it.hint && <span className="shrink-0 truncate text-[11px] text-ink-tertiary">{it.hint}</span>}
                    </button>
                  </div>
                );
              })}
            </div>
            <div className="flex items-center gap-3 border-t border-white/5 px-4 py-2 text-[10px] text-ink-muted">
              <span><kbd className="rounded bg-white/5 px-1 py-0.5 font-mono">↑↓</kbd> naviguer</span>
              <span><kbd className="rounded bg-white/5 px-1 py-0.5 font-mono">↵</kbd> ouvrir</span>
              <span><kbd className="rounded bg-white/5 px-1 py-0.5 font-mono">esc</kbd> fermer</span>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
