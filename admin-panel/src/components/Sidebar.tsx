import { NavLink } from 'react-router-dom';
import { cn } from '@/lib/utils';
import { getCurrentUser, isOwnerRole, userCan } from '@/lib/api';
import { useRtStatus } from '@/lib/realtime';
import { useT } from '@/lib/i18n';

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

const OWNER_NAV: NavSection[] = [
  {
    titleKey: 'navsec.activation',
    items: [
      { key: 'nav.activate',    to: '/activate' },
      { key: 'nav.activations', to: '/activations' },
      { key: 'nav.customers',   to: '/customers' },
      { key: 'nav.devices',     to: '/devices' },
      { key: 'nav.radar',       to: '/radar' },
      { key: 'nav.resellers',   to: '/resellers' },
      { key: 'nav.credits',     to: '/credits' },
      { key: 'nav.families',    to: '/families' },
      { key: 'nav.transfer',    to: '/transfer' },
      { key: 'nav.shares',      to: '/shares' },
      { key: 'nav.masters',     to: '/masters' },
      { key: 'nav.adminMonitor', to: '/admin-monitor' },
      { key: 'nav.pricing',     to: '/tarifs' },
      { key: 'nav.references',  to: '/references' },
    ],
  },
  {
    titleKey: 'navsec.channels',
    items: [
      { key: 'nav.servers',     to: '/servers' },
      { key: 'nav.gateway',     to: '/gateway' },
    ],
  },
  {
    titleKey: 'navsec.content',
    items: [
      { key: 'nav.controlCenter', to: '/control-center' },
      { key: 'nav.homeManager',   to: '/home-manager' },
      { key: 'nav.featured',      to: '/featured' },
      { key: 'nav.theme',         to: '/theme' },
      { key: 'nav.ad',            to: '/ad' },
      { key: 'nav.affiliation',   to: '/affiliation' },
      { key: 'nav.notifications', to: '/notifications' },
      { key: 'nav.forceUpdate',   to: '/force-update' },
      { key: 'nav.reviews',       to: '/reviews' },
    ],
  },
  {
    titleKey: 'navsec.system',
    items: [
      { key: 'nav.dashboard', to: '/' },
      { key: 'nav.online',    to: '/online' },
      { key: 'nav.apps',      to: '/apps' },
      { key: 'nav.history',   to: '/history' },
      { key: 'nav.account',   to: '/account' },
    ],
  },
];

const RESELLER_NAV: NavSection[] = [
  {
    titleKey: 'navsec.activation',
    // Chaque entrée n'apparaît que si l'admin a coché le droit correspondant.
    items: [
      { key: 'nav.activate',      to: '/activate',    cap: 'activate' },
      { key: 'nav.families',      to: '/families',    cap: 'activate' },
      { key: 'nav.transfer',      to: '/transfer',    cap: 'transfer' },
      { key: 'nav.credits',       to: '/credits',     cap: 'buy_credits' },
      { key: 'nav.myResellers',   to: '/resellers',   cap: 'resellers' },
      { key: 'nav.myDevices',     to: '/devices',     cap: 'devices' },
      { key: 'nav.myActivations', to: '/activations', cap: 'activations' },
      { key: 'nav.references',    to: '/references',  cap: 'activations' },
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

export function Sidebar({
  onLogout,
  onNavigate,
}: { onLogout: () => void; onNavigate?: () => void }) {
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

  return (
    <aside className="flex h-screen w-60 shrink-0 flex-col border-r border-white/5 bg-obsidian">
      {/* ===== Brand ===== */}
      <div className="flex h-16 items-center gap-3 px-5 border-b border-white/5">
        <div className="h-8 w-8 rounded-lg bg-accent/15 ring-1 ring-accent/30 grid place-items-center">
          <span className="text-accent font-bold text-xs tracking-tight">TF</span>
        </div>
        <div className="flex flex-col">
          <span className="text-sm font-semibold tracking-tight">{t('brand')}</span>
          <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">
            {owner ? t('role.admin') : t('role.reseller')}
          </span>
        </div>
      </div>

      {/* ===== Solde credits (revendeur) ===== */}
      {!owner && user?.credit_balance !== undefined && (
        <div className="mx-3 mt-3 rounded-lg border border-accent/30 bg-accent/10 px-3 py-2">
          <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{t('common.credits')}</div>
          <div className="text-lg font-semibold text-accent-bright">{user.credit_balance}</div>
        </div>
      )}

      {/* ===== Nav (regroupée par sections) ===== */}
      <nav className="flex-1 overflow-y-auto px-2 py-4">
        {sections.map((section, idx) => (
          <div key={section.titleKey} className={cn(idx > 0 && 'mt-5')}>
            {/* Titre de section — sépare visuellement Activation / Chaînes / etc. */}
            <div className="px-3 pb-1.5 text-[10px] font-semibold uppercase tracking-widest text-ink-tertiary">
              {t(section.titleKey)}
            </div>
            <ul className="space-y-0.5">
              {section.items.map((item) => (
                <li key={item.to}>
                  <NavLink
                    to={item.to}
                    end={item.to === '/'}
                    onClick={() => onNavigate?.()}
                    className={({ isActive }) =>
                      cn(
                        'group relative flex items-center rounded-md px-3 py-2 text-sm transition-colors',
                        isActive
                          ? 'bg-white/5 text-ink-primary'
                          : 'text-ink-secondary hover:bg-white/[0.03] hover:text-ink-primary',
                      )
                    }
                  >
                    {({ isActive }) => (
                      <>
                        {isActive && (
                          <span className="absolute left-0 top-1/2 -translate-y-1/2 h-5 w-0.5 rounded-r bg-accent" />
                        )}
                        <span>{t(item.key)}</span>
                      </>
                    )}
                  </NavLink>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </nav>

      {/* ===== État temps réel (rôles admin uniquement) ===== */}
      {owner && <RtIndicator />}

      {/* ===== Logout ===== */}
      <div className="border-t border-white/5 p-3">
        <button
          onClick={onLogout}
          className="w-full rounded-md px-3 py-2 text-left text-sm text-ink-secondary hover:bg-white/5 hover:text-ink-primary"
        >
          {t('common.logout')}
        </button>
      </div>
    </aside>
  );
}

/// Petit indicateur d'état du WebSocket temps réel :
/// ● vert « Direct » quand connecté, ○ gris « Différé » sinon
/// (le panel retombe alors sur le polling HTTP classique).
function RtIndicator() {
  const status = useRtStatus();
  const live = status === 'connected';
  return (
    <div
      className="flex items-center gap-2 border-t border-white/5 px-5 py-2.5"
      title={live
        ? 'Temps réel actif : mises à jour instantanées'
        : 'Temps réel indisponible : rafraîchissement différé (polling)'}
    >
      <span
        className={cn(
          'h-1.5 w-1.5 rounded-full',
          live ? 'bg-success animate-pulse' : 'bg-white/20',
        )}
      />
      <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">
        {live ? 'Direct' : 'Différé'}
      </span>
    </div>
  );
}
