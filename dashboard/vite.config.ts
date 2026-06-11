import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const apiTarget = env.VITE_API_TARGET || 'http://localhost:5003'
  const wsTarget = apiTarget.replace('http', 'ws')

  return {
    plugins: [react()],
    server: {
      allowedHosts: ['.ngrok-free.app', '.ngrok-free.app:5003'],
      proxy: {
        '/status': apiTarget,
        '/health': apiTarget,
        '/sessions': apiTarget,
        '/ws': {
          target: wsTarget,
          ws: true,
        },
        '/events': {
          target: wsTarget,
          ws: true,
        }
      }
    }
  }
})
