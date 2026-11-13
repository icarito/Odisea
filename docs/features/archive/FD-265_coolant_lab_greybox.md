# FD-265: Laboratorio de criogenia grey-box (pruebas del sistema de coolant)

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-08-18
**Parent:** FD-255 (Maestro) / FD-256 (Criocoolant) / FD-264 (grafo de flujo OCLS)
**Reusa:** `LogicCircuitManager` + `CircuitGraphResource` (OLCS), `CoolantFlowAdapter`,
`CoolantLeak`, `LeakPatchPoint`, `PipeManometer`, `CoolantTank`, `PipeValve`, `PipeCoolantRun`

## Problem

FD-264 entregó todas las piezas del circuito de coolant (grafo OCLS, adaptador visual-lógico,
fisuras parcheables con gloo, manómetros, tanque), pero **no hay ninguna escena que las instancie
y las cablee entre sí**. Los tests existentes (`test_coolant_circuit_flow.gd`) validan la lógica a
nivel de script, pero no hay forma de **jugar** el sistema: abrir/cerrar válvulas, ver el flujo
reaccionar, parchear una fuga con gloo y leer la presión en un manómetro.

`Dome_Intro.tscn` tiene las válvulas/tanques/leaks como decorado, pero **no** instancia el grafo
OCLS ni los nodos nuevos (`LogicCircuitManager`, `CircuitGraphResource`, `CoolantFlowAdapter`,
`LeakPatchPoint`, `PipeManometer`). El layout espacial del dome es dominio de Sebastián; no se toca.

Falta un **laboratorio de criogenia grey-box** aislado, autocontenido y reproducible, que sirva de
banco de pruebas del sistema sin depender del trabajo espacial en curso.

## Solution

Crear una escena nueva `CoolantLab.tscn` (no toca `Dome_Intro`), 100% grey-box (CSG y primitivas,
sin arte), que instancia y cablea el sistema completo en un layout simple y legible. Dos ramas
(este/oeste) espejadas, cada una con su cadena FUENTE → VÁLVULAS → FISURA → SUMIDERO.

### 1. Escena `CoolantLab.tscn` (grey-box)

Nodos raíz y composición:

```
CoolantLab (Spatial)
├─ Camera (Camera)
├─ Lights (luz direccional + ambiental mínima)
├─ LogicCircuitManager (script LogicCircuitManager.gd)
│    └─ circuit_data = CircuitGraphResource (SubResource embebida, topología §2)
├─ TankWest  (CoolantTank.gd)
├─ TankEast  (CoolantTank.gd)
├─ ValveWest_1, ValveWest_2  (PipeValve.gd)
├─ ValveEast_1, ValveEast_2  (PipeValve.gd)
├─ LeakWest  (CoolantLeak.gd)  + LeakWest_Patch (LeakPatchPoint.gd)
├─ LeakEast  (CoolantLeak.gd)  + LeakEast_Patch (LeakPatchPoint.gd)
├─ PipeRunWest, PipeRunEast   (PipeCoolantRun.gd, tramos de caño CSG)
├─ ManometerWest, ManometerEast (PipeManometer.gd, con hijo "Needle")
├─ CoolantFlowAdapterWest, CoolantFlowAdapterEast (CoolantFlowAdapter.gd)
└─ Floor (CSGBox) + paredes simples para contener la sala
```

Cada `PipeValve` es un `InteractableBaseV2` (heredado). Las válvulas arrancan **abiertas**
(`starts_active = true`); cerrarlas corta el flujo aguas abajo (reversible).

Cada `CoolantLeak` usa `starts_leaking = true` (o se dispara al abrir su válvula aguas arriba,
vía `valve_path`). El `LeakPatchPoint` referencia su `CoolantLeak` por `leak_path` y su
`PipeCoolantRun` por `target_pipe_run_path`.

### 2. Topología OCLS (grafo embebido)

Dos cadenas independientes (una por rama), deterministas, reusando la regla de FD-264 §1:

```
TankWest  → ValveWest_1 → ValveWest_2 → LeakWest  → (sumidero)
TankEast  → ValveEast_1 → ValveEast_2 → LeakEast  → (sumidero)
```

`CircuitGraphResource` embebida como SubResource en el `.tscn` (mismo patrón que
`CircuitExample.tscn`): nodos `PROP` con `scene_path` apuntando a cada válvula/tanque, y
conexiones `WIRED` en el orden de la cadena. El `LogicCircuitManager` corre con
`auto_build_cables = true` para ver los cables procedimentales entre nodos.

### 3. Adaptadores de flujo (uno por rama)

Cada `CoolantFlowAdapter` se configura con:
- `circuit_manager_path` → `LogicCircuitManager`
- `tank_path` → su `Tank*`
- `valves` → sus dos `Valve*` (array de NodePath)
- `leaks` → su `Leak*`
- `pipe_runs` → su `PipeRun*`

