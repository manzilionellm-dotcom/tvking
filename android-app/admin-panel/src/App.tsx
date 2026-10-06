import { useCallback, useEffect, useState } from 'react';
import { Navigate, Route, Routes, useNavigate, useLocation } from 'react-router-dom';
import {
  authApi, getToken, setToken, setCurrentUser,
  ApiError,
} from '@/lib/api';
import { LoginPage } from '@/pages/LoginPage';
import { DashboardPage } from '@/pages/DashboardPage';
import { CustomersPage } from '@/pages/CustomersPage';
import { DevicesPage } from '@/pages/DevicesPage';
import { AppsPage } from '@/pages/AppsPage';
import { ServersPage } from '@/pages/ServersPage';
import { ActivationsPage } from '@/pages/ActivationsPage';
import { ResellersPage } from '@/pages/ResellersPage';
import { ActivatePage } from '@/pages/ActivatePage';
import { ChainesPage } from '@/pages/ChainesPage';
import { NotificationsPage } from '@/pages/NotificationsPage';
import { HomeManagerPage } from '@/pages/HomeManagerPage';
import { ControlCenterPage } from '@/pages/ControlCenterPage';
import { ForceUpdatePage } from '@/pages/ForceUpdatePage';
import { OnlinePage } from '@/pages/OnlinePage';
import { FeaturedPage } from '@/pages/FeaturedPage';
import { ThemePage } from '@/pages/ThemePage';
import { AdPage } from '@/pages/AdPage';
import { TarifsPage } from '@/pages/TarifsPage';
import { ReviewsPage } from '@/pages/ReviewsPage';
import { AccountPage } from '@/pages/AccountPage';
import { HistoryPage } from '@/pages/HistoryPage';
import { ReferencesPage } from '@/pages/ReferencesPage';
import { TransferPage } from '@/pages/TransferPage';
import { FamiliesPage } from '@/pages/FamiliesPage';
import { BlackBoxPage } from '@/pages/BlackBoxPage';
import { startPanelChannel } from '@/lib/box-channel';

/// Etats possibles de l'app :
///   - bootstrapping : on verifie si le token est encore valide
///   - logged_in     : token OK, on rend les pages
///   - logged_out    : on rend LoginPage
type AuthStatus = 'bootstrapping' | 'logged_in' | 'logged_out';

export default function App() {
  const [status, setStatus] = useState<AuthStatus>('bootstrapping');
  const nav = useNavigate();

  // Au chargement initial, on tente /auth/me avec le token stocke.
  // Si 401 → on flush et on bascule en logged_out.
  useEffect(() => {
    const t = getToken();
    if (!t) {
      setStatus('logged_out');
      return;
    }
    authApi.me()
      .then((r) => { setCurrentUser(r.user); setStatus('logged_in'); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) setToken(null);
        setStatus('logged_out');
      });
  }, []);

  const handleLoggedIn = useCallback(() => {
    // On recharge le profil (role + solde) avant d'afficher les pages,
    // pour que la Sidebar et le routage connaissent owner vs revendeur.
    authApi.me()
      .then((r) => { setCurrentUser(r.user); })
      .catch(() => {})
      .finally(() => { setStatus('logged_in'); nav('/'); });
  }, [nav]);

  useEffect(() => {
    if (status !== 'logged_in') return;
    return startPanelChannel();
  }, [status]);

  const handleLogout = useCallback(() => {
    setToken(null);
    setCurrentUser(null);
    setStatus('logged_out');
    nav('/login');
  }, [nav]);

  if (status === 'bootstrapping') {
    return (
      <div
        role="status"
        aria-live="polite"
        className="flex h-screen w-screen flex-col items-center justify-center gap-3 bg-obsidian"
      >
        <div className="h-9 w-9 animate-pulse rounded-lg bg-accent/20 ring-1 ring-accent/40" />
        <p className="text-sm text-ink-secondary">Chargement du panneau…</p>
      </div>
    );
  }

  if (status === 'logged_out') {
    return (
      <Routes>
        <Route path="/login" element={<LoginPage onLoggedIn={handleLoggedIn} />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    );
  }

  // Logged in
  return (
    <Routes>
      <Route path="/login" element={<Navigate to="/" replace />} />
      <Route path="/"            element={<DashboardPage   onLogout={handleLogout} />} />
      <Route path="/activate"    element={<ActivatePage    onLogout={handleLogout} />} />
      {/* Ancienne adresse d'un 2e écran d'activation (fusionné le 06/10/2026
          dans /activate) : on y mène, MAC comprise (?mac=…). */}
      <Route path="/activation-distance" element={<RedirectKeepQuery to="/activate" />} />
      {/* Liste de chaînes : écran à part. L'ancienne adresse y mène. */}
      <Route path="/chaines"    element={<ChainesPage     onLogout={handleLogout} />} />
      <Route path="/playlists"   element={<Navigate to="/chaines" replace />} />
      <Route path="/notifications" element={<NotificationsPage onLogout={handleLogout} />} />
      <Route path="/control-center" element={<ControlCenterPage onLogout={handleLogout} />} />
      <Route path="/home-manager" element={<HomeManagerPage onLogout={handleLogout} />} />
      <Route path="/force-update" element={<ForceUpdatePage onLogout={handleLogout} />} />
      <Route path="/online" element={<OnlinePage onLogout={handleLogout} />} />
      <Route path="/featured" element={<FeaturedPage onLogout={handleLogout} />} />
      <Route path="/theme" element={<ThemePage onLogout={handleLogout} />} />
      <Route path="/ad" element={<AdPage onLogout={handleLogout} />} />
      <Route path="/tarifs" element={<TarifsPage onLogout={handleLogout} />} />
      <Route path="/reviews" element={<ReviewsPage onLogout={handleLogout} />} />
      <Route path="/customers"   element={<CustomersPage   onLogout={handleLogout} />} />
      <Route path="/devices"     element={<DevicesPage     onLogout={handleLogout} />} />
      <Route path="/apps"        element={<AppsPage        onLogout={handleLogout} />} />
      <Route path="/servers"     element={<ServersPage     onLogout={handleLogout} />} />
      <Route path="/activations" element={<ActivationsPage onLogout={handleLogout} />} />
      {/* Revendeurs : owner ET revendeurs (qui gerent leurs sous-revendeurs).
          Les permissions/scoping sont appliques cote API. */}
      <Route path="/resellers" element={<ResellersPage onLogout={handleLogout} />} />
      <Route path="/account" element={<AccountPage onLogout={handleLogout} />} />
      <Route path="/history" element={<HistoryPage onLogout={handleLogout} />} />
      <Route path="/references" element={<ReferencesPage onLogout={handleLogout} />} />
      <Route path="/transfer" element={<TransferPage onLogout={handleLogout} />} />
      <Route path="/families" element={<FamiliesPage onLogout={handleLogout} />} />
      <Route path="/blackbox" element={<BlackBoxPage onLogout={handleLogout} />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

/// Redirection qui garde la requête (`?mac=…`) : les liens déjà copiés ou
/// mis en favori vers l'ancienne adresse continuent de marcher.
function RedirectKeepQuery({ to }: { to: string }) {
  const { search } = useLocation();
  return <Navigate to={to + search} replace />;
}
