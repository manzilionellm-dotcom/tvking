import { ReactNode, useEffect, useState } from 'react';
import { Sidebar } from './Sidebar';
import { useT } from '@/lib/i18n';

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
  const t = useT();

  // Échap ferme le tiroir mobile (le clic sur le fond le fermait déjà).
  useEffect(() => {
    if (!navOpen) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setNavOpen(false);
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [navOpen]);

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-obsidian text-ink-primary">
      <a href="#contenu" className="skip-link">
        {t('a11y.skip')}
      </a>

      <div className="hidden md:block">
        <Sidebar onLogout={onLogout} />
      </div>

      {navOpen && (
        <div className="fixed inset-0 z-50 md:hidden" role="presentation">
          <button
            type="button"
            aria-label={t('a11y.closeMenu')}
            className="absolute inset-0 bg-black/70"
            onClick={() => setNavOpen(false)}
          />
          <div
            className="absolute left-0 top-0 h-full"
            role="dialog"
            aria-modal="true"
            aria-label={t('a11y.nav')}
          >
            <Sidebar
              onLogout={onLogout}
              onNavigate={() => setNavOpen(false)}
              onClose={() => setNavOpen(false)}
            />
          </div>
        </div>
      )}

      <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <header className="flex min-h-16 shrink-0 flex-wrap items-center justify-between gap-2 border-b border-white/10 bg-midnight/80 px-4 py-2 md:flex-nowrap md:px-8">
          <div className="flex min-w-0 items-center gap-3">
            <button
              type="button"
              onClick={() => setNavOpen(true)}
              aria-label={t('a11y.openMenu')}
              aria-expanded={navOpen}
              className="-ml-1 grid h-10 w-10 shrink-0 place-items-center rounded-md text-ink-secondary hover:bg-white/5 hover:text-ink-primary md:hidden"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none"
                   stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
                <line x1="3" y1="6" x2="21" y2="6" />
                <line x1="3" y1="12" x2="21" y2="12" />
                <line x1="3" y1="18" x2="21" y2="18" />
              </svg>
            </button>
            <div className="min-w-0">
              <h1 className="truncate text-base font-semibold tracking-tight text-ink-primary md:text-lg">
                {title}
              </h1>
              {subtitle && (
                <p className="truncate text-xs text-ink-secondary">{subtitle}</p>
              )}
            </div>
          </div>
          {/* Actions de page + déconnexion, y compris sur mobile. */}
          <div className="flex min-w-0 flex-wrap items-center justify-end gap-2">
            {actions}
            <button
              type="button"
              onClick={onLogout}
              aria-label={t('common.logout')}
              title={t('common.logout')}
              className="flex items-center gap-1.5 rounded-md border border-white/15 px-2.5 py-1.5 text-xs font-medium text-ink-secondary transition hover:border-accent hover:text-accent-bright"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none"
                   stroke="currentColor" strokeWidth="2" strokeLinecap="round"
                   strokeLinejoin="round" aria-hidden="true">
                <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
                <polyline points="16 17 21 12 16 7" />
                <line x1="21" y1="12" x2="9" y2="12" />
              </svg>
              <span className="hidden sm:inline">{t('common.logout')}</span>
            </button>
          </div>
        </header>

        <div id="contenu" tabIndex={-1} className="flex-1 overflow-y-auto px-4 py-6 outline-none md:px-8 md:py-8">
          {children}
        </div>
      </main>
    </div>
  );
}
