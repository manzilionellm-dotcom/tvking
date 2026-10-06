import { NavLink } from 'react-router-dom';
import { cn } from '@/lib/utils';
import { getCurrentUser, isOwnerRole, userCan } from '@/lib/api';
import { LangSelect, useT } from '@/lib/i18n';

// =========================================================
//  Sidebar — navigation principale du panel (multilangue)
// =========================================================
//  La navigation s'adapte au role : l'owner voit tout, le revendeur
//  ne voit que l'activation + ses propres donnees. Libelles traduits.
// =========================================================

// `cap` (optionnel) = capacité requise pour voir l'entrée (revendeur).
// Sans `cap`, l'entrée est toujours visible. L'admin voit tout.
type NavItem = { key: string; to: string; cap?: string };
// Une section = un titre traduit (`titleKey`) + ses entrées. Le menu est
// REGROUPÉ par section pour séparer clairement l'ACTIVATION (abonnement,
// appareils, revendeurs…) des CHAÎNES & SOURCES (serveurs IPTV) — demande
// produit « bien séparer activation et chaînes ». Présentation uniquement :
// aucune logique d'activation/abonnement n'est touchée ici.
type NavSection = { titleKey: string; items: NavItem[] };

// Organisation « centre de contrôle » (06/10/2026) : chaque page existante
// est rangée dans un groupe métier, sans en renommer aucune ni en ajouter.
// Centre de contrôle (vue d'ensemble, en direct), Clients (abonnés,
// appareils, activations), Applications (versions, mise à jour forcée,
// avis), Revendeurs, Contenu (listes, serveurs, publicité, annonces, mise
// en avant, accueil, thème), Boîte noire, Système (journal, compte).
const OWNER_NAV: NavSection[] = [
  {
    titleKey: 'navsec.control',
    items: [
      { key: 'nav.dashboard',     to: '/' },
      { key: 'nav.online',        to: '/online' },
      { key: 'nav.controlCenter', to: '/control-center' },
    ],
  },
  {
    titleKey: 'navsec.customers',
    items: [
      { key: 'nav.customers',      to: '/customers' },
      { key: 'nav.devices',        to: '/devices' },
      { key: 'nav.activations',    to: '/activations' },
      { key: 'nav.remoteActivate', to: '/activation-distance' },
      { key: 'nav.activate',       to: '/activate' },
      { key: 'nav.transfer',       to: '/transfer' },
      { key: 'nav.families',       to: '/families' },
    ],
  },
  {
    titleKey: 'navsec.apps',
    items: [
      { key: 'nav.apps',        to: '/apps' },
      { key: 'nav.forceUpdate', to: '/force-update' },
      { key: 'nav.reviews',     to: '/reviews' },
    ],
  },
  {
    titleKey: 'navsec.resellers',
    items: [
      { key: 'nav.resellers',  to: '/resellers' },
      { key: 'nav.pricing',    to: '/tarifs' },
      { key: 'nav.references', to: '/references' },
    ],
  },
  {
    titleKey: 'navsec.content',
    items: [
      { key: 'nav.chaines',       to: '/chaines' },
      { key: 'nav.servers',       to: '/servers' },
      { key: 'nav.ad',            to: '/ad' },
      { key: 'nav.notifications', to: '/notifications' },
      { key: 'nav.featured',      to: '/featured' },
      { key: 'nav.homeManager',   to: '/home-manager' },
      { key: 'nav.theme',         to: '/theme' },
    ],
  },
  {
    titleKey: 'navsec.blackbox',
    items: [
      { key: 'nav.blackbox', to: '/blackbox' },
    ],
  },
  {
    titleKey: 'navsec.system',
    items: [
      { key: 'nav.history', to: '/history' },
      { key: 'nav.account', to: '/account' },
    ],
  },
];

