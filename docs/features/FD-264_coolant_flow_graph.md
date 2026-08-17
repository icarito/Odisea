# FD-264: Lógica de circuitos de coolant — grafo de flujo + puente visual (OCLS)

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-08-17
**Parent:** FD-255 (Maestro) / FD-256 (Criocoolant)
**Reusa:** OCLS (`core_v2/systems/circuit/`), `PipeCoolantRun` + `pipe_coolant.shader`, `CoolantLeak`

## Problem

El criocoolant tiene las dos mitades, pero no están unidas:

1. **Mitad visual (ya existe):** `pipe_coolant.shader` muestrea ruido en **coordenadas de
   mundo** (atraviesa codos y uniones sin costura), deduce el eje por tramo
   (`use_local_axis`), y acumula la fase en script para que frenar ≠ congelar. `PipeCoolantRun.gd`
   ya expone `set_flow_intensity()` / `set_flow_speed()` como "palanca de gameplay" — el
   comentario del propio archivo dice *"una fuga la hace caer"*.

2. **Mitad lógica (parcial):** las válvulas (`PipeValve`) emiten `valve_state_changed` hacia
   los `CoolantLeakController`, y `CoolantLeak` modela el ciclo SANO→AVISO→FUGA→SELLADO. Pero
   **nadie escribe `flow_intensity`/`flow_speed` en las corridas según el estado del circuito**.

Resultado: el shader de flujo no reacciona a cerrar una válvula ni a una fuga. El circuito es
decorado, no un órgano vivo. Falta el **modelo de flujo explícito** (grafo) y el **puente**
que lo traduce a lo visual.

## Solution

Modelar el circuito como un **grafo de flujo sobre OCLS**, con un adaptador que lea el grafo
y escriba en las `PipeCoolantRun`. El shader **no se toca** — ya es circuit-aware.

### 1. Grafo de flujo (OCLS)

Topología canónica por rama (una rama oeste, una este):

```
FUENTE (tanque, nivel>0)
   └─ VÁLVULA_1 … VÁLVULA_N   (PROP, abierta/cerrada)
        └─ FISURA (CoolantLeak, parcheable)
             └─ SUMIDERO (criopods)
```

Regla de flujo, determinista:

```
flujo(segmento) = (∀ válvula aguas arriba abierta) ∧ (nivel_tanque > 0)
fuga(i)         = fisura_i.abierta ∧ flujo(i)
```

- **Válvula** = triage reversible: corta el síntoma (niebla), no repara la causa.
- **Gloo** = parche **temporal** (ver §3). No es el fix definitivo.
- **Win:** *sistema estabilizado* — todas las fisuras parcheadas (aunque temporales) y
  válvulas abiertas. Como el parche degrada y re-dispara la fuga, es **mantenimiento**, no
  cierre definitivo. El cierre permanente es otro tool (backlog).

### 2. Puente visual ↔ lógico

`CoolantFlowAdapter` (nuevo, análogo a `CircuitTerminalBridge`): se suscribe al grafo OCLS y
escribe `set_flow_intensity()` / `set_flow_speed()` sobre las `PipeCoolantRun` aguas abajo de
cada nodo. Con velocidad con rampa (ya implementada), cerrar una válvula **frena** el patrón
en vez de congelarlo; una fuga **baja** la intensidad.

### 3. Fisura y parche de gloo

- **`LeakPatchPoint`** (nuevo): un **Spatial** que representa la fisura sobre el caño. Al
  activarse, dispara el daño visual del tubo (shader de fisura/agrietado — parámetro de
  material, no malla nueva) y dispara el `CoolantLeak` asociado (los "famosos leaks").
  Vive en grupo `gloo_patchable`.
- **Parche de gloo = temporal:** `MultiToolGlooProjectile` al `_stick_at` detecta el punto y
  sella → la fisura queda parcheada por `gloo_patch_duration` segundos (exportable), con
  **decay timer** determinista (en `_physics_process`, sin `randf()`). Al degradarse,
  re-dispara la fuga. **No** se reusa `_has_been_sealed` para el gloo (eso es para el fix
  permanente).
