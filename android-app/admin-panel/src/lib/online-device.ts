import { isValidMac, normalizeMac } from './mac.ts';

/** Type matériel, jamais le namespace produit `platform` (ZUNO = tv même
 * sur téléphone). L'absence de preuve reste visible, sans appareil inventé. */
export type OnlineDeviceKind =
  | 'android_tv' | 'fire_tv' | 'android_phone' | 'android_tablet'
  | 'android' | 'unknown';

export interface OnlineDeviceMetadata {
  mac: string;
  deviceKind: string;
  deviceModel: string;
  manufacturer: string;
  androidRelease: string;
  appVersion: string;
}

export interface OnlineDeviceSummary {
  label: string;
  model: string;
  os: string;
  kind: OnlineDeviceKind;
  appVersion: string;
}

const labels: Record<OnlineDeviceKind, string> = {
  android_tv: 'Android TV',
  fire_tv: 'Fire TV',
  android_phone: 'Téléphone Android',
  android_tablet: 'Tablette Android',
  android: 'Android · type non communiqué',
  unknown: 'Appareil non identifié',
};

function object(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown> : {};
}

function text(value: unknown, max = 80): string {
  return typeof value === 'string'
    ? value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, max) : '';
}

/** Jointure par identité complète : pas de recherche par suffixe ou par IP. */
export function normalizeOnlineMac(value: unknown): string {
  if (typeof value !== 'string' || value.length > 64) return '';
  const mac = normalizeMac(value);
  return isValidMac(mac) ? mac : '';
}

/** Liste blanche : ni codes IPTV, ni secret appareil, ni données client dans
 * le cache de la page En ligne. Accepte aussi le futur contrat camelCase. */
function metadata(value: unknown): OnlineDeviceMetadata {
  const row = object(value);
  return {
    mac: normalizeOnlineMac(row.mac),
    deviceKind: text(row.deviceKind || row.device_kind, 32).toLowerCase(),
    deviceModel: text(row.deviceModel || row.device_model),
    manufacturer: text(row.manufacturer || row.device_manufacturer),
    androidRelease: text(row.androidRelease || row.android_release, 24),
    appVersion: text(row.appVersion || row.app_version, 40),
  };
}

function explicitKind(value: string): OnlineDeviceKind | undefined {
  return ['android_tv', 'fire_tv', 'android_phone', 'android_tablet'].includes(value)
    ? value as OnlineDeviceKind : undefined;
}

export function summaryForOnlineDevice(
  onlineRow: unknown,
  matchedDevice?: unknown,
): OnlineDeviceSummary {
  const live = metadata(onlineRow);
  const candidate = metadata(matchedDevice);
  // Un appelant ne peut pas accidentellement afficher la fiche d'une autre MAC.
  const saved = live.mac && candidate.mac === live.mac ? candidate : metadata(null);
  const model = live.deviceModel || saved.deviceModel;
  const release = live.androidRelease || saved.androidRelease;
  let kind = explicitKind(live.deviceKind) || explicitKind(saved.deviceKind);
  if (!kind) {
    // Modèles explicites uniquement. Amazon documente les modèles AFT pour
    // Fire TV : developer.amazon.com/docs/fire-tv/user-agent-strings.html
    // Le fabricant Amazon seul ne suffit pas : il vend aussi des tablettes.
    if (/^AFT[A-Z0-9]{1,24}$/i.test(model) || /\bFire TV\b/i.test(model)) {
      kind = 'fire_tv';
    } else if (/\bSHIELD(?: ANDROID)? TV(?: PRO)?\b/i.test(model)
      || /\b(?:ANDROID|GOOGLE) TV\b/i.test(model)) {
      kind = 'android_tv';
    } else if (/\bSHIELD Tablet\b/i.test(model)
      || /^(?:Amazon )?Fire (?:HD \d+|Max \d+)(?:\b.*)?$/i.test(model)) {
      kind = 'android_tablet';
    } else {
      kind = release ? 'android' : 'unknown';
    }
  }
  return {
    label: labels[kind], model, kind,
    os: release ? `Android ${release}` : '',
    appVersion: live.appVersion || saved.appVersion,
  };
}

export interface OnlineDeviceMetadataRead {
  devices: Map<string, OnlineDeviceMetadata>;
  /** Tous les appareils demandés ont une fiche, même si ses champs sont vides. */
  complete: boolean;
  failed: boolean;
}

type FetchDevicePage = (
  page: { limit: number; offset: number },
  signal?: AbortSignal,
) => Promise<unknown>;

function assertNotAborted(signal?: AbortSignal): void {
  if (signal?.aborted) throw new DOMException('Lecture annulée', 'AbortError');
}

/** Un parcours paginé borné du registre, pas une requête par appareil.
 * Le Worker récent limite à 200 lignes ; les anciens répondent jusqu'à 500.
 * On avance donc selon les lignes reçues, jamais selon le 500 demandé.
 * Une panne conserve les fiches déjà reçues, sans supprimer les présences. */
export async function readOnlineDeviceMetadata(
  macs: readonly unknown[],
  fetchPage: FetchDevicePage,
  signal?: AbortSignal,
): Promise<OnlineDeviceMetadataRead> {
  const wanted = new Set(macs.map(normalizeOnlineMac).filter(Boolean));
  const devices = new Map<string, OnlineDeviceMetadata>();
  const visited = new Set<string>();
  let offset = 0;
  let failed = false;
  assertNotAborted(signal);
  for (let page = 0; page < 20 && devices.size < wanted.size; page++) {
    let body: Record<string, unknown>;
    try {
      body = object(await fetchPage({ limit: 500, offset }, signal));
      assertNotAborted(signal);
    } catch (error) {
      if (signal?.aborted || (error instanceof Error && error.name === 'AbortError')) {
        throw new DOMException('Lecture annulée', 'AbortError');
      }
      failed = true;
      break;
    }
    if (!Array.isArray(body.items)) { failed = true; break; }
    const rows = body.items.slice(0, 500);
    if (rows.length === 0) break;
    let newIdentities = 0;
    for (const raw of rows) {
      const row = metadata(raw);
      if (!row.mac) continue;
      if (!visited.has(row.mac)) { visited.add(row.mac); newIdentities++; }
      if (wanted.has(row.mac) && !devices.has(row.mac)) devices.set(row.mac, row);
    }
    offset += rows.length;
    // Un ancien Worker peut ignorer offset : arrêter au lieu de relire la
    // même page vingt fois. Les appareils non trouvés restent non identifiés.
    if (newIdentities === 0) break;
    const total = typeof body.total === 'number' ? body.total : Number.NaN;
    if (Number.isFinite(total) && total >= 0 && offset >= total) break;
    if (body.truncated === false) break;
  }
  return { devices, complete: devices.size === wanted.size, failed };
}
