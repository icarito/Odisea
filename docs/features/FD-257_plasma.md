# FD-257: Sistema Plasma

**Status:** Design
**Priority:** High
**Effort:** Small
**Created:** 2026-08-15
**Parent:** FD-255 (Maestro)
**Assets a reutilizar:** `props/exhaust/PlasmaExhaust.tscn`, `systems/fire/`, `systems/gas/`

## 1. Función y lugar físico

El plasma es la energía de alta temperatura de la nave. Vive en las conducciones
principales de energía, junto a consolas de energía y el Lever auxiliar. Color **ámbar/naranja**.

## 2. Lenguaje visual

- Naranja/ámbar, tuberías con brillo pulsante (el nozzle `PlasmaExhaust.tscn` ya tiene
  pulso IDLE con `pulse_factor`).
- Señal de sistema sano: brillo ámbar estable, ritmo de pulso regular.

## 3. Fallo y aviso

- **Fallo:** fuga de plasma = **barrera de daño móvil** (ya previsto como `FireEmitter`/
  `GasArea3D` inflamable). El plasma daña al contacto.
- **Aviso (patrón legible, siempre en este orden):**
  1. La tubería empieza a brillar más (sobrecalentamiento)
  2. Zumbido agudo creciente
  3. Estalla en chorro de plasma (la barrera aparece)

El jugador aprende: *brillo + zumbido = va a salir el chorro, retrocede*.

## 4. Liberación (mini-game de restaurar)

**Redirigir el flujo de plasma.** Reutiliza el puzzle de "tuberías" de redireccionamiento
ya previsto en `Diseno/Narrativa/LUGARES/Locacion_Mantenimiento.md` y la lógica de
`LogicCircuitManager`:
- El jugador rota `PipeValve`s (o `PipeTee`/`PipeCorner` con estados) para que el flujo vaya
  por una conducción segura en vez de la rota.
- Al alinear el circuito, el chorro se corta y la barrera desaparece.

## 5. Integración de efectos y archivos

**Problema de nombres:** `props/exhaust/PlasmaExhaust.tscn` es el nozzle de reactor con
máquina de estados (IDLE/FLARE/SURGE) y ciclo de color. **Es el plasma real** — queda como
está, no se renombra. (El `visual/plasma_exhaust/` se reasigna a CryoVent en FD-256.)

- **Nozzle:** `props/exhaust/PlasmaExhaust.tscn`. Conectar su estado SURGE al fallo
  (fuga inminente) y IDLE al sistema sano. Su `_is_odisea_active()` hoy lee una env var;
  reemplazar por señal del sistema lógico.
- **Barrera de daño:** `systems/fire/FireSystem` o `GasArea3D` inflamable como zona de daño
  por contacto (reusar, no inventar).
- **Conducciones:** `props/pipe/` (PipeSection/Corner/Tee) para la geometría visible de la ruta.

**Archivos:**
- `core_v2/systems/plasma/` (nuevo, lógica ligera: estado de flujo + zona de daño)
- Reusar `props/exhaust/PlasmaExhaust.tscn` y `props/pipe/`

## 6. Verificación

1. Una sala con conducción rota + válvulas. Sin tocar nada → chorro de plasma activo (daña).
2. Al alinear el circuito (redirigir), el chorro se corta y la barrera desaparece.
3. El aviso (brillo → zumbido → chorro) se ve y se oye antes del daño.
4. Determinista y snapshot-able (estado de flujo y de válvulas).
