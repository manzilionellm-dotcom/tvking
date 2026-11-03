import { useEffect, useState } from 'react';
import { ApiError, devicesApi } from './api';
import {
  normalizeOnlineMac, readOnlineDeviceMetadata,
  type OnlineDeviceMetadata,
} from './online-device';

// Les modèles changent rarement : leur lecture est indépendante des battements
// de présence (2 s), et ne retarde jamais l'affichage des appareils en ligne.
export const DEVICE_METADATA_REFRESH_MS = 60_000;

export function useOnlineDeviceMetadata(macs: readonly string[], onLogout: () => void) {
  const key = [...new Set(macs.map(normalizeOnlineMac).filter(Boolean))].sort().join('|');
  const [devices, setDevices] = useState(new Map<string, OnlineDeviceMetadata>());
  const [loading, setLoading] = useState(false);
  const [unavailable, setUnavailable] = useState(false);

  useEffect(() => {
    const wanted = key ? key.split('|') : [];
    const wantedSet = new Set(wanted);
    let disposed = false;
    let pending: AbortController | null = null;
    // Une disparition de la présence ne laisse pas son ancien modèle attaché
    // à une autre ligne. Seule la MAC normalisée sert de clé de rapprochement.
    setDevices((previous) => new Map([...previous].filter(([mac]) => wantedSet.has(mac))));
    setUnavailable(false);
    if (wanted.length === 0) {
      setLoading(false);
      return;
    }

    async function load() {
      if (pending || disposed) return;
      const controller = new AbortController();
      pending = controller;
      setLoading(true);
      const timeout = setTimeout(() => controller.abort(), 15_000);
      try {
        const result = await readOnlineDeviceMetadata(wanted, async (page, signal) => {
          try { return await devicesApi.list('', page, signal); }
          catch (error) {
            if (!disposed && error instanceof ApiError && error.status === 401) onLogout();
            throw error;
          }
        }, controller.signal);
        if (disposed || controller.signal.aborted) return;
        // Une erreur transitoire ne remplace pas un modèle connu par du vide.
        setDevices((previous) => {
          if (result.complete && !result.failed) return result.devices;
          const merged = new Map(previous);
          for (const [mac, incoming] of result.devices) {
            const known = previous.get(mac);
            // Un parcours interrompu peut avoir reçu une fiche incomplète.
            // Garder chaque champ connu de cette même MAC et accepter les
            // valeurs nouvelles, sans toucher aux autres appareils présents.
            merged.set(mac, known ? {
              mac,
              deviceKind: incoming.deviceKind || known.deviceKind,
              deviceModel: incoming.deviceModel || known.deviceModel,
              manufacturer: incoming.manufacturer || known.manufacturer,
              androidRelease: incoming.androidRelease || known.androidRelease,
              appVersion: incoming.appVersion || known.appVersion,
            } : incoming);
          }
          return merged;
        });
        setUnavailable(result.failed || !result.complete);
      } catch {
        if (!disposed) setUnavailable(true);
      } finally {
        clearTimeout(timeout);
        pending = null;
        if (!disposed) setLoading(false);
      }
    }

    void load();
    const interval = setInterval(() => { void load(); }, DEVICE_METADATA_REFRESH_MS);
    return () => {
      disposed = true;
      clearInterval(interval);
      pending?.abort();
    };
  }, [key, onLogout]);

  return { devices, loading, unavailable };
}
