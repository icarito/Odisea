# FD-262: Generador procedural de rutas de tuberías

**Status:** Open
**Priority:** High
**Effort:** Large
**Created:** 2026-08-16
**Completed:** -

## Problem

Las tuberías de la nave (criocoolant, plasma, atmósfera, energía) se colocan hoy a mano
con tramos sueltos `PipeSection`, `PipeCorner`, `PipeTee`. No hay forma de generar la
ruta entre dos fixtures (tanque, criopod, válvula, tee) automáticamente abrazando
paredes/techo. Esto hace lento y frágil el layout de niveles y no escala para los puzzles
de los 4 sistemas.

## Solution

Extraer un **generador procedural de rutas de tubería** como componente aislado
(`PipeRouter`), reutilizando la generación de malla de tubo y el modelo de daño que ya
existe en `CircuitCable`.

### Modelo (distinción clave)

- **Circuito = grafo de señal** (booleano, compuertas): `LogicCircuitManager`.
- **Tubería = grafo de flujo** (recurso continuo: presión, temperatura, caudal).
  Comparten topología y daño, pero NO semántica: cable roto corta la señal; caño roto
  hace escapar el fluido (el caudal sigue, la presión cae aguas abajo).

El router solo genera **rutas y geometría**; la capa de flujo (presión/caudal) queda
fuera de este FD y se tratará aparte.

### Alcance del router

1. **Fixtures a mano** (tienen significado de gameplay): tanque, criopod, válvula
   (`PipeValve`), tee. Se referencian por `NodePath` / ancla.
2. **Rutas automáticas entre fixtures**: el router calcula un camino que abraza
   paredes/techo (NO por el piso, a diferencia de `_generate_catenary` de los cables).
   - API propuesta: `generate_route(from_anchor, to_anchor, options) -> Curve3D` (o lista
     de segmentos con tipo recto/codo/tee).
   - opciones: `offset` desde la pared/techo, `snap` a grid, `clearance`.
3. **Geometría**: reutilizar/extraer el constructor de tubo de `CircuitCable.gd`
   (`_generate_tube_mesh`, `build`, `init_from_curve`) a un `TubeBuilder` compartido o
   reutilizarlo directo. Radio/segmentos configurables.
4. **Daño**: compartir el modelo de `CircuitCable` (`health`, `take_damage`, `is_broken`,
   `connection_broken`) vía composición o base común. Un tramo dañado = fuga (emisor de
   partículas/chorro), señal `pipe_broken`.
5. **Flujo visible**: la corrida generada se monta bajo un controlador tipo
   `PipeCoolantRun` para pintar el fluido. **Un solo material compartido + fase global**
   (eliminar el `.duplicate()` por corrida de `PipeCoolantRun`).

### Trampas de rendimiento (resolver en este FD)

1. `PipeCoolantRun` hace `.duplicate()` del material por corrida → para N corridas, N
   materiales. Pasar a **un material compartido** + fase global (por instancia, no por
   recurso).
2. `pipe_coolant.shader` usa `fbm` de 4 octavas por fragmento → caro en GLES2. Ruido más
   barato o LOD (reducir octavas según distancia).
3. Un `StaticBody`+trimesh por tramo → explosión de draw calls + colisión. Usar **merge
   estático** de la corrida o streaming tipo `DuctMazeStreamer`/`DuctArcBuilder` (cache
   de mallas por key).

### Determinismo

- El router (lógica de ruta) debe ser determinista y reproducible (mismo input → misma
  ruta). Registrar en grupo `replay_sync`; la geometría es presentación, la ruta es
  lógica reproducible.

## Files to Modify

- `core_v2/systems/pipe/PipeRouter.gd` (new) — generador de rutas
- `core_v2/systems/pipe/TubeBuilder.gd` (new, opcional) — builder de malla de tubo extraído de CircuitCable
- `core_v2/systems/pipe/PipeRun.gd` (new) — corrida generada con daño + flujo visible
- `core_v2/systems/circuit/CircuitCable.gd` (modify) — usar TubeBuilder compartido
- `core_v2/props/pipe/PipeCoolantRun.gd` (modify) — material compartido + fase global
- `core_v2/props/pipe/pipe_coolant.shader` (modify) — ruido más barato/LOD
- `core_v2/tests/TestShipSystems.tscn` (modify) — estación de prueba del router

## Verification

1. Colocar dos fixtures (p.ej. tanque y criopod) en el banco de pruebas; el router genera
   una ruta que abraza pared/techo sin atravesar geometría.
2. La corrida se ve con flujo (material compartido), sin duplicar material por corrida
   (inspeccionar recursos).
3. Dañar un tramo → fuga (partículas) + `pipe_broken`; el resto de la corrida sigue.
4. Mismo layout → misma ruta (determinismo) en dos corridas.
5. Perf: N=20 corridas no dispara draw calls ni materiales; FPS estable en GLES2.
6. F6 sin errores.
