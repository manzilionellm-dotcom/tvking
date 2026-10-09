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
  /// `false` = liste ÉTEINTE par le panel (la box la masque sans l'effacer).
  /// Absent ou `true` = allumée.
  enabled?: boolean | null;
  /// Identifiant serveur d'une liste du client (`origin: 'self'`), celui
  /// que le Worker attend pour la retirer.
  id?: string | null;
}

export type SourceInput = Pick<
  SourceLike,
  'type' | 'label' | 'server_url' | 'username' | 'password' | 'm3u_url' | 'epg_url' | 'enabled'
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
  // Une liste éteinte le reste quand on renvoie les autres.
  if (s.enabled === false) out.enabled = false;
  return out;
}

/// Liste allumée ? (absent = oui)
export function isListOn(s: SourceLike): boolean {
  return s.enabled !== false;
}

export type TogglePlan =
  | { kind: 'send'; sources: SourceInput[]; nowOn: boolean }
  | { kind: 'client' }
  | { kind: 'invalid' };

/// Allumer / éteindre la liste [index] : on renvoie toutes les listes du
/// panel, celle-ci avec l'état inverse. Le Worker prévient la box
/// (ordre « source ») et elle masque ou réaffiche la liste à l'instant.
export function planToggleSource(sources: SourceLike[], index: number): TogglePlan {
  if (!Number.isInteger(index) || index < 0 || index >= sources.length) {
    return { kind: 'invalid' };
  }
  if (isClientList(sources[index])) return { kind: 'client' };
  const nowOn = !isListOn(sources[index]);
  const out: SourceInput[] = [];
  sources.forEach((s, i) => {
    if (isClientList(s)) return;
    const input = toSourceInput(s);
    if (i === index) {
      if (nowOn) delete input.enabled;
      else input.enabled = false;
    }
    out.push(input);
  });
  return { kind: 'send', sources: out, nowOn };
}

/// Liste ajoutée par le client lui-même (pas par le panel).
export function isClientList(s: SourceLike): boolean {
  return s.origin === 'self';
}

export type RemovePlan =
  | { kind: 'keep'; sources: SourceInput[] }
  | { kind: 'clear' }
  | { kind: 'client'; id: string | null }
  | { kind: 'invalid' };

