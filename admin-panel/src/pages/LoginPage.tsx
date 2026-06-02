import { FormEvent, useState } from 'react';
import { authApi, setToken, ApiError } from '@/lib/api';

/// Ecran login : email + password, JWT en retour.
/// Bootstrap : si la base D1 est vide, le Worker cree
/// automatiquement un compte super_admin avec email='admin' et
/// password=ADMIN_SECRET du Worker (transition seamless).
export function LoginPage({ onLoggedIn }: { onLoggedIn: () => void }) {
  // Lien revendeur dedie : si l'URL contient ?revendeur (ou ?reseller),
  // on n'affiche QUE la connexion revendeur (aucun onglet Admin visible).
  // Ex: https://tvking-admin.pages.dev/?revendeur
  const resellerOnly = (() => {
    try {
      const p = new URLSearchParams(window.location.search);
      return p.has('revendeur') || p.has('reseller') || p.get('mode') === 'reseller';
    } catch {
      return false;
    }
  })();

  const [mode, setMode] = useState<'admin' | 'reseller'>(
    resellerOnly ? 'reseller' : 'admin',
  );
  const [email, setEmail] = useState(resellerOnly ? '' : 'admin');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  function switchMode(m: 'admin' | 'reseller') {
    setMode(m);
    setErr(null);
    // En mode revendeur on vide l'identifiant 'admin' par defaut.
    setEmail(m === 'admin' ? 'admin' : '');
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const res = mode === 'reseller'
        ? await authApi.resellerLogin(email.trim(), password)
        : await authApi.login(email.trim(), password);
      setToken(res.token);
      onLoggedIn();
    } catch (e: any) {
      const msg = e instanceof ApiError
        ? e.message
        : 'Connexion impossible. Réessaie.';
      setErr(msg);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex h-screen w-screen items-center justify-center bg-obsidian px-6">
      <form
        onSubmit={submit}
        className="w-full max-w-sm space-y-6 rounded-2xl border border-white/5 bg-midnight p-8 shadow-2xl"
      >
        <div className="text-center">
          <div className="mx-auto mb-4 h-12 w-12 rounded-xl bg-accent/15 ring-1 ring-accent/40 grid place-items-center">
            <span className="text-accent font-bold text-lg">A</span>
          </div>
          <h1 className="text-xl font-semibold tracking-tight">
            Licensing Platform
          </h1>
          <p className="mt-1 text-xs uppercase tracking-widest text-ink-tertiary">
            {mode === 'admin' ? 'Super Admin' : 'Espace revendeur'}
          </p>
        </div>

        {/* ===== Bascule Admin / Revendeur (cachee sur le lien revendeur) ===== */}
        {!resellerOnly && (
          <div className="grid grid-cols-2 gap-1 rounded-lg border border-white/5 bg-slate p-1">
            {(['admin', 'reseller'] as const).map((m) => (
              <button
                key={m}
                type="button"
                onClick={() => switchMode(m)}
                className={
                  'rounded-md px-3 py-1.5 text-xs font-medium transition ' +
                  (mode === m
                    ? 'bg-accent text-black'
                    : 'text-ink-secondary hover:text-ink-primary')
                }
              >
                {m === 'admin' ? 'Admin' : 'Revendeur'}
              </button>
            ))}
          </div>
        )}

        <div className="space-y-3">
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Identifiant
            </label>
            <input
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoFocus
              className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none ring-accent focus:ring-1"
              placeholder="admin"
            />
          </div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Mot de passe
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none ring-accent focus:ring-1"
              placeholder="••••••••"
            />
          </div>
        </div>

        {err && (
          <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
            {err}
          </div>
        )}

        <button
          type="submit"
          disabled={busy || !password}
          className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition disabled:cursor-not-allowed disabled:opacity-50 hover:bg-accent-bright"
        >
          {busy ? 'Connexion…' : 'Se connecter'}
        </button>

        {!resellerOnly && (
          <p className="text-center text-[11px] text-ink-tertiary">
            Première connexion : utilise ton <span className="text-ink-secondary">ADMIN_SECRET</span> Worker comme mot de passe.
          </p>
        )}
        {resellerOnly && (
          <p className="text-center text-[11px] text-ink-tertiary">
            Connecte-toi avec l'email et le mot de passe fournis par ton fournisseur.
          </p>
        )}
      </form>
    </div>
  );
}
