// =========================================================
//  sources.ts — Retirer UNE liste d'une box depuis le panel
// =========================================================
//  Le Worker en place remplace l'ensemble des listes d'une MAC à chaque
//  envoi (PUT /api/v1/sources/:mac, 1 à 3 listes). Pour retirer la liste
//  n°2, on renvoie donc les AUTRES telles quelles. S'il n'en reste
//  aucune, on appelle l'effacement (DELETE).
//
//  Côté box (v106 et suivantes) : une liste qui était envoyée par le
//  serveur et qui ne l'est plus est effacée toute seule à la vérification
//  suivante (chaînes, favoris et récents de cette liste compris).
//
//  Fichier pur : testé par sources.test.ts.
// =========================================================

export interface SourceLike {
  type: 'xtream' | 'm3u';
  label?: string | null;
  server_url?: string | null;
  username?: string | null;
  password?: string | null;
  m3u_url?: string | null;
  epg_url?: string | null;
  /// « self » = liste ajoutée par le CLIENT (Mon espace). Le serveur la
  /// garde d'office à chaque envoi : le panel ne doit jamais la renvoyer
  /// (elle deviendrait une liste « panel », verrouillée, et en double).
  origin?: string | null;
}

export type SourceInput = Pick<
  SourceLike,
  'type' | 'label' | 'server_url' | 'username' | 'password' | 'm3u_url' | 'epg_url'
>;

/// Garde seulement les champs qu'accepte l'envoi (pas de mac, date,
/// identifiant de revendeur…), sans toucher aux valeurs.
export function toSourceInput(s: SourceLike): SourceInput {
  const out: SourceInput = { type: s.type };
  if (s.label != null && s.label !== '') out.label = s.label;
  if (s.type === 'xtream') {
    out.server_url = s.server_url ?? null;
    out.username = s.username ?? null;
    out.password = s.password ?? null;
  } else {
    out.m3u_url = s.m3u_url ?? null;
  }
  if (s.epg_url != null && s.epg_url !== '') out.epg_url = s.epg_url;
  return out;
}

/// Liste ajoutée par le client lui-même (pas par le panel).
export function isClientList(s: SourceLike): boolean {
  return s.origin === 'self';
}

export type RemovePlan =
  | { kind: 'keep'; sources: SourceInput[] }
  | { kind: 'clear' }
  | { kind: 'client' }
  | { kind: 'invalid' };

/// Que faut-il envoyer pour retirer la liste [index] ?
/// - reste au moins une liste du PANEL → « keep » + les autres listes du
///   panel, dans le même ordre (le serveur remet lui-même celles du client) ;
/// - plus aucune liste du panel → « clear » (le serveur garde celles du client) ;
/// - la liste visée a été ajoutée par le client → « client » : le Worker
///   actuel ne sait pas la retirer depuis le panel, on n'envoie rien ;
/// - index hors limites → « invalid » (on n'envoie rien).
export function planRemoveSource(sources: SourceLike[], index: number): RemovePlan {
  if (!Number.isInteger(index) || index < 0 || index >= sources.length) {
    return { kind: 'invalid' };
  }
  if (isClientList(sources[index])) return { kind: 'client' };
  const rest = sources
    .filter((s, i) => i !== index && !isClientList(s))
    .map(toSourceInput);
  return rest.length === 0 ? { kind: 'clear' } : { kind: 'keep', sources: rest };
}

/// Empreinte d'une liste, identique à celle de la box
/// (lib/features/playlists/domain/source_fingerprint.dart) :
///   xtream|<serveur sans « / » final, minuscules>|<identifiant>
///   m3u|<adresse exacte, espaces retirés>
export function sourceFingerprint(s: SourceLike): string | null {
  if (s.type === 'xtream') {
    const server = String(s.server_url ?? '').trim().replace(/\/+$/, '').toLowerCase();
    const user = String(s.username ?? '').trim();
    return server && user ? `xtream|${server}|${user}` : null;
  }
  const url = String(s.m3u_url ?? '').trim();
  return url ? `m3u|${url}` : null;
}

function isHttpUrl(v: string): boolean {
  try {
    const u = new URL(v);
    return (u.protocol === 'http:' || u.protocol === 'https:') && u.host.length > 0;
  } catch {
    return false;
  }
}

/// Vérifie une liste saisie AVANT toute activation (pour ne jamais
/// débiter une licence puis échouer sur une faute de frappe).
/// `null` = valide ; sinon le message à afficher.
export function validateListInput(s: SourceInput): string | null {
  if (s.type === 'xtream') {
    const server = String(s.server_url ?? '').trim();
    if (!server) return 'Serveur Xtream manquant.';
    if (!isHttpUrl(server)) return 'Serveur Xtream : adresse http:// ou https:// attendue.';
    if (!String(s.username ?? '').trim()) return 'Identifiant Xtream manquant.';
    if (!String(s.password ?? '').trim()) return 'Mot de passe Xtream manquant.';
    return null;
  }
  const url = String(s.m3u_url ?? '').trim();
  if (!url) return 'Lien M3U manquant.';
  if (!isHttpUrl(url)) return 'Lien M3U : adresse http:// ou https:// attendue.';
  return null;
}

export type ActivationListPlan =
  | { kind: 'send'; sources: SourceInput[] }
  | { kind: 'already' }
  | { kind: 'full' };

/// Ajoute [add] aux listes déjà posées sur la box, sans rien perdre.
/// - déjà présente (panel ou client) → « already » : rien à envoyer ;
/// - 3 listes du panel déjà en place → « full » (limite du serveur) ;
/// - sinon → « send » : listes du panel existantes + la nouvelle.
export function planActivationList(existing: SourceLike[], add: SourceInput): ActivationListPlan {
  const fp = sourceFingerprint(add);
  if (fp && existing.some((s) => sourceFingerprint(s) === fp)) return { kind: 'already' };
  const panel = existing.filter((s) => !isClientList(s));
  if (panel.length >= 3) return { kind: 'full' };
  const clean: SourceInput = { ...toSourceInput(add as SourceLike) };
  return { kind: 'send', sources: [...panel.map(toSourceInput), clean] };
}
