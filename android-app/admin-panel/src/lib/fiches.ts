// =========================================================
//  fiches.ts — Où mène un clic, et quelles actions existent
// =========================================================
//  Une fiche = un appareil (MAC), un client, ou une liste.
//  Une action n'est « prête » que si une route /api/v1 existe déjà,
//  ou si elle est purement locale (copier). Sinon elle reste
//  « bientôt ». Le masquage d'une liste est en plus derrière
//  l'interrupteur FLAG_LISTE_MASQUEE, coupé par défaut : même allumé,
//  aucun corps n'est envoyé tant que le Worker n'a pas le champ.
//
//  Le PUT /api/v1/sources/:mac continue de remplacer l'ensemble
//  avec uniquement type, label, server_url, username, password,
//  m3u_url, epg_url (voir toSourceInput). On n'ajoute pas hidden.
//
//  Fichier pur : testé par fiches.test.ts.
// =========================================================

import { flagOn, type FlagStore, FLAG_FICHES, FLAG_LISTE_MASQUEE } from './flags.ts';

export type FicheKind = 'appareil' | 'client' | 'liste';
export type ListOrigin = 'panel' | 'locale';
export type ActionEtat = 'prete' | 'bientot' | 'coupee';

const MAC_RE = /^MK(?::[0-9A-F]{2}){5}$/i;

export interface FicheCible {
  kind: FicheKind;
  deviceId?: string;
  mac?: string;
  customerId?: string;
  listIndex?: number;
  listOrigin?: ListOrigin;
}

export interface FicheAction {
  id: string;
  label: string;
  /// Route déjà servie par le Worker, ou null.
  route: string | null;
  /// Copie locale : pas une route, et pas « bientôt ».
  local?: boolean;
  /// Reste inerte tant que l'interrupteur nommé est coupé.
  fallbackFlag?: typeof FLAG_LISTE_MASQUEE;
}

export interface ListeApercu {
  index: number;
  origin: ListOrigin;
  type: 'xtream' | 'm3u';
  label: string;
  identifiant: string;
  resume: string;
}

export interface FicheFlags {
  fiches: boolean;
  listeMasquee: boolean;
}

/// Écrans où une MAC, un client, une liste ou un appareil devient cliquable
/// quand l'interrupteur des fiches est allumé.
export const ECRANS_CLIQUABLES: { ecran: string; cibles: FicheKind[] }[] = [
  { ecran: 'Appareils', cibles: ['appareil', 'client', 'liste'] },
  { ecran: 'Clients', cibles: ['client', 'appareil'] },
  { ecran: 'Activations', cibles: ['appareil', 'client'] },
  { ecran: 'En ligne', cibles: ['appareil'] },
  { ecran: 'Familles', cibles: ['appareil'] },
  { ecran: 'Références', cibles: ['appareil'] },
  { ecran: 'Avis', cibles: ['appareil'] },
  { ecran: 'Historique', cibles: ['appareil', 'client'] },
  { ecran: 'Liste de chaînes', cibles: ['appareil', 'liste'] },
  { ecran: 'Pousser une source', cibles: ['appareil'] },
  { ecran: 'Activer', cibles: ['appareil'] },
  { ecran: 'Transférer', cibles: ['appareil'] },
];

export const ACTIONS_APPAREIL: FicheAction[] = [
  { id: 'activer', label: 'Activer / prolonger', route: 'POST /api/v1/activate' },
  { id: 'prolonger-essai', label: 'Prolonger l’essai', route: 'POST /api/v1/trial-extend' },
  { id: 'geler', label: 'Geler', route: 'PATCH /api/v1/devices/:id' },
  { id: 'bannir', label: 'Bannir', route: 'PATCH /api/v1/devices/:id' },
  { id: 'reactiver', label: 'Réactiver', route: 'PATCH /api/v1/devices/:id' },
  { id: 'desactiver', label: 'Désactiver l’abonnement', route: null },
  { id: 'supprimer', label: 'Supprimer', route: 'DELETE /api/v1/devices/:id' },
  { id: 'pousser-liste', label: 'Pousser une liste', route: 'PUT /api/v1/sources/:mac' },
  { id: 'retirer-listes', label: 'Retirer les listes poussées', route: 'DELETE /api/v1/sources/:mac' },
  { id: 'transferer', label: 'Transférer', route: 'POST /api/v1/transfer' },
  { id: 'copier-mac', label: 'Copier la MAC', route: null, local: true },
  { id: 'notes-client', label: 'Notes du client', route: 'PATCH /api/v1/customers/:id' },
  { id: 'notes-appareil', label: 'Notes de l’appareil', route: null },
  { id: 'historique', label: 'Historique de cet appareil', route: null },
];

