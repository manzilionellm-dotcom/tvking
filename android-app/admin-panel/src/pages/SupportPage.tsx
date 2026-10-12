import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { ApiError, getCurrentUser, supportApi, type SupportMessage, type SupportPage as MessagePage, type SupportThread } from '@/lib/api';

const time = (at: number) => new Intl.DateTimeFormat('fr', { dateStyle: 'short', timeStyle: 'short' }).format(at);
const messageError = (e: unknown) => e instanceof Error ? e.message : 'Connexion interrompue. Réessaie.';

export function SupportPage({ onLogout }: { onLogout: () => void }) {
  const [threads, setThreads] = useState<SupportThread[]>([]);
  const [selected, setSelected] = useState('');
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');
  const queryVersion = useRef(0);
  const owner = getCurrentUser()?.role === 'super_admin';
  const load = useCallback(async () => {
    if (document.hidden || !owner) return;
    const version = ++queryVersion.current;
    try { const r = await supportApi.list(query); if (version !== queryVersion.current) return; setThreads(r.items); setError(''); }
    catch(e) { if (version !== queryVersion.current) return; if (e instanceof ApiError && e.status === 401) onLogout(); else setError(messageError(e)); }
  }, [owner, onLogout, query]);
  useEffect(() => { const delay = setTimeout(() => void load(), 250); const id = setInterval(() => void load(), 5000); return () => { ++queryVersion.current; clearTimeout(delay); clearInterval(id); }; }, [load]);
  return <AppLayout title="Chat privé" subtitle="Les conversations de tes clients, directement dans 7MOTION." onLogout={onLogout}>
    {!owner ? <p role="alert">Réservé au propriétaire.</p> : <>
      {error && <p role="alert" className="mb-4 text-accent">{error}</p>}
      <div className="grid min-h-[600px] gap-4 lg:grid-cols-[300px_minmax(0,1fr)]">
        <aside className="rounded-2xl border border-white/10 bg-midnight p-4"><div className="mb-4 flex items-center justify-between"><h2 className="font-semibold">Conversations</h2><span className="rounded-full bg-accent/15 px-2 py-1 text-xs">{threads.reduce((n,t) => n + t.unread, 0)} non lus</span></div>
          <input aria-label="Rechercher un appareil" placeholder="Rechercher une MAC…" className="mb-4 w-full rounded-xl border border-white/10 bg-slate p-3 text-sm" value={query} onChange={e => setQuery(e.target.value)} />
          <div className="max-h-[560px] space-y-2 overflow-auto">{threads.filter(t => `${t.device_label} ${t.mac}`.toUpperCase().includes(query.toUpperCase())).map(t => <button key={t.mac} className={`w-full rounded-xl border p-3 text-left ${selected === t.mac ? 'border-accent/50 bg-accent/10' : 'border-transparent hover:bg-white/5'}`} onClick={() => setSelected(t.mac)}><div className="flex justify-between gap-2"><span className="font-mono text-xs">{t.device_label || `Client ${t.mac.slice(0,8)}`}</span>{t.unread > 0 && <span className="rounded-full bg-accent px-2 text-xs">{t.unread}</span>}</div><p className="mt-2 truncate text-sm text-ink-secondary">{t.preview}</p><p className="mt-2 text-xs text-ink-tertiary">{time(t.updated_at)}</p></button>)}</div>
          {threads.length === 0 && <p className="py-8 text-sm text-ink-secondary">Le premier message d’un client apparaîtra ici.</p>}<p className="mt-4 text-xs text-ink-tertiary">Les 100 conversations les plus récentes. La recherche inclut les conversations anciennes. La MAC est déclarée par le client ; elle ne prouve pas son identité.</p>
        </aside>
        {selected ? <Conversation key={selected} mac={selected} onRead={load} onLogout={onLogout} /> : <div className="grid place-items-center rounded-2xl border border-white/10 bg-midnight p-8"><div className="max-w-sm text-center"><div className="mx-auto mb-5 grid h-20 w-20 place-items-center rounded-3xl border border-accent/30 bg-accent/10 text-3xl" aria-hidden="true">✦</div><h2 className="text-xl font-semibold">Un espace pour échanger</h2><p className="mt-3 text-sm text-ink-secondary">Choisis une conversation. Seuls le client concerné et le propriétaire peuvent lire et répondre.</p></div></div>}
      </div>
    </>}
  </AppLayout>;
}

