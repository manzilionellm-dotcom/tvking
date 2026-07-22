import { useCallback, useEffect, useState } from 'react';
import { Navigate, Route, Routes, useNavigate } from 'react-router-dom';
import {
  authApi, getToken, setToken, setCurrentUser, isOwnerRole,
  ApiError,
} from '@/lib/api';
import { rtConnect, rtDisconnect } from '@/lib/realtime';
import { LoginPage } from '@/pages/LoginPage';
import { DashboardPage } from '@/pages/DashboardPage';
import { CustomersPage } from '@/pages/CustomersPage';
import { DevicesPage } from '@/pages/DevicesPage';
import { AppsPage } from '@/pages/AppsPage';
import { ServersPage } from '@/pages/ServersPage';
import { ActivationsPage } from '@/pages/ActivationsPage';
import { ResellersPage } from '@/pages/ResellersPage';
import { ActivatePage } from '@/pages/ActivatePage';
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
import { SharesPage } from '@/pages/SharesPage';
import { MastersPage } from '@/pages/MastersPage';
import { MonitorPage } from '@/pages/MonitorPage';
import { FamiliesPage } from '@/pages/FamiliesPage';
import { RadarPage } from '@/pages/RadarPage';
import { GatewayPage } from '@/pages/GatewayPage';
import { CreditsPage } from '@/pages/CreditsPage';

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
      .then((r) => {
        setCurrentUser(r.user);
        setStatus('logged_in');
        // Couche temps réel : rôles admin uniquement (no-op sinon).
        if (isOwnerRole(r.user.role)) rtConnect();
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) setToken(null);
        setStatus('logged_out');
      });
  }, []);

  // Ferme proprement le WebSocket au démontage de l'app.
  useEffect(() => () => { rtDisconnect(); }, []);

  const handleLoggedIn = useCallback(() => {
    // On recharge le profil (role + solde) avant d'afficher les pages,
    // pour que la Sidebar et le routage connaissent owner vs revendeur.
    authApi.me()
      .then((r) => {
        setCurrentUser(r.user);
        if (isOwnerRole(r.user.role)) rtConnect();
      })
      .catch(() => {})
      .finally(() => { setStatus('logged_in'); nav('/'); });
  }, [nav]);

  const handleLogout = useCallback(() => {
    rtDisconnect();
    setToken(null);
    setCurrentUser(null);
    setStatus('logged_out');
    nav('/login');
  }, [nav]);

  if (status === 'bootstrapping') {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-obsidian">
        <div className="text-xs uppercase tracking-widest text-ink-tertiary">
          Chargement…
        </div>
      </div>
    );
  }

  if (status === 'logged_out') {
    // On rend LoginPage pour N'IMPORTE QUELLE URL (sans rediriger), afin de
    // PRÉSERVER le lien revendeur dédié : /revendeur, /?revendeur ou le
    // sous-domaine revendeur.* — LoginPage lit l'URL pour se mettre en mode
    // revendeur seul. Un redirect vers /login effacerait ce marqueur.
    return (
      <Routes>
        <Route path="*" element={<LoginPage onLoggedIn={handleLoggedIn} />} />
      </Routes>
    );
  }

  // Logged in
  return (
    <Routes>
      <Route path="/login" element={<Navigate to="/" replace />} />
      <Route path="/"            element={<DashboardPage   onLogout={handleLogout} />} />
      <Route path="/activate"    element={<ActivatePage    onLogout={handleLogout} />} />
      {/* Fusionné dans « Activer un appareil » — on redirige l'ancienne URL. */}
      <Route path="/playlists"   element={<Navigate to="/activate" replace />} />
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
      <Route path="/shares" element={<SharesPage onLogout={handleLogout} />} />
      <Route path="/masters" element={<MastersPage onLogout={handleLogout} />} />
      <Route path="/admin-monitor" element={<MonitorPage onLogout={handleLogout} />} />
      <Route path="/families" element={<FamiliesPage onLogout={handleLogout} />} />
      <Route path="/radar" element={<RadarPage onLogout={handleLogout} />} />
      <Route path="/gateway" element={<GatewayPage onLogout={handleLogout} />} />
      <Route path="/credits" element={<CreditsPage onLogout={handleLogout} />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
