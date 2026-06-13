import React from 'react'
import ReactDOM from 'react-dom/client'
import { registerSW } from 'virtual:pwa-register'
import { toast } from 'react-hot-toast'
import App from './App.tsx'
import './index.css'

const DASHBOARD_ORIENTATION = 'portrait'

function lockDashboardOrientation() {
  const orientation = window.screen?.orientation
  if (!orientation || typeof orientation.lock !== 'function') return
  if (document.visibilityState === 'hidden') return

  orientation.lock(DASHBOARD_ORIENTATION).catch(() => {
    // Browsers that only allow orientation lock in installed/fullscreen contexts
    // reject here. The PWA manifest still provides the preferred orientation.
  })
}

function installDashboardOrientationLock() {
  lockDashboardOrientation()
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') lockDashboardOrientation()
  })
  window.addEventListener('focus', lockDashboardOrientation)
  window.addEventListener('resize', lockDashboardOrientation)
  window.addEventListener('orientationchange', lockDashboardOrientation)
  document.addEventListener('click', lockDashboardOrientation, { passive: true })
  document.addEventListener('touchend', lockDashboardOrientation, { passive: true })
  document.addEventListener('keydown', lockDashboardOrientation)
}

installDashboardOrientationLock()

// PWA detection — add .pwa-mode class when running as standalone
const isPWA = window.matchMedia('(display-mode: standalone)').matches
if (isPWA) {
  document.body.classList.add('pwa-mode')
  // Keep the back button from exiting the PWA on the home screen
  window.history.pushState({ noBackExitsApp: true }, '')
  window.addEventListener('popstate', (event) => {
    if (event.state && (event.state as any).noBackExitsApp) {
      window.history.pushState({ noBackExitsApp: true }, '')
    }
  })
}

// Register the service worker and auto-reload when a new version takes over.
// With registerType 'autoUpdate' the new SW skips waiting and claims clients;
// `controllerchange` then fires once. We toast first, then reload shortly after
// so the user sees why the page refreshed. The `refreshing` guard prevents a
// reload loop.
if ('serviceWorker' in navigator) {
  let refreshing = false
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (refreshing) return
    refreshing = true
    toast.success('Nueva versión del dashboard · actualizando…', { icon: '✨', duration: 2000 })
    setTimeout(() => window.location.reload(), 1500)
  })
}

// Check for a new SW on load and every 30 min so a long-open dashboard picks up
// a fresh deploy without a manual refresh (skipWaiting+clientsClaim then reload).
registerSW({
  immediate: true,
  onRegisteredSW(_swUrl, registration) {
    if (!registration) return
    registration.update()
    setInterval(() => registration.update(), 30 * 60 * 1000)
  },
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
