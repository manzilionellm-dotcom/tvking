// La réponse et le champ doivent désigner exactement le même appareil.
// Un code proche ne remplace jamais celui choisi par le revendeur.
import { isValidMac, normalizeMac } from './mac.ts';

export function sameBoxTarget(requestMac: string, selectedMac: string): boolean {
  return isValidMac(requestMac) && isValidMac(selectedMac)
    && normalizeMac(requestMac) === normalizeMac(selectedMac);
}

export interface BoxIdentity {
  mac: string;
  device_model?: string | null;
  app_build?: number | null;
  platform?: string | null;
  last_seen_at?: number | null;
}

export type BoxTargetDescription =
  | { kind: 'missing'; mac: string }
  | { kind: 'unidentified'; mac: string }
  | { kind: 'reported'; mac: string; model: string | null; lastSeen: number | null };

// La date seule ne prouve pas un retour de l'app : une activation manuelle
// remplit aussi last_seen_at. Modèle/version proviennent du retour appareil.
export function describeBoxTarget(mac: string, devices: readonly BoxIdentity[]): BoxTargetDescription {
  const normalized = normalizeMac(mac);
  const device = devices.find(d => sameBoxTarget(d.mac, normalized));
  if (!device) return { kind: 'missing', mac: normalized };
  const model = (device.device_model ?? '').trim();
  const knownModel = model && model !== '—' && model !== '-' ? model : null;
  const knownBuild = Number.isFinite(device.app_build) && Number(device.app_build) > 0;
  if (!knownModel && !knownBuild) return { kind: 'unidentified', mac: normalized };
  return { kind: 'reported', mac: normalized, model: knownModel,
    lastSeen: typeof device.last_seen_at === 'number' ? device.last_seen_at : null };
}
