import { FormEvent, useEffect, useMemo, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { themeApi, ApiError } from '@/lib/api';

// =========================================================
//  ThemePage — personnalisation de l'app à distance (owner)
// =========================================================
//  L'owner change le NOM de l'app (ex. « WorldCup2026 ») et sa COULEUR
//  d'accent, avec un APERÇU LIVE du téléphone. À l'enregistrement, l'app
//  lit /api/theme au prochain démarrage et s'adapte — sans mise à jour
//  de store. Le fond clair/blanc est prévu mais arrive côté app ensuite.
// =========================================================

const DEFAULT_ACCENT = '#D63A30'; // braise (défaut historique)
const DEFAULT_NAME = 'The Few';

// Pastilles de couleurs proposées (l'owner peut aussi piocher la sienne).
const SWATCHES: { hex: string; label: string }[] = [
  { hex: '#D63A30', label: 'Braise' },
  { hex: '#D6A030', label: 'Or' },
  { hex: '#2FA96A', label: 'Vert' },
  { hex: '#2E7DD6', label: 'Bleu' },
  { hex: '#8E5AD6', label: 'Violet' },
  { hex: '#D63A8E', label: 'Rose' },
  { hex: '#2EC4C6', label: 'Turquoise' },
  { hex: '#FFFFFF', label: 'Blanc' },
];

export function ThemePage({ onLogout }: { onLogout: () => void }) {
  const [appName, setAppName] = useState('');
  const [accent, setAccent] = useState('');
  const [bg, setBg] = useState<'dark' | 'light'>('dark');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  useEffect(() => {
    themeApi.get()
      .then((r) => {
        setAppName(r.appName || '');
        setAccent(r.accent || '');
        setBg(r.bg === 'light' ? 'light' : 'dark');
      })
      .catch(fail)
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, []);

  // Valeurs effectives utilisées par l'aperçu (défauts si vide).
  const effAccent = useMemo(() => {
    const a = accent.trim();
    return /^#?[0-9a-fA-F]{6}$/.test(a)
      ? (a[0] === '#' ? a : '#' + a)
      : DEFAULT_ACCENT;
  }, [accent]);
  const effName = (appName.trim() || DEFAULT_NAME);
  const light = bg === 'light';

  async function save(e: FormEvent) {
    e.preventDefault();
    const a = accent.trim();
    if (a && !/^#?[0-9a-fA-F]{6}$/.test(a)) {
      setErr('Couleur invalide — format attendu #RRGGBB (ex. #FFFFFF).');
      return;
    }
    setBusy(true); setErr(null); setOk(null);
    try {
      await themeApi.save({ appName: appName.trim(), accent: a, bg });
      setOk('✅ Thème enregistré. L\'app s\'adapte à sa prochaine ouverture.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function reset() {
    setAppName(''); setAccent(''); setBg('dark');
    setBusy(true); setErr(null); setOk(null);
    try {
      await themeApi.save({ appName: '', accent: '', bg: 'dark' });
      setOk('Thème réinitialisé (The Few, braise, sombre).');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Thème"
      subtitle="Personnalise le nom et les couleurs de l'app — aperçu en direct"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 max-w-3xl rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
          {err}
        </div>
      )}
      {ok && (
        <div className="mb-4 max-w-3xl rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
          {ok}
        </div>
      )}

      {loading ? (
        <div className="text-sm text-ink-tertiary">Chargement…</div>
      ) : (
        <div className="grid max-w-4xl grid-cols-1 gap-6 md:grid-cols-2">
          {/* ===== Réglages ===== */}
          <form onSubmit={save} className="space-y-5 rounded-xl border border-white/5 bg-midnight p-6">
            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Nom de l'application
              </label>
              <input
                value={appName}
                onChange={(e) => setAppName(e.target.value)}
                maxLength={40}
                placeholder={DEFAULT_NAME}
                className={inputCls}
              />
              <p className="mt-1 text-[10px] text-ink-tertiary">
                Ex. « WorldCup2026 ». Vide = nom par défaut (The Few).
              </p>
            </div>

            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Couleur d'accent
              </label>
              <div className="mb-2 flex flex-wrap gap-2">
                {SWATCHES.map((s) => (
                  <button
                    type="button"
                    key={s.hex}
                    title={s.label}
                    onClick={() => setAccent(s.hex)}
                    className="h-7 w-7 rounded-full border-2 transition"
                    style={{
                      backgroundColor: s.hex,
                      borderColor:
                        effAccent.toUpperCase() === s.hex.toUpperCase()
                          ? '#ffffff'
                          : 'rgba(255,255,255,0.15)',
                    }}
                  />
                ))}
              </div>
              <div className="flex items-center gap-2">
                <input
                  type="color"
                  value={effAccent}
                  onChange={(e) => setAccent(e.target.value.toUpperCase())}
                  className="h-9 w-12 cursor-pointer rounded border border-white/10 bg-transparent"
                />
                <input
                  value={accent}
                  onChange={(e) => setAccent(e.target.value)}
                  placeholder={DEFAULT_ACCENT}
                  maxLength={7}
                  className={inputCls}
                />
              </div>
            </div>

            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Fond
              </label>
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => setBg('dark')}
                  className={
                    'flex-1 rounded-md border px-3 py-2 text-sm transition ' +
                    (!light
                      ? 'border-accent bg-accent/10 text-ink-primary'
                      : 'border-white/10 text-ink-secondary hover:bg-white/5')
                  }
                >
                  Sombre
                </button>
                <button
                  type="button"
                  onClick={() => setBg('light')}
                  className={
                    'flex-1 rounded-md border px-3 py-2 text-sm transition ' +
                    (light
                      ? 'border-accent bg-accent/10 text-ink-primary'
                      : 'border-white/10 text-ink-secondary hover:bg-white/5')
                  }
                >
                  Clair / Blanc
                </button>
              </div>
              <p className="mt-1 text-[10px] text-ink-tertiary">
                Le fond clair s'affiche dans l'aperçu. Son application dans
                l'app arrive à l'étape suivante (l'app est conçue en sombre).
              </p>
            </div>

            <div className="flex gap-2 pt-1">
              <button
                type="submit"
                disabled={busy}
                className="flex-1 rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
              >
                {busy ? '…' : 'Enregistrer le thème'}
              </button>
              <button
                type="button"
                onClick={reset}
                disabled={busy}
                className="rounded-md border border-white/10 px-4 py-2.5 text-sm text-ink-secondary transition hover:bg-white/5 disabled:opacity-50"
              >
                Réinitialiser
              </button>
            </div>
          </form>

          {/* ===== Aperçu téléphone ===== */}
          <div className="flex flex-col items-center">
            <div className="mb-3 text-[10px] uppercase tracking-widest text-ink-tertiary">
              Aperçu de l'app
            </div>
            <PhonePreview name={effName} accent={effAccent} light={light} />
          </div>
        </div>
      )}
    </AppLayout>
  );
}

// ---- Maquette du téléphone (reflète nom + accent + fond) ----
function PhonePreview({
  name, accent, light,
}: { name: string; accent: string; light: boolean }) {
  const bg = light ? '#F4F4F6' : '#0B0B0F';
  const surface = light ? '#FFFFFF' : '#16121C';
  const text = light ? '#111114' : '#F2F2F5';
  const textDim = light ? '#6B6B72' : '#8A8A93';
  const border = light ? 'rgba(0,0,0,0.08)' : 'rgba(255,255,255,0.06)';

  const cats = [
    { n: 'FR| FRANCE SPORT VIP', c: 161 },
    { n: 'FR| CINÉMA HD/4K', c: 40 },
    { n: '8K| WORLD CUP 2026', c: 71 },
    { n: 'BE| DAZN PPV', c: 100 },
    { n: 'IT| AMAZON PRIME', c: 6 },
  ];

  return (
    <div
      className="w-[280px] overflow-hidden rounded-[28px] border-4 shadow-2xl"
      style={{ background: bg, borderColor: '#000' }}
    >
      {/* Header */}
      <div className="flex items-center gap-2 px-3 pt-4 pb-3">
        <div
          className="grid h-7 w-7 place-items-center rounded-md text-xs font-bold"
          style={{ background: accent, color: light ? '#fff' : '#000' }}
        >
          7
        </div>
        <div className="flex-1 text-center text-[13px] font-bold" style={{ color: text }}>
          {name}
        </div>
        <div className="h-5 w-5 rounded-full" style={{ background: border }} />
      </div>

      {/* Catégories */}
      <div className="space-y-2 px-3 pb-3">
        {cats.map((cat) => (
          <div
            key={cat.n}
            className="flex items-center gap-2 rounded-xl px-3 py-2.5"
            style={{ background: surface, border: `1px solid ${border}` }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill={accent}>
              <path d="M10 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z" />
            </svg>
            <div className="flex-1 truncate text-[11px] font-medium" style={{ color: text }}>
              {cat.n}
            </div>
            <div
              className="rounded-full px-2 py-0.5 text-[10px] font-bold"
              style={{ background: `${accent}22`, color: accent }}
            >
              {cat.c}
            </div>
          </div>
        ))}
      </div>

      {/* Bottom nav */}
      <div
        className="flex items-center justify-around px-2 py-2"
        style={{ borderTop: `1px solid ${border}` }}
      >
        {[
          { label: 'Accueil', on: true },
          { label: 'Favoris', on: false },
          { label: 'IA', on: false },
          { label: 'Ajouter', on: false },
        ].map((it) => (
          <div key={it.label} className="flex flex-col items-center gap-0.5">
            <div
              className="h-4 w-4 rounded-full"
              style={{ background: it.on ? accent : textDim }}
            />
            <span
              className="text-[8px]"
              style={{ color: it.on ? accent : textDim }}
            >
              {it.label}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
