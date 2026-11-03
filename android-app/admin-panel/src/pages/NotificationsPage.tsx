import { FormEvent, useEffect, useRef, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { confirmAction } from '@/components/confirm';
import {
  announcementsApi, type Announcement, ApiError,
  COUNTRIES, flagEmoji,
} from '@/lib/api';

/// Page « Annonces » (owner uniquement) — publie une nouveauté / promo /
/// info / maintenance qui s'affiche dans TOUTES les apps (bandeau en haut
/// de l'accueil + notification douce à la prochaine ouverture).
///
/// Chaque annonce a :
///   - une CATÉGORIE (kind) → pilote l'icône + la couleur du bandeau ;
///   - un titre + un message ;
///   - un lien optionnel + le libellé d'un bouton d'action (cta).
///
/// Un APERÇU en direct montre exactement le rendu côté app avant publi.
/// Au submit → POST /api/v1/announcements. L'app lit la dernière via
/// GET /api/announcement au démarrage (et ne la montre qu'une fois).

// Catégories : doivent rester alignées avec ANNOUNCEMENT_KINDS (worker)
// et le mapping couleur/icône de l'app (announcement_banner.dart).
const KINDS = [
  { id: 'nouveaute', label: 'Nouveauté', emoji: '🎬', color: '#D63A30' },
  { id: 'promo', label: 'Promo', emoji: '🔥', color: '#D69847' },
  { id: 'info', label: 'Info', emoji: 'ℹ️', color: '#6A8DB0' },
  { id: 'maintenance', label: 'Maintenance', emoji: '🛠️', color: '#E84A3E' },
] as const;

type KindId = (typeof KINDS)[number]['id'];

function kindMeta(id?: string) {
  return KINDS.find((k) => k.id === id) ?? KINDS[0];
}

export function NotificationsPage({ onLogout }: { onLogout: () => void }) {
  const [kind, setKind] = useState<KindId>('nouveaute');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [url, setUrl] = useState('');
  const [cta, setCta] = useState('');
  // Ciblage géographique : '' = tout le monde, sinon code ISO (ex. 'SE').
  const [country, setCountry] = useState('');
  // Durée d'affichage (minutes) avant disparition auto. 0 = toujours.
  const [durationMin, setDurationMin] = useState(30);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [recent, setRecent] = useState<Announcement[]>([]);
  // Interrupteur GLOBAL : coupe / réactive toutes les notifications.
  const [notifsOn, setNotifsOn] = useState<boolean | null>(null);
  const [loading, setLoading] = useState(true);
  const [ready, setReady] = useState(false);
  const mounted = useRef(false);
  const loadGeneration = useRef(0);
  // Le ref ferme aussi la fenêtre entre deux clics avant le rendu React.
  const writing = useRef(false);

  function fail(e: unknown) {
    if (!mounted.current) return;
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Impossible de joindre le serveur. Réessaie.');
  }

  function requireSaved(r: { ok: boolean }) {
    if (r?.ok !== true) throw new ApiError(502, 'bad_response', 'Enregistrement non confirmé par le serveur.');
  }

  async function load() {
    const generation = ++loadGeneration.current;
    setLoading(true); setReady(false); setErr(null);
    const [list, settings] = await Promise.allSettled([
      announcementsApi.list(), announcementsApi.getSettings(),
    ]);
    if (!mounted.current || generation !== loadGeneration.current) return;
    let valid = true;
    if (list.status === 'fulfilled' && Array.isArray(list.value?.items)) {
      setRecent(list.value.items);
    } else {
      valid = false;
      fail(list.status === 'rejected' ? list.reason : new ApiError(502, 'bad_response', 'Liste des annonces invalide. Réessaie.'));
    }
    if (settings.status === 'fulfilled' && typeof settings.value?.enabled === 'boolean') {
      setNotifsOn(settings.value.enabled);
    } else {
      valid = false; setNotifsOn(null);
      fail(settings.status === 'rejected' ? settings.reason : new ApiError(502, 'bad_response', 'État des notifications illisible. Réessaie.'));
    }
    setReady(valid); setLoading(false);
  }

  useEffect(() => {
    mounted.current = true;
    void load();
    return () => { mounted.current = false; loadGeneration.current++; };
  }, []);

  function beginAction() {
    if (!ready || writing.current) return false;
    writing.current = true; setBusy(true); setErr(null); setOk(null);
    return true;
  }

  function endAction() {
    writing.current = false;
    if (mounted.current) setBusy(false);
  }

  async function toggleGlobal() {
    if (notifsOn === null || !beginAction()) return;
    const next = !notifsOn;
    try {
      const r = await announcementsApi.setSettings(next);
      requireSaved(r);
      if (typeof r.enabled !== 'boolean') throw new ApiError(502, 'bad_response', 'État des notifications non confirmé.');
      if (mounted.current) setNotifsOn(r.enabled);
    } catch (e) { fail(e); } finally { endAction(); }
  }

  async function toggleActive(id: number, active: boolean) {
    if (!beginAction()) return;
    try {
      const r = await announcementsApi.setActive(id, active);
      requireSaved(r);
      if (typeof r.active !== 'boolean') throw new ApiError(502, 'bad_response', 'État de l’annonce non confirmé.');
      if (!mounted.current) return;
      setRecent((list) =>
        list.map((x) => (x.id === id ? { ...x, active: r.active ? 1 : 0 } : x)));
    } catch (e) { fail(e); } finally { endAction(); }
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!ready || writing.current) return;
    setErr(null);
    setOk(null);
    if (!title.trim() && !body.trim()) {
      setErr('Écris au moins un titre ou un message.');
      return;
    }
    const actionUrl = url.trim();
    if (actionUrl) {
      try {
        const parsed = new URL(actionUrl);
        if (!/^https?:\/\/[^/\\\s?#]/i.test(actionUrl) || actionUrl.includes('\\') ||
            !['http:', 'https:'].includes(parsed.protocol) || !parsed.hostname ||
            parsed.username || parsed.password) throw new Error('Lien invalide');
      } catch {
        setErr('Le lien doit être une adresse HTTP ou HTTPS complète, sans identifiants.');
        return;
      }
    }
    if (!beginAction()) return;
    try {
      const r = await announcementsApi.create({
        title: title.trim(),
        body: body.trim(),
        url: actionUrl,
        kind,
        cta: cta.trim(),
        country,
        durationMin,
      });
      requireSaved(r);
      if (!mounted.current) return;
      setOk(
        !notifsOn
          ? 'Annonce enregistrée. La diffusion est désactivée : réactive les notifications pour la rendre disponible.'
          : `Annonce enregistrée${country ? ` pour ${flagEmoji(country)} ${country}` : ' pour tous les pays'}. La réception par les applications n’est pas encore confirmée.`,
      );
      setTitle('');
      setBody('');
      setUrl('');
      setCta('');
      const list = await announcementsApi.list();
      if (!Array.isArray(list?.items)) throw new ApiError(502, 'bad_response', 'Annonce enregistrée, mais la liste n’a pas pu être actualisée.');
      if (mounted.current) setRecent(list.items);
    } catch (e) { fail(e); } finally { endAction(); }
  }

  async function clearAll() {
    if (!beginAction()) return;
    try {
      const confirmed = await confirmAction({
        title: 'Retirer toutes les annonces ?',
        message: 'Les annonces seront retirées du serveur. Les applications seront actualisées à leur prochaine synchronisation.',
        confirmLabel: 'Tout retirer',
        danger: true,
      });
      if (!confirmed || !mounted.current) return;
      requireSaved(await announcementsApi.clear());
      if (!mounted.current) return;
      setOk('Toutes les annonces ont été retirées du serveur.');
      setRecent([]);
    } catch (e) { fail(e); } finally { endAction(); }
  }

  async function removeOne(id: number) {
    if (!beginAction()) return;
    try {
      requireSaved(await announcementsApi.remove(id));
      if (!mounted.current) return;
      setRecent((list) => list.filter((x) => x.id !== id));
    } catch (e) { fail(e); } finally { endAction(); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  const meta = kindMeta(kind);
  const previewTitle = title.trim() || 'Titre de ton annonce';
  const previewBody = body.trim()
    || 'Le message qui décrit ta nouveauté apparaîtra ici.';

  return (
    <AppLayout
      title="Annonces"
      subtitle="Annonce tes nouveautés, promos et infos à tous tes clients — elles s'affichent dans l'app"
      onLogout={onLogout}
    >
      {/* ===== Interrupteur global ===== */}
      <div className="mb-5 flex max-w-2xl items-center justify-between gap-4 rounded-xl border border-white/5 bg-midnight px-5 py-4">
        <div>
          <div className="text-sm font-semibold">
            {notifsOn === null ? 'État des notifications inconnu' : `Notifications ${notifsOn ? 'activées' : 'désactivées'}`}
          </div>
          <div className="text-[11px] text-ink-tertiary">
            {notifsOn === null ? 'Lecture de la configuration serveur nécessaire.' : notifsOn
              ? 'Les annonces actives sont disponibles pour les applications.'
              : 'Diffusion coupée. Les applications retireront les annonces à leur prochaine synchronisation.'}
          </div>
        </div>
        <button
          type="button"
          onClick={toggleGlobal}
          disabled={busy || !ready}
          aria-label="Activer les notifications"
          aria-pressed={notifsOn ?? false}
          title={notifsOn ? 'Tout désactiver' : 'Réactiver'}
          className={'relative h-7 w-12 shrink-0 rounded-full transition disabled:opacity-50 ' + (notifsOn ? 'bg-accent' : 'bg-white/15')}
        >
          <span className={'absolute top-0.5 h-6 w-6 rounded-full bg-white transition ' + (notifsOn ? 'left-[22px]' : 'left-0.5')} />
        </button>
      </div>

      {loading && <p role="status" className="mb-4 text-sm text-ink-secondary">Chargement des annonces et de la configuration…</p>}
      {!loading && !ready && (
        <button type="button" onClick={() => void load()} className="mb-4 rounded-md border border-white/10 px-4 py-2 text-sm">
          Réessayer le chargement
        </button>
      )}

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
        {/* ===== Formulaire ===== */}
        <form
          onSubmit={submit}
          className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6"
        >
          <fieldset disabled={busy || !ready} className="min-w-0 space-y-4">
          {/* Catégorie */}
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Catégorie
            </label>
            <div className="flex flex-wrap gap-2">
              {KINDS.map((k) => {
                const active = k.id === kind;
                return (
                  <button
                    key={k.id}
                    type="button"
                    onClick={() => setKind(k.id)}
                    className={`flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition ${
                      active
                        ? 'text-black'
                        : 'border-white/10 text-ink-secondary hover:bg-white/5'
                    }`}
                    style={active
                      ? { backgroundColor: k.color, borderColor: k.color }
                      : undefined}
                  >
                    <span>{k.emoji}</span>
                    {k.label}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Ciblage par pays */}
          <div>
            <label htmlFor="ann-country" className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Cible (pays)
            </label>
            <select
              id="ann-country"
              value={country}
              onChange={(e) => setCountry(e.target.value)}
              className={inputCls}
            >
              <option value="">🌍 Tout le monde</option>
              {COUNTRIES.map((c) => (
                <option key={c.code} value={c.code}>
                  {flagEmoji(c.code)} {c.name}
                </option>
              ))}
            </select>
            <p className="mt-1 text-[10px] text-ink-tertiary">
              Ex. choisis « Suède » → seuls les utilisateurs en Suède la verront.
            </p>
          </div>

          {/* Durée d'affichage (disparition auto) */}
          <div>
            <label htmlFor="ann-duration" className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Durée d'affichage
            </label>
            <select
              id="ann-duration"
              value={durationMin}
              onChange={(e) => setDurationMin(parseInt(e.target.value, 10))}
              className={inputCls}
            >
              <option value={15}>15 minutes</option>
              <option value={30}>30 minutes</option>
              <option value={60}>1 heure</option>
              <option value={180}>3 heures</option>
              <option value={1440}>24 heures</option>
              <option value={0}>Toujours (jusqu'à suppression)</option>
            </select>
            <p className="mt-1 text-[10px] text-ink-tertiary">
              L'annonce disparaît d'elle-même de tous les téléphones et TV
              passé ce délai (au plus tard à la prochaine ouverture).
            </p>
          </div>

          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Titre
            </label>
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              autoFocus
              maxLength={120}
              placeholder="Ex. De nouvelles chaînes sont arrivées 🎬"
              className={inputCls}
            />
          </div>

          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Message
            </label>
            <textarea
              value={body}
              onChange={(e) => setBody(e.target.value)}
              rows={3}
              maxLength={500}
              placeholder="Ex. Profite des nouvelles chaînes sport et cinéma, bon visionnage !"
              className={inputCls}
            />
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="ann-url" className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Lien (optionnel)
              </label>
              <input
                id="ann-url"
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                maxLength={300}
                inputMode="url"
                placeholder="https://…"
                className={inputCls}
              />
            </div>
            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Bouton (optionnel)
              </label>
              <input
                value={cta}
                onChange={(e) => setCta(e.target.value)}
                maxLength={40}
                placeholder="Ex. En profiter"
                className={inputCls}
              />
            </div>
          </div>

          {err && (
            <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
              {err}
            </div>
          )}
          {ok && (
            <div className="rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
              {ok}
            </div>
          )}

          <div className="flex gap-2">
            <button
              type="submit"
              disabled={busy || !ready}
              className="flex-1 rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
            >
              {busy ? 'Enregistrement…' : 'Publier à tous'}
            </button>
            <button
              type="button"
              onClick={clearAll}
              disabled={busy || !ready}
              className="rounded-md border border-white/10 px-4 py-2.5 text-sm text-ink-secondary transition hover:bg-white/5 disabled:opacity-50"
            >
              Tout retirer
            </button>
          </div>
          </fieldset>
        </form>

        {/* ===== Aperçu en direct (rendu côté app) ===== */}
        <div className="lg:sticky lg:top-6 lg:self-start">
          <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">
            Aperçu dans l'app
          </div>
          <div className="rounded-2xl border border-white/5 bg-[#0A0A0C] p-4">
            <div
              className="rounded-2xl border p-3.5"
              style={{
                backgroundColor: `${meta.color}1F`,
                borderColor: `${meta.color}80`,
              }}
            >
              <div className="flex items-start gap-2.5">
                <span className="text-lg leading-none" style={{ marginTop: 1 }}>
                  {meta.emoji}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-extrabold text-ink-primary">
                    {previewTitle}
                  </div>
                  <div className="mt-0.5 text-xs text-ink-secondary">
                    {previewBody}
                  </div>
                  {url.trim() && (
                    <div className="mt-2">
                      <span
                        className="inline-block rounded-md px-3 py-1 text-xs font-bold text-black"
                        style={{ backgroundColor: meta.color }}
                      >
                        {cta.trim() || 'Ouvrir'}
                      </span>
                    </div>
                  )}
                </div>
              </div>
            </div>
            <div className="mt-2 text-center text-[10px] text-ink-tertiary">
              Catégorie {meta.label.toLowerCase()} · refermable par le client
            </div>
          </div>
        </div>
      </div>

      {/* ===== Historique récent ===== */}
      {recent.length > 0 && (
        <div className="mt-8 max-w-2xl">
          <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">
            Dernières annonces ({recent.length})
          </div>
          <ul className="space-y-2">
            {recent.map((aRow) => {
              const m = kindMeta(aRow.kind);
              return (
                <li
                  key={aRow.id}
                  className={'flex items-start gap-3 rounded-lg border border-white/5 bg-midnight px-4 py-3 '
                    + (aRow.active === 0 ? 'opacity-50' : '')}
                >
                  <span
                    className="mt-0.5 inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs"
                    style={{ backgroundColor: `${m.color}26` }}
                    title={m.label}
                  >
                    {m.emoji}
                  </span>
                  <div className="min-w-0 flex-1">
                    {aRow.title && (
                      <div className="text-sm font-semibold text-ink-primary">
                        {aRow.title}
                      </div>
                    )}
                    {aRow.body && (
                      <div className="mt-0.5 text-xs text-ink-secondary">
                        {aRow.body}
                      </div>
                    )}
                    <div className="mt-1 text-[10px] text-ink-tertiary">
                      {new Date(aRow.created_at).toLocaleString()}
                      {aRow.country
                        ? ` · ${flagEmoji(aRow.country)} ${aRow.country}`
                        : ' · 🌍 tous'}
                      {aRow.expires_at
                        ? (aRow.expires_at > Date.now()
                            ? ` · ⏱ expire ${new Date(aRow.expires_at).toLocaleTimeString()}`
                            : ' · ⏱ expiré')
                        : ' · ⏱ permanent'}
                      {aRow.url ? ' · 🔗 lien' : ''}
                    </div>
                  </div>
                  {/* Activer / désactiver (sans supprimer) */}
                  <button
                    type="button"
                    onClick={() => toggleActive(aRow.id, aRow.active === 0)}
                    disabled={busy || !ready}
                    title={aRow.active === 0 ? 'Activer' : 'Désactiver'}
                    className={'relative mt-0.5 h-5 w-9 shrink-0 rounded-full transition '
                      + (aRow.active === 0 ? 'bg-white/15' : 'bg-accent')}
                  >
                    <span className={'absolute top-0.5 h-4 w-4 rounded-full bg-white transition '
                      + (aRow.active === 0 ? 'left-0.5' : 'left-[18px]')} />
                  </button>
                  <button
                    type="button"
                    onClick={() => removeOne(aRow.id)}
                    disabled={busy || !ready}
                    title="Supprimer cette annonce"
                    className="shrink-0 rounded-md border border-white/10 px-2 py-1 text-xs text-ink-tertiary transition hover:border-accent/40 hover:text-accent-bright"
                  >
                    ✕
                  </button>
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </AppLayout>
  );
}
