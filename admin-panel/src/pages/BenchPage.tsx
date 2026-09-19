// =========================================================
//  BenchPage — « le dernier build tient-il mieux que l'avant-dernier ? »
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) : « Fais l'excellence, et fais
//  un benchmark. »
//
//  ---------------------------------------------------------
//  CE QUE CETTE PAGE CHANGE
//  ---------------------------------------------------------
//  Jusqu'ici, entre « le build est vert » et « un client appelle », il
//  n'y avait rien. Les trois pannes du 18/09 ont toutes été trouvées
//  par le propriétaire, sur du vrai matériel, après coup.
//
//  Et quand ça s'améliorait, on ne pouvait pas le prouver : « la box
//  tient 6 h 40 au lieu de 25 minutes » avait été mesuré à la main,
//  une fois, sur une box.
//
//  Maintenant chaque box note son build toute seule, à partir de sa
//  propre boîte noire, et la note remonte. Cette page les met côte à
//  côte.
//
//  ---------------------------------------------------------
//  TROIS HONNÊTETÉS QUI TIENNENT TOUTE LA PAGE
//  ---------------------------------------------------------
//  1. LA MÉDIANE, PAS LA MOYENNE. Une seule box pourrie — fournisseur
//     en rade, box qui chauffe dans un meuble fermé — tirerait la
//     moyenne vers le bas et ferait condamner un build sain. La médiane
//     dit ce que vit la box TYPIQUE.
//
//  2. LA PIRE NOTE RESTE VISIBLE, juste à côté. « La moitié du parc va
//     bien » ne console pas quand l'autre moitié appelle.
//
//  3. LE NOMBRE DE BOX EST AFFICHÉ, et un build noté par une seule box
//     est signalé comme tel. Comparer 1 box à 30 box, c'est comparer
//     une anecdote à une mesure.
//
//  ---------------------------------------------------------
//  ET CE QUE CETTE PAGE NE PROUVE PAS
//  ---------------------------------------------------------
//  C'est écrit à l'écran, en permanence, même quand tout est vert : le
//  banc lit le journal, il ne regarde pas l'image ; une panne du
//  fournisseur y compte comme une erreur de lecture ; une box ne
//  représente pas le parc. Une note sans ses limites ment par omission
//  — c'est le défaut qui revient le plus souvent dans ce dépôt, et il
//  n'a pas le droit de renaître dans l'outil censé le débusquer.
// =========================================================

