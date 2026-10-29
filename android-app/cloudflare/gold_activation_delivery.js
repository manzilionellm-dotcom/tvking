// Suivi en lecture seule de la préparation fournisseur. Aucun identifiant
// de ligne, mot de passe, solde ou message fournisseur ne quitte ce module.
const messages = {
  waiting: 'En attente du résultat de la préparation de la ligne.',
  preparing: 'Préparation de la ligne en cours.',
  source_saved: 'Liste enregistrée sur le serveur. En attente de sa réception par l’appareil.',
  renewed: 'Abonnement renouvelé. La liste existante est conservée.',
  skipped: 'Aucune création automatique de ligne prévue pour cette activation.',
  failed: 'La préparation ou la livraison de la ligne a échoué. Vérifiez son historique avant toute nouvelle activation.',
};

export async function activationDeliveryState(env, mac, trace) {
  const row = await env.DB.prepare(`SELECT detail_json FROM gold_history
    WHERE mac=? AND event='activation.delivery'
      AND CASE WHEN json_valid(detail_json) THEN json_extract(detail_json,'$.trace_id') END=?
    ORDER BY created_at DESC,
      CASE json_extract(detail_json,'$.stage') WHEN 'preparing' THEN 0 ELSE 1 END DESC,
      id DESC LIMIT 1`).bind(mac, trace).first();
  let detail = {};
  try { detail = JSON.parse(row?.detail_json || '{}'); } catch { /* Journal ancien illisible. */ }
  const stage = Object.hasOwn(messages, detail.stage) ? detail.stage : 'waiting';
  const order = typeof detail.order_id === 'string' && /^[A-Za-z0-9_.:-]{8,80}$/.test(detail.order_id)
    ? detail.order_id : null;
  return { stage, order_id: stage === 'source_saved' ? order : null, message: messages[stage] };
}
