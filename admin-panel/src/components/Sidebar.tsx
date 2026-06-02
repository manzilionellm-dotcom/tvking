import { NavLink } from 'react-router-dom';
import { cn } from '@/lib/utils';
import { getCurrentUser, isOwnerRole } from '@/lib/api';
import { useT } from '@/lib/i18n';

// =========================================================
//  Sidebar — navigation principale du panel (multilangue)
// =========================================================
//  La navigation s'adapte au role : l'owner voit tout, le revendeur
//  ne voit que l'activation + ses propres donnees. Libelles traduits.
// =========================================================

type NavItem = { key: string; to: string };

const OWNER_NAV: NavItem[] = [
  { key: 'nav.dashboard',   to: '/' },
  { key: 'nav.activate',    to: '/activate' },
  { key: 'nav.resellers',   to: '/resellers' },
  { key: 'nav.customers',   to: '/customers' },
  { key: 'nav.devices',     to: '/devices' },
  { key: 'nav.apps',        to: '/apps' },
  { key: 'nav.servers',     to: '/servers' },
  { key: 'nav.activations', to: '/activations' },
  { key: 'nav.account',     to: '/account' },
];

const RESELLER_NAV: NavItem[] = [
  { key: 'nav.dashboard',     to: '/' },
  { key: 'nav.activate',      to: '/activate' },
  { key: 'nav.myResellers',   to: '/resellers' },
  { key: 'nav.myDevices',     to: '/devices' },
  { key: 'nav.myActivations', to: '/activations' },
  { key: 'nav.account',       to: '/account' },
];

export function Sidebar({
  onLogout,
  onNavigate,
}: { onLogout: () => void; onNavigate?: () => void }) {
  const t = useT();
  const user = getCurrentUser();
  const owner = isOwnerRole(user?.role);
  const nav = owner ? OWNER_NAV : RESELLER_NAV;

  return (
    <aside className="flex h-screen w-60 shrink-0 flex-col border-r border-white/5 bg-obsidian">
      {/* ===== Brand ===== */}
      <div className="flex h-16 items-center gap-3 px-5 border-b border-white/5">
        <div className="h-8 w-8 rounded-lg bg-accent/15 ring-1 ring-accent/30 grid place-items-center">
          <span className="text-accent font-bold text-sm">A</span>
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

      {/* ===== Nav ===== */}
      <nav className="flex-1 overflow-y-auto px-2 py-4">
        <ul className="space-y-0.5">
          {nav.map((item) => (
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
      </nav>

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
