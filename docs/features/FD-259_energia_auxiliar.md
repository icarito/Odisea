# FD-259: Sistema Energía Auxiliar

**Status:** Design
**Priority:** High
**Effort:** Small
**Created:** 2026-08-15
**Parent:** FD-255 (Maestro)
**Assets a reutilizar:** `systems/circuit/` (LogicCircuitManager, CircuitGraphResource, CircuitCable destructible, CircuitTerminalBridge), `InteractableBaseV2`

## 1. Función y lugar físico

La energía auxiliar es el respaldo de emergencia que abre puertas selladas cuando la energía
principal falla. Vive en consolas de respaldo, levers verticales y salas B (la "Sala B" del
layout de criogenia). Color **verde**.

## 2. Lenguaje visual

- Verde, paneles con lectura tipo "OD-02" (energía/respaldo).
- Señal de sistema sano: lectura estable en verde.

## 3. Fallo y aviso

- **Fallo:** sin energía → **puertas selladas** (no es daño, es bloqueo de ruta).
- **Aviso (patrón legible):**
  1. Lectura OD-02 parpadeando
  2. Mensaje "respaldo sin energía"
  3. Puerta bloqueada (no abre)

El jugador aprende: *lectura parpadeando = hay que restaurar energía para abrir*.

## 4. Liberación (mini-game de restaurar)

**Accionar lever / secuencia de paneles.** Reutiliza `InteractableBaseV2` (levers) y
`LogicCircuitManager` para encadenar pasos:
- Lever vertical de energía auxiliar (ya en `Diseno/Narrativa/LUGARES/Locacion_Criogenia.md`:
  `Lever (ENERGÍA AUXILIAR)`).
- Secuencia de recalibración: activar paneles en orden correcto (los `CircuitTerminalBridge`
  y `CircuitGraphResource` ya soportan topología y compuertas lógicas).
- Al completar, la puerta sellada se desbloquea.

## 5. Integración y archivos

- **Circuitos:** `LogicCircuitManager` ya hace tick-based logic con compuertas AND/OR/XOR/NOT/
  DELAY y cables destructibles (`CircuitCable`). El puzzle de energía auxiliar es un grafo
  `CircuitGraphResource` que conecta levers → puertas.
- **Puertas selladas:** `HeavyBlastDoor.tscn` / `VerticalDoor.tscn` que responden al estado
  del circuito.
- **Lecturas OD-02:** panel con `CircuitUINode` o un label simple ligado al estado del grafo.

**Archivos:**
- `core_v2/systems/auxpower/` (nuevo, o un `CircuitGraphResource` de ejemplo en `circuit/examples/`)
- Reusar `LogicCircuitManager`, `InteractableBaseV2`, `HeavyBlastDoor.tscn`

## 6. Verificación

1. Una sala con puerta sellada + lever. Sin lever → puerta no abre.
2. Accionar lever → lectura OD-02 pasa a estable → puerta se desbloquea.
3. (Opcional) Secuencia de N paneles en orden correcto vía `LogicCircuitManager`.
4. Determinista y snapshot-able (estado del grafo de circuito).
