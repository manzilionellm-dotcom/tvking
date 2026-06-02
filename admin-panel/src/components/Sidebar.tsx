import { NavLink } from 'react-router-dom';
import { cn } from '@/lib/utils';
import { getCurrentUser, isOwnerRole } from '@/lib/api';

// =========================================================
//  Sidebar — navigation principale du panel
// =========================================================
//  Style SaaS premium : fond obsidian, liens minimalistes,
//  indicateur de selection sur la gauche (barre ember), survol
//  doux. La navigation s'adapte au role : l'owner voit tout, le
//  revendeur ne voit que l'activation + ses propres donnees.
// =========================================================

type NavItem = { label: string; to: string; phase: '1.A' | '1.B' | '2+' };

const OWNER_NAV: NavItem[] = [
  { label: 'Dashboard',           to: '/',            phase: '1.A' },
  { label: 'Activer un appareil', to: '/activate',    phase: '1.A' },
  { label: 'Revendeurs',          to: '/resellers',   phase: '1.A' },
  { label: 'Customers',           to: '/customers',   phase: '1.A' },
  { label: 'Devices',             to: '/devices',     phase: '1.A' },
  { label: 'Apps',                to: '/apps',        phase: '1.A' },
  { label: 'Activations',         to: '/activations', phase: '1.A' },
];

const RESELLER_NAV: NavItem[] = [
  { label: 'Dashboard',           to: '/',            phase: '1.A' },
  { label: 'Activer un appareil', to: '/activate',    phase: '1.A' },
  { label: 'Mes appareils',       to: '/devices',     phase: '1.A' },
  { label: 'Mes activations',     to: '/activations', phase: '1.A' },
];

export function Sidebar({ onLogout }: { onLogout: () => void }) {
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
          <span className="text-sm font-semibold tracking-tight">
            Licensing Platform
          </span>
          <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">
            {owner ? 'Super Admin' : 'Revendeur'}
          </span>
        </div>
      </div>

      {/* ===== Solde credits (revendeur) ===== */}
      {!owner && user?.credit_balance !== undefined && (
        <div className="mx-3 mt-3 rounded-lg border border-accent/30 bg-accent/10 px-3 py-2">
          <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">Crédits</div>
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
                className={({ isActive }) =>
                  cn(
                    'group relative flex items-center justify-between rounded-md px-3 py-2 text-sm transition-colors',
                    isActive
                      ? 'bg-white/5 text-ink-primary'
                      : 'text-ink-secondary hover:bg-white/[0.03] hover:text-ink-primary',
                    item.phase !== '1.A' && 'opacity-60',
                  )
                }
              >
                {({ isActive }) => (
                  <>
                    {isActive && (
                      <span className="absolute left-0 top-1/2 -translate-y-1/2 h-5 w-0.5 rounded-r bg-accent" />
                    )}
                    <span>{item.label}</span>
                    {item.phase !== '1.A' && (
                      <span className="rounded-sm bg-white/5 px-1.5 py-0.5 text-[9px] uppercase tracking-wider text-ink-tertiary">
                        soon
                      </span>
                    )}
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
          Se déconnecter
        </button>
      </div>
    </aside>
  );
}
