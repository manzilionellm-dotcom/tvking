// =========================================================
//  MainPage — « Prendre la main », une entrée de menu à elle
// =========================================================
//  POURQUOI CETTE PAGE EXISTE (19/09/2026).
//
//  Le propriétaire a cherché « Prendre la main » TROIS FOIS dans le
//  menu. Captures à l'appui : il ouvre le menu, il descend, il ne
//  trouve pas, il redemande. La fonction existait pourtant — dans la
//  page Téléphone, en bas d'une colonne, derrière plusieurs écrans de
//  défilement sur un mobile.
//
//  J'ai d'abord remonté le bloc sur mobile. Ça ne suffisait pas : il
//  ne cherchait pas DANS une page, il cherchait UNE ENTRÉE. Continuer
//  à lui expliquer où c'est caché aurait été lui demander de s'adapter
//  à mon rangement.
//
//  C'est la règle écrite noir sur blanc dans ce dépôt, à propos de
//  « Changer la MAC » qui s'appelait « Transférer » : UNE
//  FONCTIONNALITÉ QU'ON NE TROUVE PAS N'EXISTE PAS. Elle vaut aussi
//  quand c'est moi qui l'ai rangée.
//
//  ---------------------------------------------------------
//  UNE PAGE, PAS UNE COPIE
//  ---------------------------------------------------------
//  Le bloc lui-même (`PrendreLaMain`) est le MÊME composant que dans
//  Téléphone et Télévision. Cette page n'est qu'une porte d'entrée :
//  une MAC, l'état de l'appareil, et le bloc.
//
//  Le recopier aurait créé deux versions du même panneau, et le jour
//  où l'une gagne un bouton que l'autre n'a pas, le support dépend de
//  la porte par laquelle il est entré. Même raison que
//  DeviceScreenPage, ci/build_label.sh et cloudflare/stream_proxy.js.
// =========================================================

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { ListesAppareil } from '@/components/ListesAppareil';
import { PrendreLaMain } from '@/components/PrendreLaMain';
import { toast } from '@/components/Toast';
import { useLiveDevices } from '@/lib/realtime';
import { formatMacInput } from '@/lib/utils';
import { devicesApi, ApiError, type DeviceOverview } from '@/lib/api';

/// Télé ou téléphone ? Uniquement pour donner sa SILHOUETTE à la
/// maquette tactile (16/9 ou allongée).
///
///  C'EST UNE SUPPOSITION, ET ELLE PEUT SE TROMPER : le modèle remonté
///  par l'appareil est un texte libre, et une tablette ou un mini-PC
///  ne ressemblent ni à l'un ni à l'autre. C'est pour ça que la
///  maquette garde un interrupteur Télé / Téléphone : on propose, on
///  n'impose pas. Se tromper ici ne casse rien — les positions
///  envoyées sont des fractions, pas des pixels.
function silhouetteDe(modele?: string | null): 'tv' | 'phone' {
  const m = (modele || '').toLowerCase();
  const indices = ['tv', 'shield', 'box', 'stick', 'mibox', 'chromecast', 'firetv'];
  return indices.some((i) => m.includes(i)) ? 'tv' : 'phone';
}

