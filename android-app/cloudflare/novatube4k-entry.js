// Entrée de développement reproductible depuis les sources du dépôt.
// La mise à jour en production applique le même pont au bundle actuellement
// déployé, pour ne pas y inclure d'autres différences entre dépôt et production.
import legacy from './gold.js';
import original, { rateLimitOk, recordPresence } from './worker.js';
import { createNovatube4kEntry } from './novatube4k-wrapper.js';
import { recordAck, markRevisionAck } from './box_orders.js';
export * from './gold.js';
export default createNovatube4kEntry(legacy, original, { recordAck, markRevisionAck, rateLimitOk, recordPresence });
