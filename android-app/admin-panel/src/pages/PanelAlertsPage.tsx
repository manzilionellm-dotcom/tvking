import { useCallback, useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { getCurrentUser, panelAlertsApi, type PanelAlertEvent } from '@/lib/api';
import { readPanelTarget } from '@/lib/panel-links';
import { formatDateTime } from '@/lib/utils';

function validEvent(value: PanelAlertEvent): boolean {
  return value?.v === 1 && ['new_device', 'activation', 'problem'].includes(value.type)
    && /^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/.test(value.event_id)
    && Number.isSafeInteger(value.seq) && value.seq > 0
    && Number.isSafeInteger(value.created_at) && value.created_at > 0
    && !Number.isNaN(new Date(value.created_at).getTime())
    && typeof value.title === 'string' && value.title.length > 0 && value.title.length <= 96
    && typeof value.message === 'string' && value.message.length <= 240
    && !!readPanelTarget(value.url, window.location.origin);
}

export function PanelAlertsPage({ onLogout }: { onLogout: () => void }) {
  if (getCurrentUser()?.role !== 'super_admin') return <AppLayout title="Alertes du panneau" onLogout={onLogout}><p>Cette page est réservée au propriétaire du panneau.</p></AppLayout>;
  return <Inbox key={getCurrentUser()?.id} onLogout={onLogout} />;
}

function Inbox({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<PanelAlertEvent[]>([]);
  const [unread, setUnread] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [marking, setMarking] = useState(false);
  const busy = useRef(false);
  const markingRef = useRef(false);
  const alive = useRef(true);
  const cursor = useRef<number | undefined>();
  const abort = useRef<AbortController | null>(null);
  const refresh = useCallback(async () => {
    if (busy.current || getCurrentUser()?.role !== 'super_admin') return;
    busy.current = true;
    const request = new AbortController();
    const userId = getCurrentUser()?.id;
    abort.current = request;
    try {
      const result = await panelAlertsApi.events(cursor.current, request.signal);
      if (!alive.current || request.signal.aborted || getCurrentUser()?.id !== userId || getCurrentUser()?.role !== 'super_admin') return;
      if (result?.ok !== true || !Array.isArray(result.items) || !result.items.every(validEvent)
          || !Number.isSafeInteger(result.next_cursor) || result.next_cursor < (cursor.current || 0)
          || !Number.isSafeInteger(result.unread_count) || result.unread_count < 0) throw new Error();
      setItems((current) => {
        const byId = new Map(current.map((item) => [item.event_id, item]));
        for (const item of result.items) byId.set(item.event_id, item);
        return Array.from(byId.values()).sort((a, b) => b.seq - a.seq).slice(0, 200);
      });
      cursor.current = result.next_cursor;
      setUnread(result.unread_count);
      setError(null);
    } catch {
      if (alive.current && !request.signal.aborted) setError('Les alertes n’ont pas pu être actualisées. Les éléments déjà reçus sont conservés.');
    } finally {
      if (abort.current === request) {
        busy.current = false;
        if (alive.current) setLoading(false);
      }
    }
  }, []);
  useEffect(() => {
    alive.current = true;
    busy.current = false;
    void refresh();
    const timer = window.setInterval(() => { void refresh(); }, 30_000);
    const focus = () => { void refresh(); };
    window.addEventListener('focus', focus);
    return () => { alive.current = false; abort.current?.abort(); window.clearInterval(timer); window.removeEventListener('focus', focus); };
  }, [refresh]);

  async function markRead(ids: string[]) {
    if (markingRef.current || !ids.length || getCurrentUser()?.role !== 'super_admin') return;
    markingRef.current = true;
    setMarking(true);
    try {
      const result = await panelAlertsApi.read(ids);
      if (result?.ok !== true) throw new Error();
      if (!alive.current) return;
      setItems((current) => current.map((item) => ids.includes(item.event_id) ? { ...item, read_at: Date.now() } : item));
      void refresh();
    } catch { if (alive.current) setError('La lecture de ces alertes n’a pas pu être enregistrée.'); }
    finally { markingRef.current = false; if (alive.current) setMarking(false); }
  }

  return <AppLayout title="Alertes du panneau" subtitle="Événements confirmés et problèmes détectés" onLogout={onLogout}>
    <div className="mb-4 flex max-w-3xl flex-wrap items-center justify-between gap-3">
      <p className="text-sm text-ink-secondary">{unread == null ? 'Vérification…' : `${unread} alerte${unread === 1 ? '' : 's'} non lue${unread === 1 ? '' : 's'}`}</p>
      <Link to="/account" className="text-sm text-accent underline">Préférences et notifications sur ce téléphone</Link>
    </div>
    {error && <p role="alert" className="mb-4 max-w-3xl rounded-md border border-accent/30 p-3 text-sm text-accent-bright">{error}</p>}
    {loading && <p role="status">Chargement des alertes…</p>}
    {!loading && !error && items.length === 0 && <p>Aucune alerte reçue.</p>}
    <div className="max-w-3xl space-y-3">
      {items.map((item) => <article key={item.event_id} className="rounded-xl border border-white/10 bg-midnight p-4">
        <div className="flex flex-wrap items-start justify-between gap-2"><h2 className="font-semibold">{item.title}</h2><time className="text-xs text-ink-tertiary" dateTime={new Date(item.created_at).toISOString()}>{formatDateTime(item.created_at)}</time></div>
        <p className="mt-2 text-sm text-ink-secondary">{item.message}</p>
        <div className="mt-3 flex flex-wrap items-center gap-4 text-xs">
          <Link className="text-accent underline" to={readPanelTarget(item.url, window.location.origin)!.url}>{item.type === 'problem' ? 'Ouvrir le diagnostic' : 'Ouvrir la fiche'}</Link>
          {item.read_at == null ? <button type="button" disabled={marking} className="text-ink-secondary underline disabled:opacity-50" onClick={() => { void markRead([item.event_id]); }}>Marquer comme lue</button> : <span className="text-ink-tertiary">Lue</span>}
        </div>
      </article>)}
    </div>
  </AppLayout>;
}
