# FD-266: Semántica del puzle de refrigerante (despresurizar para reparar)

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-08-17
**Parent:** FD-255 (Maestro) / FD-256 (Criocoolant) / FD-264 (grafo OCLS) / FD-265 (laboratorio)

## Problem

El laboratorio de FD-265 ya instancia y cablea el sistema completo, pero **el puzle no se
entiende**. El síntoma que lo delata: *cerrar una válvula hace desaparecer la fisura*.

En `CoolantLeak._on_valve_state_changed()`, cerrar la válvula llama `seal()`, que lleva el estado
a `SEALED` y de ahí a `HEALTHY` — y `_has_been_sealed` bloquea el re-disparo salvo `auto_restart`.
O sea: **la válvula repara el caño**. Nadie que lo juegue va a leer eso como "corté el caudal";
lo va a leer como "cerrar la llave suelda la grieta", que es absurdo.

Esto **no es un bug**: es la semántica de FD-256, donde el coolant es un *hazard* (la niebla
ciega, no daña) y "cerrar la válvula lo resuelve" es la lección de diseño. El brief original
(`docs/features/tasks/FD-255-j3-coolant-leak-logic.md`) lo dice con todas las letras. El problema
es que esa semántica de hazard, trasladada a un circuito con tanques, manómetros y gloo, deja al
resto de las piezas sin función:

- **La válvula** no tiene motivo para tocarse: cerrarla solo corta tu propio enfriamiento.
- **El manómetro** informa una presión que no cambia ninguna decisión.
- **El tanque** nunca baja (`drain_rate` por defecto 0), así que no hay costo ni reloj.
- **El gloo** repara en cualquier momento, así que el parche no compite con nada.
- **La condición de victoria** exige `is_patched()`, pero el parche caduca a los 15 s: "ganar"
  dura un rato y se deshace solo, sin cierre.

Ninguna pieza le da razón de ser a otra. Eso es lo que no se entiende.

## Solution

**Despresurizar para reparar.** El caudal y la avería se separan en dos ejes distintos, y la
válvula pasa a ser la herramienta que los desacopla:

```
FUGA ACTIVA (presión alta)
   │  el tanque drena mientras el refrigerante escapa con presión
   ▼  cerrar la válvula aguas arriba
TRAMO DESPRESURIZADO (presión ~0)
   │  la fuga deja de escupir — el caño SIGUE roto
   ▼  disparar gloo
PARCHE FIRME
   │
   ▼  reabrir la válvula
FLUJO NORMAL — el tanque deja de drenar
```

La regla que sostiene todo: **el gloo solo agarra en un tramo despresurizado.** Parchear un caño
con presión encima hace que el parche salte a los pocos segundos. El manómetro es cómo el jugador
sabe que es seguro disparar.

Con eso, cada pieza tiene función:

| Pieza | Para qué sirve ahora |
|---|---|
| Válvula | Despresurizar el tramo: es el paso previo obligatorio a reparar |
| Manómetro | Leer si el tramo está seguro para el parche |
| Gloo | Reparar de verdad (permanente si se aplicó sin presión) |
| Tanque | El reloj: drena mientras haya fuga presurizada |

### Compatibilidad con el hazard de FD-256

Esta semántica **no rompe** la lección de FD-256. Cerrar la válvula sigue cortando la niebla que
ciega: el jugador que entra en pánico y cierra la llave sigue resolviendo el peligro inmediato.
Lo único que cambia es que el caño queda roto y el refrigerante perdido no vuelve — hay que
volver, parchear y reabrir. El hazard se convierte en la primera mitad de un ciclo de
mantenimiento en vez de ser todo el ciclo.

### 1. `CoolantLeak`: cerrar la válvula despresuriza, no repara

`_on_valve_state_changed(false)` deja de llamar `seal()`. En su lugar, un estado o bandera de
**despresurizado**: la fuga no escupe (`get_leak_intensity()` cae a 0 con la rampa de disipación
que ya existe) pero la avería persiste — reabrir la válvula la vuelve a soltar, sin pasar por
`WARNING`, las veces que haga falta. `seal()` queda reservado para la reparación real (gloo).

`_has_been_sealed` deja de bloquear el re-disparo por cierre de válvula: solo un parche firme
termina el ciclo.

### 2. `CoolantTank`: drain condicionado

