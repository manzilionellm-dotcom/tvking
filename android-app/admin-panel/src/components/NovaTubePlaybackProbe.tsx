import { useEffect } from 'react';
import { ApiError, blackboxApi, devicesApi } from '@/lib/api';
import {
  JOURNAL_FRESH_MS, JOURNAL_REFRESH_MS, lastTvPlayback, normalizePanelMac,
  NOVATUBE_TV_VERSION, type PlaybackObservation,
} from '@/lib/blackbox';

export interface TvReading {
  model: string;
  observation: PlaybackObservation | null;
  expiresAt: number;
}

interface Props {
  mac: string;
  version: string;
  platform: string;
  onReading: (mac: string, reading: TvReading | null) => void;
}

// Seules les lignes visibles sans chaîne en direct consultent la fiche.
// Uniquement des GET : la box garde la main sur l'envoi de son journal.
export function NovaTubePlaybackProbe({ mac, version, platform, onReading }: Props) {
  useEffect(() => {
    const normalized = normalizePanelMac(mac) || '';
    if (!normalized || (version && version !== NOVATUBE_TV_VERSION) || (platform && platform !== 'tv')) return;

    const controller = new AbortController();
    const { signal } = controller;
    let timer: ReturnType<typeof setTimeout>;
    let checkDeviceAfter = 0;
    let model = '';
    async function refresh() {
      try {
        if (Date.now() >= checkDeviceAfter) {
          const devices = await devicesApi.list(normalized, { limit: 5 }, signal);
          const device = devices.items.find(d => d.mac?.toUpperCase() === normalized);
          if (signal.aborted) return;
          if (device?.app_version !== NOVATUBE_TV_VERSION || device.platform !== 'tv') {
            onReading(mac, null);
            return;
          }
          model = device.device_model || '';
          checkDeviceAfter = Date.now() + 5 * 60_000;
        }
        const journal = await blackboxApi.get(normalized, signal);
        if (signal.aborted) return;
        const expiresAt = journal.updated_at + JOURNAL_FRESH_MS;
        const now = Date.now();
        const fresh = journal.mac === normalized && journal.updated_at <= now && expiresAt > now;
        const observation = fresh && typeof journal.text === 'string' ? lastTvPlayback(journal.text) : null;
        onReading(mac, { model, observation, expiresAt: observation ? expiresAt : 0 });
      } catch (error) {
        if (signal.aborted) return;
        onReading(mac, null);
        if (error instanceof ApiError && [401, 403, 404].includes(error.status)) return;
      }
      // La présence se rafraîchit toutes les 2 s. Le journal a sa propre
      // cadence de 45 s ; une lecture lente se termine avant la suivante.
      if (!signal.aborted) timer = setTimeout(refresh, JOURNAL_REFRESH_MS);
    }
    void refresh();
    return () => { controller.abort(); clearTimeout(timer); };
  }, [mac, version, platform, onReading]);
  return null;
}
