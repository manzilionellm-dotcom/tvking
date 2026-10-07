// Ne conserver que la licence et le NOMBRE de listes. Les réponses complètes
// peuvent contenir des accès IPTV : elles ne sont jamais écrites ni affichées.
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const fields = ['exists', 'status', 'paid', 'plan', 'paid_until', 'expires_at', 'frozen', 'banned'];

export function referenceState(status, source) {
  if (!status || typeof status !== 'object' || Array.isArray(status) || status.exists !== true) throw new Error('Licence de référence absente ou réponse invalide');
  if (!source || typeof source !== 'object' || Array.isArray(source)) throw new Error('Réponse des listes invalide');
  const license = Object.fromEntries(fields.map((key) => {
    const value = status[key] ?? null;
    if (value !== null && !['boolean', 'string', 'number'].includes(typeof value)) throw new Error('Champ de licence invalide');
    return [key, value];
  }));
  if (!Array.isArray(source.sources) && !Object.hasOwn(source, 'source')) throw new Error('Nombre de listes absent');
  const sourceCount = Array.isArray(source.sources) ? source.sources.length : source.source == null ? 0 : 1;
  return { license, sourceCount };
}

export function assertReferenceUnchanged(before, after) {
  if (JSON.stringify(before.license) !== JSON.stringify(after.license)) throw new Error('Licence, plan ou échéance de référence modifiés');
  if (before.sourceCount !== after.sourceCount) throw new Error('Nombre de listes de référence modifié');
}

export async function captureReference(base, mac) {
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(mac || '')) throw new Error('MAC de référence invalide');
  const url = new URL(base);
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/') throw new Error('Adresse API invalide');
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && url.hostname === '127.0.0.1')) throw new Error('API HTTPS obligatoire');
  async function read(path) {
    let response;
    try { response = await fetch(new URL(path, url), { signal: AbortSignal.timeout(30_000), redirect: 'error' }); }
    catch { throw new Error('Lecture de référence impossible : réseau ou délai'); }
    if (!response.ok) throw new Error(`Lecture de référence refusée : HTTP ${response.status}`);
    try { return await response.json(); } catch { throw new Error('Lecture de référence impossible : JSON invalide'); }
  }
  const [status, source] = await Promise.all([read(`/api/status/${mac}`), read(`/api/device-source/${mac}`)]);
  return referenceState(status, source);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [action, file] = process.argv.slice(2);
    if (action === 'capture' && file) {
      const state = await captureReference(process.env.WORKER_URL, process.env.MAC);
      writeFileSync(file, JSON.stringify(state), { mode: 0o600 });
      console.log('Référence relevée : licence, plan, échéance et nombre de listes ; accès exclus');
    } else if (action === 'compare' && file) {
      const before = JSON.parse(readFileSync(file, 'utf8'));
      const after = await captureReference(process.env.WORKER_URL, process.env.MAC);
      assertReferenceUnchanged(before, after);
      console.log('Référence identique avant/après : licence, plan, échéance et nombre de listes');
    } else throw new Error('Commande de référence invalide');
  } catch (error) {
    console.error(`::error::${error instanceof SyntaxError ? 'Fichier de référence invalide' : error.message}`);
    process.exitCode = 1;
  }
}
