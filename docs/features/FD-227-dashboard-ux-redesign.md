# FD-227: Dashboard UX Redesign — Cockpit Layout & Navigation Overhaul

**Status:** Open
**Priority:** High
**Effort:** Large
**Created:** 2026-06-18
**Completed:** -

## Problem

El dashboard actual es una colección de visualizaciones sueltas organizadas por tecnología (`Live / Globe / Heatmap / History`) en vez de por tareas del usuario. Esto obliga al desarrollador/productor a saber de antemano bajo qué tab buscar cada cosa, y dificulta el drilldown contextual.

Problemas concretos identificados:

1. **Home sin foco** — la landing (`Live` tab) muestra stats y charts genéricos en vez de un cockpit condensado con players activos, problema y mapa.
2. **Navegación técnica** — `Heatmap`, `Globe` y `History` son conceptos de implementación, no de tarea del usuario. Un diseñador que busca "¿qué escenas tienen baja performance?" no sabe si entrar a Heatmap o History.
3. **Drilldown sin contexto** — al abrir un player o sesión se pierde el contexto (escena, build, filtros).
4. **Layout estático** — no es resizable ni adaptable a distintas prioridades (debugging vs diseño).
5. **Mobile vs desktop** — las vistas de escritorio desperdician espacio horizontal; mobile tiene overlays que compiten.

## Solution

Rediseñar el dashboard como **cockpit condensado** con navegación orientada a tareas, usando componentes reutilizables existentes y nuevos.

### 5-Tab Navigation (Mission-Oriented)

Reemplazar `live / heatmap / history / mapa` por:

| Tab | Propósito | Equivale (parcialmente) a |
|-----|-----------|--------------------------|
| **Dashboard** | Cockpit de triage: players activos, mapa, alerts, timeline | `live` + `heatmap` stats |
| **Scenes** | Índice operativo de escenas y su salud | parte de `heatmap` + `history` |
| **Players** | Historial de todos los players conocidos | disperso en `live` + `history` |
| **Analysis** | Rendimiento temporal, comparación de builds | stats dispersos en `history` + FD-224 |
| **Replays** | Inbox de hotzones, sesiones, reproductor | `history` hotzones |

### Componentes Reutilizables (nuevos y existentes)

#### Existentes (reutilizar sin cambios o con ajustes mínimos)

| Componente | Uso en nuevo diseño |
|------------|---------------------|
| `CollapsibleCard` | Todo panel colapsable (Dashboard stats, charts) |
| `FiltersDrawer` / `FiltersSidebar` | Filtros globales (persisten entre tabs) |
| `PlayerBottomSheet` | Lista expandible de players en mobile |
| `PlayerCard` | Miniatura de player en Dashboard/Scenes |
| `PlayerFocus` | Vista detalle de un player |
| `PlayerTagEditor` | Edición de tags de player |
| `PlayerBottomSheet` | Lista de players en Dashboard home |
| `Heatmap3D` | Vista heatmap dentro de Scenes y Analysis |
| `Viewport3D` | Vista 3D dentro de Dashboard y Replays |
| `GlobeView` | Vista geo dentro de Players y Analysis |
| `LiveCombinedChart` | Charts de FPS/memoria en vivo en Analysis |
| `HistoricalTable` | Tabla de sesiones en Players y Analysis |
| `SessionPlayback` | Reproductor de sesión en Replays |
| `HotzonePlayerModal` | Modal de reproducción en Replays |
| `FpsTimeline` / `MemTimeline` | Timeline FPS/memoria en Analysis |
| `SessionTimeline` | Timeline de eventos en session detail |
| `SceneGeometry` | Geometría de escena en Scene detail |
| `WebLoads` | Cargas web en Analysis |
| `useLayoutPersistence` | Persistencia de layout colapsable/resizable |
| `Badge`, `Button`, `Card`, `CollapsibleCard`, `Input`, `Tabs` | Design system retro |

#### Nuevos componentes

