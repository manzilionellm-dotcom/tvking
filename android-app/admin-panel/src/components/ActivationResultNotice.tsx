import { Link } from 'react-router-dom';
import { type ActivateResult } from '@/lib/api';
import { activationResultText } from '@/lib/activation';
import { formatDateTime } from '@/lib/utils';
import { NovatubeReassociation } from './NovatubeReassociation';

/** Le POST confirme la licence en base, pas sa réception sur la box.
 * Le diagnostic NovaTube reste une lecture authentifiée séparée. Une clé
 * différente exige toujours le code physique et l'approbation du propriétaire.
 */
export function ActivationResultNotice({ result, plan, showDeviceLink = true }: {
  result: ActivateResult; plan: string; showDeviceLink?: boolean;
}) {
  return (
    <section className="mt-4 rounded-xl border border-white/10 bg-white/[.02] px-4 py-3" aria-label="Résultat de l’activation">
      <p className="text-sm text-success" role="status">Licence enregistrée sur le serveur. {activationResultText(plan, result, formatDateTime)}</p>
      <p className="mt-2 text-xs leading-relaxed text-ink-secondary">La réception par l’application n’est pas encore confirmée. Laisse l’application ouverte et connectée pour sa prochaine vérification.</p>
      <NovatubeReassociation mac={result.mac} />
      {showDeviceLink && <Link to={`/devices?mac=${encodeURIComponent(result.mac)}`} className="mt-3 inline-block text-sm font-medium text-accent-bright underline-offset-2 hover:underline">Vérifier la fiche de l’appareil</Link>}
    </section>
  );
}
