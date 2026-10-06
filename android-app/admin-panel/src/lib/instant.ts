// =========================================================
//  instant.ts — « Envoi instantané » : la liste est-elle SUR la TV ?
// =========================================================
//  Le Worker prévient la box en moins d'une seconde (mesuré le
//  05/10/2026). Ce qui manquait au revendeur, c'est la PREUVE que la
//  liste est arrivée sur la TV. La box remonte son inventaire réel
//  (type, hôte du serveur, identifiant, nombre de chaînes) par le
//  heartbeat ; depuis le build 107-test.158 elle le fait tout de suite
//  après un import demandé par le panel. Ce fichier compare la liste
//  envoyée à cet inventaire, et formule ce qu'on affiche.
//
//  Aucun mot de passe ne transite : l'inventaire ne contient que l'hôte.
//  Fichier pur : testé par instant.test.ts.
// =========================================================

import type { SourceLike } from './sources';

/// Une source telle que la TV la décrit (inventaire heartbeat).
export interface InventoryLike {
  type: 'xtream' | 'm3u';
  server: string;
  username?: string | null;
  channels?: number | null;
}

/// Relecture de l'inventaire toutes les 2 s : la box envoie son heartbeat
/// 1 à 2 s après l'import, le revendeur voit la confirmation sans attendre.
export const INSTANT_POLL_MS = 2000;

/// Au-delà de 2 minutes sans voir la liste, on arrête de relire et on
/// dit pourquoi (box éteinte, liste refusée…), au lieu de tourner sans fin.
export const INSTANT_GIVE_UP_MS = 120_000;

