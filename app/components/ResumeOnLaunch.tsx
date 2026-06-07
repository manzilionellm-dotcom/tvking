"use client";

/*
 * Reprise instantanée — au démarrage à froid, on rouvre directement la dernière
 * chaîne regardée (recents[0]) si le réglage « resumeLast » est actif.
 *
 * Règles (CLAUDE.md : zéro friction, ça marche TOUJOURS) :
 *  - UNE seule fois par session (drapeau module) : revenir à l'accueil avec
 *    Retour ne redéclenche jamais la reprise.
 *  - On attend que la source soit retombée (ready/error) avant de décider.
 *  - Jamais bloquant : réglage off, recents vide, chaîne disparue de la
 *    playlist, hors-ligne / source en erreur → on reste sur l'accueil.
 *  - router.replace (pas push) → Retour depuis le lecteur ramène à l'accueil,
 *    sans boucle de redirection.
 *
 * Composant sans rendu : monté UNIQUEMENT par l'accueil, donc la reprise ne se
 * déclenche qu'au lancement de l'app sur la home.
 */

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useSource } from "../lib/client-source";
import { useRecents } from "../lib/favorites";
import { useBoolPref } from "../lib/prefs";

// Vrai dès qu'on a tranché une fois pour cette session (process WebView).
let handledThisSession = false;

export default function ResumeOnLaunch() {
  const { status, playlist } = useSource();
  const recents = useRecents();
  const enabled = useBoolPref("resumeLast", true);
  const router = useRouter();
  const localDone = useRef(false);

  useEffect(() => {
    if (handledThisSession || localDone.current) return;

    // Réglage désactivé : on marque comme traité (et on ne reprendra pas si le
    // réglage est activé plus tard dans la même session — c'est un comportement
    // de lancement).
    if (!enabled) {
      handledThisSession = true;
      localDone.current = true;
      return;
    }

    // On attend que la source soit chargée (sinon recents[0] ne résout pas).
    if (status === "idle" || status === "loading") return;

    // Source retombée : décision définitive pour cette session.
    handledThisSession = true;
    localDone.current = true;

    // Hors-ligne / erreur / playlist vide → on reste sur l'accueil.
    if (status !== "ready" || playlist.total === 0) return;

    const lastId = recents[0];
    if (!lastId) return; // jamais regardé → accueil

    // La chaîne existe-t-elle encore dans la playlist actuelle ?
    if (!playlist.channels.some((c) => c.id === lastId)) return;

    router.replace(`/watch?c=${encodeURIComponent(lastId)}`);
  }, [status, playlist, recents, enabled, router]);

  return null;
}