const RESELLER_NAV: NavSection[] = [
  {
    titleKey: 'navsec.activation',
    // Chaque entrée n'apparaît que si l'admin a coché le droit correspondant.
    items: [
      { key: 'nav.remoteActivate', to: '/activation-distance', cap: 'activate' },
      { key: 'nav.activate',      to: '/activate',    cap: 'activate' },
      { key: 'nav.families',      to: '/families',    cap: 'activate' },
      { key: 'nav.transfer',      to: '/transfer',    cap: 'activate' },
      { key: 'nav.myResellers',   to: '/resellers',   cap: 'resellers' },
      { key: 'nav.myDevices',     to: '/devices',     cap: 'devices' },
      { key: 'nav.blackbox',      to: '/blackbox',    cap: 'devices' },
      { key: 'nav.myActivations', to: '/activations', cap: 'activations' },
      { key: 'nav.references',    to: '/references',  cap: 'activations' },
    ],
  },
  {
    titleKey: 'navsec.channels',
    items: [
      { key: 'nav.chaines', to: '/chaines', cap: 'sources' },
    ],
  },
  {
    titleKey: 'navsec.system',
    items: [
      { key: 'nav.dashboard', to: '/' },
      { key: 'nav.account',   to: '/account' },
    ],
  },
];

function NavIcon({ name }: { name: string }) {
  const common = {
    width: 16,
    height: 16,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.8,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    'aria-hidden': true as const,
  };
  switch (name) {
    case 'nav.dashboard':
      return <svg {...common}><rect x="3" y="3" width="7" height="7" rx="1.5" /><rect x="14" y="3" width="7" height="7" rx="1.5" /><rect x="3" y="14" width="7" height="7" rx="1.5" /><rect x="14" y="14" width="7" height="7" rx="1.5" /></svg>;
    case 'nav.activate':
      return <svg {...common}><path d="M13 2 4 14h7l-1 8 9-12h-7l1-8z" /></svg>;
    case 'nav.activations':
    case 'nav.myActivations':
      return <svg {...common}><path d="M9 11l3 3L22 4" /><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" /></svg>;
    case 'nav.customers':
    case 'nav.resellers':
    case 'nav.myResellers':
    case 'nav.families':
      return <svg {...common}><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="3" /><path d="M22 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a3 3 0 0 1 0 5.75" /></svg>;
    case 'nav.devices':
    case 'nav.myDevices':
      return <svg {...common}><rect x="3" y="4" width="18" height="14" rx="2" /><path d="M8 21h8" /></svg>;
    case 'nav.transfer':
      return <svg {...common}><path d="M7 7h11l-3-3" /><path d="M17 17H6l3 3" /></svg>;
    case 'nav.pricing':
      return <svg {...common}><path d="M20.6 13.4 12 22l-8-8 8.6-8.6a2 2 0 0 1 1.4-.6H20a2 2 0 0 1 2 2v6.6a2 2 0 0 1-.6 1.4z" /><circle cx="16" cy="8" r="1" /></svg>;
    case 'nav.references':
      return <svg {...common}><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" /><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" /></svg>;
    case 'nav.servers':
      return <svg {...common}><rect x="3" y="3" width="18" height="6" rx="1.5" /><rect x="3" y="15" width="18" height="6" rx="1.5" /><path d="M7 6h.01M7 18h.01" /></svg>;
    case 'nav.chaines':
      return <svg {...common}><path d="M8 6h13M8 12h13M8 18h13" /><path d="M3 6h.01M3 12h.01M3 18h.01" /></svg>;
    case 'nav.online':
      return <svg {...common}><path d="M2 12h2" /><path d="M20 12h2" /><path d="M12 2v2" /><circle cx="12" cy="12" r="3" /><path d="M5 19a9 9 0 0 1 14 0" /></svg>;
    case 'nav.history':
      return <svg {...common}><circle cx="12" cy="12" r="9" /><path d="M12 7v6l4 2" /></svg>;
    case 'nav.account':
      return <svg {...common}><circle cx="12" cy="8" r="3.5" /><path d="M5 20a7 7 0 0 1 14 0" /></svg>;
    case 'nav.notifications':
      return <svg {...common}><path d="M6 8a6 6 0 1 1 12 0c0 7 3 7 3 9H3c0-2 3-2 3-9" /><path d="M10 21a2 2 0 0 0 4 0" /></svg>;
    case 'nav.homeManager':
      return <svg {...common}><path d="M4 11.5 12 4l8 7.5" /><path d="M6 10.5V20h12v-9.5" /></svg>;
    default:
      return <svg {...common}><circle cx="12" cy="12" r="3" /><path d="M12 3v2M12 19v2M3 12h2M19 12h2" /></svg>;
  }
}

