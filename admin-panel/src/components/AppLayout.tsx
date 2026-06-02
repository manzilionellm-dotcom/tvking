import { ReactNode, useState } from 'react';
import { Sidebar } from './Sidebar';

interface AppLayoutProps {
  children: ReactNode;
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  onLogout: () => void;
}

/// Shell de page responsive :
///  - Desktop (md+) : Sidebar fixe a gauche + contenu.
///  - Mobile : Sidebar masquee ; un bouton hamburger ouvre un tiroir
///    qui glisse par-dessus. Le contenu prend toute la largeur.
/// Toutes les pages utilisent ce layout → mobile OK partout.
export function AppLayout({
  children,
  title,
  subtitle,
  actions,
  onLogout,
}: AppLayoutProps) {
  const [navOpen, setNavOpen] = useState(false);

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-obsidian text-ink-primary">
      {/* ===== Sidebar fixe (desktop) ===== */}
      <div className="hidden md:block">
        <Sidebar onLogout={onLogout} />
      </div>

      {/* ===== Tiroir mobile ===== */}
      {navOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <div
            className="absolute inset-0 bg-black/60"
            onClick={() => setNavOpen(false)}
          />
          <div className="absolute left-0 top-0 h-full">
            <Sidebar onLogout={onLogout} onNavigate={() => setNavOpen(false)} />
          </div>
        </div>
      )}

      <main className="flex flex-1 flex-col overflow-hidden">
        {/* ===== Topbar ===== */}
        <header className="flex h-16 shrink-0 items-center justify-between gap-3 border-b border-white/5 px-4 md:px-8">
          <div className="flex min-w-0 items-center gap-3">
            {/* Hamburger (mobile only) */}
            <button
              onClick={() => setNavOpen(true)}
              aria-label="Menu"
              className="md:hidden -ml-1 grid h-9 w-9 shrink-0 place-items-center rounded-md text-ink-secondary hover:bg-white/5 hover:text-ink-primary"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none"
                   stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <line x1="3" y1="6" x2="21" y2="6" />
                <line x1="3" y1="12" x2="21" y2="12" />
                <line x1="3" y1="18" x2="21" y2="18" />
              </svg>
            </button>
            <div className="min-w-0">
              <h1 className="truncate text-base font-semibold tracking-tight md:text-lg">
                {title}
              </h1>
              {subtitle && (
                <p className="truncate text-xs text-ink-tertiary">{subtitle}</p>
              )}
            </div>
          </div>
          {actions && (
            <div className="flex shrink-0 items-center gap-2">{actions}</div>
          )}
        </header>

        {/* ===== Contenu ===== */}
        <div className="flex-1 overflow-y-auto px-4 py-6 md:px-8 md:py-8">
          {children}
        </div>
      </main>
    </div>
  );
}
