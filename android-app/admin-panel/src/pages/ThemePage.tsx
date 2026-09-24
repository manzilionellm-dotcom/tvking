import { FormEvent, useEffect, useMemo, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { themeApi, ApiError, type ThemeRule } from '@/lib/api';

const MONTHS_FR = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
];

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

// PRESETS : un « look » complet (couleur + fond) appliqué en 1 clic. Pilotés
// par le panel → l'app les applique au prochain démarrage, AUCUN nouvel APK.
const PRESETS: {
  key: string; label: string; emoji: string; accent: string; bg: 'dark' | 'light';
}[] = [
  { key: 'braise', label: 'Braise', emoji: '🔥', accent: '#D63A30', bg: 'dark' },
  { key: 'gold', label: 'Gold', emoji: '🏆', accent: '#D6A030', bg: 'dark' },
  { key: 'platinum', label: 'Platinum', emoji: '💎', accent: '#AEB6C2', bg: 'dark' },
  { key: 'noel', label: 'Noël', emoji: '🎄', accent: '#1E8E4E', bg: 'dark' },
  { key: 'worldcup', label: 'World Cup', emoji: '⚽', accent: '#2E7DD6', bg: 'dark' },
  { key: 'halloween', label: 'Halloween', emoji: '🎃', accent: '#E8722B', bg: 'dark' },
  { key: 'neon', label: 'Néon', emoji: '⚡', accent: '#2EC4C6', bg: 'dark' },
  { key: 'light', label: 'Light', emoji: '☀️', accent: '#2E7DD6', bg: 'light' },
];

