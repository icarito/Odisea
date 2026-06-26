# Handoff — Rediseño del dashboard (incident-first sobre Vite PWA)

Estado para continuar la sesión (incluso en la nube). Rama: **`feature/dashboard-incident-redesign`**.

## Contexto / decisión

El dashboard de prod se había migrado a **Expo / React Native** (repo aparte `Odisea_Dashboard`, alias git "Rottapaint") y quedó una regresión: lento, sin caché/PWA real, ~10% de las features, y sin APK. Se **revirtió al original Vite + React 19 + workbox PWA** (`src/dashboard`, ~90 componentes) y se está **rediseñando la IA a incident-first** de forma **aditiva** sobre ese stack, con estética **retro limpio** (sin CRT/animaciones de más).

- IA elegida: **incident-first** (Incidentes → Heatmap → Globe; detalle por ruta).
- Backend ya tiene los endpoints `/incidents*` (ver `odisea_central.py`).
- El workflow de prod del repo Expo quedó `disabled_manually` (no re-pisa prod).

## Qué está EN VIVO (https://odisea.educa.juegos)

- `/` = **dashboard clásico** `<App/>` intacto (header con link "Incidentes ▸").
- Shell nueva retro-limpia (`src/app/`):
  - `/investigate` — **Inbox/triage** de incidentes (filtros estado, acciones inline).
  - `/investigation/:id` — detalle: timeline FPS (recharts) + trayectoria X/Z (SVG) + acciones.
  - `/heatmap` — Heatmap3D + **nube de jugadores 3D por FPS** (toggle "Puntos 3D").
  - `/globe` — GlobeView/Globo3D.
- **Filtros globales** (`GlobalFilterBar`): escena (cruza Incidentes+Heatmap), país (Globo).

## Arquitectura de datos (lo importante)

Capa central `src/dashboard/src/data/`:
- `queryClient.ts` — **TanStack Query** + persistencia en **IndexedDB** (reusa `lib/idbCache.ts`) → pinta al instante al reabrir.
- `filters.store.ts` — **Zustand** persistido: `scene/country/platform/minDurationSec/windowMs`.
- `queries.ts` — hooks react-query (crudos + filtrados) + `useUpdateIncidentStatus` (mutación **optimista**, actualiza lista y detalle).
- `selectors.ts` — funciones **puras** (sin React) → testeables: `filterIncidents`, `filterGeoPlayers`, `countriesFromGeo`.

Regla: **las vistas son presentacionales**; nada de `fetch` ad-hoc, todo via el pipeline + filtros.

### Gotchas
- **SPA fallback del server** (resuelto): `odisea_central.py::handle_pwa_root_file` ahora sirve la SPA shell para **cualquier ruta de un segmento sin extensión** (p.ej. `/sessions`, `/live`, `/history`, `/hotzones`) — se eliminó el allowlist `html_routes` hardcodeado. Ya **no hace falta tocar el server** para agregar rutas nuevas al router del frontend. Rutas con extensión (parecen archivos) que no estén en el allowlist de PWA siguen dando 404; `/investigation/*` (multi-segmento) tiene su ruta dedicada.
- Tooltips de recharts: tipar el `content` como `any` (convención del repo).
- `Globo3D` y `Heatmap3D` son **compartidos con el clásico** — los cambios (sin arcos, leyenda compacta, labels HTML mono con escala por zoom, `ringAltitude`, prop opcional `ghosts`) son aditivos/seguros.
- react-globe.gl **2.38** (viejo): soporta `htmlElementsData`; `ringAltitude` no verificado a ojo.
- Verificación **visual con datos requiere login admin** (token del usuario) — hasta ahora solo se verificó build + routing + endpoints.

## Deploy

`cd src/dashboard && ./deploy.sh` → build (Vite) → rsync a staging → swap atómico → restart `odisea-central.service` → verifica. Preserva `scene-data/` de prod (lo del server manda; `OdiseaExterior.json` pesa 6.4MB). Backup del anterior en `static/dashboard.old`. Sirve desde `/home/ubuntu/anna-central/static/dashboard` (host `ubuntu@odisea.educa.juegos`).

## Pendiente (Fase 3 — necesita OK, riesgoso)

1. Portar a la shell nueva las vistas aún enredadas en `App.tsx` (2897 líneas, ~30 `useState`, `useTelemetry` por WS): **Live (3D/birdseye en tiempo real), Sesiones, Hotzones, History**.
2. Recién ahí **voltear `/`** a la shell nueva y **borrar `App.tsx`**.
3. ~~Agregar **SPA fallback genérico** en `odisea_central.py`.~~ **Hecho** (`handle_pwa_root_file`): rutas de un segmento sin extensión → SPA shell; se borró el allowlist `html_routes`. Las rutas nuevas del frontend ya no requieren cambios en el server.
4. Sumar filtros **plataforma/duración/ventana** cuando exista la vista Sesiones (ya están en el store).
5. ~~Tests de los `selectors.ts` puros y del pipeline.~~ **Hecho** (`src/data/selectors.test.ts`): vitest, 21 tests cubriendo `filterIncidents`, `filterGeoPlayers` (país case-insensitive, ventana de recencia con fake timers, combinados), `countriesFromGeo` (conteo/orden/normalización) y `applyIncidentStatusToList` (núcleo puro de la mutación optimista, extraído de `queries.ts`). Correr con `pnpm test`.

## Commits de la rama

`81474cc1` revert+scaffold (fase 0+1) · `152a0109` Heatmap/Globe (fase 2) · `6b48b660` link clásico→nuevo · `6ef59560` cache incidentes + pulido globo · `f01fcd93` pipeline TanStack Query + filtros globales · `724d3262` heatmap nube 3D.

> Nota: en el working tree puede haber cambios **ajenos** (`project.godot`, `.kilo/`, `CLAUDE.md`…) que NO son de este trabajo — no commitearlos acá.