| Componente | Descripción |
|------------|-------------|
| `CockpitGrid` | Layout grid responsive para el Dashboard (2/3 columnas en desktop, 1 columna mobile). Soporta drag-resize entre paneles. |
| `CockpitPanel` | Panel individual dentro del CockpitGrid. Título, colapsable via CollapsibleCard, resizable. |
| `ActivePlayersGrid` | Grid de players activos agrupados por escena, con FPS, plataforma y última posición. Click → PlayerFocus. |
| `SceneHealthCard` | Card de salud de escena: FPS avg/min, players activos, hotzone count, último evento. Click → Scene detail. |
| `EventTimeline` | Timeline compacto de eventos recientes (conexión, disconexión, alerta, hotzone capturada). |
| `AnalysisTimeline` | Timeline de rendimiento con markers de build/commit. Zoom, brush, overlay de FPS/memoria. |
| `BuildComparisonPanel` | Comparación lado a lado entre dos builds (FPS, memoria, draw calls). |
| `RegressionDetectorBar` | Barra que marca regresiones sugeridas automáticamente al comparar builds. |
| `HotzoneInbox` | Lista de hotzones recientes con score de prioridad (low FPS, duración, player). |
| `NavigationRail` | Barra de navegación lateral (desktop) o bottom bar (mobile) con los 5 tabs. |
| `GlobalFilterBar` | Barra compacta de filtros activos (escena, plataforma, build) visible siempre. |

### Layout Desktop

```
┌─────────────────────────────────────────────────────┐
│ Odisea Central  [⟐]  [NavigationRail]  [user]       │  ← Header
├─────────────────────────────────────────────────────┤
│ [Dashboard] [Scenes] [Players] [Analysis] [Replays]  │  ← Top Tabs (desktop) / Bottom Nav (mobile)
├─────────────────────────────────────────────────────┤
│ [Filtros activos: escena=X | plataforma=Y] [⟳]      │  ← GlobalFilterBar
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌───────────────┐ ┌─────────────────────────────┐   │
│  │ CockpitPanel  │ │ CockpitPanel                │   │
│  │ Players activos│ │ Mapa / Escena / Heatmap    │   │
│  │ ▼ agrupados   │ │ (Viewport3D o Heatmap3D    │   │
│  │ por escena    │ │  según contexto)            │   │
│  └───────────────┘ └─────────────────────────────┘   │
│  ┌───────────────┐ ┌─────────────────────────────┐   │
│  │ CockpitPanel  │ │ CockpitPanel                │   │
│  │ Scoreboard    │ │ EventTimeline               │   │
│  │ (Sessions,    │ │ (últimos eventos)            │   │
│  │  Players,     │ └─────────────────────────────┘   │
│  │  Play Time,   │                                   │
│  │  Avg FPS)     │                                   │
│  └───────────────┘                                   │
└─────────────────────────────────────────────────────┘
```

### Layout Mobile (single column, scroll)

```
┌─────────────────────┐
│ [NavigationRail]     │  ← Bottom bar (5 tabs)
├─────────────────────┤
│ [Dashboard] activo   │
├─────────────────────┤
│ Filtros activos: X  │  ← GlobalFilterBar compacta
├─────────────────────┤
│ ▼ Players activos   │  ← CollapsibleCard, default open
│ │ player1 (45fps)   │
│ │ player2 (30fps)   │
├─────────────────────┤
│ ▼ Mapa              │  ← CollapsibleCard, default open
│ │ [Viewport3D]      │
├─────────────────────┤
│ ▼ Scoreboard        │  ← CollapsibleCard, default collapsed
├─────────────────────┤
│ ▼ Eventos recientes │  ← CollapsibleCard, default collapsed
└─────────────────────┘
```

### Each Tab Detail

#### 1. Dashboard

Vista principal de triage. Dos modos: **live** (cuando hay players activos) y **summary** (cuando no hay nadie conectado).

**Componentes en el CockpitGrid:**

