// Page d'accueil — version SCAFFOLD (sera remplacée à l'étape 8 par le
// Hero + les rangées + la sélection de profil). Ici on valide juste que
// le design system et le build fonctionnent.
export default function HomePage() {
  return (
    <main
      style={{
        padding: "var(--safe-y) var(--safe-x)",
        position: "relative",
        zIndex: 1,
      }}
    >
      <h1
        className="font-serif"
        style={{ fontSize: "4rem", margin: 0, color: "var(--text-high)" }}
      >
        <span style={{ color: "var(--gold)" }}>👑 TV King</span>
      </h1>
      <p style={{ fontSize: "1.6rem", color: "var(--text-medium)" }}>
        Échafaudage prêt — design system chargé.
      </p>
    </main>
  );
}
