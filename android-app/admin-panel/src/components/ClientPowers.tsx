import { ReactNode, useCallback, useEffect, useState } from 'react';
import { confirmAction } from '@/components/confirm';
import {
  ApiError, powersApi,
  type ClientAction, type ClientNote, type DevicePowers,
} from '@/lib/api';
import {
  DEFAULT_PAYMENT_MESSAGE, buildPaymentPayload, describeAction,
  parseDays, parseHours,
} from '@/lib/powers';
import { formatDateTime } from '@/lib/utils';

/// Bloc « Pouvoirs client » de la fiche appareil : bloquer, demande de
/// paiement, message, prolonger / suspendre, relecture forcée, notes et
/// journal. Réservé à l'admin (le Worker refuse les revendeurs) ; masqué
/// tant que l'interrupteur CLIENT_POWERS du Worker est coupé.
export function ClientPowers({ deviceId, mac }: { deviceId: string; mac: string }) {
  const [powers, setPowers] = useState<DevicePowers | null>(null);
  const [notes, setNotes] = useState<ClientNote[]>([]);
  const [actions, setActions] = useState<ClientAction[]>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  // Formulaires.
  const [payMsg, setPayMsg] = useState(DEFAULT_PAYMENT_MESSAGE);
  const [payAmount, setPayAmount] = useState('');
  const [payCur, setPayCur] = useState('EUR');
  const [payLink, setPayLink] = useState('');
  const [msgTitle, setMsgTitle] = useState('');
  const [msgBody, setMsgBody] = useState('');
  const [msgHours, setMsgHours] = useState('');
  const [days, setDays] = useState('30');
  const [reason, setReason] = useState('');
  const [noteText, setNoteText] = useState('');

  const reload = useCallback(async () => {
    try {
      const p = await powersApi.get(deviceId);
      setPowers(p);
      if (!p.enabled) return;
      const [n, a] = await Promise.all([powersApi.notes(deviceId), powersApi.actions(deviceId)]);
      setNotes(n.items);
      setActions(a.items);
    } catch (e) {
      // Un revendeur (403) ou un ancien Worker (404) : on masque sans bruit.
      if (e instanceof ApiError && (e.status === 403 || e.status === 404)) {
        setPowers({ enabled: false });
      } else {
        setErr(e instanceof ApiError ? e.message : 'Échec.');
      }
    }
  }, [deviceId]);

  useEffect(() => { setPowers(null); void reload(); }, [reload]);

  /// Exécute une action, puis recharge l'état et le journal.
  async function run(fn: () => Promise<unknown>, okMsg: string) {
    setBusy(true); setErr(null); setInfo(null);
    try {
      await fn();
      setInfo(okMsg);
      await reload();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally {
      setBusy(false);
    }
  }

  if (!powers || !powers.enabled) return null;

  const blocked = powers.block_status && powers.block_status !== 'active';

  async function block(status: 'active' | 'frozen' | 'banned') {
    if (status !== 'active') {
      const ok = await confirmAction({
        title: status === 'banned' ? 'Bannir ce client ?' : 'Geler ce client ?',
        message: `L'application de ${mac} sera bloquée à sa prochaine lecture du statut.`,
        confirmLabel: status === 'banned' ? 'Bannir' : 'Geler',
        danger: true,
      });
      if (!ok) return;
    }
    await run(() => powersApi.block(deviceId, status, reason),
      status === 'active' ? 'Client débloqué.' : 'Client bloqué.');
  }

  async function sendPayment() {
    const built = buildPaymentPayload({ message: payMsg, amount: payAmount, currency: payCur, link: payLink });
    if ('error' in built) { setErr(built.error); return; }
    await run(() => powersApi.setPayment(deviceId, built.payload), 'Demande de paiement envoyée.');
  }

  async function sendMessage() {
    const h = parseHours(msgHours);
    if ('error' in h) { setErr(h.error); return; }
    if (!msgBody.trim()) { setErr('Écris un message.'); return; }
    await run(() => powersApi.sendMessage(deviceId, {
      title: msgTitle.trim() || undefined,
      body: msgBody.trim(),
      expires_in_hours: h.hours ?? undefined,
    }), 'Message envoyé.');
    setMsgBody('');
  }

  async function extend() {
    const d = parseDays(days);
    if ('error' in d) { setErr(d.error); return; }
    await run(() => powersApi.extend(deviceId, d.days), `+${d.days} jour(s) ajouté(s).`);
  }

  async function toggleSuspend() {
    const next = !powers!.suspended;
    if (next) {
      const ok = await confirmAction({
        title: 'Suspendre l\'abonnement ?',
        message: 'La date de fin est conservée ; le client est bloqué jusqu\'à la reprise.',
        confirmLabel: 'Suspendre',
        danger: true,
      });
      if (!ok) return;
    }
    await run(() => powersApi.suspend(deviceId, next, reason), next ? 'Abonnement suspendu.' : 'Abonnement repris.');
  }

  async function addNote() {
    if (!noteText.trim()) return;
    await run(() => powersApi.addNote(deviceId, noteText.trim()), 'Note ajoutée.');
    setNoteText('');
  }

  const inputCls = 'w-full rounded-md border border-white/10 bg-obsidian px-2 py-1.5 text-xs';

  return (
    <div className="mt-5 border-t border-white/5 pt-4" data-testid="client-powers">
      <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">Pouvoirs client</div>

      {err && <div className="mb-2 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
      {info && <div className="mb-2 rounded-md border border-white/10 bg-white/5 px-3 py-2 text-xs">{info}</div>}

      <Section title="Accès">
        <input className={inputCls} placeholder="Motif (facultatif, gardé dans le journal)"
          value={reason} maxLength={200} onChange={(e) => setReason(e.target.value)} />
        <div className="mt-2 flex flex-wrap gap-1.5">
          {!blocked && <Btn busy={busy} onClick={() => block('frozen')}>Bloquer (geler)</Btn>}
          {powers.block_status !== 'banned' && <Btn busy={busy} onClick={() => block('banned')}>Bannir</Btn>}
          {blocked && <Btn busy={busy} primary onClick={() => block('active')}>Débloquer</Btn>}
          <Btn busy={busy} onClick={toggleSuspend}>{powers.suspended ? 'Reprendre l\'abonnement' : 'Suspendre l\'abonnement'}</Btn>
          <Btn busy={busy} onClick={() => run(() => powersApi.refresh(deviceId), 'Relecture demandée à la box.')}
            title="La box relit statut et listes à sa prochaine vérification">Forcer la relecture</Btn>
        </div>
      </Section>

      <Section title="Prolonger">
        <div className="flex items-center gap-2">
          <input className={inputCls + ' max-w-[90px]'} inputMode="numeric" value={days}
            onChange={(e) => setDays(e.target.value)} aria-label="Jours à ajouter" />
          <span className="text-xs text-ink-tertiary">jours</span>
          <Btn busy={busy} onClick={extend}>Ajouter</Btn>
        </div>
        {powers.lifetime && <p className="mt-1 text-[11px] text-ink-tertiary">Licence à vie : rien à prolonger.</p>}
      </Section>

      <Section title="Demande de paiement (« merci de payer »)">
        {powers.payment_request && (
          <p className="mb-2 text-[11px] text-accent-bright">
            Active depuis {formatDateTime(powers.payment_request.sent_at)} : « {powers.payment_request.message} »
          </p>
        )}
        <textarea className={inputCls} rows={2} maxLength={500} value={payMsg}
          onChange={(e) => setPayMsg(e.target.value)} aria-label="Message de paiement" />
        <div className="mt-2 grid grid-cols-3 gap-2">
          <input className={inputCls} placeholder="Montant" value={payAmount} maxLength={32}
            onChange={(e) => setPayAmount(e.target.value)} />
          <input className={inputCls} placeholder="Devise" value={payCur} maxLength={8}
            onChange={(e) => setPayCur(e.target.value)} />
          <input className={inputCls} placeholder="Lien https (option)" value={payLink}
            onChange={(e) => setPayLink(e.target.value)} />
        </div>
        <div className="mt-2 flex gap-1.5">
          <Btn busy={busy} primary onClick={sendPayment}>Envoyer la demande</Btn>
          {powers.payment_request && (
            <Btn busy={busy} onClick={() => run(() => powersApi.clearPayment(deviceId), 'Demande retirée.')}>Retirer</Btn>
          )}
        </div>
      </Section>

      <Section title="Message au client">
        {powers.message && (
          <p className="mb-2 text-[11px] text-accent-bright">
            Affiché : « {powers.message.body} »
          </p>
        )}
        <input className={inputCls} placeholder="Titre (option)" value={msgTitle} maxLength={80}
          onChange={(e) => setMsgTitle(e.target.value)} />
        <textarea className={inputCls + ' mt-2'} rows={2} placeholder="Message" maxLength={500}
          value={msgBody} onChange={(e) => setMsgBody(e.target.value)} />
        <div className="mt-2 flex items-center gap-2">
          <input className={inputCls + ' max-w-[110px]'} placeholder="Durée (h)" value={msgHours}
            onChange={(e) => setMsgHours(e.target.value)} />
          <Btn busy={busy} primary onClick={sendMessage}>Envoyer</Btn>
          {powers.message && (
            <Btn busy={busy} onClick={() => run(() => powersApi.clearMessage(deviceId), 'Message retiré.')}>Retirer</Btn>
          )}
        </div>
      </Section>

      <Section title="Notes internes (jamais vues du client)">
        {notes.map((n) => (
          <div key={n.id} className="mb-1 flex items-start justify-between gap-2 rounded-md bg-obsidian px-2 py-1.5 text-xs">
            <span>{n.body}<span className="ml-2 text-[10px] text-ink-tertiary">{formatDateTime(n.created_at)}</span></span>
            <button className="text-[11px] text-ink-tertiary hover:text-accent-bright"
              onClick={() => run(() => powersApi.deleteNote(deviceId, n.id), 'Note supprimée.')}>Supprimer</button>
          </div>
        ))}
        <div className="mt-1 flex gap-2">
          <input className={inputCls} placeholder="Ajouter une note" value={noteText} maxLength={1000}
            onChange={(e) => setNoteText(e.target.value)} />
          <Btn busy={busy} onClick={addNote}>Ajouter</Btn>
        </div>
      </Section>

      <Section title="Journal des actions">
        {actions.length === 0 && <p className="text-[11px] text-ink-tertiary">Aucune action enregistrée.</p>}
        {actions.slice(0, 20).map((a) => (
          <div key={a.id} className="flex justify-between gap-2 border-b border-white/5 py-1 text-[11px]">
            <span>{describeAction(a.action)}</span>
            <span className="text-ink-tertiary">{formatDateTime(a.created_at)}</span>
          </div>
        ))}
      </Section>
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="mb-4">
      <h4 className="mb-1.5 text-xs font-semibold text-ink-secondary">{title}</h4>
      {children}
    </div>
  );
}

function Btn({ children, onClick, busy, primary, title }: {
  children: ReactNode; onClick: () => void; busy?: boolean; primary?: boolean; title?: string;
}) {
  const cls = primary
    ? 'bg-accent text-black hover:bg-accent-bright border border-transparent'
    : 'border border-white/10 hover:border-white/30';
  return (
    <button onClick={onClick} disabled={busy} title={title}
      className={'rounded-md px-2.5 py-1 text-xs font-medium disabled:opacity-50 ' + cls}>
      {children}
    </button>
  );
}
