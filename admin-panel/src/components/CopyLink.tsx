import { useState } from 'react';

/// Lien cliquable + bouton « Copier ». Pour les liens de telechargement
/// a donner aux clients (Downloader).
export function CopyLink({ url }: { url: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      /* clipboard indispo (vieux navigateur) — l'utilisateur peut copier a la main */
    }
  }

  return (
    <div className="flex items-center gap-2 rounded-md border border-white/10 bg-slate px-3 py-2">
      <a
        href={url}
        target="_blank"
        rel="noreferrer"
        className="flex-1 truncate font-mono text-xs text-accent hover:underline"
      >
        {url}
      </a>
      <button
        type="button"
        onClick={copy}
        className="shrink-0 rounded-md bg-accent px-2.5 py-1 text-xs font-semibold text-black hover:bg-accent-bright"
      >
        {copied ? 'Copié ✔' : 'Copier'}
      </button>
    </div>
  );
}
