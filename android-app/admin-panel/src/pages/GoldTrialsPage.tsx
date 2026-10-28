import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { ApiError, getCurrentUser, goldTrialApi, GoldTrialSettings, GoldTrialSnapshot } from '@/lib/api';
import { historyRows, HistoryRow, pollTrials, trialDate, trialMac } from '@/lib/goldTrial';

type Draft = Pick<GoldTrialSettings, 'gold_trial_enabled' | 'daily_cap' | 'revision'>;
const inputClass = 'rounded-md border border-white/10 bg-slate px-3 py-2 text-sm focus:ring-2 focus:ring-accent';
const buttonClass = 'rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black disabled:opacity-50';

function HistoryTable({ rows }: { rows: HistoryRow[] }) {
  return <div className="overflow-x-auto"><table className="w-full text-left text-sm">
    <thead><tr>{['Date', 'Événement', 'Expiration', 'Ligne', 'IP', 'Version app'].map(label =>
      <th key={label} scope="col" className="p-3 text-ink-secondary">{label}</th>)}</tr></thead>
    <tbody>{rows.map(row => <tr key={row.key} className="border-t border-white/5">
      <td className="p-3 whitespace-nowrap">{trialDate(row.date)}</td><td className="p-3">{row.event}</td>
      <td className="p-3 whitespace-nowrap">{trialDate(row.expire)}</td><td className="p-3">{row.line}</td>
      <td className="p-3">{row.ip}</td><td className="p-3">{row.version}</td>
    </tr>)}</tbody>
  </table>{rows.length === 0 ? <p className="p-3 text-ink-secondary">Aucun événement.</p> : null}</div>;
}

