# FD-223: Dashboard colapsable panels + Stats tab + Live default

**Status:** Open
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-06-15
**Completed:** -

## Problem

Tres issues de UI en el dashboard:

1. **Overlay de hotzones en el HeatMap** (`App.tsx` ~línea 2297): un div `absolute bottom-3 right-3` con la lista de hotzons siempre visible. Sin botón de colapsar. En mobile o pantallas chicas tapa contenido del mapa.
2. **Stats de History** (`HistoryOverview` ~línea 206): las 4 cards (Sessions, Players, Play Time, Avg FPS) + charts de sesiones/escenas/países solo se ven en desktop. No deberían estar en la página de History como cards fijas — deberían estar en una **pestaña independiente tipo "Stats"**, como funciona el HeatMap (que es una pestaña aparte).
3. **Charts de Live** (~línea 720): los gráficos de rendimiento en vivo deberían ser colapsables, redimensionables, y ser la **vista default** de la sección Live.

## Solution

### 1. Hotzone overlay colapsable en HeatMap

Agregar un componente reutilizable `CollapsibleCard` que envuelva la lista de hotzones:

```
┌─────────────────────────────┐
│ ▼ Hotzones (8)              │  ← clickeable
└─────────────────────────────┘
  (contenido oculto)
```

- Por defecto: colapsado (`defaultOpen: false`)
- Persistencia en `localStorage` con key `heatmap_hotzones_collapsed`
- Transición suave al expandir/colapsar
- El título muestra el count de hotzones

### 2. Stats como pestaña independiente (tipo HeatMap)

Actualmente las stats (Sessions, Players, Play Time, Avg FPS, escenas, países) están dentro de `HistoryOverview` como un grid de cards + charts. Moverlas a una **nueva pestaña** en el mismo nivel que "HeatMap" y "History".

En la navegación del panel lateral (donde está HeatMap, History, Live), agregar pestaña "Stats":

```
[Historia] [Calor] [Stats] [En Vivo]
```

Al hacer clic en "Stats", se muestra:
- Grid de 4 cards: Sessions, Players, Play Time, Avg FPS
- Charts: Sesiones por día, Top escenas, Top países (lo que ya existe en HistoryOverview)
- Misma data que History, solo que en una vista dedicada

Esto resuelve que las stats "solo se vean en desktop" — ahora tienen su propio panel accesible en cualquier tamaño.

### 3. Live charts colapsables + resizables + default view

- Envolver los charts de Live en un `CollapsibleCard` colapsable y redimensionable (usando react-resizable o un drag handle simple)
- Al entrar a la sección Live, que los charts estén **expandidos por defecto** (vista default)
- Persistencia del estado colapsado en `localStorage` con key `live_charts_collapsed`
- Resizable: arrastrar el borde inferior para cambiar el alto de los charts

## Files to Modify

1. `dashboard/src/components/retro/CollapsibleCard.tsx` (new) — componente reutilizable con toggle + animación + localStorage
2. `dashboard/src/App.tsx`:
   - Envolver hotzone overlay en CollapsibleCard (default colapsado)
   - Agregar pestaña "Stats" con las cards y charts extraídos de HistoryOverview
   - Envolver Live charts en CollapsibleCard (default expandido, resizable)
   - Marcar Live como vista default

## Verification

1. HeatMap → hotzone overlay colapsado por defecto, al toggle se expande la lista
2. Nueva pestaña "Stats" accesible desde la navegación, muestra cards + charts
3. HistoryOverview ya no muestra las cards stats (se movieron a su propia pestaña)
4. Live → charts colapsables y redimensionables, expandidos por defecto
5. Live es la vista default al entrar a la sección Live
6. Estados persisten al recargar (localStorage)
7. Sin regresión en mobile
