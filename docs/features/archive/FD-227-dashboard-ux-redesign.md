# FD-227: Dashboard UX Redesign — Cockpit Layout & Navigation Overhaul

**Status:** Open
**Priority:** High
**Effort:** Large (6 fases)
**Created:** 2026-06-18
**Completed:** -

## 1. Objetivo del rediseño

Rediseñar el dashboard de telemetría de Odisea para convertirlo en un centro de control condensado, orientado a dos perfiles principales:

1. **Desarrollador/debugger** — necesita detectar problemas técnicos, entender performance, reproducir fallos y relacionarlos con player, escena, plataforma, build y replay.
2. **Diseñador/productor** — necesita entender comportamiento, exploración, fricción, uso de escenas, trayectorias, hotzones y actividad histórica.

El dashboard no debe ser una colección de visualizaciones sueltas. Debe responder rápidamente: qué problemas técnicos están ocurriendo, qué players están activos, qué partes del juego están usando, qué zonas muestran fricción, y qué cambió desde el último build.

La acción principal ante un problema técnico es: abrir una sesión/replay contextual.

## 2. Principios de diseño

### 2.1 Dashboard como cockpit
La home debe funcionar como un cockpit condensado, no como landing visual ni tabla de datos. Debe mostrar simultáneamente: players activos, mapa/escena/heatmap, FPS y salud, timeline/eventos recientes, alertas y filtros globales activos.

### 2.2 Navegación por tareas y entidades
Reemplazar tabs técnicos (Live / Globe / Heatmap / History) por tabs misionales:

- Dashboard
- Scenes
- Players
- Analysis
- Replays

Las visualizaciones (globo, mapa 3D, heatmap, timelines) pasan a ser modos o componentes dentro de estas secciones.

### 2.3 Drilldown contextual
Abrir detalle no debe hacer perder el lugar. Preservar: player, escena, hotzone, build/commit, filtros actuales, métricas FPS/memoria, ruta de navegación previa.

### 2.4 Mobile-first, desktop completo
Mobile: navegación clara, consulta rápida, drilldown usable. Desktop: múltiples paneles simultáneos, más densidad, comparación, layout configurable/resizable.

## 3. Componentes existentes a reutilizar

| Componente | Uso |
|------------|-----|
| `CollapsibleCard` | Todo panel colapsable (Dashboard stats, charts) |
| `FiltersDrawer` / `FiltersSidebar` | Filtros globales (persisten entre tabs) |
| `PlayerBottomSheet` | Lista expandible de players en mobile |
| `PlayerCard` | Miniatura de player en Dashboard/Scenes |
| `PlayerFocus` | Vista detalle de un player |
| `PlayerTagEditor` | Edición de tags de player |
| `Heatmap3D` | Vista heatmap dentro de Scenes y Analysis |
| `Viewport3D` | Vista 3D dentro de Dashboard y Replays |
| `GlobeView` | Vista geo dentro de Players y Analysis |
| `LiveCombinedChart` | Charts de FPS/memoria en vivo en Analysis |
| `HistoricalTable` | Tabla de sesiones en Players y Analysis |
| `SessionPlayback` | Reproductor de sesión en Replays |
| `HotzonePlayerModal` | Modal de reproducción en Replays |
| `FpsTimeline` / `MemTimeline` | Timeline en Analysis |
| `SessionTimeline` | Timeline de eventos en session detail |
| `SceneGeometry` | Geometría de escena en Scene detail |
| `WebLoads` | Cargas web en Analysis |
| `useLayoutPersistence` | Persistencia de layout |
| `Badge`, `Button`, `Card`, `CollapsibleCard`, `Input`, `Tabs` | Design system retro |

## 4. Nuevos componentes a crear

