// =========================================================
//  ChannelPlayer — lire la chaîne du client depuis le panel
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) :
//
//    « Je dois avoir accès à toute l'app du téléphone, même faire play
//      à tous. »
//
//  ---------------------------------------------------------
//  POURQUOI ÇA NE PEUT PAS ÊTRE UNE SIMPLE BALISE <video>
//  ---------------------------------------------------------
//  Un flux Xtream en direct est du MPEG-TS (`…/42.ts`). AUCUN
//  navigateur ne sait lire ça nativement — `<video src="….ts">` reste
//  noir, sans erreur exploitable. Il faut un démultiplexeur en
//  JavaScript : mpegts.js, exactement celui que le récepteur Cast du
//  projet utilise déjà.
//
//  ET IL Y A UN SECOND MUR : le panel est en HTTPS, le fournisseur est
//  presque toujours en HTTP simple. Le navigateur refuse alors de
//  charger le flux (contenu mixte), et là encore sans rien dire de
//  clair. D'où le relais `/cast-proxy` — même origine, HTTPS, CORS
//  ouvert — qui existait déjà pour le Cast et qu'on réutilise.
//
//  On ne réinvente donc NI le démultiplexeur NI le relais : les deux
//  sont en production depuis des mois, sur le même genre de flux.
//
//  ---------------------------------------------------------
//  LA LIBRAIRIE VIENT DU WORKER, PAS D'UN CDN
//  ---------------------------------------------------------
//  `/vendor/mpegts.js` sert une version ÉPINGLÉE, mise en cache par le
//  Worker. C'est le même chemin que le récepteur Cast utilise, et pour
//  la même raison : si le CDN est lent ou bloqué, tout le chemin
//  MPEG-TS meurt. Un `<script>` chargé à la demande — pas une
//  dépendance npm — pour que le panel ne grossisse pas de 200 ko pour
//  une fonction qu'on n'ouvre qu'en dépannage.
// =========================================================

import { useEffect, useRef, useState } from 'react';
import { API_BASE, devicesApi, ApiError } from '@/lib/api';

/// mpegts.js pose son objet sur `window`. On ne le charge qu'une fois
/// par session, et on garde la promesse pour que deux ouvertures
/// rapprochées ne lancent pas deux `<script>`.
let chargementMpegts: Promise<unknown> | null = null;

function chargerMpegts(): Promise<unknown> {
  const w = window as unknown as { mpegts?: unknown };
  if (w.mpegts) return Promise.resolve(w.mpegts);
  if (chargementMpegts) return chargementMpegts;
  chargementMpegts = new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = `${API_BASE}/vendor/mpegts.js`;
    s.async = true;
    s.onload = () => {
      const g = window as unknown as { mpegts?: unknown };
      if (g.mpegts) resolve(g.mpegts);
      else reject(new Error('mpegts.js chargé mais introuvable'));
    };
    s.onerror = () => {
      // On remet à zéro : un réseau qui retombe doit pouvoir réessayer.
      chargementMpegts = null;
      reject(new Error('mpegts.js injoignable'));
    };
    document.head.appendChild(s);
  });
  return chargementMpegts;
}

type MpegtsPlayer = {
  attachMediaElement: (el: HTMLVideoElement) => void;
  load: () => void;
  play: () => Promise<void> | void;
  destroy: () => void;
  unload: () => void;
  detachMediaElement: () => void;
  on: (ev: string, cb: (...a: unknown[]) => void) => void;
};
type MpegtsApi = {
  isSupported: () => boolean;
  createPlayer: (cfg: { type: string; isLive: boolean; url: string }) => MpegtsPlayer;
  Events: { ERROR: string };
};

export function ChannelPlayer({
  mac,
  index,
  channel,
  onClose,
}: {
  mac: string;
  index: number;
  channel: { id: string; name: string };
  onClose: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const playerRef = useRef<MpegtsPlayer | null>(null);
  const [etat, setEtat] = useState<'ouverture' | 'lecture' | 'erreur'>('ouverture');
  const [message, setMessage] = useState<string>('');

  useEffect(() => {
    let vivant = true;

    async function demarrer() {
      setEtat('ouverture');
      setMessage('');
      try {
        // 1. Le lien signé. C'est le Worker qui connaît le mot de passe ;
        //    nous, on ne reçoit qu'un lien de relais valable 12 h.
        const lien = await devicesApi.play(mac, channel.id, index);
        if (!vivant) return;

        // 2. Le démultiplexeur.
        const mpegts = (await chargerMpegts()) as MpegtsApi;
        if (!vivant) return;
        if (!mpegts.isSupported()) {
          setEtat('erreur');
          setMessage(
            'Ce navigateur ne sait pas lire un flux de télévision en '
            + 'direct. Essaie avec Chrome ou Edge.',
          );
          return;
        }

        const el = videoRef.current;
        if (!el) return;
        const p = mpegts.createPlayer({ type: 'mpegts', isLive: true, url: lien.url });
        playerRef.current = p;
        p.on(mpegts.Events.ERROR, (...a: unknown[]) => {
          if (!vivant) return;
          setEtat('erreur');
          //  ON DIT CE QU'ON A MESURÉ. « Erreur de lecture » tout court a
          //  déjà envoyé chercher une panne du panel là où le
          //  fournisseur était simplement en rade.
          setMessage(
            'Le flux s\'est interrompu (' + String(a[1] ?? a[0] ?? 'inconnu')
            + '). Si ça se reproduit sur plusieurs chaînes de la même '
            + 'liste, c\'est le fournisseur — le client voit la même chose.',
          );
        });
        p.attachMediaElement(el);
        p.load();
        await p.play();
        if (vivant) setEtat('lecture');
      } catch (e) {
        if (!vivant) return;
        setEtat('erreur');
        setMessage(
          e instanceof ApiError
            ? e.message
            : (e instanceof Error ? e.message : 'Lecture impossible.'),
        );
      }
    }

    void demarrer();

    return () => {
      vivant = false;
      //  TOUT DÉBRANCHER EN PARTANT. Un lecteur laissé en vie continue
      //  de tirer le flux en arrière-plan : de la bande passante du
      //  fournisseur consommée pour une fenêtre que plus personne ne
      //  regarde, et une place de connexion prise sur la ligne du
      //  client — qui, lui, se ferait éjecter.
      const p = playerRef.current;
      playerRef.current = null;
      if (p) {
        try { p.unload(); } catch { /* déjà mort */ }
        try { p.detachMediaElement(); } catch { /* idem */ }
        try { p.destroy(); } catch { /* idem */ }
      }
    };
  }, [mac, index, channel.id]);

  return (
    <div className="mb-3 rounded-xl border border-white/10 bg-black p-2">
      <div className="mb-1.5 flex items-center justify-between gap-2">
        <span className="truncate text-xs font-semibold text-[#F0EDE9]">
          {channel.name}
        </span>
        <button
          type="button"
          onClick={onClose}
          className="shrink-0 rounded px-1.5 py-0.5 text-[11px] text-[#B6B0A8] hover:text-[#F0EDE9]"
        >
          ✕ Fermer
        </button>
      </div>
      <video
        ref={videoRef}
        controls
        autoPlay
        muted
        playsInline
        className="aspect-video w-full rounded-lg bg-black"
      />
      {etat === 'ouverture' && (
        <p className="mt-1.5 text-[11px] text-[#7E7872]">Ouverture du flux…</p>
      )}
      {etat === 'erreur' && (
        <p className="mt-1.5 rounded border border-red-500/40 bg-red-500/10 px-2 py-1 text-[11px] text-red-200">
          {message}
        </p>
      )}
    </div>
  );
}
