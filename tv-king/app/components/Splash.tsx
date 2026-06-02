// =========================================================
//  Splash.tsx — Écran d'attente très bref (lecture des préférences)
// =========================================================
//  Affiché le temps de lire le localStorage, pour éviter un flash de
//  mauvaise échelle/contraste. Calme, centré, sobre.
// =========================================================

export function AppFrameSplash() {
  return (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        position: "relative",
        zIndex: 1,
      }}
      aria-label="Chargement de TV King"
      role="status"
    >
      <div
        className="font-serif"
        style={{ fontSize: "3rem", color: "var(--gold)", opacity: 0.9 }}
      >
        👑 TV King
      </div>
    </div>
  );
}
