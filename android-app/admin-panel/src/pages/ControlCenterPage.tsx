import { Link } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';

/// Page « Centre de contrôle » — hub qui présente les 10 modules du
/// pilotage temps réel de l'app (cf. docs/centre-de-controle.md).
/// Les modules ACTIFS sont cliquables ; les autres affichent leur phase.
/// 100 % panel : cette page ne touche en rien au moteur de cast.

type Status = 'active' | 'partial' | 'soon';
interface Mod {
  n: number;
  emoji: string;
  title: string;
  desc: string;
  status: Status;
  to?: string;
  phase?: string;
}

const MODULES: Mod[] = [
  { n: 1, emoji: '🏠', title: 'Accueil dynamique', status: 'active', to: '/home-manager',
    desc: 'Ordre, visibilité, rubans et vedette des sections — en direct.' },
  { n: 8, emoji: '🎛️', title: 'Live Control', status: 'active', to: '/home-manager',
    desc: 'Activer / masquer / réordonner une section instantanément.' },
  { n: 4, emoji: '📣', title: 'Annonces & Notifications', status: 'active', to: '/notifications',
    desc: 'Nouveautés, promos, infos — diffusées à tous ou ciblées par pays.' },
  { n: 5, emoji: '📊', title: 'Analytics — En ligne', status: 'active', to: '/online',
    desc: 'Utilisateurs connectés, pays et IP en temps réel.' },
  { n: 10, emoji: '🛡️', title: 'Admin Experience', status: 'partial', phase: 'En partie',
    desc: 'Multilingue, dark mode, historique des modifications (rollback).' },
  { n: 11, emoji: '⬆️', title: 'Mise à jour forcée', status: 'active', to: '/force-update',
    desc: 'Oblige tous les utilisateurs à installer la dernière version.' },
  { n: 2, emoji: '🖼️', title: 'Bannières', status: 'soon', phase: 'Phase 2',
    desc: 'Carrousel image / vidéo, dates de diffusion, bouton et lien.' },
  { n: 3, emoji: '🎨', title: 'Thèmes dynamiques', status: 'soon', phase: 'Phase 3',
    desc: 'Couleurs, logos, presets (Gold, Platinum, World Cup, Noël…).' },
  { n: 6, emoji: '⭐', title: 'Favori du jour', status: 'active', to: '/featured',
    desc: 'Mets une chaîne en avant chaque jour (HERO de l\'accueil).' },
  { n: 7, emoji: '⚙️', title: 'Automatisation', status: 'soon', phase: 'Phase 5',
    desc: '« Si Coupe du Monde → Sport #1 », « si décembre → thème Noël ».' },
  { n: 9, emoji: '🧪', title: 'A/B Testing', status: 'soon', phase: 'Phase 5',
    desc: 'Tester accueils, couleurs, bannières — mesurer clics / conversion.' },
];

function StatusChip({ m }: { m: Mod }) {
  if (m.status === 'active') {
    return (
      <span className="rounded-full border border-success/40 bg-success/10 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-success">
        Actif
      </span>
    );
  }
  if (m.status === 'partial') {
    return (
      <span className="rounded-full border border-amber-400/40 bg-amber-400/10 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-amber-300">
        {m.phase ?? 'Partiel'}
      </span>
    );
  }
  return (
    <span className="rounded-full border border-white/10 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-ink-tertiary">
      {m.phase ?? 'Bientôt'}
    </span>
  );
}

function Card({ m }: { m: Mod }) {
  const inner = (
    <div
      className={`flex h-full flex-col gap-2 rounded-xl border bg-midnight p-4 transition ${
        m.to
          ? 'border-white/5 hover:border-accent/40 hover:bg-white/[0.03]'
          : 'border-white/5 opacity-80'
      }`}
    >
      <div className="flex items-start justify-between gap-2">
        <span className="text-2xl leading-none">{m.emoji}</span>
        <StatusChip m={m} />
      </div>
      <div className="text-sm font-semibold text-ink-primary">{m.title}</div>
      <div className="text-xs leading-relaxed text-ink-secondary">{m.desc}</div>
      {m.to && (
        <div className="mt-auto pt-1 text-[11px] font-semibold text-accent-bright">
          Ouvrir →
        </div>
      )}
    </div>
  );
  return m.to ? (
    <Link to={m.to} className="block h-full">{inner}</Link>
  ) : (
    <div className="h-full">{inner}</div>
  );
}

export function ControlCenterPage({ onLogout }: { onLogout: () => void }) {
  const active = MODULES.filter((m) => m.status === 'active').length;
  return (
    <AppLayout
      title="Centre de contrôle"
      subtitle="Pilote toute l'app en temps réel — sans mise à jour du Play Store / App Store"
      onLogout={onLogout}
    >
      <div className="mb-5 rounded-xl border border-accent/20 bg-accent/[0.06] px-4 py-3 text-xs text-ink-secondary">
        <span className="font-semibold text-ink-primary">{active} modules actifs</span>{' '}
        sur {MODULES.length}. Les modifications sont instantanées et réversibles.
        Les modules « Bientôt » arrivent par phases (voir la feuille de route).
      </div>

      <div className="grid auto-rows-fr gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {MODULES.map((m) => (
          <Card key={m.n} m={m} />
        ))}
      </div>
    </AppLayout>
  );
}