/// Que faut-il envoyer pour retirer la liste [index] ?
/// - reste au moins une liste du PANEL → « keep » + les autres listes du
///   panel, dans le même ordre (le serveur remet lui-même celles du client) ;
/// - plus aucune liste du panel → « clear » (le serveur garde celles du client) ;
/// - la liste visée a été ajoutée par le client → « client » avec son `id` :
///   depuis le 05/10/2026 le Worker la retire par
///   `DELETE /api/v1/sources/:mac/self/:id` (sans `id`, on n'envoie rien) ;
/// - index hors limites → « invalid » (on n'envoie rien).
export function planRemoveSource(sources: SourceLike[], index: number): RemovePlan {
  if (!Number.isInteger(index) || index < 0 || index >= sources.length) {
    return { kind: 'invalid' };
  }
  if (isClientList(sources[index])) {
    const id = sources[index].id;
    return { kind: 'client', id: typeof id === 'string' && id ? id : null };
  }
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

export type ActivationListPlan = {
  kind: 'send';
  /// Ce que le panel envoie : la liste saisie, seule (les listes du client
  /// restent : le serveur les garde d'office, cf. `origin: 'self'`).
  sources: SourceInput[];
  /// Nombre d'anciennes listes du panel que cet envoi remplace.
  replaced: number;
  /// Nombre de listes du client qui restent sur la box.
  clientKept: number;
  /// Vrai si la liste saisie était déjà la seule liste du panel : l'envoi
  /// sert alors seulement à prévenir la box à l'instant.
  unchanged: boolean;
};

/// « Activer avec une liste » = CETTE liste, maintenant. Mesuré le 05/10/2026
/// (box de test, 3 listes du panel déjà posées) : l'ancienne règle « on ajoute,
/// maximum 3 » refusait l'envoi (« full ») et la box gardait l'ancien serveur ;
/// le revendeur voyait « il me donne toujours l'ancien serveur ». Désormais
/// la liste saisie REMPLACE les listes du panel ; celles du client restent.
/// Pour ajouter une liste sans remplacer : fiche appareil.
export function planActivationList(existing: SourceLike[], add: SourceInput): ActivationListPlan {
  const fp = sourceFingerprint(add);
  const panel = existing.filter((s) => !isClientList(s));
  const clientKept = existing.length - panel.length;
  const unchanged = panel.length === 1 && fp !== null && sourceFingerprint(panel[0]) === fp;
  const clean: SourceInput = { ...toSourceInput(add as SourceLike) };
  return {
    kind: 'send',
    sources: [clean],
    replaced: unchanged ? 0 : panel.filter((s) => sourceFingerprint(s) !== fp).length,
    clientKept,
    unchanged,
  };
}

export type AddListPlan =
  | { kind: 'send'; sources: SourceInput[]; already: boolean }
  | { kind: 'full' }
  | { kind: 'invalid'; message: string };

/// Écran « Listes » : ajouter un lien à une box (06/10/2026).
/// Défaut corrigé : l'écran ne renvoyait que les listes Xtream du panel ;
/// « Ajouter » un M3U effaçait donc les autres M3U, et rallumait celles qui
/// étaient éteintes (l'état n'était pas renvoyé). Règle, prouvée par
/// sources.test.ts et le parcours E2E :
///   - ajouter = TOUTES les listes du panel, telles quelles (éteintes
///     comprises), puis la nouvelle ; 3 au maximum ;
///   - remplacer = la nouvelle seule ;
///   - lien déjà présent = pas de doublon : il est rallumé à sa place ;
///   - les listes du client ne sont jamais renvoyées (le serveur les garde).
export function planAddList(existing: SourceLike[], url: string, replace: boolean): AddListPlan {
  return planAddSource(existing, { type: 'm3u', m3u_url: url }, replace);
}

/// Le formulaire Listes accepte M3U et Xtream sans changer la licence.
/// Renvoyer le même compte Xtream met à jour ses accès, sans doublon.
export function planAddSource(existing: SourceLike[], add: SourceInput, replace: boolean): AddListPlan {
  const fresh = toSourceInput(add);
  if (fresh.type === 'xtream') {
    fresh.server_url = String(fresh.server_url ?? '').trim();
    fresh.username = String(fresh.username ?? '').trim();
    fresh.password = String(fresh.password ?? '').trim();
  } else {
    fresh.m3u_url = String(fresh.m3u_url ?? '').trim();
  }
  const bad = validateListInput(fresh);
  if (bad) return { kind: 'invalid', message: bad };
  if (replace) return { kind: 'send', sources: [fresh], already: false };
  const fp = sourceFingerprint(fresh);
  const panel = existing.filter((s) => !isClientList(s));
  let already = false;
  const out: SourceInput[] = panel.map((s) => {
    let input = toSourceInput(s);
    if (sourceFingerprint(s) === fp) {
      already = true;
      // La saisie explicite remplace les anciens accès. Le libellé et
      // le guide restent si le formulaire ne fournit pas ces champs.
      input = { ...input, ...fresh };
      delete input.enabled;
    }
    return input;
  });
  if (!already) out.push(fresh);
  if (out.length > 3) return { kind: 'full' };
  return { kind: 'send', sources: out, already };
}

/// Nom affichable d'une liste SANS secret : son libellé, sinon l'hôte seul
/// (jamais le chemin ni les paramètres, qui portent souvent les codes).
export function listDisplayName(s: SourceLike): string {
  const label = String(s.label ?? '').trim();
  if (label) return label;
  const raw = s.type === 'xtream' ? s.server_url : s.m3u_url;
  try {
    return new URL(String(raw ?? '')).host || (s.type === 'xtream' ? 'Xtream' : 'M3U');
  } catch {
    return s.type === 'xtream' ? 'Xtream' : 'M3U';
  }
}

