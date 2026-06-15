# FD-222: Dashboard milestones — integrar achievements en frontend

**Status:** Open
**Priority:** Medium
**Effort:** Small
**Created:** 2026-06-15
**Completed:** -

## Problem

El bridge (`odisea_central.py`) tiene un sistema completo de milestones/achievements: 18 hitos configurados (jugadores únicos, sesiones, horas de gameplay, heartbeats, FPS, concurrentes), endpoints `/api/milestones` y `/api/milestones/achieved`, detector que corre en tiempo real y persiste en SQLite. Pero el dashboard nunca integró el frontend — no hay componentes, ni llamadas API, ni UI.

## Solution

Agregar un panel de milestones/achievements en el dashboard.

### Backend (bridge)

Los endpoints ya existen y funcionan:
- `GET /api/milestones` — lista todos los milestones con su estado (achieved: true/false)
- `GET /api/milestones/achieved` — solo los alcanzados, ordenados por fecha

Respuesta de `/api/milestones`:
```json
[
  {"id": "players_10", "title": "10 jugadores únicos", "icon": "users", "achieved": true},
  {"id": "players_50", "title": "50 jugadores únicos", "icon": "users", "achieved": false},
  ...
]
```

Respuesta de `/api/milestones/achieved`:
```json
[
  {"milestone_id": "players_10", "title": "10 jugadores únicos", "icon": "users", "achieved_at": 1718000000, "value": 12},
  ...
]
```

### Frontend (dashboard)

Nuevo componente `DashboardMilestones.tsx`:

1. **Fetch**: llamar a `GET /api/milestones` para la lista completa + `GET /api/milestones/achieved` para los alcanzados con fecha/valor.
2. **Layout**: 2 estados:
   - Con achievements: mostrar los que ya se ganaron con icono, fecha y valor
   - Los no alcanzados: atenuados/blureados con candado
3. **Integración**: pestaña o panel en la sección History (o sidebar), accesible desde la navegación del dashboard.
4. **Iconos mapeados**:
   - `users` → 👥
   - `zap` → ⚡
   - `activity` → 📊
   - `clock` → 🕐
   - `heart` → ❤️
   - `play` → ▶️

### Estado actual de hitos alcanzados (según telemetría acumulada)

Ya deberían estar alcanzados (o cerca):
- ✅ `players_10` — 10 jugadores únicos
- ✅ `concurrent_5` — 5 jugadores simultáneos (posible)
- ✅ `heartbeats_10k` — 10,000 heartbeats
- ✅ `gameplay_1h` — 1 hora acumulada
- ✅ `sessions_10` — 10 sesiones de juego

## Files to Modify

1. `dashboard/src/components/DashboardMilestones.tsx` (new)
2. `dashboard/src/App.tsx` — importar y renderizar el nuevo componente
3. `dashboard/src/api.ts` — agregar funciones `getMilestones()` y `getAchievedMilestones()`

## Verification

1. Abrir dashboard → ver panel de milestones con los hitos alcanzados visibles y no alcanzados atenuados
2. Cada hito alcanzado muestra: icono, título, fecha, valor numérico
3. Llamar a `GET /api/milestones/achieved` directo desde la consola para verificar que matchea con la UI
4. Al lograr un nuevo hito (ej: sesión #100), aparece automáticamente al recargar