| Componente | Descripción |
|------------|-------------|
| `AppShell` | Shell principal: Header + GlobalFiltersDrawer + PrimaryNav + MainContent + ContextPanel/OverlayHost |
| `NavigationRail` | Barra de navegación de 5 tabs (desktop top/mobile bottom) |
| `GlobalFilterBar` | Barra compacta de filtros activos con chips removibles |
| `CockpitGrid` | Layout grid responsive para Dashboard (2-3 columnas desktop, 1 mobile) |
| `CockpitPanel` | Panel individual dentro del CockpitGrid, colapsable + resizable |
| `ActivePlayersGrid` | Grid de players activos agrupados por escena |
| `PlayerHealthCard` | Card de FPS: número grande, sparkline, estado OK/warning/critical, target por plataforma |
| `PlayerDetailPanel` | Panel lateral/bottom sheet al seleccionar player |
| `PlayerSceneGroup` | Grupo de players dentro de una escena en el grid |
| `PlayerTrajectoryPreview` | Preview simplificada de trayectoria del player |
| `HealthScoreboard` | Scoreboard de estado: Sessions, Players, Play Time, Avg FPS |
| `SceneHealthCard` | Card de salud de escena: FPS avg/min, players activos, hotzones |
| `ScenesIndex` | Índice operativo de escenas |
| `SceneDetail` | Pantalla completa de detalle de escena |
| `SceneVisual` | Visual analítico-contextual de escena (3D/birdseye con overlays) |
| `SceneOverlayControls` | Controles para activar/desactivar overlays en SceneVisual |
| `SceneHotzonesPanel` | Hotzones agrupadas por escena |
| `SceneRecentTrajectories` | Trayectorias recientes en escena con prioridad visual |
| `EventTimeline` | Timeline compacto de eventos recientes |
| `AnalysisTimeline` | Timeline de rendimiento con markers de build/commit |
| `BuildMarkersLayer` | Capa de markers de build/commit sobre timeline |
| `BuildComparisonPanel` | Comparación lado a lado entre builds |
| `RegressionDetectorBar` | Barra que marca regresiones sugeridas |
| `HotzoneInbox` | Lista de hotzones recientes con score de prioridad |
| `HotzoneCard` | Card de hotzone: escena, severidad FPS, players afectados |
| `HotzoneCandidatesList` | Candidatos de replay para una hotzone (selección manual) |
| `HotzoneOverlay` | Overlay de hotzones sobre SceneVisual |
| `ReplaysHome` | Inicio de Replays = inbox de hotzones recientes |
| `ReplayContextPanel` | Panel contextual al abrir replay |
| `ReplayCandidateCard` | Card de candidato de replay |
| `ReplayBreadcrumb` | Breadcrumb de navegación contextual |
| `TagBadge` | Badge de tag |
| `TagPicker` | Selector de tags |
| `TagCategoryGroup` | Grupo de tags por categoría |
| `TaggableEntityEditor` | Editor genérico de tags/notas para entidad |
| `NotesField` | Campo de notas libres |
| `BreadcrumbNav` | Breadcrumb contextual |

## 5. Navegación principal

```
Odisea Central
├── Dashboard    (cockpit de triage)
├── Scenes       (índice operativo de escenas)
├── Players      (historial de todos los players)
├── Analysis     (rendimiento temporal y comparativo)
└── Replays      (inbox de hotzones + reproductor contextual)
```

### 5.1 Dashboard
Rol: vista principal de triage. Condensa: players activos agrupados por escena, visual espacial central, FPS health, problemas técnicos, timeline/eventos recientes, filtros globales activos.

### 5.2 Scenes
Rol: índice operativo de escenas. Muestra: escenas ordenadas por actividad reciente, health por escena, players activos, FPS agregado, hotzones, plataformas afectadas, CTA para abrir Scene Detail.

### 5.3 Players
Rol: historial de todos los players conocidos. Muestra: player_id como identidad técnica primaria, tags y notas como capa humana, sesiones, escenas visitadas, plataformas, performance, acceso a replays/sesiones.

### 5.4 Analysis
Rol: análisis temporal y comparativo con performance como eje. Inicia con timeline FPS/memoria con markers de build/commit. Roadmap: v1 timeline+markers, v1.5 filtro por build, v2 comparación lado a lado + regresiones.

### 5.5 Replays
Rol: espacio de investigación y reproducción. Inicia como inbox de hotzones recientes con candidatos de replay. Incluye: lista de sesiones/replays, búsqueda por player/escena/build/plataforma, reproductor contextual.

