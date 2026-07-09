import { FormEvent, useCallback, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  integrationsApi, API_KEY_SCOPES, WEBHOOK_EVENTS,
  type ApiKey, type Webhook, ApiError,
} from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

/// Page INTÉGRATIONS — « je peux mettre un API pour définir ce qu'il va
/// faire ». Deux briques :
///  • CLÉS API : accès programmatique au backend (site web, bot WhatsApp,
///    n8n/Zapier, script) avec des SCOPES précis — la clé ne fait QUE ce
///    que tu as coché. Affichée une seule fois, révocable à tout moment.
///  • WEBHOOKS : le backend PRÉVIENT tes systèmes (activation, source
///    poussée, appareil bloqué…) par un POST signé HMAC.

export function IntegrationsPage({ onLogout }: { onLogout: () => void }) {
  const [keys, setKeys] = useState<ApiKey[]>([]);
  const [hooks, setHooks] = useState<Webhook[]>([]);
  const [err, setErr] = useState<string | null>(null);

  // Création de clé
  const [keyName, setKeyName] = useState('');
  const [keyScopes, setKeyScopes] = useState<string[]>(['read']);
  const [newKey, setNewKey] = useState<string | null>(null);
  const [busyKey, setBusyKey] = useState(false);

  // Création de webhook
  const [whUrl, setWhUrl] = useState('');
  const [whEvents, setWhEvents] = useState<string[]>(['activation.created']);
  const [newSecret, setNewSecret] = useState<string | null>(null);
  const [busyWh, setBusyWh] = useState(false);

  const reload = useCallback(() => {
    integrationsApi.listKeys()
      .then((r) => setKeys(r.items))
      .catch((e) => { if (e instanceof ApiError && e.status === 401) onLogout(); });
    integrationsApi.listWebhooks()
      .then((r) => setHooks(r.items))
      .catch(() => {});
  }, [onLogout]);

  useEffect(() => { reload(); }, [reload]);

  function toggle(list: string[], v: string): string[] {
    return list.includes(v) ? list.filter((x) => x !== v) : [...list, v];
  }

  async function createKey(e: FormEvent) {
    e.preventDefault();
    setBusyKey(true); setErr(null); setNewKey(null);
    try {
      const r = await integrationsApi.createKey(keyName.trim(), keyScopes);
      setNewKey(r.key);
      setKeyName('');
      reload();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally {
      setBusyKey(false);
    }
  }

  async function revokeKey(k: ApiKey) {
    if (!window.confirm(`Révoquer la clé « ${k.name} » ? Les systèmes qui l'utilisent perdront l'accès immédiatement.`)) return;
    try {
      await integrationsApi.revokeKey(k.id);
      reload();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) onLogout();
    }
  }

  async function createWebhook(e: FormEvent) {
    e.preventDefault();
    setBusyWh(true); setErr(null); setNewSecret(null);
    try {
      const r = await integrationsApi.createWebhook(whUrl.trim(), whEvents);
      setNewSecret(r.secret);
      setWhUrl('');
      reload();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally {
      setBusyWh(false);
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';
  const chipCls = (on: boolean) =>
    'rounded-full border px-3 py-1 text-xs transition ' +
    (on
      ? 'border-accent bg-accent/10 text-accent-bright'
      : 'border-white/10 bg-slate text-ink-secondary hover:border-white/25');

  return (
    <AppLayout
      title="API & intégrations"
      subtitle="Clés API à portée limitée + webhooks signés — branche ton site, ton bot, tes automatisations."
      onLogout={onLogout}
    >
      <div className="grid max-w-6xl gap-6 xl:grid-cols-2">
        {/* ================= CLÉS API ================= */}
        <section className="space-y-4">
          <form onSubmit={createKey} className="space-y-3 rounded-xl border border-white/5 bg-midnight p-6">
            <h2 className="text-sm font-semibold">Créer une clé API</h2>
            <input value={keyName} required maxLength={100}
              onChange={(e) => setKeyName(e.target.value)}
              placeholder="Nom (ex. Site vitrine, Bot WhatsApp)" className={inputCls} />
            <div>
              <p className="mb-1.5 text-[10px] uppercase tracking-widest text-ink-tertiary">
                Ce que cette clé a le droit de faire
              </p>
              <div className="flex flex-wrap gap-2">
                {API_KEY_SCOPES.map((s) => (
                  <button type="button" key={s.key} title={s.hint}
                    onClick={() => setKeyScopes((prev) => toggle(prev, s.key))}
                    className={chipCls(keyScopes.includes(s.key))}>
                    {s.label}
                  </button>
                ))}
              </div>
            </div>
            <button type="submit" disabled={busyKey || !keyName.trim() || keyScopes.length === 0}
              className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
              {busyKey ? 'Création…' : 'Générer la clé'}
            </button>
            {newKey && (
              <div className="rounded-md border border-success/30 bg-success/10 p-3">
                <p className="mb-1 text-xs font-semibold text-success">
                  Clé créée — copie-la MAINTENANT, elle ne sera plus jamais affichée :
                </p>
                <div className="flex items-center gap-2">
                  <code className="min-w-0 flex-1 truncate rounded bg-black/40 px-2 py-1.5 font-mono text-xs text-ink-primary">
                    {newKey}
                  </code>
                  <button type="button"
                    onClick={() => navigator.clipboard?.writeText(newKey)}
                    className="rounded-md border border-white/10 px-2.5 py-1.5 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                    Copier
                  </button>
                </div>
              </div>
            )}
          </form>

          <div className="rounded-xl border border-white/5 bg-obsidian p-6">
            <h3 className="mb-3 text-sm font-semibold">Clés existantes</h3>
            {keys.length === 0 && <p className="text-sm text-ink-tertiary">Aucune clé.</p>}
            <ul className="space-y-2">
              {keys.map((k) => (
                <li key={k.id}
                  className={
                    'rounded-lg border border-white/10 bg-slate/30 p-3 text-sm ' +
                    (k.revoked_at ? 'opacity-50' : '')
                  }>
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{k.name}</span>
                    {k.revoked_at ? (
                      <span className="rounded-full bg-white/5 px-2 py-0.5 text-[10px] uppercase tracking-widest text-ink-tertiary">
                        révoquée
                      </span>
                    ) : (
                      <button onClick={() => revokeKey(k)}
                        className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                        Révoquer
                      </button>
                    )}
                  </div>
                  <div className="mt-1 flex flex-wrap gap-2 text-[11px] text-ink-tertiary">
                    <span className="font-mono">{k.prefix}</span>
                    <span>· {k.scopes.map((s) => API_KEY_SCOPES.find((x) => x.key === s)?.label || s).join(', ')}</span>
                    <span>· créée {formatDateTime(k.created_at)}</span>
                    {k.last_used_at && <span>· utilisée {formatDateTime(k.last_used_at)}</span>}
                  </div>
                </li>
              ))}
            </ul>
          </div>

          {/* Mini-doc développeur */}
          <div className="rounded-xl border border-white/10 bg-slate/30 p-5 text-xs leading-relaxed text-ink-tertiary">
            <p className="mb-2 font-semibold text-ink-secondary">Utilisation (doc rapide)</p>
            <pre className="overflow-x-auto rounded bg-black/40 p-3 font-mono text-[11px] text-ink-secondary">{`# Activer un appareil (scope « Activer »)
curl -X POST https://app.7themotion.com/api/v1/activate \\
  -H "Authorization: Bearer 7mk_..." \\
  -H "Content-Type: application/json" \\
  -d '{"mac":"MK:1A:2B:3C:4D:5E","plan":"yearly"}'

# Pousser une source (scope « Sources »)
curl -X PUT https://app.7themotion.com/api/v1/sources/MK%3A1A%3A2B%3A3C%3A4D%3A5E \\
  -H "Authorization: Bearer 7mk_..." \\
  -H "Content-Type: application/json" \\
  -d '{"sources":[{"type":"m3u","m3u_url":"http://..."}]}'`}</pre>
            <p className="mt-2">
              Chaque clé est limitée à ses scopes — tout le reste répond 403.
              Les appels sont journalisés dans l'historique.
            </p>
          </div>
        </section>

        {/* ================= WEBHOOKS ================= */}
        <section className="space-y-4">
          <form onSubmit={createWebhook} className="space-y-3 rounded-xl border border-white/5 bg-midnight p-6">
            <h2 className="text-sm font-semibold">Ajouter un webhook</h2>
            <input value={whUrl} required
              onChange={(e) => setWhUrl(e.target.value)}
              placeholder="https://ton-systeme.com/webhook (https obligatoire)"
              className={inputCls + ' font-mono'} />
            <div>
              <p className="mb-1.5 text-[10px] uppercase tracking-widest text-ink-tertiary">
                Événements à recevoir
              </p>
              <div className="flex flex-wrap gap-2">
                {WEBHOOK_EVENTS.map((ev) => (
                  <button type="button" key={ev.key}
                    onClick={() => setWhEvents((prev) => toggle(prev, ev.key))}
                    className={chipCls(whEvents.includes(ev.key))}>
                    {ev.label}
                  </button>
                ))}
              </div>
            </div>
            <button type="submit" disabled={busyWh || !whUrl.trim() || whEvents.length === 0}
              className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
              {busyWh ? 'Ajout…' : 'Ajouter le webhook'}
            </button>
            {newSecret && (
              <div className="rounded-md border border-success/30 bg-success/10 p-3">
                <p className="mb-1 text-xs font-semibold text-success">
                  Webhook créé — voici son SECRET de signature (affiché une seule fois) :
                </p>
                <div className="flex items-center gap-2">
                  <code className="min-w-0 flex-1 truncate rounded bg-black/40 px-2 py-1.5 font-mono text-xs text-ink-primary">
                    {newSecret}
                  </code>
                  <button type="button"
                    onClick={() => navigator.clipboard?.writeText(newSecret)}
                    className="rounded-md border border-white/10 px-2.5 py-1.5 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                    Copier
                  </button>
                </div>
                <p className="mt-1 text-[11px] text-ink-tertiary">
                  Chaque livraison porte l'en-tête <span className="font-mono">X-Signature-256: sha256=HMAC(body, secret)</span> —
                  vérifie-la pour authentifier l'émetteur.
                </p>
              </div>
            )}
          </form>

          <div className="rounded-xl border border-white/5 bg-obsidian p-6">
            <h3 className="mb-3 text-sm font-semibold">Webhooks actifs</h3>
            {hooks.length === 0 && <p className="text-sm text-ink-tertiary">Aucun webhook.</p>}
            <ul className="space-y-2">
              {hooks.map((h) => (
                <li key={h.id} className="rounded-lg border border-white/10 bg-slate/30 p-3 text-sm">
                  <div className="flex items-center justify-between gap-2">
                    <span className="min-w-0 truncate font-mono text-xs">{h.url}</span>
                    <span className={
                      'shrink-0 rounded-full px-2 py-0.5 text-[10px] uppercase tracking-widest ' +
                      (h.active ? 'bg-success/15 text-success' : 'bg-white/5 text-ink-tertiary')
                    }>
                      {h.active ? 'actif' : 'en pause'}
                    </span>
                  </div>
                  <div className="mt-1 flex flex-wrap gap-2 text-[11px] text-ink-tertiary">
                    <span>{h.events.map((e) => WEBHOOK_EVENTS.find((x) => x.key === e)?.label || e).join(', ')}</span>
                    {h.last_fired_at && (
                      <span>· dernier envoi {formatDateTime(h.last_fired_at)} (statut {h.last_status})</span>
                    )}
                  </div>
                  <div className="mt-2 flex gap-2">
                    <button
                      onClick={() => integrationsApi.testWebhook(h.id).then(reload).catch(() => {})}
                      className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                      Envoyer un test
                    </button>
                    <button
                      onClick={() => integrationsApi.updateWebhook(h.id, { active: !h.active }).then(reload).catch(() => {})}
                      className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                      {h.active ? 'Mettre en pause' : 'Réactiver'}
                    </button>
                    <button
                      onClick={() => {
                        if (window.confirm('Supprimer ce webhook ?')) {
                          integrationsApi.deleteWebhook(h.id).then(reload).catch(() => {});
                        }
                      }}
                      className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                      Supprimer
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </div>

          {err && (
            <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
          )}
        </section>
      </div>
    </AppLayout>
  );
}
