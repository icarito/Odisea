# FD-167: PWA Push Notifications + Offline Cache

**Status:** Design
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-06-12
**Completed:** -

## Problem

El dashboard de Odisea Central ya es PWA (manifest, íconos) pero no aprovecha capacidades PWA clave:
1. No genera notificaciones push en Android cuando ocurren eventos
2. No funciona offline — si no hay conexión, muestra pantalla en blanco
3. El service worker no existe

El developer (Sebastián) quiere recibir alertas del dashboard en su teléfono Android sin tener la pestaña abierta, y poder abrir el dashboard aunque el bridge esté momentáneamente caído.

## Solution

### Parte A — Push Notifications

Agregar soporte de Web Push API al dashboard:

1. **Service Worker** (`sw.js`) que maneje eventos `push` y muestre notificaciones del sistema
2. **Registro de subscription** en el frontend: `PushManager.subscribe()` al iniciar sesión
3. **UI de configuración** en el dashboard: toggles para elegir qué eventos notificar
4. **Backend** (`odisea_central.py`): almacenar subscriptions, endpoint para enviar push, envío automático cuando ocurren los eventos seleccionados
5. **VAPID keys**: generar par en el servidor para autenticar los pushes

**Eventos notificables (solo los que YA existen en el dashboard hoy):**

| Evento | Origen | Prioridad inicial |
|---|---|---|
| Jugador desconectado | `useTelemetry` disconnect detection | Alta |
| Bridge offline | `isConnected` toggle | Alta |
| Bridge reconectado | `isConnected` toggle | Media |
| Alerta vía WebSocket | Mensaje `type: alert` del backend | Media |

### Parte B — Offline Cache (nivel básico)

1. **Cache de shell**: precachear HTML, JS, CSS e íconos durante `install` del service worker
2. **Cache de última snapshot**: guardar en IndexedDB los últimos datos de `/status` y mostrarlos offline con un banner "sin conexión"
3. **Banner offline**: indicador visual claro cuando el dashboard está sirviendo datos cacheados

**Fuera de scope para este FD (backlog):**
- Background sync (acciones offline que se sincronizan después)
- Notificaciones de CI, hotzone, deploy, tests (esos eventos no existen aún en el dashboard)
- Estrategia de cache avanzada (stale-while-revalidate complejo)

### Considered Options

- **Web Push API nativa** — ventaja: funciona en Chrome Android sin dependencias. El estándar.
- **Firebase Cloud Messaging** — ventaja: más features, pero requiere cuenta Google y SDK externo. Overkill.
- **Selected: Web Push API nativa** — minimal, sin dependencias, suficiente para notificar eventos simples.

## Files to Modify

### Nuevos
- `dashboard/public/sw.js` — Service Worker (push events + cache shell)
- `dashboard/src/hooks/usePushNotifications.ts` — hook de registro y gestión de subscription
- `dashboard/src/components/NotificationSettings.tsx` — panel de toggles de notificaciones
- `dashboard/src/lib/pushStorage.ts` — helpers IndexedDB para snapshot offline

### Modificados
- `dashboard/src/App.tsx` — integrar usePushNotifications, panel de settings, banner offline
- `dashboard/src/hooks/useTelemetry.ts` — emitir eventos notificables (disconnect, bridge status)
- `dashboard/src/hooks/useWebSocket.ts` — exponer eventos WS para push
- `dashboard/vite.config.ts` — si es necesario ajustar build para sw.js
- `dashboard/index.html` — registrar service worker
- `odisea_central.py` — endpoints: POST /push/subscribe, POST /push/send, almacenar subscriptions

## Verification

1. Abrir dashboard en Chrome Android → aceptar notificaciones → configurar toggles
2. Cerrar dashboard → desconectar un peer → verificar que llega notificación al teléfono
3. Abrir dashboard → desconectar WiFi → verificar que carga shell + datos cacheados con banner offline
4. Reconectar WiFi → verificar que el banner desaparece y datos se refrescan
5. Abrir notificación push desde Android → verificar que abre el dashboard en la pestaña correcta