- **Fix permanente:** otro tool u otro tipo de gloo → **backlog**. En el slice el gloo es el
  único sellado y es temporal.

### 4. Laboratorio de coolant + guía

- **Manómetros** (`PipeManometer`, nuevo): prop que lee la presión del circuito
  (`f(flujo, nivel)`) y la muestra como aguja/lectura. Sirve para que el jugador lea *qué
  rama pierde presión* sin texto.
- **Escena-laboratorio** de tuberías de coolant con manómetros y una **guía** (tutorial
  in-game: texto/paneles) de cómo funciona el circuito (válvula = corta, gloo = parche
  temporal, manómetro = lee presión).
  - **Layout espacial → Sebastián.** El código del manómetro y el contenido de la guía son
    delegables; la disposición física de la sala es suya.

### 5. Láser (slice)

Solo **anti-gloo**: derrite blobs de gloo (ya implementado). Ignición/corte se desbloquean en
Acto II. Mantiene el slice en "coolant únicamente".

## Considered Options

- **A. Shader nuevo "consciente del circuito"** — innecesario: `pipe_coolant.shader` ya es
  circuit-aware (eje por tramo, fase continua, ruido en mundo). Descartado.
- **B. Cada `PipeCoolantRun` lee su propio estado por get_parent()** — acopla y rompe el
  determinismo. Descartado.
- **C. Grafo OCLS + `CoolantFlowAdapter`** — reusa OCLS, mantiene el shader intacto, y deja
  el flujo legible como topología. **Seleccionado.**

## Files to Modify

- `core_v2/systems/cryo/CoolantFlowAdapter.gd` (new) — lee el grafo, escribe `flow_intensity`/`flow_speed`.
- `core_v2/systems/cryo/LeakPatchPoint.gd` (new) — Spatial de fisura: daño visual + `CoolantLeak` + parche temporal con decay.
- `core_v2/props/pipe/PipeManometer.gd` (new) — manómetro que lee presión del circuito.
- `core_v2/props/pipe/CoolantTank.gd` (new/extend) — fuente con nivel (reloj de presión suave, **sin derrota**).
- `core_v2/player/MultiToolGlooProjectile.gd` (modify) — detectar `LeakPatchPoint` al `_stick_at`, sellado temporal.
- `core_v2/things/CoolantSystemStatusUI.gd` (extend) — dos lecturas nuevas: nivel de tanque + estado de fisura por piso.
- `core_v2/systems/circuit/CircuitGraphResource` (reuse, no modificar).

**Fuera de alcance (Sebastián, espacial):** layout del laboratorio, geometría, `Floor_6`,
riser este, meshes. Plasma/atmósfera/energía/radiación → backlog (FD-255/FD-257/258/259).
Este FD es **coolant únicamente**.

## Verification

1. Cerrar una válvula aguas arriba → la corrida aguas abajo **frena** (rampa) y la intensidad baja, sin salto de patrón.
2. Abrir la válvula → el flujo retoma sin costura.
3. Fuga activa + gloo sobre `LeakPatchPoint` → `CoolantLeak` pasa a `SEALED`; tras `gloo_patch_duration` degrada y re-dispara la fuga (sin `randf()`).
4. El manómetro baja su lectura cuando su rama tiene una fisura abierta o una válvula cerrada.
5. `CoolantSystemStatusUI` muestra nivel de tanque y estado de fisura correctos en vivo.
6. Determinismo: snapshot del grafo + adaptador a mitad de ciclo, restaurar, correr los mismos ticks → mismo `flow_intensity`.

## Decisions (resueltas)

1. **Tanque a 0:** NO derrota. Solo presión visual (coherente con "ciega, no daña" de FD-256).
2. **Fisuras:** Spatial que provoca daño visual en el caño (shader) y dispara el leak; + laboratorio con manómetros y guía.
3. **Parche de gloo:** temporal (decay). Fix permanente = otro tool/gloo → backlog.