export function MainPage({ onLogout }: { onLogout: () => void }) {
  const [sp, setSp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [ov, setOv] = useState<DeviceOverview | null>(null);
  const [charge, setCharge] = useState(false);

  const { devices: live, connected: rtOk } = useLiveDevices();
  const macCourante = ov?.mac || '';
  const enLigne = rtOk && live.some((d) => d.mac === macCourante);

  const ouvrir = useCallback(async (cible: string) => {
    const clef = cible.trim();
    if (clef.length < 8) {
      toast('Colle d’abord la MAC (MK:…)', 'warning');
      return;
    }
    setCharge(true);
    try {
      const fiche = await devicesApi.overview(clef);
      setOv(fiche);
      if (fiche.mac && fiche.mac !== sp.get('mac')) {
        setSp({ mac: fiche.mac }, { replace: true });
      }
    } catch (e) {
      setOv(null);
      toast(
        e instanceof ApiError
          ? e.message
          : 'Aucune fiche pour cette MAC.',
        'error',
      );
    } finally {
      setCharge(false);
    }
  }, [sp, setSp]);

  useEffect(() => {
    const depuisUrl = sp.get('mac');
    if (depuisUrl && depuisUrl.length >= 8) {
      setMac(formatMacInput(depuisUrl));
      void ouvrir(depuisUrl);
    }
    // Une seule fois à l'arrivée.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    void ouvrir(mac);
  }

  return (
    <AppLayout
      onLogout={onLogout}
      title="Prendre la main"
      subtitle="Colle une MAC : tu conduis son application, il regarde son écran."
    >
      <form onSubmit={onSubmit} className="mb-5 flex flex-wrap items-center gap-2">
        <input
          value={mac}
          onChange={(e) => setMac(formatMacInput(e.target.value))}
          placeholder="MK:XX:XX:XX:XX:XX"
          spellCheck={false}
          className="w-64 rounded-lg border border-white/10 bg-obsidian px-3 py-2 font-mono text-sm text-ink-primary outline-none focus:border-accent/50"
        />
        <button
          type="submit"
          disabled={charge}
          className="rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-black disabled:opacity-50"
        >
          {charge ? 'Ouverture…' : 'Ouvrir'}
        </button>
        {ov && (
          <span className="inline-flex items-center gap-2 text-xs text-ink-tertiary">
            <span
              className={
                'h-1.5 w-1.5 rounded-full '
                + (enLigne ? 'animate-pulse bg-success' : 'bg-white/20')
              }
            />
            {enLigne ? 'en ligne' : 'hors ligne'}
            {ov.device?.device_model ? ` · ${ov.device.device_model}` : ''}
            {ov.device?.build_label ? ` · ${ov.device.build_label}` : ''}
          </span>
        )}
      </form>

      {/* L'APPAREIL HORS LIGNE : on le DIT AVANT qu'il clique, pas
          après. Prendre la main suppose que son app tourne — sans ça
          il n'y a personne au bout du fil, et un bouton qui ne répond
          pas ferait croire à une panne du panel. */}
      {ov && !enLigne && (
        <div className="mb-4 max-w-2xl rounded-lg border border-warning/40 bg-warning/10 px-3 py-2 text-xs text-warning">
          <b>Cet appareil est hors ligne.</b> Tu conduis son
          <b> application</b>, pas son téléphone : il faut qu’il ouvre
          7 MOTION pour que quoi que ce soit parte. Demande-lui de la
          lancer, puis reviens — le point passera au vert.
        </div>
      )}

      {ov ? (
        <div className="max-w-2xl">
          <PrendreLaMain
            mac={macCourante}
            enLigne={enLigne}
            forme={silhouetteDe(ov.device?.device_model)}
          />

          {/* =========================================================
               LES LISTES, ICI AUSSI (19/09/2026)
              =========================================================
               « Dans cette option, je dois avoir le secteur de
               supprimer / ajouter la liste. »

               C'est une question de MOMENT : quand on a un client au
               téléphone et qu'on conduit son app, le geste suivant est
               presque toujours « je lui remets sa liste ». L'envoyer
               changer de page pour ça, c'est lui faire perdre le fil —
               et la MAC qu'il vient de coller.

               C'est le MÊME composant que sur Téléphone et Télévision,
               pas une copie : le jour où l'un gagne un bouton, l'autre
               l'a aussi. */}
          <div className="mt-5">
            <ListesAppareil
              mac={macCourante}
              kind={silhouetteDe(ov.device?.device_model) === 'tv' ? 'tv' : 'phone'}
              enLigne={enLigne}
            />
          </div>
        </div>
      ) : (
        <div className="max-w-2xl rounded-xl border border-white/10 bg-obsidian px-4 py-4 text-sm text-ink-secondary">
          <p className="font-semibold text-ink-primary">
            Colle la MAC du client et ouvre-la.
          </p>
          <p className="mt-2">
            Il verra une question sur son écran, avec ton nom. S’il
            accepte, un bandeau rouge reste chez lui pendant toute la
            session — et ce que tu appuies ici bouge vraiment sur son
            appareil.
          </p>
          <p className="mt-2">
            Il peut arrêter à la seconde, et ça se coupe tout seul au
            bout de 30 minutes.
          </p>
        </div>
      )}
    </AppLayout>
  );
}
