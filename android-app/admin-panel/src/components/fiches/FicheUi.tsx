// Présentation des fiches (appareil, client, liste).
// Aucun appel réseau ici : l'hôte et l'aperçu fournissent les données.
import { useEffect, type ReactNode } from 'react';
import { StatusBadge } from '@/components/ui';
import {
  actionsPour,
  etatAction,
  type ActionEtat,
  type FicheAction,
  type FicheKind,
  type ListeApercu,
  type ListOrigin,
} from '@/lib/fiches';

export interface AppareilVue {
  mac: string;
  client: string;
  customerId: string | null;
  plateforme: string;
  modele: string;
  android: string;
  version: string;
  etiquette: string;
  derniereVue: string;
  premiereVue: string;
  acces: string;
  blockStatus: string;
  abonnement: string;
  abonnementOk: boolean;
  presence: string;
  enLigne: boolean;
  listes: ListeApercu[];
  locales: ListeApercu[];
}

export interface ClientVue {
  id: string;
  nom: string;
  email: string;
  telephone: string;
  notes: string;
  appareils: { id: string; mac: string; label: string }[];
}

export function FichePanneau({
  testId,
  kind,
  origin,
  titre,
  sousTitre,
  badge,
  message,
  erreur,
  listeMasquee,
  onToggleMasquee,
  inertes,
  titreInerte,
  busy,
  onAction,
  onClose,
  onBack,
  children,
}: {
  testId: string;
  kind: FicheKind;
  origin?: ListOrigin;
  titre: string;
  sousTitre: string;
  badge?: string;
  message?: string | null;
  erreur?: string | null;
  listeMasquee: boolean;
  onToggleMasquee?: (on: boolean) => void;
  inertes: string[];
  titreInerte?: (id: string) => string | undefined;
  busy?: boolean;
  onAction: (id: string) => void;
  onClose: () => void;
  onBack?: () => void;
  children: ReactNode;
}) {
  const actions = actionsPour(kind, origin);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="fiche-titre"
        data-testid={testId}
        className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <h2 id="fiche-titre" className="text-lg font-semibold tracking-tight">{titre}</h2>
            <p className="mt-0.5 truncate font-mono text-xs text-accent">{sousTitre}</p>
          </div>
          {badge && <StatusBadge status={badge} />}
        </div>

        {onBack && (
          <button type="button" onClick={onBack} className="mb-3 text-xs text-ink-secondary hover:text-ink-primary">
            ← Retour
          </button>
        )}

        {erreur && (
          <div role="alert" className="mb-3 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
            {erreur}
          </div>
        )}
        {message && (
          <div role="status" className="mb-3 rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
            {message}
          </div>
        )}

        {children}

        <div className="mt-5 border-t border-white/5 pt-4">
          <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">Actions</div>
          <div className="flex flex-wrap gap-1.5">
            {actions.filter((a) => a.id !== 'masquer-liste').map((action) => (
              <BoutonAction
                key={action.id}
                action={action}
                etat={etatAction(action, { listeMasquee })}
                inerte={inertes.includes(action.id)}
                titreInerte={titreInerte?.(action.id)}
                busy={busy}
                onAction={onAction}
              />
            ))}
          </div>

          {kind === 'liste' && (
            <MasquerListe
              listeMasquee={listeMasquee}
              onToggle={onToggleMasquee}
              action={actions.find((a) => a.id === 'masquer-liste')}
              busy={busy}
              onAction={onAction}
            />
          )}
        </div>

        <div className="flex justify-end pt-5">
          <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">
            Fermer
          </button>
        </div>
      </div>
    </div>
  );
}

function MasquerListe({
  listeMasquee,
  onToggle,
  action,
  busy,
  onAction,
}: {
  listeMasquee: boolean;
  onToggle?: (on: boolean) => void;
  action?: FicheAction;
  busy?: boolean;
  onAction: (id: string) => void;
}) {
  if (!action) return null;
  const etat = etatAction(action, { listeMasquee });
  return (
    <div className="mt-4 rounded-lg border border-white/10 bg-obsidian px-3 py-3">
      <label className="flex items-start gap-2 text-sm text-ink-secondary">
        <input
          type="checkbox"
          className="mt-1"
          checked={listeMasquee}
          data-testid="interrupteur-liste-masquee"
          onChange={(e) => onToggle?.(e.target.checked)}
        />
        <span>
          Interrupteur de repli « masquer la liste sur la box ».
          {' '}
          {listeMasquee ? 'Allumé.' : 'Coupé (défaut).'}
          {' '}
          Le serveur ne conserve pas encore le drapeau hidden : aucun envoi ne l’ajoute.
        </span>
      </label>
      <div className="mt-2">
        <BoutonAction
          action={action}
          etat={etat}
          inerte={false}
          busy={busy}
          onAction={onAction}
        />
      </div>
    </div>
  );
}

