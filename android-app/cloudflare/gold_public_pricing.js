// Lecture seule des tarifs réellement enregistrés. L'ancien GET /api/pricing
// fabriquait des prix par défaut et omettait les textes/liens du panel.
// Aucun droit d'accès, durée d'essai ou statut de licence n'est modifié ici.
const keys = ['price_currency', 'price_lifetime', 'price_yearly', 'promo_enabled',
  'promo_msg', 'trial_block_title_fr', 'trial_block_body_fr',
  'trial_block_title_en', 'trial_block_body_en', 'trial_pay_url'];
const text = (value, max) => typeof value === 'string'
  ? value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, max) : '';

export async function attachPublicPricing(env, response) {
  if (!response.ok || !env.DB) return response;
  try {
    const value = await response.clone().json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) return response;
    const rows = await env.DB.prepare(`SELECT key,value FROM app_config WHERE key IN
      (${keys.map(() => '?').join(',')})`).bind(...keys).all();
    const config = Object.fromEntries((rows.results || []).map(row => [row.key, row.value]));
    const pay = text(config.trial_pay_url, 500);
    let payUrl = '';
    try {
      const url = new URL(pay);
      if (url.protocol === 'https:' && url.hostname && !url.username && !url.password) payUrl = url.href;
    } catch { /* Aucun lien de paiement implicite. */ }
    const next = {
      ...value,
      configured: keys.some(key => key !== 'promo_enabled' && text(config[key], 500)),
      currency: text(config.price_currency, 8),
      lifetime: text(config.price_lifetime, 30),
      yearly: text(config.price_yearly, 30),
      promoEnabled: config.promo_enabled === '1',
      promoMessage: text(config.promo_msg, 500),
      blockTitleFr: text(config.trial_block_title_fr, 120),
      blockBodyFr: text(config.trial_block_body_fr, 500),
      blockTitleEn: text(config.trial_block_title_en, 120),
      blockBodyEn: text(config.trial_block_body_en, 500),
      payUrl,
    };
    const headers = new Headers(response.headers); headers.delete('Content-Length');
    return new Response(JSON.stringify(next), { status: response.status, headers });
  } catch {
    // Les nouveaux clients exigent configured=true ; une ancienne réponse
    // sans ce témoin n'affiche donc aucun prix inventé après une panne.
    return response;
  }
}
