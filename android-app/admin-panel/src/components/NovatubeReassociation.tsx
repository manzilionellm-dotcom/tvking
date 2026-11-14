import { type FormEvent, useEffect, useId, useRef, useState } from 'react';
import {
  ApiError, getCurrentUser, isAbortError, novatubeReassociationApi,
  type NovatubeReassociationPreview,
} from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

const APP_ID = 'app_novatube4k';
const REQUEST_ID = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const MAX_LIFETIME = 600_000;
const EXPIRED = 'Ce code a expiré. Demande au client un nouveau code d’assistance.';
const BUTTON = 'rounded-md border border-white/10 px-3 py-2 text-xs text-ink-secondary hover:border-accent/50 hover:text-ink-primary disabled:cursor-not-allowed disabled:opacity-50';
type Pending = 'preview' | 'approve' | null;
type Preview = NovatubeReassociationPreview & { code: string; deadline: number };

function validMetadata(value: unknown, maximum: number): boolean {
  return value === null || (typeof value === 'string' && value.length <= maximum);
}

// Même alphabet que le serveur : pas de conversion ambiguë O → 0 ou I → 1.
// La saisie peut venir d'un code dicté, collé avec espaces, ou déjà regroupé.
export function normalizeAssistanceCode(value: string): string | null {
  if (value.length > 64) return null;
  const plain = value.toUpperCase().replace(/[\s-]/g, '');
  if (!/^[0-9A-HJKMNP-TV-Z]{12}$/.test(plain)) return null;
  return `${plain.slice(0, 4)}-${plain.slice(4, 8)}-${plain.slice(8)}`;
}

/** Ce garde est volontairement plus strict que isOwnerRole (qui inclut support).
 * Le serveur vérifie à nouveau la session et le rôle pour chacune des étapes.
 */
export function NovatubeReassociation({ mac, disabled = false }: { mac: string; disabled?: boolean }) {
  if (getCurrentUser()?.role !== 'super_admin') return null;
  return <ReassociationFlow key={mac} mac={mac} disabled={disabled} />;
}

