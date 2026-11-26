import { defineConfig } from "vitest/config";

// Plain Node tests of the sending logic, with Firestore and Cloud Messaging
// replaced by fakes.
export default defineConfig({
  test: { environment: "node", include: ["test/**/*.test.ts"] },
});
