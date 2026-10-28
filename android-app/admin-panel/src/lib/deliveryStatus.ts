// « Écrit sur le serveur » n'est pas « appliqué sur l'appareil ».
// Seul l'accusé de CET ordre et de SA révision autorise la confirmation.
export interface DeliveryOrder {
  order_id: string;
  kind: string;
  state: string;
  config_rev?: number | null;
  applied_rev?: number | null;
  received_srv?: number | null;
  applied_srv?: number | null;
  created_at?: number;
}
export function deliveryConfirmed(order?: DeliveryOrder): boolean {
  return order?.state === 'applied' && (order.config_rev == null ||
    (order.applied_rev != null && order.applied_rev >= order.config_rev));
}
export function deliveryLabel(order?: DeliveryOrder): string {
  if (!order) return 'En attente de confirmation';
  if (order.state === 'applied') {
    if (order.config_rev != null && (order.applied_rev == null || order.applied_rev < order.config_rev)) {
      return 'Reçu — révision de la liste non confirmée';
    }
    return 'Appliqué sur l’appareil';
  }
  if (order.state === 'failed') return 'Reçu — application en échec';
  if (order.state === 'received') return 'Reçu — application en cours';
  if (order.state === 'expired') return 'Confirmation non reçue — vérifiez la connexion de l’appareil';
  return 'Enregistré — en attente de l’appareil';
}
export function resolvePanelApiBase(configured: string | undefined, production: boolean): string {
  // Vite conserve son proxy local ; le panel Vercel parle au même Worker
  // que les apps, même si VITE_API_BASE n'a pas été renseignée.
  return (configured?.trim() || (production ? 'https://api.zuno8k.com' : '')).replace(/\/+$/, '');
}
