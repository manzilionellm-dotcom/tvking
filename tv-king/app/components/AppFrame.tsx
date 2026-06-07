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
import { shouldBlock } from "../lib/license";
import { usePreferences } from "../lib/preferences";
import { AppFrameSplash } from "./Splash";
import { HelpBar } from "./HelpBar";
import { useLicense } from "./LicenseProvider";
import { ProfileGate } from "./ProfileGate";
import { Sidebar } from "./Sidebar";
import { SpatialNav } from "./SpatialNav";
import { SubscriptionGate } from "./SubscriptionGate";
import { TrialBadge } from "./TrialBadge";

export function AppFrame({ children }: { children: ReactNode }) {
  const { prefs, ready: prefsReady } = usePreferences();
  const { ready: licenseReady, status } = useLicense();

  // On attend la lecture des préférences ET le 1er heartbeat de licence.
  if (!prefsReady || !licenseReady) return <AppFrameSplash />;

  // Blocage d'accès (essai fini non payé / gelé / banni) — prime sur tout.
  if (shouldBlock(status)) {
    return (
      <>
        <SpatialNav />
        <SubscriptionGate status={status} />
      </>
    );
  }

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
      <TrialBadge />
      <div className="app-shell">
        <Sidebar />
        <main className="content">{children}</main>
      </div>
      <HelpBar />
    </>
  );
}
