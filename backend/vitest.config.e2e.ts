import { defineConfig } from 'vitest/config';
import tsconfigPaths from 'vite-tsconfig-paths';
import { resolve } from 'node:path';
import { config } from 'dotenv';

// Load .env from apps/backend so DATABASE_URL is available
config({ path: resolve(__dirname, '.env') });

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    globals: true,
    root: './',
    include: ['**/*.e2e-spec.ts'],
  },
});
