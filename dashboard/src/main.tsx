import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { registerSW } from 'virtual:pwa-register'
import App from './App.tsx'
import { IncidentShell } from './app/IncidentShell'
import { Inbox } from './app/Inbox'
import { Investigation } from './app/Investigation'
import { Heatmap } from './app/Heatmap'
import { Globe } from './app/Globe'
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

// PWA detection — add .pwa-mode class when running as standalone.
// NOTE: we intentionally do NOT trap `popstate` here anymore. The old trap
// re-pushed state on every back press to keep the PWA from exiting, but it
// also defeated all in-app back navigation. The app now drives history via
// the URL (`?tab=`/`?player=`), and only guards the *root* entry so the back
// button doesn't immediately exit the PWA from the home tab (see App.tsx).
const isPWA = window.matchMedia('(display-mode: standalone)').matches
if (isPWA) {
  document.body.classList.add('pwa-mode')
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
    <BrowserRouter>
      <Routes>
        {/* IA incident-first (nueva). Aditiva: no toca el dashboard clásico. */}
        <Route element={<IncidentShell />}>
          <Route path="/investigate" element={<Inbox />} />
          <Route path="/investigation/:id" element={<Investigation />} />
          <Route path="/heatmap" element={<Heatmap />} />
          <Route path="/globe" element={<Globe />} />
        </Route>
        {/* Dashboard clásico — todo lo demás (?tab=…) lo maneja App internamente. */}
        <Route path="/*" element={<App />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
)