Paneles fijos:
- **ActivePlayersGrid** — players conectados ahora, agrupados por escena. Cada card muestra: player_id, display_name, FPS (con fpsColor), escena, plataforma, última posición. Click → PlayerFocus. Click en escena → filtra por esa escena.
- **Viewport3D o Heatmap3D** — visualización central. Por defecto: Viewport3D con ghosts en vivo. Si no hay ghosts vivos: Heatmap3D agregado de la última hora.
- **Scoreboard (HomeStats existente)** — Sessions total, Players únicos, Play Time total, Avg FPS general. Números grandes, minimal.
- **EventTimeline** — últimos N eventos: conexiones, disconexiones, alertas, hotzones capturadas. Scroll infinito virtualizado.

**Modo summary** (sin players activos):
- `SessionsPerDayChart` existente como gráfico principal
- Heatmap3D de últimas 24h
- `HotzoneInbox` con hotzones recientes priorizados

#### 2. Scenes

Índice operativo de escenas. Reemplaza la vista "scenes" del heatmap actual.

**Layout:**

```
┌─────────────────────────────────────────────────┐
│ Buscar escena...  [Plataforma▼] [Build▼]        │  ← FilterBar
├─────────────────────────────────────────────────┤
│                                                  │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐│
│ │ SceneHealth  │ │ SceneHealth │ │ SceneHealth  ││
│ │ Dome_Crio    │ │ Scaffold    │ │ Exterior     ││
│ │ 45fps avg    │ │ 30fps avg   │ │ 55fps avg    ││
│ │ 2 players    │ │ 0 players   │ │ 1 player     ││
│ │ ▶ Detail     │ │ ▶ Detail    │ │ ▶ Detail     ││
│ └─────────────┘ └─────────────┘ └─────────────┘│
│  [▼ Ver más escenas]                            │
└─────────────────────────────────────────────────┘
```

**SceneHealthCard** existente (mejorada):
- Nombre de escena con icono
- FPS promedio y mínimo (última hora / última sesión)
- Players activos ahora (o "0 — última visita: hace 2h")
- Hotzone count (últimas 24h)
- Build más reciente reportado
- Último evento: "hotzone capturada", "player conectado", etc.
- CTA: "Abrir detalle" → muestra Heatmap3D de esa escena + lista de sesiones + FpsTimeline

**Scene Detail** (drilldown):
- Heatmap3D filtrado por esa escena
- Lista de sesiones recientes en esa escena (HistoricalTable)
- FpsTimeline limitado a esa escena
- Players que visitaron esa escena
- Hotzones capturadas en esa escena

#### 3. Players

Catálogo de todos los players conocidos.

**Layout:**

```
┌─────────────────────────────────────────────────┐
│ [Lista] [Globe] [Tags]                          │  ← Sub-views
├─────────────────────────────────────────────────┤
│                                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ PlayerCard / PlayerFocus                    │ │
│ │ (reutilizado del existente)                  │ │
│ │                                              │ │
│ │ player_id: sebastian_libre                   │ │
│ │ display_name: Sebastian (editable)           │ │
│ │ tags: [dev] [design] [nightly]              │ │
│ │ última sesión: hace 5min                     │ │
│ │ escenas: Dome_Crio, Scaffold, Exterior      │ │
│ │ plataformas: Linux, HTML5                    │ │
│ │ FPS avg: 42.3                                │ │
│ │ ▶ Ver sesiones ▶ Ver replays                │ │
│ └─────────────────────────────────────────────┘ │
│  [▼ Ver más players — scroll virtualizado]      │
└─────────────────────────────────────────────────┘
```

**Sub-views:**
- **Lista** — tabla/search/filtro de players con PlayerCard. Virtualizada.
- **Globe** — GlobeView existente, mostrando ubicación geográfica de players conocidos.
- **Tags** — vista agrupada por tags (dev, designer, tester, etc.). Misma data, organizada por tag.

**Drilldown:** click en player → PlayerFocus (existente) con sus sesiones, escenas, performance histórico.

#### 4. Analysis

Análisis temporal de rendimiento y comparación entre builds. Donde viven los timelines y charts.

