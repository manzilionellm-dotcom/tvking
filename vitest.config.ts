import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: [
        "app/lib/spatial.ts",
        "app/lib/focusMemory.ts",
        "app/lib/telemetry.ts",
        "app/lib/playerKeys.ts",
        "app/lib/data.ts",
      ],
      reporter: ["text", "json-summary"],
      // Coverage gate on the logic under test (qa-gates: ≥80% on touched code).
      thresholds: { lines: 80, functions: 80, statements: 80, branches: 70 },
    },
  },
});
