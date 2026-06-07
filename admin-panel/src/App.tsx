import { useCallback, useEffect, useState } from 'react';
import { Navigate, Route, Routes, useNavigate } from 'react-router-dom';
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
import { PushSourcePage } from '@/pages/PushSourcePage';
import { NotificationsPage } from '@/pages/NotificationsPage';
import { HomeManagerPage } from '@/pages/HomeManagerPage';
import { ControlCenterPage } from '@/pages/ControlCenterPage';
import { ForceUpdatePage } from '@/pages/ForceUpdatePage';
import { AccountPage } from '@/pages/AccountPage';

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

  const handleLogout = useCallback(() => {
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
      <Route path="/playlists"   element={<PushSourcePage  onLogout={handleLogout} />} />
      <Route path="/notifications" element={<NotificationsPage onLogout={handleLogout} />} />
      <Route path="/control-center" element={<ControlCenterPage onLogout={handleLogout} />} />
      <Route path="/home-manager" element={<HomeManagerPage onLogout={handleLogout} />} />
      <Route path="/force-update" element={<ForceUpdatePage onLogout={handleLogout} />} />
      <Route path="/customers"   element={<CustomersPage   onLogout={handleLogout} />} />
      <Route path="/devices"     element={<DevicesPage     onLogout={handleLogout} />} />
      <Route path="/apps"        element={<AppsPage        onLogout={handleLogout} />} />
      <Route path="/servers"     element={<ServersPage     onLogout={handleLogout} />} />
      <Route path="/activations" element={<ActivationsPage onLogout={handleLogout} />} />
      {/* Revendeurs : owner ET revendeurs (qui gerent leurs sous-revendeurs).
          Les permissions/scoping sont appliques cote API. */}
      <Route path="/resellers" element={<ResellersPage onLogout={handleLogout} />} />
      <Route path="/account" element={<AccountPage onLogout={handleLogout} />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
