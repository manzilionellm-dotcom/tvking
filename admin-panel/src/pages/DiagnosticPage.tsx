import { FormEvent, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { ScanReport } from '@/components/DeviceOps';
import { toast } from '@/components/Toast';
import { devicesApi, ApiError, type DeviceScanResult } from '@/lib/api';
import { formatMacInput } from '@/lib/utils';

// =========================================================
//  DiagnosticPage — « l'app ne marche pas, dis-moi pourquoi »
// =========================================================
//  Demande du propriétaire : une OPTION dans le panel. On colle une MAC,
//  le serveur lit licence, playlist (il la SONDE vraiment), version,
//  présence, journaux — et DIT en français ce qui cloche + quoi faire.
//  N'invente aucune mutation : lecture seule, même scan que le bouton
//  de la fiche 360°.
// =========================================================

export function DiagnosticPage({ onLogout }: { onLogout: () => void }) {
  const [sp, setSp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [busy, setBusy] = useState(false);
  const [scan, setScan] = useState<DeviceScanResult | null>(null);

  async function run(target = mac) {
    const key = target.trim();
    if (key.length < 8) {
      toast('Colle d’abord la MAC (MK:…)', 'warning');
      return;
    }
    setBusy(true);
    setScan(null);
    try {
      const r = await devicesApi.scan(key);
      setScan(r);
      if (r.verdict === 'ok') toast(r.summary, 'success');
      else toast(r.summary, r.verdict === 'critique' ? 'error' : 'warning');
      if (r.mac && r.mac !== sp.get('mac')) {
        setSp({ mac: r.mac }, { replace: true });
      }
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Scan impossible.', 'error');
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    const fromUrl = sp.get('mac');
    if (fromUrl && fromUrl.length >= 8) {
      setMac(formatMacInput(fromUrl));
      void run(fromUrl);
    }
    // Une seule fois à l'arrivée, pas à chaque frappe.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    void run();
  }

  const tone = scan?.verdict === 'critique'
    ? 'border-red-500/40 bg-red-500/10'
    : scan?.verdict === 'probleme'
      ? 'border-amber-500/40 bg-amber-500/10'
      : scan?.verdict === 'ok'
        ? 'border-emerald-500/30 bg-emerald-500/10'
        : 'border-white/10 bg-midnight';

  return (
    <AppLayout
      title="Diagnostic"
      subtitle="L’app ne marche pas ? Colle la MAC — le panel scanne tout et te dit ce qui cloche."
      onLogout={onLogout}
    >
      <div className="mx-auto max-w-2xl space-y-5">
        <form
          onSubmit={onSubmit}
          className="rounded-2xl border border-sky-400/25 bg-sky-400/[0.06] p-5"
        >
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            Adresse MAC
          </label>
          <div className="flex flex-col gap-3 sm:flex-row">
            <input
              value={mac}
              onChange={(e) => setMac(formatMacInput(e.target.value))}
              autoFocus
              maxLength={17}
              placeholder="MK:1A:2B:3C:4D:5E"
              className="w-full rounded-md border border-white/10 bg-obsidian px-3 py-2.5 font-mono text-sm outline-none focus:ring-1 focus:ring-sky-400"
            />
            <button
              type="submit"
              disabled={busy}
              className="shrink-0 rounded-md bg-sky-500 px-4 py-2.5 text-sm font-semibold text-black hover:bg-sky-400 disabled:opacity-40"
            >
              {busy ? 'Scan en cours…' : 'Scanner les erreurs'}
            </button>
          </div>
          <p className="mt-2 text-[11px] text-ink-tertiary">
            On lit l’abonnement, on tape vraiment le lien M3U, on croise la version
            et les journaux de l’appareil. Rien n’est modifié.
          </p>
        </form>

        {scan && (
          <div className={`rounded-2xl border p-5 ${tone}`}>
            <p className="font-mono text-xs text-accent">{scan.mac}</p>
            <p className="mt-1 text-base font-semibold">
              {scan.verdict === 'ok' && 'RAS côté serveur'}
              {scan.verdict === 'probleme' && 'Problème détecté'}
              {scan.verdict === 'critique' && 'Ça bloque'}
            </p>
            <p className="mt-1 text-sm text-ink-secondary">{scan.summary}</p>
            <div className="mt-4">
              <ScanReport scan={scan} />
            </div>
          </div>
        )}

        {!scan && !busy && (
          <p className="text-sm text-ink-tertiary">
            Exemple : un client dit « pas d’image ». Tu colles sa MAC, le panel
            te dit si c’est l’abo, le M3U mort, l’app trop vieille, ou le Wi-Fi.
          </p>
        )}
      </div>
    </AppLayout>
  );
}