## 6. Dashboard principal (cockpit)

### 6.1 Jerarquía visual
- Foco principal: Players activos + Mapa/escena/heatmap
- Segundo nivel: HealthScoreboard + EventTimeline + Alertas

### 6.2 Layout Desktop
```
┌─────────────────────────────────────────────────────┐
│ Odisea Central · conexión · build · [filtros]       │  ← Header
├─────────────────────────────────────────────────────┤
│ [Dashboard] [Scenes] [Players] [Analysis] [Replays]  │  ← PrimaryNav
├─────────────────────────────────────────────────────┤
│ [Escena:X ✕] [Plataforma:Y ✕] [Warmup:13s]         │  ← GlobalFilterBar
├──────────────┬──────────────────────────────┬────────┤
│ Players      │ Mapa / Scene / Heatmap       │ Health │
│ agrupados    │ (Viewport3D o Heatmap3D)     │ FPS    │
│ por escena   │                              │ cards  │
│              │                              │ Alerts │
├──────────────┴──────────────────────────────┴────────┤
│ Timeline live / eventos recientes / sesiones         │
└──────────────────────────────────────────────────────┘
```

### 6.3 Layout Mobile
```
┌─────────────────────┐
│ Header compacto     │
├─────────────────────┤
│ Filtros: X, Y       │
├─────────────────────┤
▼ Scene/Player health │  ← CollapsibleCard, default open
▼ Mapa / visual       │  ← CollapsibleCard, default open
▼ Players por escena  │  ← CollapsibleCard, default open
▼ Timeline / alerts   │  ← CollapsibleCard, default collapsed
├─────────────────────┤
│ [NavRail bottom]     │
└─────────────────────┘
```

### 6.4 Players activos
Agrupados por escena actual. Dentro de cada escena, ordenar por urgencia: FPS crítico, FPS warning, OK, más reciente.

```
Dome_Crio
  - player_a · 22 FPS · critical · Android
  - player_b · 41 FPS · warning · Web
  - player_c · 58 FPS · OK · Linux
```

### 6.5 Problema individual vs problema de escena
- **Individual**: un player tiene FPS bajo.
- **De escena**: varios players tienen FPS bajo en la misma escena/zona, o hay patrón histórico repetido. Una escena puede mostrarse como "sospechosa" aunque no sea concluyente.

## 7. Player Selected State

### 7.1 Comportamiento
Al seleccionar un player: (1) el mapa/escena se centra en ese player, (2) se abre panel lateral o bottom sheet, (3) aparece overlay con acciones de drilldown.

### 7.2 Contenido del panel
- **Primary**: métricas técnicas actuales, trayectoria/posición actual.
- **Secondary CTAs**: tags/notas, historial, replay/sesión.

### 7.3 Health principal
FPS es la métrica primaria. La card debe incluir: número actual grande, sparkline reciente, estado OK/warning/critical, target aplicado.

Default target: 60 FPS general. Targets configurables por plataforma: Linux/Desktop, Windows, Android, Web.

## 8. Scene Detail

### 8.1 Rol
Scene Detail es una pantalla propia. La escena deja de ser solo un filtro y pasa a ser una entidad navegable.

Flujo: Dashboard / Scenes / Hotzone → abrir Scene Detail → investigar players, mapa, trayectorias, hotzones y replays.

### 8.2 Primer contenido visible
1. Players activos en esa escena.
2. Mapa / visual 3D / birdseye de la escena.
3. Después: hotzones, FPS/memoria agregada, sesiones/replays recientes.

### 8.3 Visual de escena
Analítico-contextual. Primary: overlays de players, trayectorias, hotzones. Secondary: contexto visual bonito/legible de la escena. No debe ser solo un visor 3D libre.

### 8.4 Overlays default
Activar por defecto: players activos + trayectorias recientes. Overlays opcionales: hotzones FPS, densidad histórica, FPS/memoria, build/plataforma.

### 8.5 Trayectorias adaptativas
- **Zoom out**: trazos simplificados, patrones generales.
- **Zoom medio**: trayectorias recientes, dirección/recencia visible.
- **Zoom in / player seleccionado**: trayectoria detallada, eventos técnicos, acceso a replay.

