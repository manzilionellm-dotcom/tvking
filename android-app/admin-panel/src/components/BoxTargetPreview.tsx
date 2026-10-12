import { useEffect, useState } from 'react';
import { ApiError, devicesApi } from '@/lib/api';
import { describeBoxTarget, sameBoxTarget, type BoxTargetDescription } from '@/lib/box-target';
import { formatDateTime, isValidMac, normalizeMac } from '@/lib/utils';

// Le modèle et le code sont visibles avant l'envoi. Aucun code proche
// ne devient automatiquement le destinataire à la place du code saisi.
export function BoxTargetPreview({ mac }: { mac: string }) {
  const normalized = normalizeMac(mac);
  const [info, setInfo] = useState<BoxTargetDescription | null>(null);
  const [unavailable, setUnavailable] = useState<{ mac: string; text: string } | null>(null);

  useEffect(() => {
    setInfo(null);
    setUnavailable(null);
    if (!isValidMac(normalized)) return;
    let active = true;
    const abort = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const result = await devicesApi.list(normalized, { limit: 100, offset: 0 }, abort.signal);
        if (active) setInfo(describeBoxTarget(normalized, result.items ?? []));
      } catch (e) {
        if (active && !abort.signal.aborted) {
          setUnavailable({ mac: normalized, text: e instanceof ApiError && e.status === 403
            ? 'Informations appareil non accessibles avec ce compte.'
            : 'Identification de l’appareil indisponible.' });
        }
      }
    }, 400);
    return () => { active = false; clearTimeout(timer); abort.abort(); };
  }, [normalized]);

  if (!isValidMac(normalized)) return null;
  const current = info && sameBoxTarget(info.mac, normalized) ? info : null;
  const error = unavailable && sameBoxTarget(unavailable.mac, normalized) ? unavailable.text : null;
  return (
    <aside aria-label="Destination de l’envoi" className="space-y-1 rounded-lg border border-white/10 bg-midnight px-3 py-2 text-sm">
      <p className="text-ink-secondary">Destination : <strong className="font-mono text-ink-primary">{normalized}</strong></p>
      {current?.kind === 'reported' && (
        <p className="text-ink-secondary">
          {current.model ?? 'Appareil identifié'}
          {current.lastSeen != null && <> · Dernière vue : {formatDateTime(current.lastSeen)}</>}
        </p>
      )}
      {current?.kind === 'unidentified' && (
        <p className="text-warning">Ce code n’a transmis ni modèle ni version de l’app. Vérifie le code affiché sur la télé.</p>
      )}
      {current?.kind === 'missing' && (
        <p className="text-warning">Aucun appareil enregistré sous ce code. Vérifie le code affiché sur la télé.</p>
      )}
      {error && <p className="text-ink-tertiary">{error} Vérifie le code affiché sur l’appareil.</p>}
    </aside>
  );
}
