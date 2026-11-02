// Métadonnées matérielles du heartbeat, indépendantes du produit « tv/mobile ».
// Le bundle exporté reste immuable : ce raccord ajoute uniquement deux champs
// à la fiche existante, puis les expose au panel déjà authentifié.
const kinds = new Set(['android_tv', 'fire_tv', 'android_phone', 'android_tablet']);
const prepared = new WeakMap();

function text(value, max) {
  return typeof value === 'string'
    ? value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, max) : '';
}

export function physicalDeviceKind(value) {
  // unknown, vide ou ancien client : ne jamais effacer une mesure connue.
  const kind = text(value, 32).toLowerCase();
  return kinds.has(kind) ? kind : '';
}

export async function ensureDeviceMetadataSchema(env) {
  if (!env.DB) return false;
  if (!prepared.has(env.DB)) {
    const pending = (async () => {
      const columns = await env.DB.prepare('PRAGMA table_info(devices)').all();
      const names = new Set((columns.results || []).map(row => row.name));
      if (!names.has('mac')) throw new Error('device_table_unavailable');
      for (const name of ['device_kind', 'device_manufacturer']) {
        if (names.has(name)) continue;
        try { await env.DB.prepare(`ALTER TABLE devices ADD COLUMN ${name} TEXT`).run(); }
        catch (error) {
          // Un autre isolate peut avoir ajouté la colonne entre les deux
          // appels. Une vraie panne D1 reste réessayable au prochain ping.
          const latest = await env.DB.prepare('PRAGMA table_info(devices)').all();
          if (!(latest.results || []).some(row => row.name === name)) throw error;
        }
      }
      return true;
    })();
    prepared.set(env.DB, pending);
  }
  try { return await prepared.get(env.DB); }
  catch { prepared.delete(env.DB); return false; }
}

export async function recordDeviceMetadata(env, body) {
  const mac = typeof body?.mac === 'string' ? body.mac.trim() : '';
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(mac)) return;
  const kind = physicalDeviceKind(body.deviceKind);
  const manufacturer = text(body.manufacturer, 80);
  if (!kind && !manufacturer) return;
  if (!await ensureDeviceMetadataSchema(env)) return;
  // La MAC est celle acceptée par le heartbeat original, sans rapprochement
  // par IP ou par suffixe et sans création d'un deuxième appareil.
  await env.DB.prepare(`UPDATE devices SET
    device_kind = CASE WHEN ? != '' THEN ? ELSE device_kind END,
    device_manufacturer = CASE WHEN ? != '' THEN ? ELSE device_manufacturer END
    WHERE mac = ?`).bind(kind, kind, manufacturer, manufacturer, mac).run();
}

export function publicDeviceMetadata(row) {
  // Liste blanche : aucune source IPTV, aucun secret ou identifiant Android.
  return {
    deviceKind: physicalDeviceKind(row.device_kind),
    manufacturer: text(row.device_manufacturer, 80),
    deviceModel: text(row.device_model, 80),
    androidRelease: text(row.android_release, 24),
    appVersion: text(row.app_version, 40),
  };
}
