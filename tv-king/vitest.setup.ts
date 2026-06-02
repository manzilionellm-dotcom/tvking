import { afterEach } from "vitest";
import { cleanup } from "@testing-library/react";

// Démonte les composants montés entre chaque test pour éviter les fuites
// de DOM (un test ne doit pas voir le rendu du précédent).
afterEach(() => {
  cleanup();
});
