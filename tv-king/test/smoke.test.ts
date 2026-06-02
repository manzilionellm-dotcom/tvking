import { describe, expect, it } from "vitest";

// Test de fumée : valide que la chaîne de tests (vitest + jsdom) tourne.
// Les vrais tests (navigation spatiale, données, accessibilité) arrivent
// à l'étape 11.
describe("fondation du projet", () => {
  it("l'environnement de test fonctionne", () => {
    expect(1 + 1).toBe(2);
  });

  it("jsdom est disponible", () => {
    const el = document.createElement("div");
    el.setAttribute("data-focusable", "true");
    expect(el.getAttribute("data-focusable")).toBe("true");
  });
});