import { useCallback, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { toast } from '@/components/Toast';
import { benchApi, ApiError, type BenchBuild } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

/// « 6 h 40 », « 45 min » — comme le propriétaire le dit à voix haute.
/// Même règle que côté app (banc_essai.dart) : jamais « 24012 s ».
function duree(minutes: number): string {
  if (minutes <= 0) return '—';
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m === 0 ? `${h} h` : `${h} h ${m}`;
}

/// « 1,8 s » — le temps jusqu'à la première image, comme on le dit.
/// Sous la seconde on garde deux décimales (« 0,85 s ») : c'est là que
/// les bons builds se départagent.
function secondes(ms: number): string {
  const s = ms / 1000;
  return `${(s < 1 ? s.toFixed(2) : s.toFixed(1)).replace('.', ',')} s`;
}

/// La couleur d'une note. Les seuils sont ceux du banc (`bon` ≥ 80).
function ton(note: number): string {
  if (note >= 90) return 'text-success';
  if (note >= 80) return 'text-accent-bright';
  if (note >= 50) return 'text-warning';
  return 'text-red-300';
}

export function BenchPage({ onLogout }: { onLogout: () => void }) {
  const [builds, setBuilds] = useState<BenchBuild[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [charge, setCharge] = useState(true);

  const charger = useCallback(async () => {
    setCharge(true);
    try {
      const r = await benchApi.list();
      setBuilds(r.builds ?? []);
      setErr(null);
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Lecture impossible.');
      setBuilds(null);
    } finally {
      setCharge(false);
    }
  }, []);

  useEffect(() => { void charger(); }, [charger]);

  //  LA COMPARAISON, EN UNE PHRASE. C'est ce que le propriétaire vient
  //  chercher : il ne veut pas lire un tableau, il veut savoir si son
  //  dernier build est meilleur.
  let verdict: string | null = null;
  if (builds && builds.length >= 2) {
    const [neuf, vieux] = builds;
    const ecart = neuf.note_mediane - vieux.note_mediane;
    if (neuf.boxes < 3) {
      verdict = `Le build ${neuf.build} n'a été noté que par `
        + `${neuf.boxes} box : trop peu pour conclure. Laisse-en tourner `
        + 'quelques-unes une nuit.';
    } else if (ecart >= 5) {
      verdict = `Le build ${neuf.build} tient MIEUX que le ${vieux.build} `
        + `(${neuf.note_mediane} contre ${vieux.note_mediane}).`;
    } else if (ecart <= -5) {
      verdict = `⚠ Le build ${neuf.build} tient MOINS BIEN que le `
        + `${vieux.build} (${neuf.note_mediane} contre `
        + `${vieux.note_mediane}). Regarde ce qui a changé entre les deux.`;
    } else {
      verdict = `Le build ${neuf.build} se comporte comme le `
        + `${vieux.build} (${neuf.note_mediane} contre `
        + `${vieux.note_mediane}) — l'écart n'est pas significatif.`;
    }
  }

  return (
    <AppLayout
      onLogout={onLogout}
      title="Banc d'essai"
      subtitle="Chaque box note son build toute seule. Ici, ils se comparent."
      actions={
        <button
          type="button"
          onClick={() => { void charger(); }}
          disabled={charge}
          className="rounded-lg border border-white/10 px-3 py-1.5 text-xs disabled:opacity-50"
        >
          {charge ? 'Lecture…' : 'Rafraîchir'}
        </button>
      }
    >
      {err && (
        <div className="mb-4 rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-200">
          {err}
        </div>
      )}

      {verdict && (
        <div className="mb-5 rounded-xl border border-white/10 bg-midnight px-4 py-3">
          <p className="text-sm font-semibold">{verdict}</p>
        </div>
      )}

      {/* PAS ENCORE DE DONNÉES ≠ PANNE. Une table vide le premier jour
          est normale : aucune box n'a encore tenu une heure sur un
          build qui sait envoyer sa note. On le dit, au lieu de laisser
          un écran vide qui fait croire à un bug. */}
      {!charge && builds && builds.length === 0 && (
        <div className="max-w-2xl rounded-xl border border-white/10 bg-obsidian px-4 py-4 text-sm text-ink-secondary">
          <p className="font-semibold text-ink-primary">
            Aucune note pour l’instant — et c’est normal au début.
          </p>
          <p className="mt-2">
            Une box n’envoie sa note qu’après <b>une heure</b> d’affilée :
            trois minutes sans incident ne prouvent rien, et un « 100/100 »
            de complaisance ferait republier par-dessus un vrai défaut.
          </p>
          <p className="mt-2">
            Il faut aussi qu’elle tourne un build qui sait la calculer —
            les versions d’avant le 18/09 ne le font pas. Laisse une box
            allumée une nuit et reviens.
          </p>
        </div>
      )}

      {builds && builds.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-white/10">
          <table className="min-w-full text-left text-sm">
            <thead className="bg-midnight text-xs uppercase tracking-wider text-ink-tertiary">
              <tr>
                <th className="px-4 py-3">Build</th>
                <th className="px-4 py-3">Note (box typique)</th>
                <th className="px-4 py-3">Pire / meilleure</th>
                <th className="px-4 py-3">1ʳᵉ image</th>
                <th className="px-4 py-3">Box</th>
                <th className="px-4 py-3">Plus longue session</th>
                <th className="px-4 py-3">Ce qui cloche</th>
                <th className="px-4 py-3">Vu le</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {builds.map((b) => (
                <tr key={b.build} className="bg-obsidian hover:bg-midnight">
                  <td className="px-4 py-3 font-mono font-semibold">{b.build}</td>
                  <td className={'px-4 py-3 text-lg font-bold ' + ton(b.note_mediane)}>
                    {b.note_mediane}
                    <span className="ml-1 text-xs font-normal text-ink-tertiary">
                      /100
                    </span>
                  </td>
                  <td className="px-4 py-3 text-xs text-ink-secondary">
                    <span className={ton(b.note_pire)}>{b.note_pire}</span>
                    {' / '}
                    <span className={ton(b.note_meilleure)}>{b.note_meilleure}</span>
                  </td>
                  {/* TEMPS JUSQU'À LA 1re IMAGE — le « temps de chargement
                      des chaînes » du banc de la famille, MESURÉ sur les
                      box (médiane des médianes). « — » = aucune box n'a
                      lu quelque chose sur ce build : pas un zéro. */}
                  <td className="px-4 py-3 font-mono">
                    {b.ttff_mediane != null ? (
                      <>
                        <span className={b.ttff_mediane <= 2500 ? 'text-success' : b.ttff_mediane <= 5000 ? 'text-warning' : 'text-red-300'}>
                          {secondes(b.ttff_mediane)}
                        </span>
                        {b.ttff_boxes < 3 && (
                          <span className="ml-1 text-[10px] text-ink-tertiary">
                            ({b.ttff_boxes} box)
                          </span>
                        )}
                      </>
                    ) : (
                      <span className="text-ink-tertiary">—</span>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    {b.boxes}
                    {/* Un build noté par une ou deux box est une
                        anecdote, pas une mesure. On le DIT plutôt que
                        de laisser comparer un chiffre solide à un
                        chiffre fragile. */}
                    {b.boxes < 3 && (
                      <span className="ml-2 rounded bg-warning/20 px-1.5 py-0.5 text-[10px] text-warning">
                        trop peu
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-ink-secondary">
                    {duree(b.minutes_max)}
                  </td>
                  <td className="px-4 py-3 text-xs text-ink-secondary">
                    <Griefs b={b} />
                  </td>
                  <td className="px-4 py-3 text-xs text-ink-tertiary">
                    {b.vu_le ? formatDateTime(b.vu_le) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* LES LIMITES, TOUJOURS AFFICHÉES — même quand tout est vert. */}
      <div className="mt-5 max-w-3xl rounded-xl border border-white/10 bg-obsidian px-4 py-3 text-xs leading-relaxed text-ink-tertiary">
        <p className="font-semibold text-ink-secondary">
          Ce que cette note ne prouve pas
        </p>
        <ul className="mt-2 space-y-1">
          <li>
            • Le banc lit le <b>journal</b> de l’app : il ne regarde pas
            l’écran. Ni l’image ni le son ne sont notés.
          </li>
          <li>
            • Une panne du <b>fournisseur</b> y compte comme une erreur de
            lecture. Une mauvaise note peut donc venir de sa ligne, pas de
            l’app — recoupe avec le panneau Téléphone ou Télévision.
          </li>
          <li>
            • Une box ne représente pas le parc : un modèle qui va bien ne
            dit rien des box à faible mémoire. D’où la colonne « Box ».
          </li>
          <li>
            • Un <b>crash</b> et un <b>refus du verrou d’écran</b> pèsent
            lourd même une seule fois : le premier vide le salon, le second
            garantit un écran noir plus tard.
          </li>
          <li>
            • La <b>1ʳᵉ image</b> est la médiane des box, chaque box
            comptant pour une voix. Elle ne pèse pas dans la note : c’est
            une mesure, pas un reproche — sous 2,5 s c’est bon, au-delà de
            5 s le client le sent.
          </li>
        </ul>
      </div>
    </AppLayout>
  );
}

/// Les pannes de ce build, dites avec leurs chiffres — et seulement
/// celles qui sont arrivées. Une liste de zéros n'apprend rien.
function Griefs({ b }: { b: BenchBuild }) {
  const items: string[] = [];
  if (b.crashs > 0) items.push(`${b.crashs} crash${b.crashs > 1 ? 's' : ''}`);
  if (b.verrou_ko > 0) items.push(`${b.verrou_ko} verrou refusé`);
  if (b.nostart > 0) items.push(`${b.nostart} chaîne(s) jamais démarrée(s)`);
  if (b.gels > 0) items.push(`${b.gels} gel(s)`);
  if (b.lecture > 0) items.push(`${b.lecture} erreur(s) de lecture`);
  if (b.mem > 0) items.push(`${b.mem} purge(s) mémoire`);
  if (items.length === 0) {
    return <span className="text-success">rien à signaler</span>;
  }
  return <span>{items.join(' · ')}</span>;
}
