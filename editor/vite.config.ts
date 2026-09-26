import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));
const base = process.env.VITE_BASE_PATH || "/";

export default defineConfig({
  base,
  root,
  plugins: [react()],
  publicDir: resolve(root, "public"),
  server: { port: 4173, host: "127.0.0.1", fs: { allow: [resolve(root, "..")] } },
  build: { outDir: resolve(root, "../dist/editor"), emptyOutDir: true },
  test: { environment: "node", include: ["src/**/*.test.ts"] },
});
