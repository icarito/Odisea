# FD-169: Geo-IP Player Tags + Globe Heatmap

**Status:** Design
**Priority:** Low
**Effort:** Medium
**Created:** 2026-06-13
**Completed:** -

## Problem

El dashboard de Odisea Central muestra players conectados con IDs numéricos anónimos (`1780893709-177616192`). No hay forma de:
1. Saber de qué país/región se conectan los jugadores
2. Asignar nombres amigables o tags a los players
3. Visualizar la distribución geográfica en un mapa

Esto hace difícil identificar testers, diagnosticar problemas regionales, o simplemente darle contexto humano a los datos de telemetría.

## Solution

### A. Geo-IP tagging (offline)

Proceso asíncrono en `odisea_central.py` que cada N minutos (default 15) geolocaliza IPs nuevas usando una base de datos offline:

- **Base de datos:** MaxMind GeoLite2 City (gratuita, descargable, sin API externa)
- **SQLite separado:** `data/geo_tags.db` con tabla `geo_ips`:
  ```sql
  CREATE TABLE geo_ips (
    ip TEXT PRIMARY KEY,
    country TEXT,
    country_code TEXT,
    city TEXT,
    latitude REAL,
    longitude REAL,
    tagged_at REAL
  );
  ```
- El proceso geo-taguea solo IPs nuevas (no vistas antes) para no repetir trabajo
- Las IPs se extraen de los heartbeats y WebSocket connections existentes

### B. Player tags desde el dashboard

UI en una **pestaña separada** del dashboard para asignar nombres/tags a player IDs:

- Tabla SQLite `player_tags`:
  ```sql
  CREATE TABLE player_tags (
    player_id TEXT PRIMARY KEY,
    display_name TEXT,
    notes TEXT,
    color TEXT,
    tagged_at REAL,
    updated_at REAL
  );
  ```
- Endpoints: `GET /api/player-tags`, `POST /api/player-tags`, `DELETE /api/player-tags/{player_id}`

### C. Globe heatmap

Componente visual en una pestaña del dashboard que muestra un mapamundi wireframe con dots pulsantes en las ubicaciones de los jugadores:

- **Librería:** `react-simple-maps` (SVG, liviano, sin Three.js/WebGL)
- **Pestaña:** "Globe" o "Mapa" separada del home
- Muestra:
  - Puntos por país/ciudad con radio proporcional a cantidad de jugadores
  - Tooltip al hover: país, ciudad, player count, nombres (si tienen tag)
  - Color del dot: verde = conectado, gris = última hora, rojo = >1h sin conexión
  - Animación sutil de pulso para jugadores activos

### D. Notificaciones con deep-link al player

Cuando el usuario toca una notificación push en Android:
- El service worker abre `/?player=<player_id>&session=<session_id>`
- El dashboard detecta los query params y activa **modo live** enfocado en ese player:
  - Filtra la tabla de ghosts a ese player_id
  - Muestra un badge/pill con el player_id en la parte superior
  - Ofrece botón **"Tag this player"** que abre el editor de tags inline (sin cambiar de pestaña)
- Los tags se guardan inmediatamente vía `POST /api/player-tags`

El payload del push se modifica para incluir `player_id`, `session_id`, y `url`:
```json
{
  "type": "disconnect",
  "playerId": "1780893709-177616192",
  "sessionId": "abc123",
  "message": "Player ABC123 disconnected"
}
```

### E. Pestañas del dashboard

Refactorizar la navegación del dashboard para soportar pestañas:

| Pestaña | Contenido |
|---|---|
| **Home** | Telemetría live, ghost table, alerts, status (lo actual) |
| **Mapa** | Globe heatmap geo-IP |

La configuración (NotificationSettings + player tags) va detrás de un **ícono de ruedita/engranaje** en el header superior derecho del dashboard. Al clickearlo abre un panel lateral o modal con las opciones de configuración, sin cambiar de pestaña.

La navegación de pestañas se implementa como tabs superiores, estilo retro-terminal.

### Considered Options

- **MaxMind GeoLite2 offline** — sin dependencia de API externa, sin rate limits, actualización manual cada ~mes. Selected.
- **ip-api.com o similar** — API gratuita con rate limits, requiere conexión externa, latencia. Rechazado.
- **Three.js globe** — visualmente impresionante pero pesado (1MB+ de librería). Overkill.
- **react-simple-maps SVG** — liviano (~50KB), nativo, responsive, suficiente para dots geo. Selected.

## Files to Modify

### Nuevos
- `dashboard/src/components/GlobeView.tsx` — Componente del mapamundi con dots
- `dashboard/src/components/PlayerTagEditor.tsx` — UI inline para asignar nombres/tags a players
- `dashboard/src/components/PlayerFocus.tsx` — Badge/pill + filtro live cuando se deep-linkea a un player
- `dashboard/src/components/DashboardTabs.tsx` — Navegación por pestañas
- `scripts/download_geolite2.py` — Script para descargar y actualizar la DB GeoLite2

### Modificados
- `dashboard/src/App.tsx` — Integrar DashboardTabs, detectar query params `?player=` para deep-link, mover NotificationSettings a pestaña Config
- `dashboard/src/sw.ts` — Modificar `notificationclick` para abrir `/?player=<id>&session=<id>`
- `dashboard/package.json` — Agregar `react-simple-maps` y `d3-geo`
- `odisea_central.py` — Agregar:
  - Proceso asíncrono de geo-tagging (usa `geoip2` Python library)
  - Tablas `geo_ips` y `player_tags` en SQLite
  - Endpoints `GET/POST/DELETE /api/player-tags`
  - Endpoint `GET /api/geo-players` (devuelve players con geo + tags para el mapa)
- `requirements-bridge.txt` — Agregar `geoip2`

### No tocar
- Cualquier archivo Godot (.gd, .tscn)
- CI/CD workflows
- ANNA V2 / bridge protocol
- Scaffold / MST / Level Design
- export_all.yml

## Verification

1. Dashboard muestra 2 pestañas (Home, Mapa) + ícono ruedita en el header
2. Pestaña Mapa muestra dots en países donde hay jugadores conectados
3. Asignar un tag a un player → el nombre aparece en el mapa y en la tabla de ghosts
4. Reiniciar central → los tags persisten (SQLite)
5. El proceso de geo-tagging corre cada 15 min sin afectar heartbeats
6. `react-simple-maps` no rompe el build de Vite
7. Tocar una notificación push en Android → abre el dashboard con `?player=<id>` → muestra el player enfocado en modo live
8. Desde el modo live enfocado, botón "Tag this player" abre editor inline y guarda el tag
9. Ícono ruedita en el header abre panel de configuración (notificaciones + tags)
