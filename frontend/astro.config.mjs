// @ts-check
import { defineConfig } from 'astro/config';

import svelte from '@astrojs/svelte';

import tailwindcss from '@tailwindcss/vite';

// https://astro.build/config
export default defineConfig({
  integrations: [svelte()],

  vite: {
    plugins: [tailwindcss()],
    server: {
      proxy: {
        // バックエンドAPIへのプロキシ設定
        '/api': {
          target: 'http://172.26.39.220:33000',
          changeOrigin: true,
        },
      },
    },
  },

  // 開発サーバーの設定
  server: {
    port: 4321,
    host: '0.0.0.0', // 全インターフェースでリッスン
  },
});