import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { familiesApi, ApiError, type Family, type FamilyMember } from '@/lib/api';

// Lecture seule. On ne crée plus de famille ni de membre.
// Les appareils déjà enregistrés restent visibles ici, et leur
// licence continue de fonctionner côté serveur.

export function FamiliesPage({ onLogout }: { onLogout: () => void }) {
  const [families, setFamilies] = useState<Family[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [members, setMembers] = useState<FamilyMember[]>([]);
  const [name, setName] = useState('');
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    familiesApi.list()
      .then((r) => setFamilies(r.items))
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        setErr(e instanceof ApiError ? e.message : 'Erreur.');
      });
  }, [onLogout]);

  function open(id: string, label: string) {
    setSelected(id);
    setName(label);
    setErr(null);
    familiesApi.get(id)
      .then((r) => setMembers(r.members))
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        setErr(e instanceof ApiError ? e.message : 'Erreur.');
      });
  }

  return (
    <AppLayout
      title="Familles déjà créées"
      subtitle="Lecture seule. On n’en crée plus. Les appareils déjà activés restent valides."
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
          {err}
        </div>
      )}
      <div className="mx-auto grid w-full max-w-3xl gap-4 sm:grid-cols-2">
        <div className="rounded-xl border border-white/10 bg-midnight p-4">
          {families.length === 0 && (
            <p className="text-sm text-ink-secondary">Aucune famille enregistrée.</p>
          )}
          <div className="space-y-2">
            {families.map((f) => (
              <button
                key={f.id}
                type="button"
                onClick={() => open(f.id, f.name)}
                className={
                  'flex w-full items-center justify-between rounded-lg border px-3 py-2 text-left text-sm ' +
                  (selected === f.id
                    ? 'border-accent bg-accent/10 text-ink-primary'
                    : 'border-white/10 text-ink-secondary')
                }
              >
                <span>{f.name}</span>
                <span className="text-xs text-ink-tertiary">{f.member_count ?? 0}</span>
              </button>
            ))}
          </div>
        </div>
        <div className="rounded-xl border border-white/10 bg-obsidian p-4">
          {!selected && (
            <p className="text-sm text-ink-secondary">Choisis une famille pour voir ses appareils.</p>
          )}
          {selected && (
            <div className="space-y-2">
              <h2 className="text-base font-semibold">{name}</h2>
              {members.length === 0 && (
                <p className="text-sm text-ink-secondary">Aucun appareil.</p>
              )}
              {members.map((m) => (
                <p key={m.mac} className="font-mono text-sm text-ink-primary">
                  {m.mac}{m.label ? ` · ${m.label}` : ''}
                </p>
              ))}
            </div>
          )}
        </div>
      </div>
    </AppLayout>
  );
}
