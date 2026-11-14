// Seuls les codes fixes du journal NovaTube authentifié sont interprétés.
// Une présence manquante, « hors ligne », un buffer vidéo ou un texte libre
// ne prouvent jamais un incident et ne deviennent pas une notification.
import { ensurePanelAlertsSchema, panelAlertMac } from './panel-alerts.js';

const CODES = Object.freeze({
  'provider.reply_refused': 'un refus de connexion à la liste',
  'provider.response_invalid': 'une réponse de liste invalide',
  'provider.http_auth': 'un refus d’authentification de la liste',
  'source.import_invalid_url': 'une adresse de liste invalide',
  'source.import_local_unavailable': 'un échec de préparation du lecteur de liste',
  'source.import_http_error': 'un échec HTTP du téléchargement de la liste',
  'source.import_too_large': 'une liste trop volumineuse',
  'source.import_timeout': 'un téléchargement de liste ayant dépassé le délai',
  'source.import_format': 'un format de liste illisible',
  'source.import_network': 'un échec de téléchargement de la liste',
  'source.import_failed': 'un échec d’import de liste',
});
const SUCCESS = new Set(['xtream.authenticated', 'm3u.catalogue_ready']);
const MAX_AGE = 600_000;

function utc(value) {
  const parts = value.match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/);
  if (!parts) return null;
  const numbers = parts.slice(1).map(Number);
  const time = Date.UTC(numbers[0], numbers[1] - 1, numbers[2], numbers[3], numbers[4], numbers[5]);
  if (!Number.isFinite(time)) return null;
  return new Date(time).toISOString().slice(0, 19).replace('T', ' ') === value ? time : null;
}

export function parseConfirmedNovatubeIncidents(text, mac, now = Date.now()) {
  if (typeof text !== 'string' || text.length > 256 * 1024 || !panelAlertMac(mac)) return [];
  const body = text.replaceAll('\r\n', '\n');
  if (!body.startsWith('NovaTube — journal de la box\n') || !body.split('\n').includes('MAC Atlas : ' + mac)) return [];
  const header = 'Événements récents (UTC) :\n', start = body.indexOf(header);
  if (start < 0) return [];
  const incidents = new Map();
  for (const line of body.slice(start + header.length).split('\n').slice(-250)) {
    const match = line.match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})  ([A-Za-z0-9_.-]{1,80})$/);
    if (!match) continue;
    const at = utc(match[1]), code = match[2];
    if (at === null || at < now - MAX_AGE || at > now + 60_000) continue;
    // Le journal est ordonné : un succès ultérieur clôt l'échec précédent,
    // même si les deux événements ont été datés dans la même seconde.
    if (SUCCESS.has(code)) { incidents.clear(); continue; }
    if (Object.hasOwn(CODES, code)) incidents.set(code, { code, at });
  }
  return [...incidents.values()].slice(-5);
}

export async function collectNovatubeBlackboxIncidents(env, binding, text, now = Date.now()) {
  const mac = panelAlertMac(binding?.mac);
  if (!mac || !binding?.raw_mac || !binding?.device_id) return { inserted: 0 };
  const incidents = parseConfirmedNovatubeIncidents(text, mac, now);
  if (!incidents.length) return { inserted: 0 };
  await ensurePanelAlertsSchema(env);
  const results = await env.DB.batch(incidents.map(({ code, at }) => env.DB.prepare(`INSERT INTO panel_alert_events
    (event_id,dedupe_key,type,mac,app_id,created_at,title,message,url,source_kind,source_id)
    SELECT ?,?,'problem',?,'app_novatube4k',?,'Échec signalé par la box',?,?, 'novatube_blackbox',?
    WHERE EXISTS(SELECT 1 FROM novatube4k_devices WHERE raw_mac=? AND mac=? AND device_id=?)
    ON CONFLICT(dedupe_key) DO NOTHING`).bind('pae_' + crypto.randomUUID().replaceAll('-', ''),
      'blackbox:' + mac + ':' + code + ':' + Math.floor(at / MAX_AGE), mac, now,
      'La box ' + mac + ' signale ' + CODES[code] + '.', '/blackbox?mac=' + mac, code,
      binding.raw_mac, mac, binding.device_id)));
  return { inserted: results.reduce((n, result) => n + Number(result.meta?.changes || 0), 0) };
}
