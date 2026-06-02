"use client";

// =========================================================
//  AppFrame.tsx — Cadre applicatif (décide quoi afficher)
// =========================================================
//  - Tant que les préférences ne sont pas lues (ready=false), on ne rend
//    rien pour éviter un « flash » de mauvais profil/échelle.
//  - Si aucun profil choisi → écran de sélection de profil (ProfileGate).
//  - Sinon → le shell complet : rail gauche + contenu + barre d'aide,
//    avec la navigation spatiale active.
//
//  SpatialNav est monté dans les deux cas (l'écran de profil se navigue
//  aussi à la télécommande).
// =========================================================

import type { ReactNode } from "react";
import { usePreferences } from "../lib/preferences";
import { AppFrameSplash } from "./Splash";
import { HelpBar } from "./HelpBar";
import { ProfileGate } from "./ProfileGate";
import { Sidebar } from "./Sidebar";
import { SpatialNav } from "./SpatialNav";

export function AppFrame({ children }: { children: ReactNode }) {
  const { prefs, ready } = usePreferences();

  if (!ready) return <AppFrameSplash />;

  if (!prefs.profile) {
    return (
      <>
        <SpatialNav />
        <ProfileGate />
      </>
    );
  }

  return (
    <>
      <SpatialNav />
      <div className="app-shell">
        <Sidebar />
        <main className="content">{children}</main>
      </div>
      <HelpBar />
    </>
  );
}