/// `hôte[:port]` en minuscules, comme la box (source_privacy.dart :
/// `uri.host` + port seulement s'il est écrit dans l'adresse).
export function hostKey(raw: string | null | undefined): string {
  const text = String(raw ?? '').trim();
  if (!text) return '';
  const withScheme = text.includes('://') ? text : `http://${text}`;
  try {
    const u = new URL(withScheme);
    if (!u.hostname) return '';
    // `u.port` est vide pour un port par défaut (80/443) ; la box, elle,
    // garde le port s'il est écrit. On compare sans le port par défaut.
    const explicit = /:\d+(\/|$|\?)/.test(withScheme.replace(/^[a-z]+:\/\//i, ''));
    const port = explicit ? (u.port || (u.protocol === 'https:' ? '443' : '80')) : '';
    return port ? `${u.hostname.toLowerCase()}:${port}` : u.hostname.toLowerCase();
  } catch {
    return '';
  }
}

function sameHost(a: string, b: string): boolean {
  if (!a || !b) return false;
  if (a === b) return true;
  // L'un avec port par défaut explicite, l'autre sans : même serveur.
  const strip = (v: string) => v.replace(/:(80|443)$/, '');
  return strip(a) === strip(b);
}

/// La liste envoyée est-elle dans l'inventaire de la TV ? Renvoie
/// l'entrée trouvée (avec son nombre de chaînes), sinon `null`.
/// M3U : même hôte. Xtream : même hôte ET même identifiant.
export function listOnTv(
  inventory: InventoryLike[] | null | undefined,
  sent: Pick<SourceLike, 'type' | 'server_url' | 'username' | 'm3u_url'>,
): InventoryLike | null {
  if (!inventory || inventory.length === 0) return null;
  const wantHost = hostKey(sent.type === 'xtream' ? sent.server_url : sent.m3u_url);
  if (!wantHost) return null;
  const wantUser = String(sent.username ?? '').trim();
  // Un lien get.php envoyé en M3U est lu par la box (107-test.160+) comme
  // un compte Xtream du même serveur : l'inventaire le décrit alors en
  // « xtream », avec l'identifiant du lien.
  const linkUser = sent.type === 'm3u' ? userFromGetPhp(sent.m3u_url) : '';
  for (const item of inventory) {
    if (!item) continue;
    if (!sameHost(hostKey(item.server), wantHost)) continue;
    const itemUser = String(item.username ?? '').trim();
    if (item.type === sent.type) {
      if (sent.type === 'xtream' && itemUser !== wantUser) continue;
      return item;
    }
    if (sent.type === 'm3u' && item.type === 'xtream' && linkUser && itemUser === linkUser) {
      return item;
    }
  }
  return null;
}

/// Identifiant d'un lien `get.php?username=…&password=…`, sinon ''.
export function userFromGetPhp(raw: string | null | undefined): string {
  const text = String(raw ?? '').trim();
  if (!text) return '';
  try {
    const u = new URL(text);
    const last = u.pathname.split('/').pop() ?? '';
    if (last.toLowerCase() !== 'get.php') return '';
    const user = (u.searchParams.get('username') ?? '').trim();
    const pass = (u.searchParams.get('password') ?? '').trim();
    return user && pass ? user : '';
  } catch {
    return '';
  }
}

/// Toutes les listes envoyées sont-elles sur la TV ? (bouton de la fiche
/// appareil, qui renvoie 1 à 3 listes d'un coup).
export function allOnTv(
  inventory: InventoryLike[] | null | undefined,
  sent: Pick<SourceLike, 'type' | 'server_url' | 'username' | 'm3u_url'>[],
): { seen: InventoryLike[]; missing: number } {
  const seen: InventoryLike[] = [];
  let missing = 0;
  for (const s of sent) {
    const hit = listOnTv(inventory, s);
    if (hit) seen.push(hit);
    else missing += 1;
  }
  return { seen, missing };
}

export interface InstantState {
  /// Millisecondes écoulées depuis l'envoi.
  elapsedMs: number;
  /// Entrées de l'inventaire qui correspondent aux listes envoyées.
  seen: InventoryLike[];
  /// Listes envoyées pas encore vues.
  missing: number;
  /// Dernière présence connue de la box (ms epoch), 0 = jamais.
  lastSeen: number;
  /// Heure courante (ms epoch), pour juger « box vue il y a longtemps ».
  now: number;
}

function seconds(ms: number): string {
  return (Math.max(0, ms) / 1000).toFixed(ms >= 10_000 ? 0 : 1).replace('.', ',');
}

function channels(items: InventoryLike[]): string {
  const total = items.reduce((n, i) => n + (Number(i.channels) || 0), 0);
  return total > 0 ? ` · ${total.toLocaleString('fr-FR')} chaînes` : '';
}

/// Phrase affichée sous le bouton. Trois états : vue, en attente, abandon.
export function instantLabel(s: InstantState): { kind: 'ok' | 'wait' | 'late'; text: string } {
  if (s.missing === 0 && s.seen.length > 0) {
    return {
      kind: 'ok',
      text: `Liste sur la TV après ${seconds(s.elapsedMs)} s${channels(s.seen)}`,
    };
  }
  if (s.elapsedMs < INSTANT_GIVE_UP_MS) {
    const part = s.seen.length > 0 ? ` (${s.seen.length} déjà vue${s.seen.length > 1 ? 's' : ''})` : '';
    return {
      kind: 'wait',
      text: `Box prévenue. En attente de la TV… ${seconds(s.elapsedMs)} s${part}`,
    };
  }
  const idle = s.lastSeen > 0 ? s.now - s.lastSeen : -1;
  const why = idle < 0
    ? 'La box ne s’est jamais connectée : l’application est-elle ouverte ?'
    : idle > 3 * 60_000
      ? `Dernière connexion de la box il y a ${Math.round(idle / 60_000)} min : est-elle allumée, l’application ouverte ?`
      : 'La box est en ligne mais n’a pas encore chargé la liste : lien ou identifiants à vérifier (Boîte noire).';
  return { kind: 'late', text: `Pas vue sur la TV après 2 min. ${why}` };
}
