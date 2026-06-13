import React from 'react'
import ReactDOM from 'react-dom/client'
import { registerSW } from 'virtual:pwa-register'
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
// `controllerchange` then fires. A toast shown here would be wiped by the
// immediate reload, so instead we set a flag and toast *after* the reload, once
// the app has mounted (see UPDATED_FLAG below).
const UPDATED_FLAG = 'odisea_dashboard_updated'
if ('serviceWorker' in navigator) {
  // Whether this page is already controlled by a SW at load time. On the very
  // first visit there is no controller yet, so the controllerchange fired by the
  // initial clients.claim() is NOT an update — reloading then would be a spurious
  // refresh. Only reload when an existing controller is replaced by a new one.
  const hadController = !!navigator.serviceWorker.controller
  let refreshing = false
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (refreshing || !hadController) return
    refreshing = true
    try { sessionStorage.setItem(UPDATED_FLAG, '1') } catch { /* ignore */ }
    window.location.reload()
  })
}

// Note: the post-reload "Dashboard actualizado" toast is fired from inside App
// (a useEffect) rather than here — emitting a toast before React mounts the
// <Toaster> drops it. App reads and clears the UPDATED_FLAG. See App.tsx.

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
