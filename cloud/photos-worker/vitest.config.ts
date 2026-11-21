import { defineConfig } from "vitest/config";

// Plain Node tests of the Worker's logic, with the R2 binding and the token
// check replaced by fakes.
export default defineConfig({
  test: { environment: "node", include: ["test/**/*.test.ts"] },
});
