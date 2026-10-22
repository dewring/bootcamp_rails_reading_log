import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["test/javascript/**/*_test.ts"],
    clearMocks: true,
    restoreMocks: true
  }
})