function Conversation({ mac, onRead, onLogout }: { mac: string; onRead: () => Promise<void>; onLogout: () => void }) {
  const [data, setData] = useState<MessagePage | null>(null);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const scroller = useRef<HTMLDivElement>(null);
  const alive = useRef(true);
  const locked = useRef(false);
  const loading = useRef(false);
  const loadingOlder = useRef(false);
  const newest = useRef(0);
  const atBottom = useRef(true);
  const lastRead = useRef(0);
  const pending = useRef<{ id: string; body: string } | null>(null);
  const fail = useCallback((e: unknown) => { if (!alive.current) return; if(e instanceof ApiError && e.status === 401) onLogout(); else setError(messageError(e)); }, [onLogout]);
  const markRead = useCallback(async (items: SupportMessage[]) => {
    const seq = items.at(-1)?.seq || 0;
    if (document.hidden || !atBottom.current || seq <= lastRead.current) return;
    await supportApi.read(mac, seq); lastRead.current = seq; await onRead();
  }, [mac, onRead]);
  const load = useCallback(async () => {
    if(document.hidden || loading.current) return;
    loading.current = true;
    try {
      const after = newest.current || undefined;
      const r = await supportApi.messages(mac, undefined, after);
      if (!alive.current) return;
      setData(old => ({ ...r, more: after ? (old?.more ?? false) : r.more, items: old ? [...new Map([...old.items, ...r.items].map(m => [m.seq,m])).values()].sort((a,b) => a.seq-b.seq) : r.items }));
      newest.current = r.items.at(-1)?.seq || newest.current;
      if(atBottom.current) requestAnimationFrame(() => { if(scroller.current) scroller.current.scrollTop = scroller.current.scrollHeight; });
      requestAnimationFrame(() => { if (alive.current) void markRead(r.items).catch(fail); });
    } catch(e) { fail(e); } finally { loading.current = false; }
  }, [mac, fail, markRead]);
  useEffect(() => { alive.current = true; void load(); const id = setInterval(() => void load(), 3000); return () => { alive.current = false; clearInterval(id); }; }, [load]);
  async function send(e: FormEvent) {
    e.preventDefault(); if(locked.current || !draft.trim()) return;
    locked.current = true; setSending(true); setError('');
    const text = draft.trim();
    if(pending.current?.body !== text) pending.current = { id: crypto.randomUUID(), body: text };
    try { await supportApi.send(mac, text, pending.current.id); if (!alive.current) return; setDraft(''); pending.current = null; atBottom.current = true; await load(); }
    catch(e) { fail(e); } finally { locked.current = false; if(alive.current) setSending(false); }
  }
  async function older() {
    if(!data?.items.length || loadingOlder.current) return;
    loadingOlder.current = true;
    try { const r = await supportApi.messages(mac, data.items[0].seq); if(alive.current) setData(old => old ? { ...old, more:r.more, items:[...new Map([...r.items,...old.items].map(m => [m.seq,m])).values()].sort((a,b) => a.seq-b.seq) } : r); }
    catch(e) { fail(e); } finally { loadingOlder.current = false; }
  }
  return <section className="flex min-w-0 flex-col overflow-hidden rounded-2xl border border-white/10 bg-midnight" aria-label={`Conversation ${mac}`}>
    <header className="flex items-center gap-3 border-b border-white/10 p-5"><span className="grid h-10 w-10 place-items-center rounded-2xl bg-accent/15 text-accent" aria-hidden="true">✦</span><div><h2 className="font-semibold">7MOTION · Assistance</h2><p className="font-mono text-xs text-ink-secondary">{`Conversation ${mac.slice(0,12)}`}</p></div></header>
    <div ref={scroller} className="h-[430px] space-y-4 overflow-y-auto p-5" role="log" aria-label="Messages" onScroll={() => { const el=scroller.current; if(!el) return; atBottom.current=el.scrollHeight-el.scrollTop-el.clientHeight<32; if(atBottom.current && data) void markRead(data.items).catch(fail); }}>
      {data?.more && <button className="block w-full text-xs text-ink-secondary underline" onClick={older}>Messages précédents</button>}
      {data?.items.map(m => <div key={m.seq} className={`flex ${m.sender==='owner'?'justify-end':'justify-start'}`}><div className={`max-w-[85%] rounded-2xl p-3 ${m.sender==='owner'?'rounded-br-sm bg-accent/15':'rounded-bl-sm bg-white/5'}`}><p className="whitespace-pre-wrap break-words text-sm">{m.body}</p><p className="mt-2 text-right text-[10px] text-ink-tertiary">{time(m.created_at)}{m.sender==='owner' ? (data.client_read_seq >= m.seq ? ' · Lu' : ' · Envoyé') : ''}</p></div></div>)}
      {data?.items.length === 0 && <p className="text-sm text-ink-secondary">Commence la conversation.</p>}
    </div>
    <form onSubmit={send} className="mt-auto border-t border-white/10 p-4"><label className="sr-only" htmlFor="support-message">Votre réponse</label><textarea id="support-message" className="w-full resize-none rounded-xl border border-white/10 bg-slate p-3 text-sm" placeholder="Une réponse claire et personnelle…" maxLength={2000} rows={3} value={draft} disabled={sending} onChange={e=>setDraft(e.target.value)} />{error && <p role="alert" className="my-2 text-sm text-accent">{error}</p>}<div className="mt-3 flex items-center justify-between"><span className="text-xs text-ink-tertiary">{draft.length}/2000 · Conversation privée</span><button disabled={sending || !draft.trim()} className="rounded-xl bg-accent px-5 py-2.5 text-sm font-semibold disabled:opacity-40">{sending?'Envoi…':'Envoyer'}</button></div></form>
  </section>;
}
