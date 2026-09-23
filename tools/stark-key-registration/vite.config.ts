/// <reference types="vitest/config" />
import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  build: {
    outDir: "dist",
    emptyOutDir: true,
    // The polyfill is an inline script, which the page's Content-Security-Policy blocks.
    modulePreload: { polyfill: false },
    sourcemap: true,
  },
  server: {
    host: "127.0.0.1",
    port: 4173,
    strictPort: true,
    // The token list is read from the repository's config directory.
    fs: { allow: ["../.."] },
  },
  preview: {
    host: "127.0.0.1",
    port: 4173,
    strictPort: true,
  },
  test: {
    testTimeout: 30_000,
  },
});