function BoutonAction({
  action,
  etat,
  inerte,
  titreInerte,
  busy,
  onAction,
}: {
  action: FicheAction;
  etat: ActionEtat;
  inerte: boolean;
  titreInerte?: string;
  busy?: boolean;
  onAction: (id: string) => void;
}) {
  const bloque = etat !== 'prete' || inerte;
  const suffix = etat === 'prete' ? '' : ' · bientôt';
  const title = etat === 'bientot'
    ? 'Bientôt — le serveur n’a pas encore cette route.'
    : etat === 'coupee'
      ? 'Bientôt — interrupteur coupé, et le serveur ne connaît pas ce drapeau.'
      : (inerte ? (titreInerte || 'Indisponible pour cet élément.') : (action.route || 'Action locale'));
  const danger = action.id === 'bannir' || action.id === 'supprimer' || action.id.startsWith('retirer');
  const primary = action.id === 'activer' || action.id === 'enregistrer-client';
  const cls = primary
    ? 'bg-accent text-black hover:bg-accent-bright border border-transparent'
    : danger
      ? 'border border-white/10 text-ink-secondary hover:border-accent hover:text-accent-bright'
      : 'border border-white/10 text-ink-primary hover:border-white/30';
  return (
    <button
      type="button"
      data-testid={`action-${action.id}`}
      disabled={busy || bloque}
      title={title}
      onClick={() => { if (!bloque) onAction(action.id); }}
      className={'rounded-md px-2.5 py-1 text-xs font-medium disabled:cursor-not-allowed disabled:opacity-40 ' + cls}
    >
      {action.label}{suffix}
    </button>
  );
}

export function CorpsAppareil({
  vue,
  onClient,
  onListe,
}: {
  vue: AppareilVue;
  onClient?: () => void;
  onListe: (index: number, origin: ListOrigin) => void;
}) {
  return (
    <>
      <div className="mb-4 grid grid-cols-2 gap-3">
        <Encart titre="Abonnement">
          {vue.abonnementOk ? <StatusBadge status="active" /> : <StatusBadge status="expired" />}
          <p className="mt-1 truncate text-[11px] text-ink-tertiary">{vue.abonnement}</p>
        </Encart>
        <Encart titre="Présence">
          <StatusBadge status={vue.enLigne ? 'online' : 'offline'} />
          <p className="mt-1 truncate text-[11px] text-ink-tertiary">{vue.presence}</p>
        </Encart>
      </div>
      <div className="mb-5 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
        <Info
          label="Client"
          value={vue.client}
          onClick={vue.customerId && onClient ? onClient : undefined}
        />
        <Info label="Plateforme" value={vue.plateforme} />
        <Info label="Modèle" value={vue.modele} />
        <Info label="Android" value={vue.android} />
        <Info label="Version app" value={vue.version} />
        <Info label="Étiquette" value={vue.etiquette} />
        <Info label="Accès" value={vue.acces} />
        <Info label="Dernière vue" value={vue.derniereVue} />
        <Info label="Première vue" value={vue.premiereVue} />
      </div>
      <BlocListes
        titre="Listes poussées"
        vide="Aucune liste poussée depuis le panel pour cette box."
        listes={vue.listes}
        onOpen={(index) => onListe(index, 'panel')}
      />
      <BlocListes
        titre="Inventaire sur la box"
        vide="La box n’a pas encore remonté ses listes."
        listes={vue.locales}
        onOpen={(index) => onListe(index, 'locale')}
      />
    </>
  );
}

