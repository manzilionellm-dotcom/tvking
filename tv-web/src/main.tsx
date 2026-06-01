// =========================================================
//  main.tsx — Point d'entree de l'app
// =========================================================
//  Monte App.tsx dans #root. Pas de Router pour l'instant — on a
//  un seul ecran (input M3U + liste + lecteur). Ajout React Router
//  ou Wouter en Phase 2 quand on aura plusieurs vues (Live / VOD /
//  Series / Settings).
// =========================================================

import React from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App.js';

const rootElement = document.getElementById('root');
if (!rootElement) {
  throw new Error('Element #root introuvable dans index.html');
}

createRoot(rootElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
