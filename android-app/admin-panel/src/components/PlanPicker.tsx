// =========================================================
//  PlanPicker — le choix de durée, identique partout
// =========================================================
//  Deux rangées étiquetées : « Essai gratuit » puis « Abonnement payé ».
//  Le coût en crédits s'affiche sous chaque abonnement pour un revendeur.
//  Catalogue : src/lib/activation.ts (une seule source).
// =========================================================
import { PAID_PLANS, TRIAL_PLANS, planCost, type PlanOption } from '@/lib/activation';

type Props = {
  value: string;
  onChange: (plan: string) => void;
  costs: { plan: string; credits: number }[];
  showCosts: boolean;
};

export function PlanPicker({ value, onChange, costs, showCosts }: Props) {
  return (
    <div className="space-y-4">
      <PlanRow
        title="Essai gratuit"
        options={TRIAL_PLANS}
        value={value}
        onChange={onChange}
        cols="grid-cols-4"
        sub={() => 'Gratuit'}
      />
      <PlanRow
        title="Abonnement payé"
        options={PAID_PLANS}
        value={value}
        onChange={onChange}
        cols="grid-cols-3 sm:grid-cols-5"
        sub={(id) => {
          if (!showCosts) return null;
          const c = planCost(id, costs);
          return c === null ? null : `${c} crédit${c > 1 ? 's' : ''}`;
        }}
      />
    </div>
  );
}

function PlanRow({
  title, options, value, onChange, cols, sub,
}: {
  title: string;
  options: PlanOption[];
  value: string;
  onChange: (plan: string) => void;
  cols: string;
  sub: (id: string) => string | null;
}) {
  return (
    <div>
      <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-ink-secondary">{title}</p>
      <div className={`grid gap-2 ${cols}`} role="radiogroup" aria-label={title}>
        {options.map((p) => {
          const selected = value === p.id;
          const s = sub(p.id);
          return (
            <button
              type="button"
              key={p.id}
              role="radio"
              aria-checked={selected}
              onClick={() => onChange(p.id)}
              className={
                'rounded-xl border px-2 py-3 text-center transition ' +
                (selected
                  ? 'border-accent bg-accent/15 text-ink-primary'
                  : 'border-white/10 bg-midnight text-ink-secondary hover:border-white/25')
              }
            >
              <span className="block text-base font-semibold leading-tight">{p.label}</span>
              {s && <span className="mt-0.5 block text-[11px] text-ink-tertiary">{s}</span>}
            </button>
          );
        })}
      </div>
    </div>
  );
}
