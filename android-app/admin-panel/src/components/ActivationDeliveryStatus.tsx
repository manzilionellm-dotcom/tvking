import { useEffect, useState } from 'react';
import { ApiError, deliveryApi, type ActivationDelivery } from '@/lib/api';
import { deliveryConfirmed, deliveryLabel, type DeliveryOrder } from '@/lib/deliveryStatus';
import { subscribePanel } from '@/lib/panelRealtime';

export function ActivationDeliveryStatus({ mac, licenseOrder, sourceOrder, trace, manualSources }: {
  mac: string;
  licenseOrder?: string | null;
  sourceOrder?: string | null;
  trace?: string | null;
  manualSources: boolean;
}) {
  const [orders, setOrders] = useState<DeliveryOrder[]>([]);
  const [provider, setProvider] = useState<ActivationDelivery | null>(null);
  const [unavailable, setUnavailable] = useState(false);
  const [expired, setExpired] = useState(false);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    let closed = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let controller: AbortController | undefined;
    let finished = false;
    let inFlight = false;
    let preparationState: ActivationDelivery | null = null;
    const deadline = Date.now() + 5 * 60_000;
    setExpired(false);
    async function poll() {
      if (closed || inFlight) return;
      if (Date.now() >= deadline) { setExpired(true); return; }
      // Un onglet caché ne martèle pas le serveur ; le retour relit sous 1 s.
      if (document.visibilityState === 'hidden') { timer = setTimeout(poll, 1000); return; }
      controller = new AbortController();
      inFlight = true;
      const timeout = setTimeout(() => controller?.abort(), 8000);
      try {
        const [receipt, preparation] = await Promise.allSettled([
          deliveryApi.orders(mac, controller.signal),
          trace && !manualSources ? deliveryApi.activation(mac, trace, controller.signal) : Promise.resolve(null),
        ]);
        if (closed) return;
        if (receipt.status === 'fulfilled') {
          setOrders(receipt.value.items);
          setUnavailable(false);
        } else {
          setUnavailable(true);
          if (receipt.reason instanceof ApiError && receipt.reason.status === 401) { finished = true; return; }
        }
        if (preparation.status === 'fulfilled') {
          preparationState = preparation.value;
          setProvider(preparation.value);
        }
        if (receipt.status === 'fulfilled') {
          const rows = receipt.value.items;
          const licenseDone = deliveryConfirmed(rows.find(row => row.order_id === licenseOrder));
          const listDone = deliveryConfirmed(rows.find(row => row.order_id === (sourceOrder || preparationState?.order_id)));
          finished = licenseDone && (manualSources ? listDone : listDone ||
            ['renewed', 'skipped', 'failed'].includes(preparationState?.stage || ''));
        }
      } finally {
        clearTimeout(timeout);
        inFlight = false;
        if (!closed && !finished) timer = setTimeout(poll, 5000);
      }
    }
    const unsubscribe = subscribePanel(event => {
      if (event.mac !== mac || event.type !== 'receipt' || !event.order_id || !event.state || !event.kind) return;
      const received = event as DeliveryOrder;
      setOrders(previous => [...previous.filter(row => row.order_id !== received.order_id), received]);
      setUnavailable(false);
      clearTimeout(timer);
      void poll();
    });
    void poll();
    return () => { closed = true; clearTimeout(timer); controller?.abort(); unsubscribe(); };
  }, [mac, trace, licenseOrder, sourceOrder, manualSources, refresh]);

  const license = orders.find(order => order.order_id === licenseOrder);
  const list = orders.find(order => order.order_id === (sourceOrder || provider?.order_id));
  return (
    <div className="space-y-2 rounded-lg border border-white/10 bg-slate/40 p-3" role="status" aria-live="polite">
      <p className="font-semibold">Réception sur l’appareil</p>
      <p>Licence : {deliveryLabel(license)}</p>
      {manualSources && <p>Liste : {sourceOrder ? deliveryLabel(list) : 'envoi au serveur non terminé'}</p>}
      {!manualSources && <p>{provider?.stage === 'source_saved'
        ? `Liste : ${deliveryLabel(list)}`
        : provider?.message || 'Préparation de la ligne : confirmation indisponible.'}</p>}
      {unavailable && <p className="text-accent-bright">Suivi momentanément indisponible. L’activation enregistrée est conservée.</p>}
      {expired && <button type="button" onClick={() => setRefresh(value => value + 1)} className="text-accent-bright underline">Relire les confirmations</button>}
      <p className="text-xs text-ink-tertiary">L’app doit être ouverte et connectée. La réception de l’ordre et le chargement des chaînes sont deux étapes distinctes.</p>
    </div>
  );
}