**Sub-views:**

- **Timeline** — `AnalysisTimeline`: FPS y memoria over time, con markers de build/commit. Reutiliza `FpsTimeline` y `MemTimeline` existentes. Zoom y brush integrados.
- **Comparar builds** — `BuildComparisonPanel`: dos builds lado a lado. Métricas: FPS avg/min/max, memoria avg, draw calls. `RegressionDetectorBar` sugiere regresiones automáticamente.
- **Plataformas** — breakdown por plataforma (reutiliza `LiveCombinedChart`).
- **Escenas** — rendimiento por escena (reutiliza `SceneHealthCard` y `Heatmap3D` filtrado).

**Layout:**

```
┌─────────────────────────────────────────────────────┐
│ [Timeline] [Comparar Builds] [Plataformas] [Escenas] │
├─────────────────────────────────────────────────────┤
│                                                      │
│ ┌─────────────────────────────────────────────────┐ │
│ │ AnalysisTimeline                                 │ │
│ │ [═══════════════•═══════•══════════════]        │ │
│ │ FPS ████████░░░░▓▓▓▓▓████████                  │ │
│ │ Mem ████░░░░▓▓▓▓▓██████░░░░                   │ │
│ │     ^build1  ^build2  ^build3                 │ │
│ │ [⇤] [⇥] [🔍]                                 │ │
│ └─────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────┐ │
│ │ BuildComparisonPanel (cuando se seleccionan 2)  │ │
│ │ build1 vs build3                                │ │
│ │ FPS: 42 → 38 ▼                                 │ │
│ │ Mem: 180 → 195 ▲                               │ │
│ │ ⚠ Posible regresión detectada                  │ │
│ └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

#### 5. Replays

Centro de investigación y reproducción de hotzones/sesiones.

**Inbox** (vista default):
- `HotzoneInbox`: hotzones recientes ordenadas por prioridad. Criterios: FPS mínimo bajo (<30), duración significativa (>5s), hotzone manual (disparada por dev). Cada item: escena, player, FPS min, duración, timestamp, trigger type. CTA: "Reproducir" → HotzonePlayerModal.
- Botón "Navegar todo" → vista completa.

**Full view:**
- Tabla de hotzones/sesiones (reutiliza `HistoricalTable`) con búsqueda y filtros: player, escena, build, plataforma, fecha.
- Al seleccionar: `SessionPlayback` (existente) o `HotzonePlayerModal` (existente) según tipo.

### GlobalFilterBar

Barra siempre visible debajo de la navegación principal. Muestra chips de filtros activos:

```
[Escena: Dome_Crio ✕] [Plataforma: Linux ✕] [Build: ff17c82b ✕] [+ Añadir filtro]
```

- Cada chip es clickeable para remover el filtro
- "+ Añadir filtro" abre FiltersDrawer/FiltersSidebar (existente)
- Los filtros persisten al cambiar de tab
- Estado: colapsable en mobile (toggle eye icon)

### NavigationRail vs BottomNav

**Desktop (≥1024px):**
- `NavigationRail` vertical en el lado izquierdo (ícono + label, 5 items)
- O bien: top bar horizontal como hoy, pero con los nuevos 5 tabs
- Decisión: usar top bar horizontal por consistencia con el diseño actual, pero renombrar los tabs. La rail vertical se evalúa como variante.

**Mobile (<1024px):**
- Bottom nav bar fija con 5 íconos + labels cortos
- El contenido principal scrolea arriba

### Preservación de Contexto en Drilldown

Toda navegación a detalle (player, escena, sesión, hotzone) preserva:
- Filtros globales activos (escena, plataforma, build)
- player_id (si aplica)
- Ruta de navegación: breadcrumb "Dashboard > Scenes > Dome_Crio"
- Botón "Volver" que regresa exactamente a donde estaba

Implementación:
- `useLayoutPersistence` se extiende para guardar el stack de navegación (`navStack: Array<{tab, view, params}>`)
- Breadcrumb component: `<Breadcrumb items={[{label, tab, params}]} />`
- Al hacer drilldown, se pushea a `navStack`. Al volver, se pope.

## Files to Create

| File | Component |
|------|-----------|
| `dashboard/src/components/CockpitGrid.tsx` | Layout grid responsive con drag-resize |
| `dashboard/src/components/CockpitPanel.tsx` | Panel colapsable/resizable |
| `dashboard/src/components/ActivePlayersGrid.tsx` | Grid de players activos |
| `dashboard/src/components/SceneHealthCard.tsx` | Card de salud de escena |
| `dashboard/src/components/EventTimeline.tsx` | Timeline compacto de eventos |
| `dashboard/src/components/AnalysisTimeline.tsx` | Timeline de rendimiento con build markers |
| `dashboard/src/components/BuildComparisonPanel.tsx` | Comparación lado a lado de builds |
| `dashboard/src/components/RegressionDetectorBar.tsx` | Barra de regresiones sugeridas |
| `dashboard/src/components/HotzoneInbox.tsx` | Inbox de hotzones priorizado |
| `dashboard/src/components/NavigationRail.tsx` | Barra de navegación de 5 tabs |
| `dashboard/src/components/GlobalFilterBar.tsx` | Barra compacta de filtros activos |
| `dashboard/src/components/BreadcrumbNav.tsx` | Breadcrumb contextual |

## Files to Modify

| File | Changes |
|------|---------|
| `dashboard/src/App.tsx` | Refactor: reemplazar tabs actuales por 5 nuevos tabs. Extraer lógica de cada vista a componentes separados. Integrar CockpitGrid, GlobalFilterBar. |
| `dashboard/src/types.ts` | Agregar `Tab = 'dashboard' \| 'scenes' \| 'players' \| 'analysis' \| 'replays'`. Agregar tipos para navStack, SceneHealth, HotzonePriority. |
| `dashboard/src/hooks/useLayoutPersistence.ts` | Extender para guardar navStack, panel collapsed states, panel sizes. |
| `dashboard/src/components/DashboardLayout.tsx` | Wrapper que integra NavigationRail + GlobalFilterBar + breadcrumb. |
| `dashboard/src/components/DashboardTabs.tsx` | Reemplazar tabs existentes con los 5 nuevos. |
| `dashboard/src/components/retro/CollapsibleCard.tsx` | Agregar prop `defaultOpen` si no tiene. Soporte para persistencia vía key en localStorage. |
| `dashboard/src/components/PlayerCard.tsx` | Extender para mostrar FPS actual, escena activa, plataforma. |
| `dashboard/src/components/Heatmap3D.tsx` | Hacerlo aceptar props de filtro (sceneId, playerId, timeRange) para reutilización en Scenes y Analysis. |
| `dashboard/src/components/Viewport3D.tsx` | Hacerlo aceptar filter prop y modo "ghosts históricos" (no solo live). |

## Out of Scope

- Rediseño del LoginScreen (queda igual)
- Reproductor de hotzone (FD-226 aparte)
- Performance code review (FD-224 aparte)
- Backend / bridge changes (todo es frontend dashboard)
- Service worker / PWA behavior (no cambia)
- Notificaciones push (no cambia)

## Verification

1. Dashboard home: muestra ActivePlayersGrid + Mapa + Scoreboard + EventTimeline
2. Players activos agrupados por escena, click → PlayerFocus
3. NavigationRail: 5 tabs funcionan, cada una muestra la vista correcta
4. GlobalFilterBar: filtros persisten entre tabs, chips removibles
5. Drilldown: breadcrumb visible, "Volver" regresa al estado anterior
6. Mobile: bottom nav, single column, CollapsibleCards por defecto
7. Desktop: CockpitGrid con 2 paneles, panel derecho resizable
8. Análisis: BuildComparisonPanel muestra regresiones sugeridas
9. Replays: HotzoneInbox muestra hotzones priorizadas
10. Sin regresiones en mobile
11. Persistencia: layout (colapsado/tamaños/tab activo) sobrevive recarga
