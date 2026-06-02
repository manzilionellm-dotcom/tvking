import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// Configuration des tests.
//  - environment jsdom : permet de monter des composants React et de
//    tester la navigation/accessibilité dans un faux DOM.
//  - globals : `describe/it/expect` dispos sans import (style Jest).
//  - alias `@` aligné sur tsconfig (`@/*` -> racine du projet).
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL(".", import.meta.url)),
    },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./vitest.setup.ts"],
    include: ["test/**/*.test.{ts,tsx}", "app/**/*.test.{ts,tsx}"],
  },
});
