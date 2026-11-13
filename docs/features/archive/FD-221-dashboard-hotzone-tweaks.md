# FD-221: Dashboard hotzone tweaks — metadatos, colapso, build tag y mDNS

**Status:** Open
**Priority:** Medium
**Effort:** Small
**Created:** 2026-06-15
**Completed:** -

## Problem

Varios bugs y mejoras identificadas en el dashboard y telemetría bridge:

1. **#218 — Metadatos de hotzones no enriquecidos igualmente**: la lista "Capturas hotzone" muestra metadatos enriquecidos (player tag, timestamp, trigger_type) pero los markers en el HeatMap 3D no — se ven truncados o con menos datos.
2. **#219 — HeatMap hotzone markers no colapsables**: los markers flotantes del HeatMap siempre están expandidos. Deberían aparecer colapsados por defecto y expandirse al hacer clic.
3. **#220 — Build tag incorrecto en sesiones live**: en el panel HISTORY, las sesiones en vivo muestran "canary" aunque el build sea "official". El tag cambia solo cuando la sesión deja de ser live.
4. **#217 — mDNS no funciona en Anbernic**: el descubrimiento mDNS de peers falla desde dispositivos retro-handheld. No hay alternativa de descubrimiento local.

## Solution

### 1. Unificar enriquecimiento de metadatos (#218)

En `dashboard/src/components/Heatmap3D.tsx`, el componente `HotzoneMarkers` actualmente recibe `HotzoneMarker[]` con datos mínimos. Modificar para pasar los mismos campos enriquecidos que la lista de capturas: `display_name`, `player_id`, `timestamp`, `trigger_type`, `frame_count`, `capture_duration`.

Los markers deben mostrar al hacer hover/clic:
- Player name/alias
- Timestamp formateado
- Trigger type (auto/manual)
- File size / duration

### 2. Hotzone markers colapsables (#219)

Modificar `HotzoneMarkers` en `Heatmap3D.tsx`:
- Estado por defecto: colapsado — solo un pin 3D (esfera o cono rojo) sin label
- Al hacer clic: expande a un panel flotante con los metadatos enriquecidos y botones de acción (descargar, reproducir)
- Al hacer clic fuera o en otro marker: colapsa el anterior
- Animación suave de transición

### 3. Build tag en sesiones live (#220)

Investigar en el backend (`odisea_central.py`) y el dashboard:
- Los heartbeats live se almacenan en `ghosts` con campos `build_channel` y `official_build`.
- En `dashboard/src/App.tsx`, la función que mapea heartbeats a sesiones (`normalizeHeartbeat` o similar) probablemente asume `canary` cuando el build_channel no está presente en datos live.
- Solución: asegurar que el build_channel se incluya desde el primer heartbeat en ANNAV2. Si no está disponible, mostrar "unknown" en vez de asumir "canary".
- Si el heartbeat no trae build_channel, el bridge debería heredarlo de la sesión existente (primer heartbeat de esa sesión que sí lo tenga).

### 4. mDNS / descubrimiento local (#217)

- Probar mDNS en red local desde Anbernic para confirmar el fallo exacto.
- Si mDNS no funciona, implementar alternativa: broadcast UDP en puerto conocido (ej: 5500) para anunciar/descubrir peers.
- Alternativa más simple: configuración manual de IP del bridge en el cliente.
- Este issue es principalmente de testing + posible parche en ANNAV2 o script de conexión.

## Files to Modify

1. `dashboard/src/components/Heatmap3D.tsx` — enriquecer HotzoneMarkers + estado colapsable
2. `dashboard/src/App.tsx` — pasar metadatos enriquecidos a Heatmap3D
3. `dashboard/src/api.ts` — posible helper para formateo
4. `odisea_central.py` — asegurar que build_channel se herede en heartbeats live (si aplica)
5. ANNAV2 (`core_v2/telemetry/`) — asegurar que build_channel se envíe desde el primer heartbeat

## Verification

1. Hover sobre marker en HeatMap → tooltip con player name, timestamp, trigger
2. Click en marker → panel expandido con botones descargar/reproducir
3. Click en otro marker o fuera → colapsa el anterior
4. Sesión live en HISTORY → build tag correcto (official/canary/dev) desde el inicio
5. mDNS desde Anbernic → reportar resultado (éxito o fallo documentado)
