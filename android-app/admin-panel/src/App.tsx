import { useCallback, useEffect, useState } from 'react';
import { Navigate, Route, Routes, useNavigate } from 'react-router-dom';
import {
  authApi, getToken, setToken, setCurrentUser,
  maybeRefreshSession, ApiError,
} from '@/lib/api';
import { decideBootOutcome, SESSION_REFRESH_POLL_MS } from '@/lib/sessionPolicy';
import { useT } from '@/lib/i18n';
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
import { FamiliesPage } from '@/pages/FamiliesPage';

/// Etats possibles de l'app :
///   - bootstrapping : on verifie si le token est encore valide
///   - logged_in     : token OK, on rend les pages
///   - logged_out    : on rend LoginPage
///   - offline       : le serveur ne répond pas, le jeton est GARDÉ
type AuthStatus = 'bootstrapping' | 'logged_in' | 'logged_out' | 'offline';

export default function App() {
  const [status, setStatus] = useState<AuthStatus>('bootstrapping');
  // true seulement quand le Worker a rejeté le jeton (expiré / falsifié).
  // Un clic « Se déconnecter » ne met pas ce drapeau.
  const [sessionExpired, setSessionExpired] = useState(false);
  const [bootAttempt, setBootAttempt] = useState(0);
  const nav = useNavigate();
  const t = useT();

  // Au chargement : si le jeton a déjà vécu plus de la moitié de sa
  // durée, on le renouvelle, puis on appelle /auth/me.
  // Seul un vrai 401 déconnecte. Réseau, 5xx, timeout : on reste
  // hors de la page de login et on réessaie, jeton intact.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const tok = getToken();
      if (!tok) {
        setStatus('logged_out');
        return;
      }
      setStatus('bootstrapping');
      try {
        await maybeRefreshSession();
        const r = await authApi.me();
        if (cancelled) return;
        setCurrentUser(r.user);
        setSessionExpired(false);
        setStatus('logged_in');
      } catch (e) {
        if (cancelled) return;
        // ApiError = le serveur a répondu. Tout le reste (TypeError
        // réseau, TimeoutError) n'a pas de statut HTTP : on garde.
        const outcome = decideBootOutcome({
          status: e instanceof ApiError ? e.status : null,
          code: e instanceof ApiError ? e.code : null,
        });
        if (outcome === 'logged_out') {
          setToken(null);
          setCurrentUser(null);
          setSessionExpired(true);
          setStatus('logged_out');
        } else {
          setStatus('offline');
        }
      }
    })();
    return () => { cancelled = true; };
  }, [bootAttempt]);

  // Contrôle régulier + au retour sur l'onglet. maybeRefreshSession
  // ne contacte le Worker que si le jeton a passé la moitié de sa vie.
  useEffect(() => {
    if (status !== 'logged_in') return;
    const tick = () => {
      maybeRefreshSession().catch(() => {
        // 401 : request() a déjà effacé le jeton. On affiche le login
        // avec le message « session expirée ». Toute autre erreur
        // (réseau, 5xx) est avalée par maybeRefreshSession.
        if (!getToken()) {
          setCurrentUser(null);
          setSessionExpired(true);
          setStatus('logged_out');
          nav('/login');
        }
      });
    };
    const id = window.setInterval(tick, SESSION_REFRESH_POLL_MS);
    const onVis = () => {
      if (document.visibilityState === 'visible') tick();
    };
    document.addEventListener('visibilitychange', onVis);
    return () => {
      window.clearInterval(id);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, [status, nav]);

  // Hors-ligne au démarrage : on réessaie tout seul, sans effacer
  // le jeton. L'utilisateur peut aussi cliquer « Réessayer ».
  useEffect(() => {
    if (status !== 'offline') return;
    const id = window.setTimeout(() => setBootAttempt((n) => n + 1), 15_000);
    return () => window.clearTimeout(id);
  }, [status, bootAttempt]);

  const handleLoggedIn = useCallback(() => {
    setSessionExpired(false);
    // On recharge le profil (role + solde) avant d'afficher les pages,
    // pour que la Sidebar et le routage connaissent owner vs revendeur.
    authApi.me()
      .then((r) => { setCurrentUser(r.user); })
      .catch(() => {})
      .finally(() => { setStatus('logged_in'); nav('/'); });
  }, [nav]);

  const handleLogout = useCallback(() => {
    // Si le jeton a déjà été effacé par un 401, ce n'est pas un clic
    // volontaire : on explique que la session est terminée.
    const expired = !getToken();
    setToken(null);
    setCurrentUser(null);
    setSessionExpired(expired);
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

  if (status === 'offline') {
    return (
      <div className="flex h-screen w-screen flex-col items-center justify-center gap-4 bg-obsidian px-6 text-center">
        <p className="max-w-sm text-sm text-ink-secondary">{t('session.offline')}</p>
        <button
          type="button"
          onClick={() => setBootAttempt((n) => n + 1)}
          className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright"
        >
          {t('session.retry')}
        </button>
      </div>
    );
  }

  if (status === 'logged_out') {
    return (
      <Routes>
        <Route
          path="/login"
          element={<LoginPage onLoggedIn={handleLoggedIn} sessionExpired={sessionExpired} />}
        />
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
      <Route path="/families" element={<FamiliesPage onLogout={handleLogout} />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
