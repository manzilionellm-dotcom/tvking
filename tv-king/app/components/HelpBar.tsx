// =========================================================
//  HelpBar.tsx — Barre d'aide permanente
// =========================================================
//  Toujours visible en bas : rappelle les 3 gestes universels. Principe
//  « personne n'est perdu » : à tout moment l'utilisateur sait comment
//  choisir, ouvrir et revenir. Non focusable (pointer-events:none) — c'est
//  un repère, pas une cible.
// =========================================================

export function HelpBar() {
  return (
    <div className="help-bar" role="note" aria-label="Aide à la navigation">
      <span>
        <kbd>◀ ▶</kbd>Choisir
      </span>
      <span>
        <kbd>OK</kbd>Ouvrir
      </span>
      <span>
        <kbd>⬅</kbd>Retour
      </span>
    </div>
  );
}