Con esto, cerrar una válvula → el flujo de su rama **frena** (rampa) y baja la intensidad;
abrirla → retoma sin costura. Una fuga activa baja la intensidad. Esto ya está implementado en
`CoolantFlowAdapter.update_flow()`; el FD solo lo **instancia y cablea**.

### 4. Manómetros

Cada `PipeManometer` se configura con `flow_adapter_path`, `tank_path` y `leak_path` de su rama.
Necesita un hijo `Needle` (Spatial, un cubo fino CSG orientable) para que la aguja gire según
`_current_pressure`. La lectura baja si su rama tiene fuga abierta o válvula cerrada.

### 5. Objetivo jugable (win condition mínima)

- El jugador puede **interactuar** con las válvulas (ya heredan interacción de `InteractableBaseV2`).
- Puede **parchear** fisuras disparando gloo (`MultiToolGlooProjectile` detecta `LeakPatchPoint`
  por grupo `gloo_patchable` → `patch_with_gloo()`), ya implementado en FD-264.
- **Win:** todas las fisuras parcheadas y válvulas abiertas → `CoolantFlowAdapter.is_flow_active()`
  en ambas ramas = true, y manómetros en presión normal. No requiere HUD nuevo; basta con poder
  leerlo por estado de los nodos (o un `Label` grey-box mínimo de debug que muestre
  "sistema estabilizado" cuando ambas ramas reporten flujo estable). Si el parche degrada,
  la fuga se re-dispara (mantenimiento, no cierre — coherente con FD-264).

## Considered Options

- **A. Cablear directo en `Dome_Intro`** — depende del layout espacial de Sebastián (Floor_6,
  riser este, etc.) que aún no está. Bloquea la validación del sistema. Descartado por ahora.
- **B. Solo tests de script (estado actual)** — valida lógica, no jugabilidad ni wiring de escena.
  No sirve para probar "qué siente el jugador".
- **C. Escena-laboratorio grey-box autocontenida** — instancia el sistema completo, reproducible
  con F6, sin tocar el dome. **Seleccionado.**

## Files to Modify

- `core_v2/scenes/CoolantLab.tscn` (new) — escena grey-box que instancia y cablea todo (§1–§4).
  Si no existe `core_v2/scenes/`, usar la carpeta de escenas de test existente más apropiada.
- `core_v2/scenes/CoolantLab.gd` (new, opcional) — script raíz mínimo si hace falta para el
  win-condition debug label / registro de estado. Si la escena se sostiene solo con nodos
  exportados, puede omitirse.
- **No modificar** scripts existentes (`CoolantFlowAdapter`, `CoolantLeak`, `LeakPatchPoint`,
  `PipeManometer`, `CoolantTank`, `PipeValve`, `PipeCoolantRun`, `LogicCircuitManager`): el
  objetivo es solo instanciarlos y cablearlos.

**Fuera de alcance:** layout del dome, `Floor_6`, riser este, meshes/arte final, plasma/atmósfera/
energía/radiación (FD-255/FD-257/258/259). Este FD es **coolant únicamente** y **grey-box**.

## Verification

1. Abrir `CoolantLab.tscn` y correr con F6: carga sin errores de script ni paths rotos.
2. Con las válvulas abiertas y sin fugas, ambos `PipeCoolantRun` muestran flujo
   (`flow_speed`/`flow_intensity` > 0) y los manómetros leen presión normal.
3. Cerrar `ValveWest_1` → el flujo de la rama oeste **frena** (rampa, sin salto) y la intensidad
   baja; el manómetro oeste baja su lectura. Reabrir → retoma sin costura.
4. Fuga activa (rama este) → intensidad de la rama este baja. Disparar gloo al `LeakEast_Patch`
   → el leak pasa a `SEALED`; tras `gloo_patch_duration` degrada y re-dispara (sin `randf()`).
5. Parchear ambas fisuras y dejar todas las válvulas abiertas → ambas ramas reportan flujo estable
   (win condition alcanzable).
6. Determinismo: snapshot del grafo + adaptador a mitad de ciclo, restaurar, correr los mismos
   ticks → mismo `flow_intensity`.

## Decisions (resueltas)

1. **Escena separada `CoolantLab.tscn`**, no toca `Dome_Intro`. Layout espacial del dome → Sebastián.
2. **Dos ramas** (este/oeste) para cubrir el caso multi-rama del grafo sin complejidad extra.
3. **Grey-box estricto**: CSG + primitivas + cables procedimentales OCLS. Sin arte final.
4. **Win = "sistema estabilizado"** (ambas ramas con flujo estable). Tanque a 0 = visual, no derrota.
5. **No modificar scripts existentes**: solo instanciar y cablear. Si falta algo (ej. un nodo
   `Needle` para el manómetro), crearlo como nodo de escena, no como código nuevo.
