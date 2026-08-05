"use client";

/*
 * Erreur dans le layout racine lui-même : ce composant remplace tout le
 * document (il doit fournir <html>/<body>). Styles inline uniquement — les
 * feuilles de style globales peuvent ne pas être chargées à ce stade.
 */
export default function GlobalError({
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  return (
    <html lang="fr">
      <body
        style={{
          margin: 0,
          minHeight: "100vh",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: "1rem",
          background: "#121212",
          color: "rgba(255,255,255,0.92)",
          fontFamily: "system-ui, sans-serif",
          textAlign: "center",
          padding: "5vh 5vw",
        }}
      >
        <div style={{ fontSize: "3rem" }}>📺</div>
        <h1 style={{ fontSize: "1.8rem", margin: 0 }}>Oups, un problème est survenu</h1>
        <p style={{ maxWidth: "42ch", color: "rgba(255,255,255,0.62)", margin: 0 }}>
          Rien de grave : appuyez sur « Réessayer » pour reprendre.
        </p>
        <button
          onClick={() => unstable_retry()}
          autoFocus
          style={{
            marginTop: "0.8rem",
            padding: "0.9rem 1.6rem",
            fontSize: "1.1rem",
            fontWeight: 700,
            color: "#000",
            background: "linear-gradient(135deg, #f7e0a3 0%, #e3b96b 42%, #c9962f 100%)",
            border: "none",
            borderRadius: "0.75rem",
            cursor: "pointer",
          }}
        >
          Réessayer
        </button>
      </body>
    </html>
  );
}
