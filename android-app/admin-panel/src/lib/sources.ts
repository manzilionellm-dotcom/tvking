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

export type RemovePlan =
  | { kind: 'keep'; sources: SourceInput[] }
  | { kind: 'clear' }
  | { kind: 'invalid' };

/// Que faut-il envoyer pour retirer la liste [index] ?
/// - reste au moins une liste → « keep » + les autres, dans le même ordre ;
/// - c'était la dernière → « clear » ;
/// - index hors limites → « invalid » (on n'envoie rien).
export function planRemoveSource(sources: SourceLike[], index: number): RemovePlan {
  if (!Number.isInteger(index) || index < 0 || index >= sources.length) {
    return { kind: 'invalid' };
  }
  const rest = sources.filter((_, i) => i !== index).map(toSourceInput);
  return rest.length === 0 ? { kind: 'clear' } : { kind: 'keep', sources: rest };
}
