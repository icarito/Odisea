import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const apiTarget = env.VITE_API_TARGET || 'http://localhost:4999'
  const wsTarget = apiTarget.replace('http', 'ws')
  const apiProxy = {
    target: apiTarget,
    changeOrigin: true,
  }

  return {
    plugins: [
      react(),
      VitePWA({
        strategies: 'injectManifest',
        srcDir: 'src',
        filename: 'sw.ts',
        registerType: 'autoUpdate',
        // We register the SW ourselves in main.tsx so we can auto-reload the
        // page when a new version activates.
        injectRegister: null,
        includeAssets: ['favicon.svg', 'icons.svg'],
        manifest: {
          name: 'Odisea Central',
          short_name: 'Odisea',
          description: 'Panel de telemetría en vivo de Odisea',
          theme_color: '#863bff',
          background_color: '#0c0e12',
          display: 'standalone',
          orientation: 'portrait',
          start_url: '/',
          icons: [
            { src: 'pwa-192x192.png', sizes: '192x192', type: 'image/png' },
            { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png' },
            { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
          ],
        },
        workbox: {
          // Precache the app shell only. Live data (API + sockets) must always
          // hit the network so the dashboard never shows stale telemetry.
          globPatterns: ['**/*.{js,css,html,svg,png,ico,woff2}'],
          navigateFallback: '/index.html',
          // Never let the SW intercept these — they're dynamic/auth'd.
          navigateFallbackDenylist: [
            /^\/api/, /^\/events/, /^\/ws/, /^\/status/,
            /^\/sessions/, /^\/command/, /^\/telemetry/, /^\/health/,
          ],
          runtimeCaching: [
            {
              urlPattern: ({ url }) => /^\/(api|events|ws|status|sessions|command|telemetry|health)/.test(url.pathname),
              handler: 'NetworkOnly',
            },
          ],
        },
        devOptions: {
          // Keep the SW off in dev so it doesn't interfere with HMR / the proxy.
          enabled: false,
        },
      }),
    ],
    server: {
      allowedHosts: ['.ngrok-free.app', '.ngrok-free.app:5003'],
      proxy: {
        '/status': apiProxy,
        '/health': apiProxy,
        '/sessions': apiProxy,
        '/telemetry': apiProxy,
        '/command': apiProxy,
        '/api': apiProxy,
        '/ws': {
          target: wsTarget,
          changeOrigin: true,
          ws: true,
        },
        '/events': {
          target: wsTarget,
          changeOrigin: true,
          ws: true,
        },
        '/push': {
          target: apiTarget,
          changeOrigin: true,
        },
      },
    },
  };
})
