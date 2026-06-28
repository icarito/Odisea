# FD-242: DDC Drone + Sigilo Básico

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-23

## Problem

El enemigo DDC (drone de patrulla) es necesario para generar tensión en el Acto I. Actualmente existe solo como spec conceptual (FD-029, 4 líneas: "NPC with patrol path + detection zone"). No hay implementación de patrulla, detección, alerta, ni mecánicas de sigilo para el jugador.

## Solution

Construir sobre AgentBase (Etapa A del FD-241) + sistema de sigilo paralelo.

### Etapa A — AgentBase (compartido con FD-241)
Misma clase base. DDC hereda estados: `PATROL`, `ALERT`, `SEARCH`, `RETURN`.

### Etapa C: DDC — Comportamiento de patrulla y detección
- `DDCDroneV2.gd` hereda de AgentBase
- Patrol path: sigue waypoints en bucle con pausas configurables
- Cono de visión 3D: detecta al jugador por ángulo y distancia
- Estados: PATROL → ALERT (cono se agranda, velocidad aumenta) → SEARCH (busca última posición vista, timer) → RETURN (vuelve a patrol si no encuentra)
- Detección: dispara señal `player_detected` → puede triggerear checkpoint, game over, o cierre de puerta
- Audio: zumbido de hover que cambia tono en ALERT
- Luz de estado: azul tenue (patrol) → rojo pulsante (alerta)

### Etapa C.2: Sigilo básico
- `PlayerStealth.gd` — nodo hijo del PlayerControllerV2
- Estados: visible / oculto / detectado
- Ocultamiento: colliders con layer "cover" (pilares, cajas) cambian estado a oculto si el jugador está detrás
- Agacharse (crouch): reduce hitbox y ralentiza movimiento, reduce radio de detección
- Señal: `stealth_state_changed(is_visible)` para UI

### Considered Options

- **Option A**: DDC como agente independiente — **Selected**. Hereda de AgentBase, máximo reuso con Cargol.
- **Option B**: DDC como sistema separado — descartado, duplicaría la lógica de estados y comandos.

## Files to Modify

- `core_v2/actors/DDCDroneV2.gd` (nuevo) — hereda de AgentBase
- `core_v2/actors/DDCDroneV2.tscn` (nuevo)
- `core_v2/player/PlayerStealth.gd` (nuevo) — sigilo
- `core_v2/player/PlayerControllerV2.gd` (modificar) — integrar PlayerStealth
- `core_v2/player/PlayerMovementV2.gd` (modificar) — crouch state
- `core_v2/tests/test_ddc_patrol.gd` (nuevo)
- `core_v2/tests/test_ddc_detection.gd` (nuevo)
- `core_v2/tests/test_player_stealth.gd` (nuevo)

## Verification

1. DDC patrulla waypoints en bucle con pausas
2. Cono de visión detecta jugador por distancia/ángulo
3. ALERT → cono se agranda, velocidad aumenta, luz roja
4. SEARCH → busca 5s, si no encuentra vuelve a PATROL
5. Crouch reduce detección
6. Cobertura (cover) oculta al jugador
7. Señal `player_detected` se dispara correctamente
8. Deterministic replay compatible
