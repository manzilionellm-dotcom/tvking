import { FormEvent, ReactNode, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  resellersApi, creditsApi, type Reseller, ApiError, RESELLER_CAPS,
  RESELLER_DEFAULT_CAPS, getCurrentUser, isOwnerRole,
} from '@/lib/api';

/// Lien UNIQUE d'inscription revendeur (à partager). `?revendeur` force
/// l'écran de connexion en mode revendeur seul → le revendeur ne voit
/// JAMAIS la partie admin.
function resellerSignupLink(): string {
  return `${window.location.origin}/?revendeur`;
}

/// Page REVENDEURS (owner only). Creer des revendeurs, leur emettre
/// des credits (tokens), voir leur solde et leur volume de ventes.
export function ResellersPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<Reseller[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [creditFor, setCreditFor] = useState<Reseller | null>(null);
  const [pwdFor, setPwdFor] = useState<Reseller | null>(null);
  const [copied, setCopied] = useState(false);

  function copyLink() {
    const link = resellerSignupLink();
    navigator.clipboard?.writeText(link).then(
      () => { setCopied(true); setTimeout(() => setCopied(false), 2000); },
      () => setErr('Copie impossible — copie manuellement : ' + link),
    );
  }

  function reload() {
    setLoading(true);
    resellersApi.list()
      .then((r) => { setItems(r.items); setErr(null); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e.message);
      })
      .finally(() => setLoading(false));
  }

  useEffect(reload, [onLogout]);

  return (
    <AppLayout
      title="Revendeurs"
      subtitle={`${items.length} revendeur(s)`}
      onLogout={onLogout}
      actions={
        <div className="flex items-center gap-2">
          <button
            onClick={copyLink}
            title={resellerSignupLink()}
            className="rounded-md border border-accent/40 bg-accent/10 px-3 py-2 text-sm font-semibold text-accent-bright hover:bg-accent/20"
          >
            {copied ? '✓ Lien copié' : '🔗 Copier le lien revendeur'}
          </button>
          <button
            onClick={() => setShowCreate(true)}
            className="rounded-md bg-accent px-3 py-2 text-sm font-semibold text-black hover:bg-accent-bright"
          >
            + Nouveau revendeur
          </button>
        </div>
      }
    >
      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      <div className="overflow-hidden rounded-xl border border-white/5">
        <table className="w-full text-sm">
          <thead className="bg-midnight">
            <tr className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
              <th className="px-4 py-3">Revendeur</th>
              <th className="px-4 py-3">Statut</th>
              <th className="px-4 py-3">Droits (coche)</th>
              <th className="px-4 py-3 text-right">Crédits</th>
              <th className="px-4 py-3 text-right">Appareils</th>
              <th className="px-4 py-3 text-right">Licences</th>
              <th className="px-4 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && Array.from({ length: 4 }).map((_, i) => (
              <tr key={i} className="bg-obsidian">
                <td className="px-4 py-3" colSpan={7}>
                  <div className="h-4 w-full animate-pulse rounded bg-white/5" />
                </td>
              </tr>
            ))}
            {!loading && items.length === 0 && (
              <tr><td colSpan={7} className="px-4 py-8 text-center text-sm text-ink-tertiary">
                Aucun revendeur. Crée le premier pour lui donner des crédits.
              </td></tr>
            )}
            {items.map((r) => (
              <tr key={r.id} className="bg-obsidian hover:bg-midnight">
                <td className="px-4 py-3">
                  <div className="font-medium">{r.name || r.email}</div>
                  <div className="text-[11px] text-ink-tertiary">{r.email}</div>
                </td>
                <td className="px-4 py-3">
                  <StatusBadge status={r.status} />
                </td>
                <td className="px-4 py-3">
                  <PermsCell r={r} onChanged={reload} onErr={setErr} />
                </td>
                <td className="px-4 py-3 text-right font-semibold text-accent-bright">{r.credit_balance}</td>
                <td className="px-4 py-3 text-right text-ink-secondary">{r.devices ?? 0}</td>
                <td className="px-4 py-3 text-right text-ink-secondary">{r.licenses ?? 0}</td>
                <td className="px-4 py-3 text-right">
                  <div className="flex justify-end gap-2">
                    <button
                      onClick={() => setCreditFor(r)}
                      className="rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-accent hover:text-accent-bright"
                    >
                      + Crédits
                    </button>
                    <button
                      onClick={() =>
                        resellersApi
                          .update(r.id, { status: r.status === 'active' ? 'suspended' : 'active' })
                          .then(reload)
                          .catch((e) => setErr(e.message))
                      }
                      className="rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-white/30"
                    >
                      {r.status === 'active'
                        ? 'Suspendre'
                        : r.status === 'pending'
                          ? 'Activer'
                          : 'Réactiver'}
                    </button>
                    <button
                      onClick={() => setPwdFor(r)}
                      className="rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-white/30"
                    >
                      Mot de passe
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {showCreate && (
        <CreateResellerModal
          onClose={() => setShowCreate(false)}
          onCreated={() => { setShowCreate(false); reload(); }}
        />
      )}
      {creditFor && (
        <CreditsModal
          reseller={creditFor}
          onClose={() => setCreditFor(null)}
          onDone={() => { setCreditFor(null); reload(); }}
        />
      )}
      {pwdFor && (
        <PasswordModal
          reseller={pwdFor}
          onClose={() => setPwdFor(null)}
          onDone={() => setPwdFor(null)}
        />
      )}
    </AppLayout>
  );
}

/// Cellule DROITS : une puce cliquable par capacité. L'admin coche
/// EXACTEMENT ce qu'il accorde — chaque clic enregistre tout de suite.
function PermsCell({
  r, onChanged, onErr,
}: { r: Reseller; onChanged: () => void; onErr: (m: string) => void }) {
  const perms = r.permissions || [];
  const [busy, setBusy] = useState(false);
  function toggle(cap: string) {
    const next = perms.includes(cap)
      ? perms.filter((p) => p !== cap)
      : [...perms, cap];
    setBusy(true);
    resellersApi.update(r.id, { permissions: next })
      .then(onChanged)
      .catch((e) => onErr(e.message))
      .finally(() => setBusy(false));
  }
  const owner = isOwnerRole(getCurrentUser()?.role);
  return (
    <div className={'flex flex-wrap gap-1 ' + (busy ? 'pointer-events-none opacity-50' : '')}>
      {RESELLER_CAPS.filter((c) => owner || !c.ownerOnly).map((c) => {
        const on = perms.includes(c.key);
        return (
          <button
            key={c.key}
            type="button"
            onClick={() => toggle(c.key)}
            className={
              'rounded-full border px-2 py-0.5 text-[10px] font-medium transition ' +
              (on
                ? 'border-accent bg-accent/20 text-accent-bright'
                : 'border-white/10 bg-slate text-ink-tertiary hover:border-white/30')
            }
          >
            {on ? '✓ ' : ''}{c.label}
          </button>
        );
      })}
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const map: Record<string, { cls: string; label: string }> = {
    active: { cls: 'bg-success/15 text-success', label: 'Actif' },
    pending: { cls: 'bg-accent/15 text-accent-bright', label: 'En attente' },
    suspended: { cls: 'bg-warning/15 text-warning', label: 'Suspendu' },
  };
  const s = map[status] || map.suspended;
  return (
    <span className={'rounded-full px-2 py-0.5 text-[11px] font-medium ' + s.cls}>
      {s.label}
    </span>
  );
}

function CreateResellerModal({
  onClose, onCreated,
}: { onClose: () => void; onCreated: () => void }) {
  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [password, setPassword] = useState('');
  const [credits, setCredits] = useState('0');
  const [caps, setCaps] = useState<string[]>(RESELLER_DEFAULT_CAPS);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const owner = isOwnerRole(getCurrentUser()?.role);

  function toggleCap(key: string) {
    setCaps((prev) => (prev.includes(key) ? prev.filter((c) => c !== key) : [...prev, key]));
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null);
    try {
      await resellersApi.create({
        email: email.trim().toLowerCase(),
        password,
        name: name.trim() || undefined,
        credit_balance: owner ? (parseInt(credits, 10) || 0) : 0,
        permissions: caps,
      });
      onCreated();
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Création impossible.');
    } finally { setBusy(false); }
  }

  return (
    <Modal title="Nouveau revendeur" onClose={onClose}>
      <form onSubmit={submit} className="space-y-3">
        <Field label="Email"><input value={email} onChange={(e) => setEmail(e.target.value)} className={inputCls} placeholder="revendeur@exemple.com" autoFocus /></Field>
        <Field label="Nom (optionnel)"><input value={name} onChange={(e) => setName(e.target.value)} className={inputCls} placeholder="Karim Reseller" /></Field>
        <Field label="Mot de passe"><input type="password" value={password} onChange={(e) => setPassword(e.target.value)} className={inputCls} placeholder="••••••••" /></Field>
        {owner && <Field label="Crédits initiaux (toi seul en donnes)"><input type="number" min={0} value={credits} onChange={(e) => setCredits(e.target.value)} className={inputCls} /></Field>}

        {/* OPTIONS / DROITS — cochés par défaut : activer, bloquer,
            transférer, achat de crédit. « Créer des sous-revendeurs » n'est
            proposé qu'à l'owner (droit sensible). */}
        <div>
          <div className="mb-1.5 text-[10px] uppercase tracking-widest text-ink-tertiary">
            Options du revendeur
          </div>
          <div className="grid grid-cols-2 gap-1.5">
            {RESELLER_CAPS.filter((c) => owner || !c.ownerOnly).map((c) => {
              const on = caps.includes(c.key);
              return (
                <button
                  key={c.key}
                  type="button"
                  onClick={() => toggleCap(c.key)}
                  className={
                    'flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-left text-xs transition ' +
                    (on
                      ? 'border-accent bg-accent/15 text-ink-primary'
                      : 'border-white/10 bg-slate text-ink-tertiary hover:border-white/30')
                  }
                >
                  <span className={'grid h-3.5 w-3.5 place-items-center rounded-sm border ' + (on ? 'border-accent bg-accent text-black' : 'border-white/30')}>
                    {on ? '✓' : ''}
                  </span>
                  {c.label}
                  {c.ownerOnly && <span className="ml-auto text-[9px] text-warning">clé</span>}
                </button>
              );
            })}
          </div>
        </div>
        {err && <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
        <div className="flex justify-end gap-2 pt-2">
          <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">Annuler</button>
          <button type="submit" disabled={busy || !email || !password} className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50">
            {busy ? 'Création…' : 'Créer'}
          </button>
        </div>
      </form>
    </Modal>
  );
}

function CreditsModal({
  reseller, onClose, onDone,
}: { reseller: Reseller; onClose: () => void; onDone: () => void }) {
  const [amount, setAmount] = useState('10');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function apply(sign: 1 | -1) {
    const n = (parseInt(amount, 10) || 0) * sign;
    if (!n) return;
    setBusy(true); setErr(null);
    try {
      await creditsApi.issue(reseller.id, n, note.trim() || undefined);
      onDone();
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Opération impossible.');
    } finally { setBusy(false); }
  }

  return (
    <Modal title={`Crédits — ${reseller.name || reseller.email}`} onClose={onClose}>
      <p className="mb-3 text-sm text-ink-tertiary">
        Solde actuel&nbsp;: <span className="font-semibold text-accent-bright">{reseller.credit_balance}</span> crédits
      </p>
      <Field label="Montant"><input type="number" min={1} value={amount} onChange={(e) => setAmount(e.target.value)} className={inputCls} autoFocus /></Field>
      <Field label="Note (optionnel)"><input value={note} onChange={(e) => setNote(e.target.value)} className={inputCls} placeholder="Paiement reçu, pack 100…" /></Field>
      {err && <div className="mt-2 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
      <div className="flex justify-end gap-2 pt-4">
        <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">Fermer</button>
        <button disabled={busy} onClick={() => apply(-1)} className="rounded-md border border-white/10 px-4 py-2 text-sm hover:border-warning hover:text-warning disabled:opacity-50">Retirer</button>
        <button disabled={busy} onClick={() => apply(1)} className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50">
          {busy ? '…' : 'Ajouter'}
        </button>
      </div>
    </Modal>
  );
}

function PasswordModal({
  reseller, onClose, onDone,
}: { reseller: Reseller; onClose: () => void; onDone: () => void }) {
  const [pwd, setPwd] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function save() {
    if (pwd.length < 4) { setErr('Au moins 4 caractères.'); return; }
    setBusy(true); setErr(null);
    try {
      await resellersApi.update(reseller.id, { password: pwd });
      setDone(true);
      setTimeout(onDone, 900);
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally { setBusy(false); }
  }

  return (
    <Modal title={`Mot de passe — ${reseller.name || reseller.email}`} onClose={onClose}>
      <p className="mb-3 text-sm text-ink-tertiary">
        Définis un nouveau mot de passe pour ce revendeur. Communique-le-lui ;
        il pourra le changer lui-même ensuite dans « Mon compte ».
      </p>
      <Field label="Nouveau mot de passe">
        <input type="text" value={pwd} onChange={(e) => setPwd(e.target.value)} className={inputCls} autoFocus placeholder="••••••••" />
      </Field>
      {err && <div className="mt-2 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
      {done && <div className="mt-2 rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">Mot de passe mis à jour ✔</div>}
      <div className="flex justify-end gap-2 pt-4">
        <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">Fermer</button>
        <button disabled={busy || done} onClick={save} className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50">
          {busy ? '…' : 'Enregistrer'}
        </button>
      </div>
    </Modal>
  );
}

const inputCls =
  'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</label>
      {children}
    </div>
  );
}

function Modal({
  title, onClose, children,
}: { title: string; onClose: () => void; children: ReactNode }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div
        className="w-full max-w-md rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="mb-4 text-lg font-semibold tracking-tight">{title}</h2>
        {children}
      </div>
    </div>
  );
}