export function Sidebar({
  onLogout,
  onNavigate,
  onClose,
}: {
  onLogout: () => void;
  onNavigate?: () => void;
  onClose?: () => void;
}) {
  const t = useT();
  const user = getCurrentUser();
  const owner = isOwnerRole(user?.role);
  // Filtre par capacité : un revendeur ne voit que ce que son niveau ouvre.
  // On filtre les ENTRÉES puis on retire les sections devenues vides.
  const sections = (owner ? OWNER_NAV : RESELLER_NAV)
    .map((sec) => ({
      ...sec,
      items: sec.items.filter((it) => !it.cap || userCan(user, it.cap)),
    }))
    .filter((sec) => sec.items.length > 0);
  const who = user?.name || user?.email;

  return (
    <aside className="flex h-screen w-64 shrink-0 flex-col border-r border-white/10 bg-midnight">
      <div className="flex h-16 items-center gap-3 border-b border-white/10 px-4">
        <div className="grid h-9 w-9 place-items-center rounded-lg bg-accent/15 ring-1 ring-accent/40">
          <span className="text-xs font-bold tracking-tight text-accent">TF</span>
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold tracking-tight">{t('brand')}</p>
          <p className="truncate text-[11px] font-medium text-ink-secondary">
            {owner ? t('role.admin') : t('role.reseller')}
          </p>
        </div>
        {onClose && (
          <button
            type="button"
            onClick={onClose}
            autoFocus
            aria-label={t('a11y.closeMenu')}
            className="grid h-9 w-9 place-items-center rounded-md text-ink-secondary hover:bg-white/5 hover:text-ink-primary"
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
              <path d="M6 6l12 12M18 6 6 18" />
            </svg>
          </button>
        )}
      </div>

      {!owner && user?.credit_balance !== undefined && (
        <div className="mx-3 mt-3 rounded-lg border border-accent/30 bg-accent/10 px-3 py-2">
          <div className="text-[11px] font-medium text-ink-secondary">{t('common.credits')}</div>
          <div className="text-lg font-semibold text-accent-bright">{user.credit_balance}</div>
        </div>
      )}

      <nav aria-label={t('a11y.nav')} className="flex-1 overflow-y-auto px-2 py-4">
        {sections.map((section, idx) => (
          <div key={section.titleKey} className={cn(idx > 0 && 'mt-5 border-t border-white/5 pt-4')}>
            <p className="px-3 pb-1.5 text-[11px] font-semibold uppercase tracking-widest text-ink-secondary">
              {t(section.titleKey)}
            </p>
            <ul className="space-y-0.5">
              {section.items.map((item) => (
                <li key={item.to + item.key}>
                  <NavLink
                    to={item.to}
                    end={item.to === '/'}
                    onClick={() => onNavigate?.()}
                    className={({ isActive }) =>
                      cn(
                        'flex min-h-10 items-center gap-2.5 rounded-md px-3 py-2 text-sm transition-colors',
                        isActive
                          ? 'bg-accent/15 font-medium text-ink-primary ring-1 ring-accent/30'
                          : 'text-ink-secondary hover:bg-white/[0.04] hover:text-ink-primary',
                      )
                    }
                  >
                    <span className="text-accent-bright/90"><NavIcon name={item.key} /></span>
                    <span className="truncate">{t(item.key)}</span>
                  </NavLink>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </nav>

      <div className="space-y-2 border-t border-white/10 p-3">
        {who && (
          <p className="truncate px-1 text-xs text-ink-secondary" title={who}>
            {who}
          </p>
        )}
        <LangSelect className="w-full rounded-md border border-white/10 bg-slate px-2 py-2 text-xs text-ink-secondary" />
        <button
          type="button"
          onClick={onLogout}
          className="flex w-full items-center rounded-md px-3 py-2 text-left text-sm text-ink-secondary hover:bg-white/5 hover:text-ink-primary"
        >
          {t('common.logout')}
        </button>
      </div>
    </aside>
  );
}
