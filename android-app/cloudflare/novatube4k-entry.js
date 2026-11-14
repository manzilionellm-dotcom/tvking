// Entrée de développement reproductible depuis les sources du dépôt.
// La mise à jour en production applique le même pont au bundle actuellement
// déployé, pour ne pas y inclure d'autres différences entre dépôt et production.
import legacy from './gold.js';
import original, { rateLimitOk, recordPresence, ensureScaleSchema, updateDeviceInfo, resetAtFor } from './worker.js';
import { createNovatube4kEntry } from './novatube4k-wrapper.js';
import { recordAck, markRevisionAck, ensureOrderTables, markOrderSent } from './box_orders.js';
import { blackboxRequestedAt } from './blackbox_journal.js';
import { ensureSourcesVersion } from './device_sources_store.js';
import { notifyBox } from './box_channel.js';
import { adminSecretMatches } from './api_v1.js';
import { parseExtendDays, nextTrialEnd, ensureTrialAnchorTable } from './trial_access.js';
export * from './gold.js';
export default createNovatube4kEntry(legacy, original, {
  recordAck, markRevisionAck, ensureOrderTables, markOrderSent, rateLimitOk,
  recordPresence, ensureScaleSchema, updateDeviceInfo, resetAtFor, blackboxRequestedAt,
  ensureSourcesVersion, notifyBox,
  adminSecretMatches, parseExtendDays, nextTrialEnd, ensureTrialAnchorTable,
});