Prioridad visual: player seleccionado > players activos > trayectorias más recientes > resto atenuado.

## 9. Hotzones v1

### 9.1 Definición
Una hotzone v1 se define principalmente como FPS bajo repetido en una zona. Señales futuras (no implementar ahora): players detenidos mucho tiempo, deaths/fails/retries, softlocks, tiempo excesivo sin progreso.

### 9.2 Lente primario
Hotzone debe presentarse principalmente como problema de escena. Lentes secundarios: player afectado, plataforma, build/commit, sesión/replay.

### 9.3 CTA principal
Cada hotzone debe tener dos acciones fuertes: (1) abrir replay candidato, (2) abrir detalle de escena. Acciones secundarias: ver players afectados, comparar por plataforma, comparar por build/commit.

### 9.4 Replay representativo
NO persistir replay representativo. Hotzone → muestra candidatos de replay → usuario elige manualmente cuál abrir → la elección no queda guardada como metadata.

### 9.5 Estados de revisión
NO implementar estados de revisión en v1 (nueva/revisada/en investigación/resuelta/bug/falso positivo). Hotzones v1 son señales analíticas, no workflow de gestión.

## 10. Replays

### 10.1 Rol
Sección de investigación. Entrada principal: inbox de hotzones recientes.

### 10.2 Orden default
Por recencia. Cada item muestra: escena, severidad FPS, cantidad de eventos, players afectados, plataforma/build, candidatos de replay.

### 10.3 Apertura contextual
- Desde Dashboard: overlay/drawer rápido.
- Desde Scene Detail: panel integrado a escena.
- Desde Replays: pantalla/panel dedicado.
- Desde Player: replay con contexto del player.
- Desde Analysis: replay con contexto de build/performance.

### 10.4 Contexto preservado
Preservar siempre: player, escena/hotzone, build/commit, FPS/memoria, filtros activos, ruta de navegación previa. Abrir replay no debe hacer perder el lugar.

## 11. Analysis

### 11.1 Eje primario
Performance. Debe permitir analizar: FPS/memoria por tiempo, por escena, por plataforma, por build/commit. Secundario: comportamiento, actividad, sesiones, comparación de builds.

### 11.2 Vista inicial
Timeline FPS/memoria + markers de build/commit. Objetivo: ver cuándo cambió el rendimiento, asociar caídas con releases, detectar regresiones.

### 11.3 Roadmap
- v1: timeline con markers.
- v1.5: filtro por build.
- v2: comparación lado a lado + detección sugerida de regresiones. (v2 out of scope ahora)

## 12. Tags transversales

### 12.1 Entidades taggeables
Tags aplican a: player, session, hotzone, scene. Más adelante build/release.

### 12.2 Tags de player
Identidad primaria: player_id técnico. Capa humana: tags, notas, display name, aliases/contexto manual.

### 12.3 Categorías sugeridas
- Persona/contexto: tester interno, invitado, QA, niño.
- Dispositivo/plataforma: low-end, Android viejo, web, laptop.
- Comportamiento: explora, se pierde, speedrunner, rompe cosas.
- Seguimiento: mirar después, confiable, bug repro, interesante.

### 12.4 UX v1
Tags con categorías predefinidas + sugerencias rápidas + posibilidad de crear tags nuevos + notas libres aparte. No sobre-especificar taxonomía global.

## 13. Filtros globales

### 13.1 Modelo v1
Filtros globales: afectan todas las secciones, persisten al navegar, se preservan al abrir replay, se muestran como chips en dashboard.

- **Filtros principales**: escena, plataforma.
- **Filtros existentes a mantener**: país, warmup.
- **Filtros secundarios/futuros**: player, build/commit, fecha/rango temporal, FPS threshold, solo hotzones.

### 13.2 UI de filtros
Desktop: panel lateral/drawer. Mobile: drawer lateral. No usar bottom sheet ni página separada.

