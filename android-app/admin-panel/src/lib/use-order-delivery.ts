// Suivi d'UN envoi accepté par le serveur. L'inventaire de la TV peut
// dater d'avant le clic : seul l'accusé de cet order_id confirme l'envoi.
import { useEffect, useState } from 'react';
import { ordersApi } from '@/lib/api';
import { onPanelChannel, onPanelChannelState } from '@/lib/box-channel';
import { DELIVERY_GIVE_UP_MS, DELIVERY_POLL_MS, deliveryStatus, findOrder } from '@/lib/delivery';

export interface OrderDelivery {
  mac: string;
  orderId: string | null;
  startedAt: number;
}

type Status = ReturnType<typeof deliveryStatus>;
type Snapshot = { request: OrderDelivery; status: Status };

function initialStatus(request: OrderDelivery): Status {
  if (!request.orderId?.trim()) {
    return {
      kind: 'late',
      text: 'Envoi enregistré sur le serveur. Application des listes non confirmée : aucun identifiant d’ordre reçu.',
      done: true,
    };
  }
  return deliveryStatus(null);
}

export function useOrderDelivery(request: OrderDelivery | null): Status | null {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);

  useEffect(() => {
    if (!request || !request.orderId?.trim()) return;
    const orderId = request.orderId;
    const mac = request.mac;
    let active = true;
    let finished = false;
    // Ces verrous appartiennent à cet envoi. Le finally d'une ancienne
    // requête ne peut donc pas déverrouiller ou relancer le nouvel envoi.
    let inFlight = false;
    let queued = false;
    let pollTimer: number | undefined;
    let deadlineTimer: number | undefined;

    const clearTimers = () => {
      window.clearTimeout(pollTimer);
      window.clearTimeout(deadlineTimer);
    };
    const publish = (status: Status) => {
      if (!active || finished) return;
      setSnapshot({ request, status });
      if (status.done) {
        finished = true;
        clearTimers();
      }
    };
    const expire = () => publish({
      kind: 'late',
      text: `Application des listes non confirmée. Le suivi s’est arrêté après ${DELIVERY_GIVE_UP_MS / 60_000} minutes.`,
      done: true,
    });
    const remaining = () => DELIVERY_GIVE_UP_MS - (Date.now() - request.startedAt);

    async function refresh() {
      if (!active || finished) return;
      if (remaining() <= 0) { expire(); return; }
      if (inFlight) { queued = true; return; }
      inFlight = true;
      window.clearTimeout(pollTimer);
      try {
        const result = await ordersApi.list(mac);
        if (!active || finished) return;
        const order = findOrder(result.items, orderId);
        // Une réponse partielle sans cet ordre ne retire pas un accusé
        // déjà reçu. Les ordres d'autres envois restent sans effet.
        if (order) publish(deliveryStatus(order));
      } catch {
        // Une panne réseau ne prouve ni réussite ni échec côté box.
        // On garde le dernier accusé connu jusqu'à la prochaine lecture.
      } finally {
        inFlight = false;
        if (!active || finished) return;
        if (remaining() <= 0) { expire(); return; }
        if (queued) {
          queued = false;
          void refresh();
        } else {
          pollTimer = window.setTimeout(() => { void refresh(); }, DELIVERY_POLL_MS);
        }
      }
    }

    const offEvent = onPanelChannel((event) => {
      if (event.mac.toUpperCase() === mac.toUpperCase()) void refresh();
    });
    const offState = onPanelChannelState((connected) => {
      if (connected) void refresh();
    });
    // Ce timer indépendant expire même si une lecture réseau ne répond
    // jamais. Il indique une absence de confirmation, pas un ACK « expired ».
    deadlineTimer = window.setTimeout(expire, Math.max(0, remaining()));
    void refresh();
    return () => {
      active = false;
      clearTimers();
      offEvent();
      offState();
    };
  }, [request]);

  // Dès le rendu du nouvel envoi, l'ancien succès disparaît, sans
  // attendre le nettoyage de l'effet ni la fin de l'ancienne requête.
  if (!request) return null;
  return snapshot?.request === request ? snapshot.status : initialStatus(request);
}
