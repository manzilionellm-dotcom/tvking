import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';
import { ConfirmHost } from './components/confirm';
import { LangProvider } from './lib/i18n';
import { FichePreviewPage } from './pages/FichePreviewPage';
import './styles.css';

// Aperçu local des fiches, données fictives, sans compte. Vite retire
// cette branche du build de production (import.meta.env.DEV).
const apercu = import.meta.env.DEV && window.location.pathname === '/apercu-fiches';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {apercu ? <FichePreviewPage /> : (
      <LangProvider>
        <BrowserRouter>
          <App />
        </BrowserRouter>
        <ConfirmHost />
      </LangProvider>
    )}
  </React.StrictMode>,
);
