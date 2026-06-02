import type { Metadata, Viewport } from "next";
import "./globals.css";
import { AppFrame } from "./components/AppFrame";
import { LicenseProvider } from "./components/LicenseProvider";
import { PreferencesProvider } from "./lib/preferences";

// Métadonnées de l'app. Pas de marque réelle, pas de tracking.
export const metadata: Metadata = {
  title: "NOVA+ — Streaming premium",
  description:
    "Application de streaming TV premium et universelle, pensée pour être utilisée à 3 mètres avec une télécommande, par tout le monde.",
};

// Viewport TV : on fige l'échelle (le zoom utilisateur n'a pas de sens
// sur une télé), la mise à l'échelle est gérée par notre design system.
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: "#121212",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  // lang="fr" : narration vocale et lecteurs d'écran utilisent le français.
  //
  // DIAGNOSTIC TV (temporaire) : un script INLINE en ES5 pur s'exécute
  // tout de suite dans le WebView, AVANT et indépendamment de React/Next.
  // Il : (1) force un fond sombre (anti écran blanc), (2) affiche la
  // version du navigateur (userAgent) et (3) capture toute erreur JS dans
  // un bandeau visible à l'écran. Objectif : voir SUR LA TV pourquoi
  // l'app ne démarre pas, au lieu de deviner. À retirer une fois réglé.
  const diag = [
    "(function(){",
    "try{var h=document.documentElement;h.style.background='#121212';}catch(e){}",
    "function show(m){try{var d=document.getElementById('nova-diag');",
    "if(!d){d=document.createElement('div');d.id='nova-diag';",
    "d.style.cssText='position:fixed;left:0;right:0;bottom:0;z-index:99999;background:#1a1a1c;color:#e3b96b;font-family:monospace;font-size:13px;line-height:1.4;padding:8px;white-space:pre-wrap;max-height:60%;overflow:auto;border-top:2px solid #e3b96b';",
    "var b=document.body||document.documentElement;b.appendChild(d);}",
    "d.appendChild(document.createTextNode(m+'\\n'));}catch(e){}}",
    "window.onerror=function(msg,src,ln,col){show('JS ERROR: '+msg+' @ '+(src||'')+':'+(ln||0));return false;};",
    "window.addEventListener&&window.addEventListener('unhandledrejection',function(ev){show('PROMISE: '+(ev&&ev.reason));});",
    "show('NOVA+ diag');show('UA: '+navigator.userAgent);",
    "setTimeout(function(){var r=document.querySelector('[data-focusable],main,.app-shell');show(r?('rendu OK: '+(r.tagName||'')) :'RIEN RENDU apres 6s (JS/Next non demarre)');},6000);",
    "})();",
  ].join("");

  return (
    <html lang="fr">
      <body style={{ background: "#121212", color: "rgba(255,255,255,0.92)", margin: 0 }}>
        <script dangerouslySetInnerHTML={{ __html: diag }} />
        <PreferencesProvider>
          <LicenseProvider>
            <AppFrame>{children}</AppFrame>
          </LicenseProvider>
        </PreferencesProvider>
      </body>
    </html>
  );
}