export function CorpsClient({
  vue,
  nom,
  telephone,
  notes,
  onNom,
  onTelephone,
  onNotes,
  onAppareil,
}: {
  vue: ClientVue;
  nom: string;
  telephone: string;
  notes: string;
  onNom: (v: string) => void;
  onTelephone: (v: string) => void;
  onNotes: (v: string) => void;
  onAppareil: (id: string, mac: string) => void;
}) {
  return (
    <>
      <div className="mb-4 grid gap-3 sm:grid-cols-2">
        <Champ id="fiche-nom" label="Nom" value={nom} onChange={onNom} />
        <Champ id="fiche-tel" label="Téléphone" value={telephone} onChange={onTelephone} />
      </div>
      <p className="mb-3 text-sm text-ink-secondary">E-mail : {vue.email || '—'}</p>
      <label htmlFor="fiche-notes" className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
        Notes
      </label>
      <textarea
        id="fiche-notes"
        value={notes}
        onChange={(e) => onNotes(e.target.value)}
        rows={3}
        className="mb-4 w-full rounded-md border border-white/10 bg-obsidian px-3 py-2 text-sm text-ink-primary outline-none focus:border-accent/60"
      />
      <h3 className="mb-2 text-sm font-semibold text-ink-secondary">Appareils</h3>
      {vue.appareils.length === 0 && (
        <p className="text-xs text-ink-tertiary">Aucun appareil lié.</p>
      )}
      <ul className="space-y-1">
        {vue.appareils.map((d) => (
          <li key={d.id}>
            <button
              type="button"
              className="font-mono text-xs text-accent underline-offset-2 hover:underline"
              onClick={() => onAppareil(d.id, d.mac)}
            >
              {d.mac}{d.label ? ` · ${d.label}` : ''}
            </button>
          </li>
        ))}
      </ul>
    </>
  );
}

export function CorpsListe({ liste }: { liste: ListeApercu | null }) {
  if (!liste) {
    return (
      <p className="text-sm text-ink-secondary">
        Cette liste n’est pas dans l’inventaire actuel.
      </p>
    );
  }
  return (
    <div className="rounded-lg border border-white/5 bg-obsidian px-3 py-3 text-sm">
      <p className="text-[10px] uppercase tracking-widest text-ink-tertiary">
        {liste.origin === 'locale' ? 'Sur la box' : 'Poussée par le panel'} · #{liste.index + 1}
      </p>
      <p className="mt-1 font-medium">{liste.label}</p>
      <p className="mt-1 text-ink-secondary">{liste.type === 'xtream' ? 'Xtream' : 'M3U'} · {liste.resume}</p>
      <p className="mt-1 font-mono text-xs text-ink-secondary">Identifiant : {liste.identifiant}</p>
    </div>
  );
}

function BlocListes({
  titre,
  vide,
  listes,
  onOpen,
}: {
  titre: string;
  vide: string;
  listes: ListeApercu[];
  onOpen: (index: number) => void;
}) {
  return (
    <div className="mb-4">
      <div className="mb-2 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-ink-secondary">{titre}</h3>
        <span className="text-[11px] text-ink-tertiary">{listes.length}</span>
      </div>
      {listes.length === 0 && (
        <p className="rounded-lg border border-white/5 bg-obsidian px-3 py-3 text-center text-xs text-ink-tertiary">{vide}</p>
      )}
      {listes.map((liste) => (
        <button
          key={`${liste.origin}-${liste.index}`}
          type="button"
          onClick={() => onOpen(liste.index)}
          className="mb-2 block w-full rounded-lg border border-white/5 bg-obsidian px-3 py-3 text-left hover:border-accent/40"
        >
          <span className="text-[10px] font-bold text-ink-tertiary">#{liste.index + 1} · {liste.type === 'xtream' ? 'XTREAM' : 'M3U'}</span>
          <span className="mt-1 block text-sm text-ink-primary">{liste.label}</span>
          <span className="block text-xs text-ink-secondary">{liste.resume}</span>
        </button>
      ))}
    </div>
  );
}

function Encart({ titre, children }: { titre: string; children: ReactNode }) {
  return (
    <div className="rounded-lg border border-white/5 bg-obsidian px-3 py-2.5">
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{titre}</div>
      <div className="mt-1">{children}</div>
    </div>
  );
}

function Info({ label, value, onClick }: { label: string; value: string; onClick?: () => void }) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</div>
      {onClick ? (
        <button type="button" onClick={onClick} className="truncate text-left text-accent underline-offset-2 hover:underline" title={value}>
          {value}
        </button>
      ) : (
        <div className="truncate text-ink-secondary" title={value}>{value}</div>
      )}
    </div>
  );
}

function Champ({
  id, label, value, onChange,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div>
      <label htmlFor={id} className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</label>
      <input
        id={id}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-md border border-white/10 bg-obsidian px-3 py-2 text-sm outline-none focus:border-accent/60"
      />
    </div>
  );
}