export function ThemePage({ onLogout }: { onLogout: () => void }) {
  const [appName, setAppName] = useState('');
  const [accent, setAccent] = useState('');
  const [bg, setBg] = useState<'dark' | 'light'>('dark');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  // Plateforme éditée : 📱 mobile (The Few) ou 📺 tv (DeFew TV).
  const [platform, setPlatform] = useState<'mobile' | 'tv'>('mobile');

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  // Recharge le thème de la plateforme sélectionnée.
  useEffect(() => {
    setLoading(true); setOk(null); setErr(null);
    themeApi.get(platform)
      .then((r) => {
        setAppName(r.appName || '');
        setAccent(r.accent || '');
        setBg(r.bg === 'light' ? 'light' : 'dark');
      })
      .catch(fail)
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, [platform]);

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
      await themeApi.save({ appName: appName.trim(), accent: a, bg }, platform);
      const who = platform === 'tv' ? 'DeFew TV' : 'The Few (mobile)';
      setOk(`✅ Thème ${who} enregistré. L'app s'adapte à sa prochaine ouverture.`);
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function reset() {
    setAppName(''); setAccent(''); setBg('dark');
    setBusy(true); setErr(null); setOk(null);
    try {
      await themeApi.save({ appName: '', accent: '', bg: 'dark' }, platform);
      setOk('Thème réinitialisé.');
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
      {/* Bascule 📱 Mobile / 📺 TV : chaque app a son propre thème. */}
      <div className="mb-5 inline-flex rounded-lg border border-white/10 bg-slate p-1">
        {([['mobile', '📱 Mobile'], ['tv', '📺 TV']] as const).map(([p, label]) => (
          <button
            key={p}
            onClick={() => setPlatform(p)}
            className={
              'rounded-md px-4 py-2 text-sm font-semibold transition ' +
              (platform === p
                ? 'bg-accent text-black'
                : 'text-ink-secondary hover:text-ink-primary')
            }
          >
            {label}
          </button>
        ))}
      </div>

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
            {/* ===== Presets : look complet en 1 clic ===== */}
            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Presets — look complet en 1 clic
              </label>
              <div className="flex flex-wrap gap-2">
                {PRESETS.map((p) => {
                  const active =
                    effAccent.toUpperCase() === p.accent.toUpperCase() && bg === p.bg;
                  return (
                    <button
                      type="button"
                      key={p.key}
                      onClick={() => { setAccent(p.accent); setBg(p.bg); }}
                      className={
                        'flex items-center gap-1 rounded-full border px-3 py-1.5 text-xs transition ' +
                        (active
                          ? 'border-accent bg-accent/15 text-accent-bright'
                          : 'border-white/10 text-ink-secondary hover:bg-white/5')
                      }
                    >
                      <span>{p.emoji}</span>{p.label}
                    </button>
                  );
                })}
              </div>
              <p className="mt-1 text-[10px] text-ink-tertiary">
                Applique couleur + fond d'un coup. Ajuste si besoin, puis « Enregistrer ».
              </p>
            </div>

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

      {!loading && <ThemeAutomations onLogout={onLogout} platform={platform} />}
    </AppLayout>
  );
}

// =========================================================
//  Automatisation du thème — règles « date → look »
// =========================================================
//  Ex. « En Décembre → preset Noël ». Évalué côté serveur quand l'app lit
//  /api/theme → le thème bascule tout seul, sans toucher à l'app.
function ThemeAutomations(
  { onLogout, platform }: { onLogout: () => void; platform: 'mobile' | 'tv' },
) {
  const [rules, setRules] = useState<ThemeRule[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    themeApi.getAutomations(platform)
      .then((r) => setRules(r.rules || []))
      .catch((e) => { if (e instanceof ApiError && e.status === 401) onLogout(); })
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, [platform]);

  function patch(i: number, p: Partial<ThemeRule>) {
    setRules((rs) => rs.map((r, k) => (k === i ? { ...r, ...p } : r)));
  }
  function addRule() {
    setRules((rs) => [
      ...rs,
      { enabled: true, label: 'Noël', month: 12, from: null, to: null,
        accent: '#1E8E4E', bg: 'dark', appName: '' },
    ]);
  }
  function remove(i: number) {
    setRules((rs) => rs.filter((_, k) => k !== i));
  }
  async function save() {
    setBusy(true); setErr(null); setOk(null);
    try {
      const r = await themeApi.saveAutomations(rules, platform);
      setRules(r.rules || []);
      setOk('✅ Règles enregistrées. Le thème basculera tout seul aux dates prévues.');
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
    } finally { setBusy(false); }
  }

  // Mêmes presets que plus haut, pour choisir le look d'une règle.
  const presetOptions = PRESETS;

  const sel = 'rounded-md border border-white/10 bg-slate px-2 py-1.5 text-xs outline-none focus:ring-1 focus:ring-accent';

  return (
    <div className="mt-8 max-w-4xl rounded-xl border border-white/5 bg-midnight p-6">
      <div className="mb-1 flex items-center justify-between">
        <h2 className="text-sm font-semibold">Automatisation du thème</h2>
        <button
          onClick={addRule}
          className="rounded-md border border-white/10 px-3 py-1.5 text-xs hover:border-accent hover:text-accent-bright"
        >
          + Ajouter une règle
        </button>
      </div>
      <p className="mb-4 text-[11px] text-ink-tertiary">
        Ex. « En Décembre → Noël ». La règle prime sur le thème manuel pendant
        sa période, puis l'app revient au thème normal. Aucun nouvel APK.
      </p>

      {err && <div className="mb-3 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
      {ok && <div className="mb-3 rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">{ok}</div>}

      {loading ? (
        <div className="text-xs text-ink-tertiary">Chargement…</div>
      ) : rules.length === 0 ? (
        <div className="text-xs text-ink-tertiary">
          Aucune règle. Clique « + Ajouter une règle » (ex. Décembre → Noël).
        </div>
      ) : (
        <div className="space-y-2">
          {rules.map((r, i) => (
            <div
              key={i}
              className="flex flex-wrap items-center gap-2 rounded-lg border border-white/5 bg-slate/40 px-3 py-2"
            >
              <label className="flex items-center gap-1 text-xs">
                <input
                  type="checkbox"
                  checked={r.enabled}
                  onChange={(e) => patch(i, { enabled: e.target.checked })}
                />
                Actif
              </label>
              {/* Mois */}
              <select
                value={r.month ?? ''}
                onChange={(e) => patch(i, { month: e.target.value ? Number(e.target.value) : null })}
                className={sel}
              >
                <option value="">— Mois —</option>
                {MONTHS_FR.map((m, idx) => (
                  <option key={m} value={idx + 1}>{m}</option>
                ))}
              </select>
              {/* Look (preset) */}
              <select
                value={presetOptions.find((p) => p.accent.toUpperCase() === (r.accent || '').toUpperCase() && p.bg === r.bg)?.key || ''}
                onChange={(e) => {
                  const p = presetOptions.find((x) => x.key === e.target.value);
                  if (p) patch(i, { accent: p.accent, bg: p.bg, label: r.label || p.label });
                }}
                className={sel}
              >
                <option value="">— Look —</option>
                {presetOptions.map((p) => (
                  <option key={p.key} value={p.key}>{p.emoji} {p.label}</option>
                ))}
              </select>
              <input
                value={r.label}
                onChange={(e) => patch(i, { label: e.target.value })}
                placeholder="Nom de la règle"
                className={sel + ' flex-1 min-w-[120px]'}
              />
              <span
                className="h-5 w-5 rounded-full border border-white/20"
                style={{ background: r.accent || '#333' }}
              />
              <button
                onClick={() => remove(i)}
                className="rounded-md border border-white/10 px-2 py-1 text-xs text-ink-tertiary hover:border-warning hover:text-warning"
              >
                Suppr.
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="mt-4">
        <button
          onClick={save}
          disabled={busy}
          className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50"
        >
          {busy ? '…' : 'Enregistrer les règles'}
        </button>
      </div>
    </div>
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