export const ACTIONS_CLIENT: FicheAction[] = [
  { id: 'enregistrer-client', label: 'Enregistrer notes et coordonnées', route: 'PATCH /api/v1/customers/:id' },
  { id: 'copier-client', label: 'Copier l’identifiant', route: null, local: true },
  { id: 'activer-client', label: 'Activer', route: null },
  { id: 'desactiver-client', label: 'Désactiver', route: null },
  { id: 'geler-client', label: 'Geler', route: null },
  { id: 'bannir-client', label: 'Bannir', route: null },
  { id: 'supprimer-client', label: 'Supprimer', route: null },
  { id: 'transferer-client', label: 'Transférer', route: null },
  { id: 'historique-client', label: 'Historique de ce client', route: null },
];

const ACTION_RETIRER_LISTE: FicheAction = {
  id: 'retirer-liste',
  label: 'Retirer cette liste',
  route: 'PUT /api/v1/sources/:mac',
};
const ACTION_MODIFIER_LISTE: FicheAction = {
  id: 'modifier-liste',
  label: 'Modifier / pousser',
  route: 'PUT /api/v1/sources/:mac',
};
const ACTION_RETIRER_LOCALE: FicheAction = {
  id: 'retirer-liste',
  label: 'Retirer cette liste',
  route: null,
};
const ACTION_COPIER_LISTE: FicheAction = {
  id: 'copier-liste',
  label: 'Copier l’identifiant',
  route: null,
  local: true,
};
const ACTION_OUVRIR_APPAREIL: FicheAction = {
  id: 'ouvrir-appareil',
  label: 'Ouvrir la fiche appareil',
  route: 'GET /api/v1/devices/:id/overview',
};
const ACTION_MASQUER: FicheAction = {
  id: 'masquer-liste',
  label: 'Masquer / réafficher sur la box',
  route: null,
  fallbackFlag: FLAG_LISTE_MASQUEE,
};

export function actionsPour(kind: FicheKind, origin: ListOrigin = 'panel'): FicheAction[] {
  if (kind === 'client') return ACTIONS_CLIENT;
  if (kind === 'liste') {
    return origin === 'locale'
      ? [ACTION_RETIRER_LOCALE, ACTION_COPIER_LISTE, ACTION_OUVRIR_APPAREIL, ACTION_MASQUER]
      : [ACTION_RETIRER_LISTE, ACTION_MODIFIER_LISTE, ACTION_COPIER_LISTE, ACTION_OUVRIR_APPAREIL, ACTION_MASQUER];
  }
  return ACTIONS_APPAREIL;
}

export function etatAction(action: FicheAction, flags: { listeMasquee: boolean }): ActionEtat {
  if (action.fallbackFlag === FLAG_LISTE_MASQUEE && !flags.listeMasquee) return 'coupee';
  if (action.local) return 'prete';
  if (!action.route) return 'bientot';
  if (action.fallbackFlag === FLAG_LISTE_MASQUEE) return 'bientot';
  return 'prete';
}

/// Actions déjà dans l'état demandé, ou impossibles sans identifiant / droit.
/// Elles restent visibles, mais le bouton ne part pas.
export function actionsInertes(ctx: {
  deviceId?: string | null;
  mac?: string | null;
  customerId?: string | null;
  blockStatus?: string | null;
  canActivate: boolean;
  canSources: boolean;
  superAdmin: boolean;
  listeAbsente?: boolean;
}): string[] {
  const out: string[] = [];
  const st = ctx.blockStatus || 'active';
  if (st === 'frozen') out.push('geler');
  else if (st === 'banned') out.push('bannir');
  else out.push('reactiver');
  if (!ctx.deviceId) out.push('geler', 'bannir', 'reactiver', 'supprimer', 'ouvrir-appareil');
  if (!ctx.mac) {
    out.push('activer', 'prolonger-essai', 'pousser-liste', 'retirer-listes', 'transferer', 'copier-mac', 'modifier-liste', 'retirer-liste');
  }
  if (!ctx.customerId) out.push('notes-client');
  if (!ctx.canActivate) out.push('activer', 'transferer');
  if (!ctx.canSources) out.push('pousser-liste', 'retirer-listes', 'modifier-liste', 'retirer-liste');
  if (!ctx.superAdmin) out.push('prolonger-essai');
  if (ctx.listeAbsente) out.push('retirer-liste', 'copier-liste', 'modifier-liste');
  return out;
}