function ReassociationFlow({ mac, disabled }: { mac: string; disabled: boolean }) {
  const [supported, setSupported] = useState(false);
  const [capabilityError, setCapabilityError] = useState(false);
  const [capabilityAttempt, setCapabilityAttempt] = useState(0);
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState('');
  const [preview, setPreview] = useState<Preview | null>(null);
  const [expired, setExpired] = useState(false);
  const [pending, setPending] = useState<Pending>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [verificationDeadline, setVerificationDeadline] = useState<number | null>(null);
  const revision = useRef(0);
  const alive = useRef(true);
  const inFlight = useRef<Pending>(null);
  const controller = useRef<AbortController | null>(null);
  const input = useRef<HTMLInputElement>(null);
  const inputId = useId();
  const helpId = useId();
  const canonicalCode = normalizeAssistanceCode(code);

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      revision.current++;
      controller.current?.abort();
    };
  }, []);

  useEffect(() => {
    let current = true;
    const abort = new AbortController();
    const startedAt = performance.now();
    setCapabilityError(false);
    setVerificationDeadline(null);
    novatubeReassociationApi.capability(mac, abort.signal).then((result) => {
      if (!current || getCurrentUser()?.role !== 'super_admin') return;
      if (result?.ok !== true || result.supported !== true || result.app_id !== APP_ID || result.mac !== mac) {
        setCapabilityError(true);
        return;
      }
      setSupported(true);
      // Une licence active ne prouve pas que la clé de cette installation
      // est reconnue. Ce diagnostic ne vaut que pour une demande actuelle
      // vérifiée par le serveur ; il n'autorise aucune réassociation.
      if (result.installation_status === 'verification_required' && result.recovery_pending === true
          && Number.isSafeInteger(result.server_now) && (result.server_now ?? 0) > 0
          && Number.isSafeInteger(result.recovery_expires_at)
          && (result.recovery_expires_at ?? 0) > result.server_now!
          && result.recovery_expires_at! - result.server_now! <= MAX_LIFETIME) {
        const deadline = startedAt + result.recovery_expires_at! - result.server_now!;
        if (deadline > performance.now()) setVerificationDeadline(deadline);
      }
    }).catch((failure: unknown) => {
      if (!current || isAbortError(failure)) return;
      // Les autres applications, et les rôles non autorisés, n'ont pas d'action.
      if (failure instanceof ApiError && [401, 403, 404].includes(failure.status)) return;
      setCapabilityError(true);
    });
    return () => { current = false; abort.abort(); };
  }, [mac, capabilityAttempt]);

  useEffect(() => {
    if (verificationDeadline === null) return;
    const timer = window.setTimeout(() => setVerificationDeadline(null), Math.max(0, verificationDeadline - performance.now()));
    return () => window.clearTimeout(timer);
  }, [verificationDeadline]);

  useEffect(() => { if (open) input.current?.focus(); }, [open]);

  useEffect(() => {
    if (!preview) return;
    const timer = window.setTimeout(() => setExpired(true), Math.max(0, preview.deadline - performance.now()));
    return () => window.clearTimeout(timer);
  }, [preview]);

  function isCurrent(token: number): boolean {
    return alive.current && revision.current === token && getCurrentUser()?.role === 'super_admin';
  }

  // L'invalidation est synchrone : une réponse qui arrive avant le prochain
  // rendu React ne peut pas remettre l'aperçu du code ou de la fiche précédents.
  function invalidate() {
    revision.current++;
    controller.current?.abort();
    controller.current = null;
    inFlight.current = null;
    setPending(null);
    setPreview(null);
    setExpired(false);
    setError(null);
  }

  function changeCode(value: string) {
    if (inFlight.current === 'approve') return;
    invalidate();
    setCode(value);
    setSuccess(false);
  }

  function close() {
    if (inFlight.current === 'approve') return;
    invalidate();
    setCode('');
    setOpen(false);
  }

  async function checkCode(event: FormEvent) {
    event.preventDefault();
    if (disabled || inFlight.current || !supported || !canonicalCode || getCurrentUser()?.role !== 'super_admin') return;
    invalidate();
    const token = revision.current;
    const abort = new AbortController();
    controller.current = abort;
    inFlight.current = 'preview';
    setPending('preview');
    const startedAt = performance.now();
    try {
      const result = await novatubeReassociationApi.preview(mac, canonicalCode, abort.signal);
      if (!isCurrent(token)) return;
      const candidate = result?.candidate;
      if (result?.ok !== true || result.app_id !== APP_ID || result.mac !== mac || !candidate
          || typeof candidate.request_id !== 'string' || !REQUEST_ID.test(candidate.request_id)
          || ![result.server_now, candidate.created_at, candidate.expires_at]
            .every((value) => Number.isSafeInteger(value) && value > 0)
          || candidate.created_at > result.server_now || candidate.expires_at <= candidate.created_at
          || candidate.expires_at - result.server_now > MAX_LIFETIME
          || candidate.expires_at - candidate.created_at > MAX_LIFETIME
          || !validMetadata(candidate.model, 96) || !validMetadata(candidate.app_version, 40)
          || !validMetadata(candidate.platform, 24)) {
        setError('L’aperçu n’a pas pu être vérifié. Réessaie.');
        return;
      }
      // On utilise la durée du serveur, pas l'heure éventuellement fausse du
      // navigateur. Décompter depuis l'envoi est volontairement prudent.
      const deadline = startedAt + candidate.expires_at - result.server_now;
      if (deadline <= performance.now()) { setError(EXPIRED); return; }
      setPreview({ ...result, code: canonicalCode, deadline });
    } catch (failure) {
      if (isCurrent(token) && !isAbortError(failure)) {
        setError(failure instanceof ApiError ? failure.message : 'Le code n’a pas pu être vérifié. Réessaie.');
      }
    } finally {
      if (isCurrent(token)) { inFlight.current = null; setPending(null); }
    }
  }

  async function approve() {
    if (disabled || inFlight.current || !preview || preview.code !== canonicalCode
        || getCurrentUser()?.role !== 'super_admin') return;
    if (expired || preview.deadline <= performance.now()) { setExpired(true); return; }
    const token = ++revision.current;
    const abort = new AbortController();
    controller.current = abort;
    inFlight.current = 'approve';
    setPending('approve');
    setError(null);
    try {
      const result = await novatubeReassociationApi.approve(mac, preview.code, preview.candidate.request_id, abort.signal);
      if (!isCurrent(token)) return;
      if (result?.ok !== true || result.app_id !== APP_ID || result.mac !== mac || result.result !== 'device_reassociated') {
        setError('Le résultat n’a pas pu être confirmé. Vérifie l’état de l’application du client.');
        setPreview(null);
        return;
      }
      setSuccess(true);
      setVerificationDeadline(null);
      setPreview(null);
      setCode('');
      setOpen(false);
    } catch (failure) {
      if (isCurrent(token) && !isAbortError(failure)) {
        setError(failure instanceof ApiError && failure.status !== 0
          ? failure.message
          : 'Le résultat n’a pas pu être confirmé. Vérifie l’état de l’application du client avant de recommencer.');
        // Un aperçu validé avant un conflit ou une panne ne permet pas une
        // nouvelle approbation automatique : il faut revérifier le code.
        setPreview(null);
      }
    } finally {
      if (isCurrent(token)) { inFlight.current = null; setPending(null); }
    }
  }

  if (!supported) {
    return capabilityError ? (
      <p className="mt-3 text-xs text-ink-tertiary" role="status">
        Vérification NovaTube indisponible.{' '}
        <button type="button" className="underline" disabled={disabled} onClick={() => setCapabilityAttempt((value) => value + 1)}>Réessayer</button>
      </p>
    ) : null;
  }

  return (
    <section className="mt-4 border-t border-white/5 pt-4" aria-label="Réassociation NovaTube">
      {verificationDeadline !== null && <div className="mb-3 rounded-lg border border-accent/30 bg-accent/5 p-3" role="status">
        <p className="text-sm font-semibold text-ink-primary">Installation NovaTube à vérifier</p>
        <p className="mt-1 text-xs leading-relaxed text-ink-secondary">Une installation attend sa réassociation. La licence existante est conservée : une nouvelle activation ou un nouvel achat ne résout pas cette liaison.</p>
        <p className="mt-2 text-xs leading-relaxed text-ink-secondary">Laisse NovaTube ouverte, relève son code d’assistance, puis utilise « Réassocier NovaTube » ci-dessous. Vérifie l’aperçu avant de confirmer.</p>
      </div>}
      {!open && <button type="button" className={BUTTON} disabled={disabled} onClick={() => { invalidate(); setSuccess(false); setOpen(true); }}>Réassocier NovaTube</button>}
      {success && <p className="mt-2 text-sm text-success" role="status">Liaison remplacée. Demande au client de laisser NovaTube ouverte pour terminer la connexion.</p>}
      {open && <>
        <h3 className="text-sm font-semibold text-ink-secondary">Réassocier NovaTube</h3>
        <form onSubmit={checkCode} className="mt-3 space-y-2">
          <label htmlFor={inputId} className="block text-xs text-ink-secondary">Code d’assistance transmis par le client</label>
          <p id={helpId} className="text-xs text-ink-tertiary">Le code affiché dans NovaTube est valable dix minutes.</p>
          <input
            ref={input} id={inputId} aria-describedby={helpId} value={code}
            onChange={(event) => changeCode(event.target.value)} maxLength={64}
            autoComplete="off" autoCapitalize="characters" spellCheck={false}
            placeholder="XXXX-XXXX-XXXX" disabled={disabled || pending === 'approve'}
            className="w-full rounded-md border border-white/10 bg-obsidian px-3 py-2 font-mono text-sm uppercase tracking-wider text-ink-primary outline-none focus:border-accent"
          />
          <div className="flex flex-wrap gap-2">
            <button type="submit" className={BUTTON} disabled={disabled || !!pending || !canonicalCode}>{pending === 'preview' ? 'Vérification…' : 'Vérifier le code'}</button>
            <button type="button" className={BUTTON} disabled={pending === 'approve'} onClick={close}>Annuler</button>
          </div>
        </form>
        {preview && <div className="mt-4 rounded-lg border border-accent/30 bg-accent/5 p-3">
          <p className="text-sm text-ink-primary">La liaison de cet appareil sera remplacée par l’installation ci-dessous.</p>
          <p className="mt-1 text-xs text-ink-tertiary">Informations déclarées par l’installation du client :</p>
          <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-2 break-words text-xs">
            <dt className="text-ink-tertiary">Code de l’appareil</dt><dd className="font-mono text-ink-primary">{mac}</dd>
            <dt className="text-ink-tertiary">Modèle</dt><dd>{preview.candidate.model || 'Non renseigné'}</dd>
            <dt className="text-ink-tertiary">Version NovaTube</dt><dd>{preview.candidate.app_version || 'Non renseignée'}</dd>
            <dt className="text-ink-tertiary">Plateforme</dt><dd>{preview.candidate.platform || 'Non renseignée'}</dd>
            <dt className="text-ink-tertiary">Demande reçue</dt><dd>{formatDateTime(preview.candidate.created_at)}</dd>
            <dt className="text-ink-tertiary">Expiration</dt><dd>{formatDateTime(preview.candidate.expires_at)}</dd>
          </dl>
          {expired && <p className="mt-3 text-xs text-accent-bright" role="alert">{EXPIRED}</p>}
          <button type="button" onClick={approve} disabled={disabled || !!pending || expired}
            className="mt-4 rounded-md bg-accent px-3 py-2 text-xs font-semibold text-black hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50">
            {pending === 'approve' ? 'Réassociation…' : 'Confirmer la réassociation'}
          </button>
        </div>}
        {error && <p className="mt-3 text-xs text-accent-bright" role="alert">{error}</p>}
      </>}
    </section>
  );
}