export function GoldTrialsPage({ onLogout }: { onLogout: () => void }) {
  const allowed = ['super_admin', 'admin'].includes(getCurrentUser()?.role ?? '');
  const [snapshot, setSnapshot] = useState<GoldTrialSnapshot | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [saving, setSaving] = useState(false);
  const [mac, setMac] = useState('');
  const [activeMac, setActiveMac] = useState<string | null>(null);
  const [before, setBefore] = useState<number | null>(null);
  const [nextBefore, setNextBefore] = useState<number | null>(null);
  const [rows, setRows] = useState<HistoryRow[]>([]);
  const [legacyRows, setLegacyRows] = useState<HistoryRow[]>([]);
  const [used, setUsed] = useState<boolean | null>(null);
  const [error, setError] = useState('');
  const [historyError, setHistoryError] = useState('');
  const [legacyError, setLegacyError] = useState('');
  const [saveMessage, setSaveMessage] = useState('');
  const [updated, setUpdated] = useState<number | null>(null);

  useEffect(() => {
    if (!allowed) return;
    return pollTrials(async signal => {
      try {
        const data = await goldTrialApi.snapshot(signal);
        if (signal.aborted) return;
        setSnapshot(data); setError(''); setUpdated(Date.now());
      } catch (e) {
        if (signal.aborted) return;
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setError('Actualisation impossible. Les données affichées peuvent être anciennes.');
      }
    });
  }, [allowed, onLogout]);

  useEffect(() => {
    if (!allowed || !activeMac) return;
    setRows([]); setLegacyRows([]); setUsed(null); setNextBefore(null);
    return pollTrials(async signal => {
      // Les deux historiques sont indépendants. Un échec n'est jamais présenté
      // comme un historique vide ; chaque origine indique son indisponibilité.
      const [events, legacy] = await Promise.allSettled([
        goldTrialApi.events(activeMac, before, signal), goldTrialApi.history(activeMac, signal),
      ]);
      if (signal.aborted) return;
      if (events.status === 'fulfilled') {
        setRows(historyRows(events.value.history, 'policy'));
        setNextBefore(events.value.next_before); setHistoryError('');
      } else {
        if (events.reason instanceof ApiError && events.reason.status === 401) onLogout();
        setHistoryError('Historique des nouveaux essais indisponible.');
      }
      if (legacy.status === 'fulfilled') {
        setLegacyRows([...historyRows(legacy.value.history ?? [], 'history'), ...historyRows(legacy.value.lines ?? [], 'line')]);
        setUsed(legacy.value.trial_used); setLegacyError('');
      } else {
        if (legacy.reason instanceof ApiError && legacy.reason.status === 401) onLogout();
        setLegacyError('Historique précédent et activations payantes indisponibles.');
      }
    });
  }, [allowed, activeMac, before, onLogout]);

  function search(event: FormEvent) {
    event.preventDefault();
    const normalized = trialMac(mac);
    if (!normalized) { setSaveMessage('Adresse MAC invalide.'); return; }
    setSaveMessage(''); setMac(normalized); setBefore(null); setActiveMac(normalized);
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    if (!draft || saving) return;
    if (!Number.isInteger(draft.daily_cap) || draft.daily_cap < 0 || draft.daily_cap > 10000) {
      setSaveMessage('Le plafond doit être un entier entre 0 et 10 000.'); return;
    }
    setSaving(true); setSaveMessage('');
    try {
      const saved = await goldTrialApi.save(draft);
      setSnapshot(previous => previous ? { ...previous, ...saved } : previous);
      setDraft(null); setSaveMessage('Réglages enregistrés.');
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onLogout();
      setSaveMessage(e instanceof ApiError ? e.message : 'Enregistrement impossible.');
    } finally { setSaving(false); }
  }

  const edit = draft ?? snapshot;
  return <AppLayout title="Essais gratuits 24 h" subtitle="7 MOTION et Zuno TV · un seul essai par MAC" onLogout={onLogout}>
    {!allowed ? <p>Accès administrateur requis.</p> : <>
      {error ? <p role="alert" className="mb-4 text-accent">{error}</p> : null}
      {snapshot && edit ? <form onSubmit={save} className="mb-8 flex flex-wrap items-end gap-5 rounded-lg border border-white/10 p-5">
        <label className="flex items-center gap-3"><input type="checkbox" role="switch" checked={edit.gold_trial_enabled}
          disabled={saving} onChange={e => setDraft({ ...edit, gold_trial_enabled: e.target.checked })} /> Essai gratuit activé</label>
        <label className="flex flex-col gap-2">Plafond par jour (UTC)<input type="number" min={0} max={10000} step={1}
          className={inputClass} value={edit.daily_cap} disabled={saving}
          onChange={e => setDraft({ ...edit, daily_cap: e.target.valueAsNumber })} /></label>
        <button className={buttonClass} disabled={!draft || saving}>{saving ? 'Enregistrement…' : 'Enregistrer'}</button>
        {draft ? <button type="button" className="underline" disabled={saving} onClick={() => setDraft(null)}>Annuler les modifications</button> : null}
        {!snapshot.integration_ready ? <p className="w-full text-ink-secondary">Le service d’essai doit être vérifié avant de pouvoir activer l’offre.</p> : null}
      </form> : <p>Chargement des réglages…</p>}
      {saveMessage ? <p role="status" className="mb-4">{saveMessage}</p> : null}
      <section className="mb-8"><h2 className="mb-3 text-lg">Rechercher un appareil</h2>
        <form onSubmit={search} className="flex flex-wrap gap-3">
          <label className="flex flex-col gap-1">Adresse MAC<input className={inputClass} value={mac} onChange={e => setMac(e.target.value)} placeholder="MK:11:22:33:44:55" /></label>
          <button className={buttonClass}>Rechercher</button>
        </form>
        {activeMac ? <>
          <p className="my-3">{activeMac} · {used === null ? 'Vérification de l’essai…' : used ? 'Essai déjà utilisé' : 'Aucun essai dans l’historique précédent'}</p>
          {historyError ? <p role="alert">{historyError}</p> : null}
          <HistoryTable rows={rows} />
          <div className="my-3 flex gap-4">
            {before ? <button className="underline" onClick={() => setBefore(null)}>Événements récents</button> : null}
            {nextBefore ? <button className="underline" onClick={() => setBefore(nextBefore)}>Événements plus anciens</button> : null}
          </div>
          <h3 className="mt-4">Historique précédent et lignes existantes</h3>
          {legacyError ? <p role="alert">{legacyError}</p> : <HistoryTable rows={legacyRows} />}
        </> : null}
      </section>
      <section><h2 className="text-lg">50 derniers essais créés</h2>
        <p className="mb-3 text-ink-secondary">Actualisation toutes les 1,5 seconde{updated ? ` · Dernière lecture : ${trialDate(updated)}` : ''}</p>
        <div className="mb-3 flex flex-wrap gap-2">{snapshot?.recent.map(item =>
          <button key={item.mac} className="rounded border border-white/10 px-2 py-1 font-mono text-xs"
            onClick={() => { setMac(item.mac ?? ''); setActiveMac(item.mac ?? null); setBefore(null); }}>{item.mac}</button>)}</div>
        <HistoryTable rows={historyRows(snapshot?.recent ?? [], 'recent')} />
      </section>
    </>}
  </AppLayout>;
}
