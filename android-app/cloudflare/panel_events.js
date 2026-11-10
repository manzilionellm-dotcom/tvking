// Accusés et présence : signaux de relecture réservés au panel authentifié.
// Aucun événement ne confirme un état avant son écriture D1. Le navigateur
// relit l'ordre exact/la fiche ; les données privées ne voyagent pas en WS.
const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/;
const ORDER_RX = /^ord_[A-Za-z0-9-]{8,64}$/;
const RECEIPT_STATES = new Set(['received', 'applied', 'failed']);
const nonnegative = value => Number.isSafeInteger(value) && value >= 0;

// Liste fermée des champs publics. Une donnée libre (erreur, URL, inventaire,
// IP, identifiant de source…) ne peut pas être recopiée par inadvertance.
export function publicPanelState(raw) {
  if (!raw || !MAC_RX.test(raw.mac) || !nonnegative(raw.at)) return null;
  const event = { v: 1, type: raw.type, mac: raw.mac, at: raw.at };
  if (raw.type === 'receipt') {
    if (!ORDER_RX.test(raw.order_id) || !/^[a-z_]{1,32}$/.test(raw.kind)
      || !RECEIPT_STATES.has(raw.state)) return null;
    Object.assign(event, { order_id: raw.order_id, kind: raw.kind, state: raw.state });
    for (const key of ['config_rev', 'applied_rev', 'elapsed_ms']) {
      if (raw[key] === undefined || raw[key] === null) continue;
      if (!nonnegative(raw[key])) return null;
      event[key] = raw[key];
    }
  } else if (raw.type === 'presence') {
    if (raw.online !== true || !nonnegative(raw.last_seen_at)) return null;
    event.online = true;
    event.last_seen_at = raw.last_seen_at;
  } else {
    return null;
  }
  return event;
}

export async function publishPanelState(env, raw) {
  if (!env?.RT_HUB || String(env.REALTIME_PUSH_OFF) === '1') return false;
  const event = publicPanelState(raw);
  if (!event) return false;
  try {
    // Route interne au binding uniquement : jamais exposée par le routeur HTTP.
    const hub = env.RT_HUB.get(env.RT_HUB.idFromName('panel-v1'));
    const response = await hub.fetch('https://hub/panel-state', {
      method: 'POST', body: JSON.stringify(event),
    });
    return response.ok;
  } catch (_) {
    // La mutation reste engagée ; le panel conserve sa relecture de secours.
    return false;
  }
}