### 13.3 Warmup filter
Excluye primeros N segundos después de cada cambio de escena. Default 13s, configurable. Vive dentro del panel de filtros, no como control permanente. Mostrar chip "Warmup: 13s" cuando activo.

## 14. Flujos principales

### 14.1 Problema técnico → replay
Dashboard → detectar player/escena con FPS bajo → seleccionar → ver contexto técnico → abrir replay candidato → volver sin perder filtros.

### 14.2 Escena problemática → Scene Detail
Dashboard/Scenes → escena con warning → abrir Scene Detail → players activos + trayectorias → activar hotzones → abrir replay candidato o analizar FPS.

### 14.3 Hotzone → investigación
Replays → inbox de hotzones recientes → hotzone → revisar candidatos → elegir replay manualmente → reproducir.

### 14.4 Player → historia
Dashboard/Players → seleccionar player → métricas actuales o resumen histórico → tags/notas → sesiones/replays relacionados.

### 14.5 Analysis → regresión
Analysis → timeline FPS/mem → detectar caída → marker build/commit → filtrar escena/plataforma → sesiones/replays relacionados.

## 15. Criterios de aceptación v1

### Dashboard
- Players activos agrupados por escena.
- Seleccionar player centra visual espacial y muestra panel con FPS, memoria, escena, plataforma, trayectoria.
- FPS es health primaria. Target default 60 FPS, ajustable por plataforma.
- Muestra filtros globales activos como chips.

### Scenes
- Índice de escenas ordenado por actividad reciente.
- Cada escena muestra health, players activos, FPS agregado, hotzones.
- Permite abrir Scene Detail.

### Scene Detail
- Players activos + visual de escena como foco inicial.
- Overlays default: players activos y trayectorias recientes.
- Trayectorias adaptativas por zoom.
- Permite activar overlays de hotzones.

### Hotzones
- Definición v1: FPS bajo repetido en una zona.
- Agrupadas y presentadas por escena.
- Sin estados de revisión, sin replay representativo persistente.
- Elección manual de candidato al investigar.

### Replays
- Inbox de hotzones recientes como entrada principal.
- Orden default por recencia.
- Abrir replay preserva contexto completo.

### Analysis
- Timeline FPS/memoria con markers de build/commit.
- Permite relacionar performance con releases/builds.

### Filtros
- Globales afectan todas las secciones.
- Principales: escena y plataforma.
- Mantener país y warmup (default 13s, configurable).
- Warmup en panel de filtros.

### Responsive
- Mobile-first. Desktop multi-panel simultáneo, resizable/configurable.

## 16. No objetivos v1

No implementar todavía:
- Workflow de revisión de hotzones (estados bug/falso positivo/resuelto).
- Replay representativo persistente.
- Detección avanzada de behavior hotzones.
- Comparación completa lado a lado entre builds.
- Detección automática robusta de regresiones.
- Taxonomía estricta global de tags.
- Backend complejo para layout compartido entre dispositivos.

## 17. Roadmap sugerido

### Fase 1 — IA y shell
- Reemplazar navegación actual por: Dashboard, Scenes, Players, Analysis, Replays.
- Crear AppShell con filtros globales y contexto persistente.
- Mantener compatibilidad con vistas actuales donde sea posible.

### Fase 2 — Dashboard cockpit
- ActivePlayersGrid agrupados por escena.
- PlayerHealthCard con FPS + sparkline + targets.
- Mapa/escena central integrado.
- PlayerDetailPanel al seleccionar.
- GlobalFilterBar con chips.

### Fase 3 — Scene Detail
- ScenesIndex + SceneCard + SceneDetail.
- Players activos, trayectorias adaptativas, overlays.
- Hotzones por escena.

### Fase 4 — Replays contextual
- Replays inbox por hotzones recientes.
- HotzoneCandidatesList (selección manual).
- Apertura preservando contexto.

### Fase 5 — Analysis performance
- AnalysisTimeline FPS/memoria + BuildMarkersLayer.
- Filtros por escena/plataforma.
- Sesiones relacionadas.

### Fase 6 — Tags transversales
- Modelo taggable flexible.
- Tags en players primero. Extender a sesiones, hotzones, escenas.

## 18. Files to Create

