// Décisions pures du canal, sans Worker.
import {
  ADMIN_ACTION_KIND,
  clampTimeout,
  commandsToApply,
  isOnline,
  kindForAdminAction,
  kindForBlock,
  kindForLicensePatch,
  SIGNAL_ONLINE_MS,
} from './box_signal.js';

let fail = 0;
const ok = (c, m) => {
  if (c) console.log('PASS', m);
  else { fail++; console.log('FAIL', m); }
};

ok(kindForAdminAction('freeze') === 'suspend', 'gel → suspension');
ok(kindForAdminAction('note') === null, 'la note interne ne part pas sur la box');
ok(kindForBlock('banned') === 'block', 'bannir → blocage');
ok(kindForBlock('active') === 'resume', 'réactiver → reprise');
ok(clampTimeout(undefined) === 20000, 'attente par défaut 20 s');
ok(clampTimeout(50) === 200, 'attente plancher 200 ms');
ok(clampTimeout(999999) === 20000, 'attente plafond 20 s');
ok(!isOnline(0, 0, 1_000_000), 'jamais vue → hors ligne');
ok(isOnline(1_000_000, 0, 1_000_000 + 1000), 'vue il y a 1 s → en ligne');
ok(!isOnline(1_000_000, 0, 1_000_000 + SIGNAL_ONLINE_MS + 1),
  'canal muet depuis plus de 45 s → hors ligne');
ok(isOnline(0, 1_000_000, 1_000_000 + 60_000),
  'ancien heartbeat dans les 15 min → encore en ligne');

const seen = new Set([2]);
const fresh = commandsToApply([
  { id: 2, kind: 'activate' },
  { id: 3, kind: 'suspend' },
  { id: 3, kind: 'suspend' },
], seen);
ok(fresh.length === 1 && fresh[0].id === 3, 'un ordre déjà vu ne se rejoue pas');
ok(ADMIN_ACTION_KIND.mark_paid === 'activate', 'marquer payé = activation');
ok(kindForLicensePatch({ status: 'active', expires_at: Date.now() - 5000 }) === 'expire',
  'date déjà passée = expiration, même si le statut dit encore actif');
ok(kindForLicensePatch({ status: 'active' }) === 'resume',
  'remettre actif, sans date = reprise');
ok(kindForLicensePatch({ plan: 'yearly' }) === 'renew', 'changement de plan = renouvellement');

console.log(fail ? `${fail} failed` : 'PASS box_signal pur');
process.exit(fail ? 1 : 0);
