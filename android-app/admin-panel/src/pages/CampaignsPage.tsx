import { type FormEvent, useCallback, useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { confirmAction } from '@/components/confirm';
import { ApiError, campaignsApi, announcementsApi, COUNTRIES, getCurrentUser } from '@/lib/api';
import { campaignState, parseLocalDate, toLocalInput, type Campaign, type CampaignContent } from '@/lib/campaigns';

const inputClass = 'w-full rounded-lg border border-white/10 bg-slate px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-accent';
const buttonClass = 'rounded-lg border border-white/15 px-3 py-2 text-sm hover:bg-white/5 disabled:cursor-not-allowed disabled:opacity-40';
const states = { draft: 'Brouillon', scheduled: 'Programmée', ready: 'Diffusion autorisée', available: 'Disponible dans l’app', paused: 'En pause', ended: 'Terminée', archived: 'Archivée', removed: 'Retirée' };

function newDraft(): CampaignContent & { id: string } {
  const starts = Math.ceil(Date.now() / 60000) * 60000 + 3600000;
  return { id: crypto.randomUUID(), type: 'advertisement', title: '', body: '', url: '', cta: '', country: '', starts_at: starts,
    ends_at: starts + 86400000, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone };
}

export function CampaignsPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<Campaign[]>([]);
  const [draft, setDraft] = useState(newDraft);
  const [editing, setEditing] = useState<Campaign | null>(null);
  const [start, setStart] = useState(() => toLocalInput(draft.starts_at));
  const [end, setEnd] = useState(() => toLocalInput(draft.ends_at));
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [enabled, setEnabled] = useState<boolean | null>(null);
  const [now, setNow] = useState(Date.now());
  const [filter, setFilter] = useState('all');
  const [query, setQuery] = useState('');
  const epoch = useRef(0);
  const lock = useRef(false);
  const isOwner = getCurrentUser()?.role === 'super_admin';

  const fail = useCallback((e: unknown) => {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setError(e instanceof Error ? e.message : 'Chargement impossible. Réessaie avec Actualiser.');
  }, [onLogout]);
  const load = useCallback(async () => {
    const request = ++epoch.current;
    const [data, settings] = await Promise.all([campaignsApi.list(), announcementsApi.getSettings()]);
    if (request !== epoch.current) return;
    setItems(data.items); setEnabled(settings.enabled); setNow(data.now);
  }, []);
  useEffect(() => {
    if (!isOwner) return;
    load().catch(fail).finally(() => setLoading(false));
    const timer = window.setInterval(() => setNow(Date.now()), 30000);
    return () => { ++epoch.current; window.clearInterval(timer); };
  }, [load, fail, isOwner]);

  function populate(value: CampaignContent & { id: string }, existing: Campaign | null = null) {
    setDraft({ ...value, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone });
    setEditing(existing); setStart(toLocalInput(value.starts_at)); setEnd(toLocalInput(value.ends_at));
    setError(''); setNotice('');
  }
  async function operation(work: () => Promise<void>) {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError(''); setNotice('');
    try { await work(); } catch (e) { fail(e); }
    finally { lock.current = false; setBusy(false); }
  }
  async function save(event: FormEvent) {
    event.preventDefault();
    await operation(async () => {
      const content = { ...draft, title: draft.title.trim(), body: draft.body.trim(), starts_at: parseLocalDate(start), ends_at: parseLocalDate(end) };
      if (content.ends_at <= content.starts_at) throw new Error('La fin doit être après le début.');
      if (editing) await campaignsApi.update(editing.id, editing.version, 'save', content);
      else await campaignsApi.create(content);
      populate(newDraft()); await load();
      setNotice('Brouillon enregistré. Clique sur Programmer pour autoriser sa diffusion.');
    });
  }
  async function action(item: Campaign, name: 'schedule' | 'pause' | 'archive') {
    if (name === 'schedule') {
      const accepted = await confirmAction({
        title: 'Programmer cette campagne ?',
        message: `${item.title} · ${item.country || 'Tous les pays'} · du ${date(item.starts_at, item.timezone)} au ${date(item.ends_at, item.timezone)}. Les apps la reçoivent à leur prochaine lecture des annonces pendant cette période.`,
        confirmLabel: 'Programmer',
      });
      if (!accepted) return;
    }
    await operation(async () => {
      await campaignsApi.update(item.id, item.version, name); await load();
      if (editing?.id === item.id) populate(newDraft());
      setNotice(name === 'schedule' ? 'Période de diffusion enregistrée.' : name === 'pause' ? 'Campagne mise en pause.' : 'Campagne archivée.');
    });
  }
  function date(at: number, timezone: string) {
    return new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium', timeStyle: 'short', timeZone: timezone }).format(at) + ` (${timezone})`;
  }
  const visible = items.filter(item => (filter === 'all' || campaignState(item, now) === filter) && `${item.title} ${item.body}`.toLocaleLowerCase().includes(query.toLocaleLowerCase()));

  return <AppLayout title="Publicités et événements" subtitle="Prépare tes campagnes, vérifie leur contenu et choisis leur période de diffusion." onLogout={onLogout}>
    {!isOwner ? <p role="alert">Cette page est réservée au propriétaire.</p> : <>
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <p className="max-w-2xl text-sm text-ink-secondary">Des messages dans l’app, à sa prochaine lecture des annonces. La période choisie ne change pas la durée de la notification à l’écran.</p>
        <button className={buttonClass} disabled={busy || loading} onClick={() => operation(load)}>Actualiser</button>
      </div>
      {enabled === false && <p role="status" className="mb-5 rounded-xl border border-accent/40 bg-accent/10 p-4 text-sm">Les annonces sont désactivées pour toutes les apps. <Link className="underline" to="/notifications">Ouvrir les réglages des annonces</Link> pour les réactiver.</p>}
      {error && <p role="alert" className="mb-4 rounded-lg border border-accent/50 p-4 text-sm">{error}</p>}
      {notice && <p role="status" className="mb-4 rounded-lg border border-white/20 p-4 text-sm">{notice}</p>}
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_340px]">
        <form onSubmit={save} className="space-y-4 rounded-xl border border-white/10 bg-midnight p-5">
          <div className="flex items-center justify-between gap-3"><h2 className="text-lg font-semibold">{editing ? 'Modifier le brouillon' : 'Nouvelle campagne'}</h2><span className="rounded-full bg-white/5 px-3 py-1 text-xs text-ink-secondary">Privée avant programmation</span></div>
          <fieldset disabled={busy} className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="block space-y-1 text-sm"><span>Type</span><select className={inputClass} value={draft.type} onChange={e => setDraft({ ...draft, type: e.target.value as CampaignContent['type'] })}><option value="advertisement">Publicité</option><option value="event">Événement</option></select></label>
              <label className="block space-y-1 text-sm"><span>Pays</span><select className={inputClass} value={draft.country} onChange={e => setDraft({ ...draft, country: e.target.value })}><option value="">Tous les pays</option>{COUNTRIES.map(c => <option key={c.code} value={c.code}>{c.name}</option>)}</select></label>
            </div>
            <label className="block space-y-1 text-sm"><span>Titre</span><input className={inputClass} required maxLength={108} value={draft.title} onChange={e => setDraft({ ...draft, title: e.target.value })} placeholder="Une offre, un rendez-vous…" /></label>
            <label className="block space-y-1 text-sm"><span>Message</span><textarea className={inputClass} required maxLength={500} rows={3} value={draft.body} onChange={e => setDraft({ ...draft, body: e.target.value })} /><span className="block text-right text-xs text-ink-tertiary">{draft.body.length}/500</span></label>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="block space-y-1 text-sm"><span>Lien public HTTPS (facultatif)</span><input type="url" className={inputClass} maxLength={300} value={draft.url} onChange={e => setDraft({ ...draft, url: e.target.value })} placeholder="https://…" /></label>
              <label className="block space-y-1 text-sm"><span>Texte du bouton</span><input className={inputClass} maxLength={40} required={Boolean(draft.url)} value={draft.cta} onChange={e => setDraft({ ...draft, cta: e.target.value })} placeholder="En savoir plus" /></label>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="block space-y-1 text-sm"><span>Début de diffusion</span><input type="datetime-local" className={inputClass} required value={start} onChange={e => setStart(e.target.value)} /></label>
              <label className="block space-y-1 text-sm"><span>Fin de diffusion</span><input type="datetime-local" className={inputClass} required value={end} onChange={e => setEnd(e.target.value)} /></label>
            </div>
            <p className="text-xs text-ink-tertiary">Fuseau de saisie : {draft.timezone}. Les dates sont conservées même si tu changes de pays.</p>
            <div className="flex flex-wrap gap-3"><button type="submit" className="rounded-lg bg-accent px-4 py-2.5 text-sm font-semibold disabled:opacity-40">{busy ? 'Enregistrement…' : 'Enregistrer le brouillon'}</button>{editing && <button type="button" className={buttonClass} onClick={() => populate(newDraft())}>Annuler la modification</button>}</div>
          </fieldset>
        </form>
        <aside className="rounded-xl border border-white/10 bg-midnight p-5">
          <h2 className="mb-1 font-semibold">Aperçu du message</h2><p className="mb-5 text-xs text-ink-tertiary">Le rendu varie selon la version de l’app et l’écran.</p>
          <div className="break-words rounded-xl border border-accent/30 bg-slate p-4">
            <span className="text-xs font-semibold uppercase tracking-wide text-accent">{draft.type === 'advertisement' ? 'Publicité' : 'Événement'}</span>
            <h3 className="mt-2 text-lg font-semibold">{draft.title || 'Ton titre'}</h3><p className="mt-2 whitespace-pre-wrap text-sm text-ink-secondary">{draft.body || 'Le message de ta campagne apparaît ici.'}</p>
            {draft.url && draft.cta && <span className="mt-4 inline-block rounded-lg bg-accent px-3 py-2 text-sm">{draft.cta}</span>}
          </div>
          <p className="mt-4 text-xs text-ink-secondary">{draft.country || 'Tous les pays'} · Message identifié comme {draft.type === 'advertisement' ? 'publicité' : 'événement'}.</p>
          <p className="mt-3 text-xs text-ink-tertiary">Une campagne déjà diffusée se duplique pour préparer un nouveau message. La reprise conserve son identifiant d’annonce.</p>
        </aside>
      </div>
      <section className="mt-7" aria-label="Campagnes enregistrées">
        <div className="mb-4 flex flex-wrap items-center gap-3"><h2 className="mr-auto text-lg font-semibold">Tes campagnes</h2><input aria-label="Rechercher une campagne" placeholder="Rechercher…" className={inputClass + ' sm:!w-60'} value={query} onChange={e => setQuery(e.target.value)} /><select aria-label="Filtrer les campagnes" className={inputClass + ' sm:!w-52'} value={filter} onChange={e => setFilter(e.target.value)}><option value="all">Tous les états</option>{Object.entries(states).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></div>
        {loading ? <p role="status">Chargement des campagnes…</p> : visible.length === 0 ? <p className="rounded-xl border border-white/10 p-6 text-sm text-ink-secondary">Aucune campagne dans cette sélection.</p> : <div className="grid gap-3 lg:grid-cols-2">{visible.map(item => {
          const state = campaignState(item, now);
          const editable = !item.broadcast_id && ['draft', 'paused'].includes(item.status);
          return <article key={item.id} className="rounded-xl border border-white/10 bg-midnight p-5">
            <div className="mb-2 flex flex-wrap justify-between gap-2"><span className="text-xs uppercase tracking-wide text-ink-tertiary">{item.type === 'event' ? 'Événement' : 'Publicité'} · {item.country || 'Tous les pays'}</span><span className="rounded-full bg-white/10 px-2 py-1 text-xs">{states[state]}</span></div>
            <h3 className="break-words font-semibold">{item.title}</h3><p className="mt-2 break-words text-sm text-ink-secondary">{item.body}</p>
            <p className="mt-3 text-xs text-ink-tertiary">Du {date(item.starts_at, item.timezone)}<br />au {date(item.ends_at, item.timezone)}</p>
            <div className="mt-4 flex flex-wrap gap-2">
              {editable && <button className={buttonClass} disabled={busy} onClick={() => { populate(item, item); window.scrollTo({ top: 0, behavior: 'smooth' }); }}>Modifier</button>}
              {['draft', 'paused'].includes(item.status) && item.ends_at > now && state !== 'removed' && <button className={buttonClass} disabled={busy} onClick={() => action(item, 'schedule')}>{item.broadcast_id ? 'Reprendre' : 'Programmer'}</button>}
              {item.status === 'scheduled' && !['ended', 'removed'].includes(state) && <button className={buttonClass} disabled={busy} onClick={() => action(item, 'pause')}>Mettre en pause</button>}
              <button className={buttonClass} disabled={busy} onClick={() => { const fresh = newDraft(); populate({ ...item, id: fresh.id, starts_at: fresh.starts_at, ends_at: fresh.ends_at }); window.scrollTo({ top: 0, behavior: 'smooth' }); }}>Dupliquer</button>
              {item.status !== 'archived' && <button className={buttonClass} disabled={busy} onClick={() => action(item, 'archive')}>Archiver</button>}
            </div>
          </article>;
        })}</div>}
        <p className="mt-3 text-xs text-ink-tertiary">Les 100 campagnes les plus récentes. « Disponible » confirme la mise à disposition, pas le nombre de vues.</p>
      </section>
    </>}
  </AppLayout>;
}