```
dashboard/src/components/AppShell.tsx
dashboard/src/components/NavigationRail.tsx
dashboard/src/components/GlobalFilterBar.tsx
dashboard/src/components/CockpitGrid.tsx
dashboard/src/components/CockpitPanel.tsx
dashboard/src/components/ActivePlayersGrid.tsx
dashboard/src/components/PlayerHealthCard.tsx
dashboard/src/components/PlayerDetailPanel.tsx
dashboard/src/components/PlayerSceneGroup.tsx
dashboard/src/components/PlayerTrajectoryPreview.tsx
dashboard/src/components/HealthScoreboard.tsx
dashboard/src/components/SceneHealthCard.tsx
dashboard/src/components/ScenesIndex.tsx
dashboard/src/components/SceneDetail.tsx
dashboard/src/components/SceneVisual.tsx
dashboard/src/components/SceneOverlayControls.tsx
dashboard/src/components/SceneHotzonesPanel.tsx
dashboard/src/components/SceneRecentTrajectories.tsx
dashboard/src/components/EventTimeline.tsx
dashboard/src/components/AnalysisTimeline.tsx
dashboard/src/components/BuildMarkersLayer.tsx
dashboard/src/components/BuildComparisonPanel.tsx
dashboard/src/components/RegressionDetectorBar.tsx
dashboard/src/components/HotzoneInbox.tsx
dashboard/src/components/HotzoneCard.tsx
dashboard/src/components/HotzoneCandidatesList.tsx
dashboard/src/components/HotzoneOverlay.tsx
dashboard/src/components/ReplaysHome.tsx
dashboard/src/components/ReplayContextPanel.tsx
dashboard/src/components/ReplayCandidateCard.tsx
dashboard/src/components/ReplayBreadcrumb.tsx
dashboard/src/components/TagBadge.tsx
dashboard/src/components/TagPicker.tsx
dashboard/src/components/TagCategoryGroup.tsx
dashboard/src/components/TaggableEntityEditor.tsx
dashboard/src/components/NotesField.tsx
dashboard/src/components/BreadcrumbNav.tsx
```

## 19. Files to Modify

| File | Changes |
|------|---------|
| `dashboard/src/App.tsx` | Refactor: integrar AppShell, nuevo sistema de tabs, extraer lógica a componentes |
| `dashboard/src/types.ts` | Agregar `Tab = 'dashboard' | 'scenes' | 'players' | 'analysis' | 'replays'`, tipos para navStack, SceneHealth, HotzonePriority, PlayerTargets, Tag |
| `dashboard/src/hooks/useLayoutPersistence.ts` | Extender para navStack, panel collapsed states, sizes |
| `dashboard/src/components/DashboardLayout.tsx` | Integrar NavigationRail + GlobalFilterBar + breadcrumb |
| `dashboard/src/components/DashboardTabs.tsx` | Reemplazar por 5 nuevos tabs |
| `dashboard/src/components/retro/CollapsibleCard.tsx` | Agregar prop defaultOpen, persistencia vía localStorage key |
| `dashboard/src/components/PlayerCard.tsx` | Extender: FPS actual, escena activa, plataforma |
| `dashboard/src/components/Heatmap3D.tsx` | Aceptar props de filtro (sceneId, playerId, timeRange) |
| `dashboard/src/components/Viewport3D.tsx` | Aceptar filter prop + modo ghosts históricos |

## 20. Notas de implementación

- **Prioridad**: Fase 1 (shell + navegación) + Fase 2 (cockpit dashboard) > Fase 3-6.
- **Persistencia de layout**: localStorage para desktop en v1. Default fijo en mobile.
- **Targets FPS por plataforma**: configurables, almacenar en useLayoutPersistence o constante.
- **Warmup filter**: los 13s default deben excluirse de métricas de health y hotzones.
- **Hotzone definición técnica**: FPS bajo repetido = N muestras consecutivas por debajo de threshold en la misma zona. Threshold y N pendientes de definir en implementación.
- **Trayectorias**: los datos existen en ghost positions. Definir límite de historial (N minutos/horas) y nivel de detalle por zoom.
