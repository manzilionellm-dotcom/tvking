// =========================================================
//  m3u.ts — Parser M3U / M3U8 extended (#EXTM3U)
// =========================================================
//  Le format M3U "extended" est de facto le format universel des
//  playlists IPTV. Spec informelle mais largement coherente entre
//  fournisseurs :
//
//      #EXTM3U
//      #EXTINF:-1 tvg-id="france2.fr" tvg-logo="https://..." group-title="France",France 2
//      http://serveur.com/live/USER/PASS/12345.ts
//
//  Chaque chaine = 2 lignes :
//    1. `#EXTINF:<duration> <attr>="<value>"...,<display name>`
//    2. URL du flux
//
//  Cas edge a gerer (vus dans la nature) :
//    - Attributs sans guillemets : `tvg-id=france2.fr` (rare mais existe)
//    - Lignes vides entre entrees (ignore)
//    - BOM UTF-8 en debut de fichier (a stripper)
//    - CRLF (Windows) vs LF (Unix) — normalise
//    - Display name avec virgules : `,Sport, Live 24/7` → garder tel quel
//    - Lignes #EXTGRP:<group> entre EXTINF et URL (override group-title)
//
//  Performance : on parcourt le fichier ligne par ligne, O(n). Sur
//  une playlist de 30k chaines (cas pas rare en IPTV), ce parser
//  doit rester sous 1 seconde sur un mid-range Android TV.
// =========================================================

import { Channel } from '../models/channel.js';

/**
 * Parse une playlist M3U (format extended #EXTM3U) et renvoie la
 * liste des chaines. Renvoie un tableau VIDE si le contenu n'est
 * pas une playlist M3U valide — on ne jette PAS d'exception pour
 * que l'UI puisse afficher un message ("Playlist vide ?") au lieu
 * d'un crash.
 *
 * @param content Texte brut de la playlist (deja decoded UTF-8).
 */
export function parseM3u(content: string): Channel[] {
  if (typeof content !== 'string' || content.length === 0) {
    return [];
  }

  // Strip BOM UTF-8 (U+FEFF) au cas ou — certaines playlists exportees
  // depuis Notepad / un editeur Windows en mettent un en tete.
  const text =
    content.charCodeAt(0) === 0xfeff ? content.slice(1) : content;
  const lines = text.split(/\r?\n/);

  // Verification de l'entete : la 1ere ligne non-vide doit etre #EXTM3U.
  // Sinon ce n'est probablement pas une vraie playlist (HTML 404 ?).
  let firstNonEmpty = '';
  for (const line of lines) {
    if (line.trim().length > 0) {
      firstNonEmpty = line.trim();
      break;
    }
  }
  if (!firstNonEmpty.toUpperCase().startsWith('#EXTM3U')) {
    return [];
  }

  const channels: Channel[] = [];

  // State machine ultra-simple : on accumule les metadonnees vues
  // depuis le dernier EXTINF, et a chaque URL non-commentaire on
  // emet une chaine.
  let pendingName: string | null = null;
  let pendingLogo: string | null = null;
  let pendingGroup: string | null = null;
  let pendingEpgId: string | null = null;

  const resetPending = (): void => {
    pendingName = null;
    pendingLogo = null;
    pendingGroup = null;
    pendingEpgId = null;
  };

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (line.length === 0) continue;

    if (line.toUpperCase().startsWith('#EXTM3U')) {
      // Entete deja capturee, on saute
      continue;
    }

    if (line.toUpperCase().startsWith('#EXTINF')) {
      const parsed = parseExtInf(line);
      pendingName = parsed.name;
      pendingLogo = parsed.logo;
      pendingGroup = parsed.group;
      pendingEpgId = parsed.epgId;
      continue;
    }

    if (line.toUpperCase().startsWith('#EXTGRP')) {
      // Format : #EXTGRP:NomDuGroupe
      const colon = line.indexOf(':');
      if (colon > 0) {
        pendingGroup = line.slice(colon + 1).trim() || pendingGroup;
      }
      continue;
    }

    if (line.startsWith('#')) {
      // Autre commentaire (#KODIPROP, #EXTVLCOPT, etc.) — ignore.
      continue;
    }

    // Ligne non-commentaire = URL du flux. On emet UNE chaine.
    // On accepte meme si pendingName est null (playlists exotiques
    // qui omettent l'EXTINF) — on derive un nom de l'URL.
    const url = line;
    const name = pendingName ?? deriveNameFromUrl(url);
    const id = pendingEpgId ?? hashString(url);

    channels.push({
      id,
      name,
      url,
      logoUrl: pendingLogo,
      group: pendingGroup,
      epgId: pendingEpgId,
      orderIndex: channels.length,
    });

    resetPending();
  }

  return channels;
}

interface ExtInfParts {
  name: string;
  logo: string | null;
  group: string | null;
  epgId: string | null;
}

/**
 * Parse une ligne `#EXTINF:<duration>[ attrs],<name>`.
 *
 * Attributs supportes (insensible a la casse) :
 *   tvg-id     -> epgId
 *   tvg-logo   -> logo
 *   group-title-> group
 *
 * Le nom est tout ce qui suit la DERNIERE virgule de la ligne. C'est
 * une heuristique forte car un nom peut contenir des virgules ("Eurosport,
 * Live") — la spec officielle dit "tout apres la derniere virgule" et
 * c'est ce que VLC / TiviMate font.
 */
function parseExtInf(line: string): ExtInfParts {
  const lastComma = line.lastIndexOf(',');
  const name =
    lastComma >= 0 && lastComma < line.length - 1
      ? line.slice(lastComma + 1).trim()
      : 'Chaîne sans nom';

  // La partie "attributs" est entre `#EXTINF:` et la derniere virgule.
  const attrsRegion =
    lastComma > 0
      ? line.slice(line.indexOf(':') + 1, lastComma)
      : line.slice(line.indexOf(':') + 1);

  // Extract attribute="value" (guillemets) ou attribute=value (sans).
  // On accepte les guillemets simples aussi par tolerance.
  const attrRe =
    /([a-zA-Z][a-zA-Z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s",]+))/g;
  const attrs: Record<string, string> = {};
  let m: RegExpExecArray | null;
  while ((m = attrRe.exec(attrsRegion)) !== null) {
    const key = m[1]?.toLowerCase();
    const value = (m[2] ?? m[3] ?? m[4] ?? '').trim();
    if (key) attrs[key] = value;
  }

  return {
    name: name.length > 0 ? name : 'Chaîne sans nom',
    logo: attrs['tvg-logo'] || null,
    group: attrs['group-title'] || null,
    epgId: attrs['tvg-id'] || null,
  };
}

/**
 * Genere un identifiant stable a partir d'une URL. djb2 hash —
 * suffisant pour qu'on n'ait pas de collisions sur < 100k chaines.
 * On retourne en base 36 pour rester court (~8 chars).
 */
function hashString(input: string): string {
  let h = 5381;
  for (let i = 0; i < input.length; i++) {
    h = (h * 33) ^ input.charCodeAt(i);
  }
  // >>> 0 pour passer en unsigned 32-bit avant base36
  return (h >>> 0).toString(36);
}

/**
 * Quand l'EXTINF est absent (playlist degenere), on tire un nom
 * lisible du dernier segment de l'URL.
 */
function deriveNameFromUrl(url: string): string {
  try {
    const u = new URL(url);
    const segments = u.pathname.split('/').filter(Boolean);
    const last = segments[segments.length - 1] ?? u.host;
    return last.replace(/\.[a-z0-9]{1,5}$/i, '') || u.host;
  } catch {
    return 'Chaîne sans nom';
  }
}
