import { FormEvent, useState } from 'react';
import { authApi, setToken, ApiError } from '@/lib/api';
import { useT, LangSelect } from '@/lib/i18n';

/// Ecran login : email + password, JWT en retour.
/// Bootstrap : si la base D1 est vide, le Worker cree
/// automatiquement un compte super_admin avec email='admin' et
/// password=ADMIN_SECRET du Worker (transition seamless).
export function LoginPage({ onLoggedIn }: { onLoggedIn: () => void }) {
  const t = useT();
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
  const [name, setName] = useState('');
  // Mode INSCRIPTION (revendeur uniquement) : auto-création de compte.
  const [signup, setSignup] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  // 2FA : le champ code n'apparaît que si le serveur le demande
  // (erreur 'otp_required' après un mot de passe correct).
  const [otpNeeded, setOtpNeeded] = useState(false);
  const [otp, setOtp] = useState('');

  function switchMode(m: 'admin' | 'reseller') {
    setMode(m);
    setErr(null);
    setOkMsg(null);
    setSignup(false);
    // En mode revendeur on vide l'identifiant 'admin' par defaut.
    setEmail(m === 'admin' ? 'admin' : '');
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    setOkMsg(null);
    try {
      // Auto-inscription revendeur : crée un compte 'pending' (pas de login).
      if (mode === 'reseller' && signup) {
        await authApi.resellerSignup(email.trim(), password, name.trim() || undefined);
        setOkMsg(
          'Compte créé ✅ Il est en attente de validation par l\'administrateur. '
          + 'Tu pourras te connecter dès qu\'il l\'aura activé.',
        );
        setSignup(false);
        return;
      }
      const res = mode === 'reseller'
        ? await authApi.resellerLogin(email.trim(), password)
        : await authApi.login(email.trim(), password, otp.trim() || undefined);
      setToken(res.token);
      onLoggedIn();
    } catch (e: any) {
      if (e instanceof ApiError && e.code === 'otp_required') {
        // Mot de passe OK, compte protégé par 2FA → on demande le code.
        setOtpNeeded(true);
        setErr(null);
        return;
      }
      const msg = e instanceof ApiError ? e.message : t('login.fail');
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
            <span className="text-accent font-bold text-base tracking-tight">TF</span>
          </div>
          <h1 className="text-xl font-semibold tracking-tight">{t('brand')}</h1>
          <p className="mt-1 text-xs uppercase tracking-widest text-ink-tertiary">
            {mode === 'admin' ? t('login.subtitleAdmin') : t('login.subtitleReseller')}
          </p>
        </div>

        {/* ===== Choix du rôle : 2 cartes distinctes (Propriétaire vs
             Revendeur), pour bien DIFFÉRENCIER les 2 connexions. Cachées
             sur le lien dédié revendeur (?revendeur). ===== */}
        {!resellerOnly && (
          <div className="grid grid-cols-2 gap-2">
            {(['admin', 'reseller'] as const).map((m) => {
              const active = mode === m;
              return (
                <button
                  key={m}
                  type="button"
                  onClick={() => switchMode(m)}
                  className={
                    'flex flex-col items-start gap-1 rounded-xl border p-3 text-left transition ' +
                    (active
                      ? 'border-accent bg-accent/10 ring-1 ring-accent'
                      : 'border-white/5 bg-slate hover:border-white/20')
                  }
                >
                  <span className="text-lg leading-none">
                    {m === 'admin' ? '👑' : '🛒'}
                  </span>
                  <span
                    className={
                      'text-sm font-semibold ' +
                      (active ? 'text-accent' : 'text-ink-primary')
                    }
                  >
                    {m === 'admin' ? t('login.tabAdmin') : t('login.tabReseller')}
                  </span>
                  <span className="text-[10px] leading-snug text-ink-tertiary">
                    {m === 'admin'
                      ? t('login.adminDesc')
                      : t('login.resellerDesc')}
                  </span>
                </button>
              );
            })}
          </div>
        )}

        <div className="space-y-3">
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              {t('login.identifier')}
            </label>
            <input
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoFocus
              className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none ring-accent focus:ring-1"
              placeholder={mode === 'reseller' ? 'ton-identifiant' : 'admin'}
            />
          </div>
          {mode === 'reseller' && signup && (
            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Nom (optionnel)
              </label>
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none ring-accent focus:ring-1"
                placeholder="Ex. Karim Reseller"
              />
            </div>
          )}
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              {t('login.password')}
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none ring-accent focus:ring-1"
              placeholder="••••••••"
            />
          </div>
          {otpNeeded && mode === 'admin' && (
            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Code de vérification (2FA)
              </label>
              <input
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))}
                autoFocus
                inputMode="numeric"
                maxLength={6}
                className="w-full rounded-md border border-accent/40 bg-slate px-3 py-2 text-center font-mono text-lg tracking-[0.4em] outline-none ring-accent focus:ring-1"
                placeholder="000000"
              />
              <p className="mt-1 text-[11px] text-ink-tertiary">
                Ouvre ton app d'authentification (Google Authenticator, Authy…).
              </p>
            </div>
          )}
        </div>

        {err && (
          <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
            {err}
          </div>
        )}
        {okMsg && (
          <div className="rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
            {okMsg}
          </div>
        )}

        <button
          type="submit"
          disabled={busy || !password}
          className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition disabled:cursor-not-allowed disabled:opacity-50 hover:bg-accent-bright"
        >
          {busy
            ? t('login.signing')
            : mode === 'reseller' && signup
              ? 'Créer mon compte revendeur'
              : t('login.signin')}
        </button>

        {/* Bascule connexion ↔ inscription (revendeur uniquement). */}
        {mode === 'reseller' && (
          <button
            type="button"
            onClick={() => { setSignup(!signup); setErr(null); setOkMsg(null); }}
            className="w-full text-center text-[11px] text-ink-tertiary underline-offset-2 hover:text-accent-bright hover:underline"
          >
            {signup
              ? 'Déjà un compte ? Se connecter'
              : 'Pas encore de compte ? Créer un compte revendeur'}
          </button>
        )}

        {!resellerOnly && (
          <p className="text-center text-[11px] text-ink-tertiary">
            Première connexion : utilise ton <span className="text-ink-secondary">ADMIN_SECRET</span> Worker comme mot de passe.
          </p>
        )}
        {resellerOnly && (
          <p className="text-center text-[11px] text-ink-tertiary">
            {t('login.hintReseller')}
          </p>
        )}

        {/* Sélecteur de langue */}
        <div className="flex justify-center pt-1">
          <LangSelect />
        </div>
      </form>
    </div>
  );
}
