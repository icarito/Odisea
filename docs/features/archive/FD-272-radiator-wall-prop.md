# FD-272: Radiador de pared al rojo vivo (prop visual)

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-08-21
**Completed:** -

## Problem

El hielo ya sube y baja en el Dome Intro (`IceLevel` + `Room3D` reaccionan a la
temperatura de sala, ya en `main`), pero no hay ningún prop que se lea como *"esto
calienta la sala"*. Falta la fuente de calor visual para vender el loop de criogenia
del Vertical Slice: el jugador debe poder ver de dónde sale el calor que derrite el
hielo.

## Solution

Prop procedural (Godot 3, GLES2) de **radiador de pared industrial**: rejilla de aletas
verticales en un marco, montado a superficie (pared). Material emisivo que interpola de
frío (apagado) a **rojo-naranja incandescente** según un nivel de calor continuo `0..1`.

Piezas concretas:

- **Geometría procedural**: marco + aletas verticales repetidas (GridMesh o MeshInstance
  con `ArrayMesh` generado en tool script). Estilo nave sci-fi, consistente con
  `core_v2/props/machinery/` (IndustrialFan, VentilationTurbine, etc.).
- **Material emisivo**: `SpatialMaterial` con `emission_enabled`, interpolando
  `emission` (frío = casi negro / apagado → rojo → naranja → blanco-rojo) y
  `emission_energy` según el nivel. Referencia de estilo: `core_v2/props/ManometerEmissive.tres`.
  Glow suave opcional; sin shader custom salvo que sea necesario para el incandescido
  (mantener GLES2 / Adreno, sin precisión rota).
- **Script `RadiatorProp.gd`**:
  - `set_heat_level(value: float)` — clamp `0..1`, interpola el material emisivo.
  - Señal `heat_level_changed(level: float)`.
  - Snapshot (`replay_sync`): `get_snapshot()` / `restore_snapshot()` con `heat_level`.
  - Determinista: sin `randf()`, sin `_process` basado en tiempo real salvo interpola
    visual (la interpolación visual es presentación, no estado).
- **NO toca** `Room3D` ni `IceLevel`: este prop solo *expone* el nivel de calor y emite
  la señal, listo para cablearse en un FD posterior (el derretimiento real). La lógica
  de calor→temperatura queda fuera de este FD.

### Considered Options

- **A: Radiador de pared procedural + emisivo** — infraestructura de nave, se lee como
  calefacción de la sala, no ocupa espacio de navegación. **Seleccionada.**
- **B: Unidad de pie (rejilla de calefacción portátil)** — ocuparía el pasillo del Dome
  Intro y se lee como objeto suelto, no como sistema de la nave. Descartada.
- **C: Flamethrower / calor con voxels** — destrucción volumétrica en tiempo real +
  simulación de hielo por chunks + arma/energía nueva. Overkill para Acto I. **Backlog.**

## Files to Modify

- `core_v2/props/machinery/RadiatorProp.tscn` (nuevo)
- `core_v2/props/machinery/RadiatorProp.gd` (nuevo)
- `core_v2/props/machinery/RadiatorEmissive.tres` (nuevo)
- `core_v2/tests/test_radiator_prop.gd` (nuevo)

**Fuera de alcance:** integrar el calor con `Room3D`/`IceLevel` (el derretimiento real),
el circuito de reparación, y la colocación/autoría final en `Dome_Intro.tscn` (eso lo
hace Sebastián).

## Verification

1. `heat_level = 0` → apagado; `heat_level = 1` → al rojo vivo; interpola sin saltos
   entre ambos.
2. Determinista: mismo `heat_level` ⇒ mismo estado visual, sin `randf()` ni deriva.
3. `heat_level_changed` se emite al cambiar el nivel.
4. Se ve bien en GLES2 (emission correcta, sin bloques de precisión en Adreno).
5. La escena del prop abre sola (F6) sin crashear.
