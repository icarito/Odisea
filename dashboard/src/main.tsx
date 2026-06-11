import React from 'react'
import ReactDOM from 'react-dom/client'
import { registerSW } from 'virtual:pwa-register'
import App from './App.tsx'
import './index.css'

// Register the service worker and auto-reload when a new version takes over.
// With registerType 'autoUpdate' the new SW skips waiting and claims clients;
// `controllerchange` then fires once, and we reload to pick up the new assets.
// The `refreshing` guard prevents a reload loop.
if ('serviceWorker' in navigator) {
  let refreshing = false
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (refreshing) return
    refreshing = true
    window.location.reload()
  })
}

registerSW({ immediate: true })

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
