import { ReactNode } from 'react';
import { Sidebar } from './Sidebar';

interface AppLayoutProps {
  children: ReactNode;
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  onLogout: () => void;
}

/// Shell de page : Sidebar a gauche + Topbar (titre + actions) en
/// haut + zone contenu scrollable. Toutes les pages du panel
/// utilisent ce layout pour une UX coherente.
export function AppLayout({
  children,
  title,
  subtitle,
  actions,
  onLogout,
}: AppLayoutProps) {
  return (
    <div className="flex h-screen w-screen bg-obsidian text-ink-primary">
      <Sidebar onLogout={onLogout} />
      <main className="flex flex-1 flex-col overflow-hidden">
        {/* ===== Topbar ===== */}
        <header className="flex h-16 shrink-0 items-center justify-between border-b border-white/5 px-8">
          <div>
            <h1 className="text-lg font-semibold tracking-tight">{title}</h1>
            {subtitle && (
              <p className="text-xs text-ink-tertiary">{subtitle}</p>
            )}
          </div>
          <div className="flex items-center gap-3">{actions}</div>
        </header>

        {/* ===== Content ===== */}
        <div className="flex-1 overflow-y-auto px-8 py-8">{children}</div>
      </main>
    </div>
  );
}