El tanque deja de drenar a ritmo fijo. Drena **proporcional al refrigerante que se está
escapando**: suma de `leak_intensity` de las fugas activas de su rama, por `drain_rate`. Sin
fugas presurizadas, el nivel no se mueve.

Tanque vacío ⇒ no hay caudal posible (`is_flow_active()` ya lo contempla vía `tank_level > 0`).
Es un estado de fracaso **legible, no letal**: coherente con FD-265 decisión 4 y con "ciega, no
daña". El jugador ve el tanque apagado y el manómetro en cero.

### 3. `LeakPatchPoint`: el parche depende de la presión al aplicarlo

`patch_with_gloo()` consulta la presión del tramo en el momento del disparo:

- **Sin presión** (por debajo de un umbral exportado) ⇒ parche **firme**: no caduca, la fuga
  queda reparada. Esto le da cierre al puzle.
- **Con presión** ⇒ parche **provisorio**: dura `gloo_patch_duration` y salta, como hoy. Es el
  camino "apurado" y sigue siendo útil para ganar tiempo bajo presión.

`is_patched()` y la señal `patch_expired` no cambian de forma; se suma el distingo firme/provisorio.

### 4. Condición de victoria con cierre

`CoolantLab.is_stabilized()` deja de exigir un parche que caduca. Estabilizado =
ambas ramas con flujo activo, sin fugas activas, y tanques por encima del umbral. Un parche firme
lo sostiene indefinidamente; uno provisorio lo pierde cuando salta. El puzle **se puede terminar**.

## Considered Options

- **A. Solo arreglar la semántica** — que cerrar la válvula corte el caudal sin curar la fisura, y
  sumar el drain. Coherente, pero deja la válvula sin motivo fuerte para tocarse y el puzle sigue
  flojo. Descartada.
- **B. Presión compartida entre ramas** — un tanque único donde cerrar una rama sobrecarga la otra.
  Más rico, pero exige un modelo de presión de verdad en vez del `f(flujo, nivel, fuga)` actual, y
  multiplica el alcance. Descartada por ahora; el modelo de presión de §3 es el primer paso hacia
  ella si algún día se quiere.
- **C. Despresurizar para reparar** — la válvula desacopla caudal de avería y es el paso previo
  obligatorio al parche. Le da función a las cuatro piezas sin inventar sistemas nuevos.
  **Seleccionada.**

## Files to Modify

- `core_v2/systems/cryo/CoolantLeak.gd` — despresurización vs reparación (§1)
- `core_v2/props/pipe/CoolantTank.gd` — drain proporcional a la fuga (§2)
- `core_v2/systems/cryo/LeakPatchPoint.gd` — parche firme vs provisorio (§3)
- `core_v2/systems/cryo/CoolantFlowAdapter.gd` — exponer presión de tramo si hace falta (§3)
- `core_v2/scenes/CoolantLab.gd` — condición de victoria con cierre (§4)
- `core_v2/tests/test_coolant_leak.gd`, `core_v2/tests/test_coolant_circuit_flow.gd` — actualizar
- `core_v2/tests/test_coolant_puzzle_loop.gd` (nuevo) — el ciclo completo

**Fuera de alcance:** `core_v2/scenes/CoolantLab.tscn` (los valores exportados los calibra
Sebastián sobre la escena ya verificada), geometría, arte, y los otros tres sistemas de FD-255.

## Verification

1. Cerrar la válvula aguas arriba de una fuga activa: la intensidad cae a 0 con rampa, pero el
   estado NO vuelve a `HEALTHY`. Reabrir la vuelve a soltar sin pasar por `WARNING`.
2. Con fuga presurizada, el nivel del tanque baja; al cerrar la válvula, deja de bajar.
3. Gloo sobre tramo presurizado ⇒ el parche salta a los `gloo_patch_duration` segundos.
4. Gloo sobre tramo despresurizado ⇒ el parche no caduca; reabrir la válvula deja flujo normal
   sin fuga.
5. Ciclo completo cerrar → parchear → reabrir en ambas ramas ⇒ `is_stabilized()` true y se
   mantiene (no se deshace solo).
6. Tanque a 0 ⇒ sin caudal, sin daño al jugador, manómetros en cero.
7. Determinismo: snapshot a mitad de ciclo, restaurar, mismos ticks ⇒ mismo estado. Sin `randf()`.
