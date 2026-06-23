# FD-241: Cargol V2 — Compañero Funcional

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-23

## Problem

CargolDroneV2 existe (476 líneas, KinematicBody, command queue, path following, determinismo) pero solo funciona como prop de exhibición controlado por lever — no tiene el comportamiento de compañero que el Acto I necesita: sigue al jugador, ilumina, expresa estado, se puede enviar a puntos, activa botones a distancia.

## Solution

Refactor CargolDroneV2 como agente que hereda de un sistema de agentes genérico (Etapa A compartida con FD-242) y añade:

### Etapa A: Sistema de Agentes (compartido FD-241 + FD-242)
- `AgentBase.gd` — clase base para NPCs/agentes con estado (idle, follow, patrol, alert, return), cola de comandos, integración replay-determinista
- CargolDroneV2 y DDCDrone heredan de AgentBase
- Estados comunes: `IDLE`, `FOLLOW_PATH`, `FOLLOW_TARGET`, `RETURN_HOME`, `ALERT`, `SEARCH`

### Etapa B: Cargol — Comportamiento de compañero
- Follow IA: sigue al jugador a distancia configurable, evita obstáculos simples, mantiene hover
- Luz de estado: emisiva azul (idle/siguiendo), verde (trabajando), rojo (peligro/IA Odisea tomando control)
- Animaciones de idle/flotar/acelerar
- Envío contextual: jugador apunta a superficie → Cargol va y espera; puede activar botones/pedestales a distancia
- Señales: `reached_target`, `player_too_far`, `obstacle_detected`, `state_changed`
- UI indicador: iconito en pantalla mostrando estado y distancia

### Considered Options

- **Option A**: Refactor CargolDroneV2 existente en vez de reescribir — **Selected**. Ya tiene 476 líneas de infrastructure (command queue, path following, determinismo). Heredar de AgentBase y añadir follow + luz + estados.
- **Option B**: Reescribir desde cero — descartado, pierde el trabajo de determinismo ya validado.

## Files to Modify

- `core_v2/actors/AgentBase.gd` (nuevo) — clase base genérica de agente
- `core_v2/actors/CargolDroneV2.gd` (modificar) — heredar de AgentBase, añadir follow + luz + estados
- `core_v2/actors/CargolDroneV2.tscn` (modificar) — añadir nodos de luz/anim
- `core_v2/props/machinery/CargolDroneProp.gd` (modificar) — actualizar para nuevo CargolDroneV2
- `core_v2/props/CargolController.gd` (modificar) — simplificar, ahora Cargol se controla directo
- `core_v2/ui/CargolHUD.gd` (nuevo) — indicador de estado del dron en pantalla
- `core_v2/tests/test_cargol_follow.gd` (nuevo)
- `core_v2/tests/test_cargol_determinism.gd` (modificar)

## Verification

1. Cargol sigue al jugador fluidamente en 1G y 0G
2. Luz cambia de estado correctamente (azul/verde/rojo)
3. Enviar Cargol a punto → va y espera
4. Cargol activa botón/pedestal cuando está cerca
5. Sigue siendo deterministic-replay compatible
6. Tests OYS existentes no se rompen