export function lireFlags(store: FlagStore | null | undefined): FicheFlags {
  return {
    fiches: flagOn(store, FLAG_FICHES),
    listeMasquee: flagOn(store, FLAG_LISTE_MASQUEE),
  };
}

export function cibleAppareil(opts: {
  deviceId?: string | null;
  mac?: string | null;
}): FicheCible | null {
  const deviceId = clean(opts.deviceId);
  const mac = clean(opts.mac)?.toUpperCase();
  const macOk = !!mac && MAC_RE.test(mac);
  if (!deviceId && !macOk) return null;
  return { kind: 'appareil', deviceId, mac: macOk ? mac : undefined };
}

export function cibleClient(customerId?: string | null): FicheCible | null {
  const id = clean(customerId);
  if (!id) return null;
  return { kind: 'client', customerId: id };
}

export function cibleListe(opts: {
  deviceId?: string | null;
  mac?: string | null;
  index: number;
  origin?: ListOrigin;
}): FicheCible | null {
  const origin: ListOrigin = opts.origin === 'locale' ? 'locale' : 'panel';
  if (!Number.isInteger(opts.index) || opts.index < 0) return null;
  if (origin === 'panel' && opts.index > 2) return null;
  if (origin === 'locale' && opts.index > 50) return null;
  const base = cibleAppareil(opts);
  if (!base) return null;
  return { ...base, kind: 'liste', listIndex: opts.index, listOrigin: origin };
}

export function cibleDepuisAudit(row: {
  target_type?: string | null;
  target_id?: string | null;
}): FicheCible | null {
  const type = (row.target_type || '').toLowerCase();
  const id = clean(row.target_id);
  if (!id) return null;
  if (type === 'customer') return cibleClient(id);
  if (type === 'device') return { kind: 'appareil', deviceId: id };
  if (type === 'device_source' || MAC_RE.test(id)) return cibleAppareil({ mac: id });
  return null;
}

/// Chemin logique de la fiche (tests de navigation, pas une route React).
export function cheminFiche(c: FicheCible): string {
  if (c.kind === 'client' && c.customerId) {
    return `/fiches/client/${encodeURIComponent(c.customerId)}`;
  }
  const who = encodeURIComponent(c.deviceId || c.mac || '');
  if (c.kind === 'liste') {
    const origin = c.listOrigin === 'locale' ? 'locale' : 'panel';
    return `/fiches/liste/${who}/${origin}/${c.listIndex ?? 0}`;
  }
  return `/fiches/appareil/${who}`;
}

export function trouverAppareil<T extends { id: string; mac: string }>(
  items: T[],
  cible: { deviceId?: string; mac?: string },
): T | null {
  if (cible.deviceId) {
    const byId = items.find((d) => d.id === cible.deviceId);
    if (byId) return byId;
  }
  if (cible.mac) {
    const want = cible.mac.toUpperCase();
    const byMac = items.find((d) => String(d.mac).toUpperCase() === want);
    if (byMac) return byMac;
  }
  return null;
}

/// Aperçu affiché d'une liste. Jamais de mot de passe ni d'URL de flux.
export function apercuesListes(
  sources: Array<{ type?: string | null; label?: string | null; name?: string | null; username?: string | null }>,
  origin: ListOrigin,
): ListeApercu[] {
  return sources.map((s, index) => {
    const type = s.type === 'xtream' ? 'xtream' : 'm3u';
    const label = clean(s.label) || clean(s.name) || (type === 'xtream' ? 'Xtream' : 'M3U');
    const identifiant = type === 'xtream' ? (clean(s.username) || '—') : label;
    return {
      index,
      origin,
      type,
      label,
      identifiant,
      resume: type === 'xtream' ? 'Identifiants enregistrés' : 'Lien enregistré',
    };
  });
}

/// Jours d'essai acceptés par POST /api/v1/trial-extend (entier 1 à 365).
export function joursEssaiValides(value: unknown): number | null {
  const n = typeof value === 'number' ? value : Number(String(value ?? '').trim());
  if (!Number.isInteger(n) || n < 1 || n > 365) return null;
  return n;
}

/// Masquer une liste : jamais d'envoi. Le champ hidden n'est pas au contrat.
export function planHideSource(flagOn: boolean): { send: false; reason: 'flag' | 'no-route' } {
  if (!flagOn) return { send: false, reason: 'flag' };
  return { send: false, reason: 'no-route' };
}

function clean(value: string | null | undefined): string | undefined {
  const v = (value ?? '').trim();
  return v ? v : undefined;
}
