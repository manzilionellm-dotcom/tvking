// Le bundle récupéré reste identique à son empreinte d'origine. Le runtime
// ajoute seulement trois exports pour réutiliser chiffrement et canal source,
// sans recopier ni reconstruire les fonctions privées depuis une autre branche.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const root = new URL('./production/', import.meta.url);
const meta = JSON.parse(readFileSync(new URL('provenance.json', root), 'utf8'));
const source = readFileSync(new URL('worker.js', root));
if (createHash('sha256').update(source).digest('hex') !== meta.sha256['worker.js']) {
  throw new Error('Le bundle de production diffère de l’export vérifié. Arrêt du build.');
}
writeFileSync(new URL('worker.runtime.js', root), Buffer.concat([source, Buffer.from(`
// Seuls ajouts au bundle vérifié : exports pour le raccordement Gold.
export { sealSource as goldSealSource, openSourceList as goldOpenSourceList,
  notifyBox as goldNotifyBox };
`)]));
