# FD-322: Bahía de máquinas radial centrífuga (cilindro rotante, 3 anillos)

**Status:** Implemented (greybox)
**Priority:** P1
**Effort:** Large
**Created:** 2026-11-14
**Rama:** `ao/redise-o-de/root-bahia-vertical-radial`
**Visión confirmada por Sebastián (2026-11-14)** — "la nave tiene dos modos, centrífuga y por propulsión".
**Contratos:** `.operator-shared/specs/machine-launch.md`, `.operator-shared/specs/machine-layout.md`, AGENTS.md §5 (determinismo), §2.1 (sistema de coordenadas: +Z = back)
**Relacionados:** FD-036 (GravityManager), FD-039 (Gravity Physics Strategy), FD-040 (PlateContentStream), FD-320 (bahía actual), FD-050/.1/.2 (scaffold WFC), FD-314 (streaming ringhub), FD-052/v2 (MST polar duct maze), FD-035 (conveyor/carrousel), FD-244 (multitool láser/gloo), FD-053 (airlock)

---

## 1. Visión

Rediseño de la Bahía de máquinas a un **cilindro rotante de 3 anillos concéntricos** — NO un pozo
con gravedad hacia abajo. La gravedad es **centrífuga radial**: el piso es la cara interior del
anillo; "subir" es ir **hacia el eje**. La bahía es agnóstica al modo de gravedad de la nave
(centrífuga vs. propulsión), y siempre lee el vector de gravedad de `GravityWorld` sin asumir una
dirección fija.

- **Los "3 niveles" son 3 anillos a radios decrecientes.** La **ruta principal** es el **anillo
  exterior** (gravedad plena). Trepar = ir hacia el eje, con gravedad **proporcional al radio**
  (más liviana al acercarse al eje).
- **La cima** (sala de control + salida) está **en el eje**, casi en **zero-G**, y es **visible
  desde cualquier punto del anillo** (baliza).
- **Fallar = caer hacia afuera**, de vuelta al anillo exterior. Sin muerte ni checkpoint (salvo
  vacío real).
- **Atajos (~5 por semilla)** = chunks curados hechos a mano: máquinas reconvertidas en chunks
  estándar, cintas (`Conveyor.gd`/`ConveyorCarrousel.gd`) en tres roles (peligro que arrastra,
  transporte, traen cajas `PushableBoxV2` para trepar), puertas de **GLOO** (construye apoyo) y
  puertas de **LÁSER** (corta panel).
- **Ciclo de protocolo global** (calma/aviso/peligro) visible en las luces de toda la sala;
  ventanas locales de peligro sincronizadas con la fase (generaliza el ciclo de
  `LabyrinthSection.gd`, no lo reinventa).
- **Semilla por partida**, guardada en save y replay. Determinismo estricto.
- **Perf:** streaming por cercanía de chunks (solo áreas vecinas). El activador genérico de
  src-51 se engancha en §8.

**Lectura diegética:** sin texto ni hints de teclas. La ruta principal usa luz cálida estable;
los atajos usan franjas de peligro y luz fría/parpadeante; la cima se ve desde el inicio.

### 1.1 Reinterpretación definitiva (corrección de premisa)

La primera versión de este FD (y del greybox) asumió un **pozo vertical** con gravedad hacia
abajo. Sebastián corrigió: el espacio radial **no es gravitatorio/orbital descendente**; es un
**cilindro rotante con gravedad centrífuga**. Esta sección reemplaza esa lectura.

| Antes (incorrecto) | Ahora (contrato) |
|---|---|
| Eje Y, gravedad hacia abajo | Eje del cilindro (Z canónico), gravedad radial centrífuga |
| 3 niveles = 3 alturas | 3 niveles = 3 anillos a radios decrecientes |
| Trepar = subir en Y | Trepar = moverse hacia el eje (radio decreciente) |
| Cima = altura máxima | Cima = el eje, casi zero-G |
| Fallar = caer al piso inferior | Fallar = caer hacia afuera, al anillo exterior |

No hardcodear "hacia afuera": `GravityWorld` es la fuente de verdad del vector de gravedad
(§3.6).

---

## 2. Máquina de gravedad (reuso, no duplicación)

Toda la gravedad sale del stack existente:

- `core_v2/systems/GravityWorld.gd` — modos `STANDARD_1G` (empuje, gravedad a lo largo del eje de
  la nave), `SPIN_WALKABLE` / `SPIN_DYNAMIC` (centrífuga) y `ZERO_G`; `set_gravity_mode`,
  `gravity_mode_changed`, `get_canonical_gravity`, `get_physical_gravity`,
  `get_axis_radial_vector`, `set_centrifugal_reference_radius`, `set_ship_axis`,
  `set_ship_angular_velocity`, `get_default_angular_velocity_for_one_g`.
- `core_v2/systems/DynamicGravityProxy.gd` — proxy radial para cuerpos/props.
- `core_v2/systems/WorldRotator.gd` / `core_v2/systems/visual/CylinderRotator.gd` — rotación del
  entorno para que la plataforma activa quede alineada con la gravedad estándar; `cylinder_axis`,
  `cylinder_radial_origin`, `centrifugal_current_plate_only_physics`.
- `core_v2/systems/scaffold/ScaffoldOrbit.gd` + `core_v2/components/ScaffoldOrbit.tscn` — la
  proyección cilíndrica canónica de chunks (`flat → theta/r/z`).
- `core_v2/levels/OdiseaExterior.gd` (~390-402, ~1635) — patrón de configuración
  (`set_centrifugal_reference_radius`, `set_ship_angular_velocity`,
  `centrifugal_current_plate_only_physics`).
- `core_v2/components/TerraceSpiral.gd` / `core_v2/places/Platforms.gd` — geometría que se adapta
  a los dos modos (`manual_blend 0=axial, 1=centrífugo`), `GravityWorld.set_gravity_blend` /
  `set_spiral_blend`.

**Lecciones de OdiseaExterior a respetar:**

- **Clip-through por hundimiento por frame** contra el suelo teletransportado: la corrección de la
  proyección debe ser acotada por frame (ver `continuous_tracking_max_step` / `max_tracking_delta`
  en `WorldRotator`). No mover el piso del jugador varios metros en un tick.
- **FPS bajo = draw calls**, no el solver: agrupar visual (MultiMesh / mallas horneadas) y limitar
  las luces dinámicas.

**Nota de integración (greybox):** el greybox monta la proyección cilíndrica canónica sobre el
mismo convenio que `CylinderRotator`/`ScaffoldOrbit` y lee la gravedad de `GravityWorld`; el
enganche a `CylinderRotator` + `ScaffoldStreamController(cylinder_mode=true)` es el destino
declarado y se deja como seam explícito en el código (`TODO(src-51/cilindro)`) cuando el
streaming controller acepte grillas curadas fijas.

---

## 3. CONTRATO DE CHUNK

### 3.1 Geometría cilíndrica canónica (compatible WFC, polar)

Convenio idéntico a `ScaffoldOrbit`/`CylinderRotator`:

- **Eje del cilindro:** Z (canónico). El anillo cierra en el plano XY.
- **Ángulo θ:** `theta = flat_x / base_radius` (X canónico = longitud de arco).
- **Radio:** `radius = base_radius - flat_y` (Y canónico = desplazamiento radial; +Y = hacia el
  eje, o sea "subir").
- **Eje:** Z canónico = posición a lo largo del eje del cilindro.
- **Grilla del generador** (reusa `ScaffoldMSTGenerator`/`ScaffoldWFCGenerator`):
  - **Grid X → sector angular θ** (`wrap_x = true`, el anillo cierra).
  - **Grid Y → anillo/radio r** = `base_radius - ring_offset` (3 anillos: exterior, medio, eje).
  - **base_height → offset axial Z** (bajo, la componente a lo largo del eje).

Transform, por celda, en espacio **canónico (flat)**:

```gdscript
# flat: x = arco, y = desplazamiento radial, z = eje
func _cell_flat_transform(cx: int, cy: int, axial: float) -> Transform:
    var theta := TAU * float(cx) / float(sectors)
    var flat_x := theta * base_radius
    var flat_y := float(cy) * ring_step        # +Y = hacia el eje
    var pos := Vector3(flat_x, flat_y, axial)
    return Transform(Basis.IDENTITY, pos)
```

La **proyección cilíndrica** (flat → mundo físico) es la de `CylinderRotator._cylindrical_transform_at`:

```gdscript
# Se aplica POR CHUNK (cada chunk es rígido y chico); theta relativo al jugador
# para que el arco bajo el jugador quede plano.
var theta := (flat_pivot.x - player_flat_x) / base_radius
var r := base_radius - flat_pivot.y
var pos := Vector3(player_flat_x + r * sin(theta), base_radius - r * cos(theta), flat_pivot.z)
var basis := Basis(Vector3(0, 0, 1), theta)
chunk.transform = Transform(basis, pos - basis.xform(local_pivot))
```

- **Módulos:** los 9 de `core_v2/props/scaffold/` con los mismos setters que
  `LabyrinthSection._instance_grid` (dims de lane, rails en todos los bordes — invariante
  FD-050.1, openings en lados conectados, `front/back_height_offset` para rampas,
  `support_base_local_y`).
- **Sockets/bordes:** 4 conexiones por celda (angular N/S y radial E/O). Las costuras entre
  vecinos son celdas `W` planas calculadas con hash estable de la semilla (mismo patrón que
  `MachineBayLabyrinthStreamer._fixed_border_tiles`).
- **extra_cycles ≥ 2** → caminos alternos garantizados.

### 3.2 Anillos (los 3 niveles)

- **Anillo exterior** (`cy = 0`, radio = `base_radius`): gravedad plena. Ruta principal.
- **Anillo medio** (`cy = 1`, radio ≈ `base_radius - ring_step`): gravedad intermedia. Atajos.
- **Anillo del eje** (`cy = 2`, radio ≈ `base_radius - 2*ring_step` → tendiendo a 0): la **cima**,
  casi zero-G. Sala de control + salida.
- `level_of(cy)` clasifica por anillo. La cima está **en el eje** (radio mínimo) y su baliza es
  visible desde todo el anillo. La entrada es una costura fija en el anillo exterior.

### 3.3 Tipos de atajo (~5 por semilla)

| Chunk | Rol | Implementación |
|---|---|---|
| **Cinta-transporte** | atajo rápido y seguro | `Conveyor.tscn` puenteando un hueco radial |
| **Cinta-arrastre** | peligro temporal | `Conveyor.tscn`/`ConveyorCarrousel.tscn` que arrastra hacia afuera si se activa en peligro |
| **Cinta-cajas** | ayuda a trepar | `Conveyor.tscn` trayendo `PushableBoxV2` (cajas apilables) |
| **Puerta gloo** | atajo por construcción | `GlooSpan` — requiere N blobs de gloo (grupo `gloo_blob` de `MultiToolV2`) |
| **Puerta láser** | atajo por corte | `LaserGate` — panel que bloquea; el láser lo corta (`laser_hit`) |

Interfaz común: `id`, `tipo`, `anillo`, `estado` serializable. Los gates usan **solo la API
pública** de `MultiToolV2` y sus proyectiles (`laser_hit`, grupo `gloo_blob`), tolerando que
src-50 rehaga controles.

### 3.4 Interfaz de peligro con fase del ciclo global

- `BayProtocolCycle` (generaliza el protocolo de `LabyrinthSection.gd`): fases `SAFE` → `WARNING`
  → `DANGER`, deterministas por acumulación de `_elapsed` en `_physics_process`.
- Cada peligro declara su **ventana local** dentro de `DANGER`; fuera de ella está inerte visual y
  físicamente.
- **Luz global** por fase (verde estable / ámbar parpadeante / rojo frío). Ruta principal = luz
  cálida estable; atajos = franjas de peligro y luz fría.
- Física de peligros siempre en `_physics_process`.

### 3.5 Estado serializable (replay + save)

- `replay_sync` con `get_snapshot`/`restore_snapshot`.
- Expone `seed`, `extra_cycles`, los 3 anillos y el estado de cada atajo (corte de láser, blobs de
  gloo, cintas). Todo reproducible desde `seed` + acumulación de `_elapsed`.
- **Semilla por partida:** `set_seed_from_save(seed)` al cargar. Save guarda semilla; replay la
  reproduce. Sin `randomize()` en runtime.

### 3.6 Cambio de modo de gravedad activado por el jugador (puzle de reconfiguración)

Decisión de Sebastián: el cambio **centrífugo ↔ propulsión** lo **activa el jugador** desde consolas
en el camino y desde la sala de control. Es un **puzle que reconfigura las rutas**, no un reloj (el
ciclo global de luces/peligros sigue aparte). Referencia: las terrazas que giran de `OdiseaExterior`.

- **Eje de "abajo" según el modo** (sin hardcodear): en **propulsión** (`STANDARD_1G`) "abajo" =
hacia popa, a lo largo del eje de la nave; en **centrífugo** (`SPIN_*`) "abajo" = hacia el anillo
(radial, hacia afuera). La dirección concreta sale de `GravityWorld`, nunca de una constante.
- **Cada chunk declara su lectura en ambos modos.** El reencuadre visual usa el patrón de
`TerraceSpiral.gd`/`Platforms.gd` (`manual_blend` 0 = axial, 1 = centrífugo; pisos que pasan a ser
paredes y viceversa), vía `GravityWorld.set_gravity_blend` / `set_spiral_blend`. No duplicar ese
sistema: los chunks se montan sobre el mismo mecanismo de blend.
- **Al menos un atajo existe en un solo modo** (se abre/cierra al conmutar).
- **Estado serializable:** el modo actual y el `blend` forman parte de `get_snapshot` /
`restore_snapshot` (save + replay). El cambio es determinista y se resuelve en
`_physics_process`/interacción, no por reloj.
- **Qué pasa con el jugador durante la transición** (lección del clip-through de `OdiseaExterior`):
la terraza lo **lleva** con el reencuadre (acarreo por delta acotado por frame, como
`continuous_tracking_max_step` / `max_tracking_delta`), o **cae** si el chunk que lo sostenía deja
de ser piso en el nuevo modo; nunca se lo teletransporta varios metros en un tick. La transición
queda acotada por frame para no hundir al jugador kinemático a través del piso.

### 3.7 Gravedad agnóstica al modo

- **Nunca** hardcodear "hacia afuera". El greybox llama a
  `GravityWorld.get_canonical_gravity(pos)` / `get_physical_gravity(pos)` según el modo vigente
  (`STANDARD_1G` empuje, `SPIN_*` centrífuga, `ZERO_G`).
- La **dirección de caída** del jugador al fallar se deriva del vector de gravedad de
  `GravityWorld`, no de un `-Vector3.UP` fijo.
- El layout es el mismo en ambos modos; lo que cambia es la gravedad y, con `set_spiral_blend` /
  `set_gravity_blend`, la orientación visual de las espiras (axial vs. centrífuga, como
  `TerraceSpiral`/`Platforms`).

---

## 4. Plan de tareas por etapas

| Etapa | Contenido | Entregable |
|---|---|---|
| A | FD-322 (este archivo), contrato de chunk, reconciliación | FD |
| B | `BayProtocolCycle.gd` (ciclo + luces) | componente |
| C | `BayVerticalWell.gd` (layout cilíndrico sembrado + proyección + streaming + gravedad de GravityWorld + enganche src-51) | greybox |
| D | Atajos: cintas, `GlooSpan`, `LaserGate` | 2+ tipos |
| D2 | Consola de modo + `GravityWorld` agnóstico + atajo mode-gated + serialización de modo/blend | puzle de modo |
| E | Escena `BayVertical.tscn` + buffers de entrada/salida | greybox jugable |
| F | Tests GdUnit de determinismo y conectividad | suite verde |
| G | Enriquecer atajos a ~5, `CylinderRotator`+`ScaffoldStreamController(cylinder_mode)`, Coriolis como sabor, pulido | iteración |

---

## 5. TABLA DE RECONCILIACIÓN DE FDs CRUZADOS

| FD | Qué aporta | En este contrato | Estado |
|---|---|---|---|
| FD-320 (bahía actual) | MachineLevel JSON, MachinePart/MachineHinge, lanzamiento inercial, retorno RingHub | Cimiento físico/formato vigente; el layout plano de estaciones pasa a chunks curados de atajo | **Parcialmente fusionado** (cimientos vigentes; layout superado) |
| FD-036 (GravityManager) | Modos de gravedad, `gravity_mode_changed` | Fuente de verdad de la gravedad; la bahía es agnóstica al modo | **Fusionado** |
| FD-039 (Gravity Physics Strategy) | Estrategia de física radial | Se respeta al leer `GravityWorld` | **Vigente** |
| FD-040 (PlateContentStream) | Stream de contenido por plate | Referencia para el streaming de chunks por cercanía | **Vigente** |
| FD-050/.1/.2 (scaffold WFC) | Generador WFC + 9 módulos + rails/openings + threaded streaming | Generador y módulos reutilizados tal cual; proyección polar nueva | **Fusionado** |
| FD-314 (ringhub scaffold streaming) | Streaming de superestructura por chunks, `DeferredSceneChunk` | Patrón de chunk por sector + colisiones normalizadas (Prop) | **Fusionado** (patrón) |
| FD-037 (campo infinito) | Scaffold procedural visual con exclusiones | No se fusiona: el cilindro es jugable y finito | **Obsoleto para esta feature** (vigente en su alcance) |
| FD-052 / v2 (MST polar duct maze) | Proyección polar, ejes ODI-001, capa Prop para cámara passthrough | Se adopta la proyección y la convención | **Fusionado** (convención) |
| FD-053 (airlock manager) | Transiciones seamless, chamber persistente | Entrada/salida como buffer físico; encaje con la API seamless de src-54 | **Vigente** (dependencia) |
| FD-035 (conveyor/carrousel) | Conveyor con occupancy, luces, carrousel | Cintas en 3 roles | **Fusionado** |
| FD-045 (gas) / FD-051 (fuego) | Zonas de gas / fuego | Candidatos de peligro curado de nivel (etapa G) | **Vigente** (opcional) |
| FD-244 (multitool) | Láser + gloo (API: `laser_hit`, grupo `gloo_blob`) | Los gates usan solo la API pública | **Fusionado** (interfaz) |
| FD-298 (linterna) | Batería/toggle OdiseaOS | Sin interacción; la luz de sala es diegética | **Vigente** |

---

## 6. Transiciones seamless (entrada/salida)

Requisito de Sebastián: toda transición es **completamente seamless, sin fade a negro** (referencia:
el airlock). src-54 generaliza el mecanismo en `SceneManager` (`SceneManager` seamless). La entrada
(anillo exterior) y la salida (cima, en el eje) son un **espacio buffer físico** (airlock/ascensor)
compatible con esa API; **no** se usa `goto_scene` con fade. Mientras la API no aterrice, el buffer
construye el espacio físico y deja el punto de enganche (`BayTransitionBuffer.request_seamless_transition`)
con `TODO(src-54)` y referencia al contrato `.operator-shared/specs/seamless-transitions.md`.

---

## 7. Verificación

1. `./.venv/bin/pytest tests/test_odisea_runner.py -k test_gd__core_v2_tests_test_bay_vertical_gd`.
2. Determinismo: misma semilla → mismo layout; semillas distintas → distinto.
3. Conectividad: BFS de la entrada (anillo exterior) a la cima (eje) sobre el grafo.
4. Anillos: la cima reside en el anillo del eje (radio mínimo).
5. Ciclo: fases deterministas; peligros solo en su ventana de `DANGER`.
6. Streaming: solo chunks dentro del radio de carga; liberación fuera del radio de descarga.
7. Gravedad agnóstica: el vector viene de `GravityWorld` (probar SPIN y, si aplica, STANDARD).
8. Capturas del greybox (máx. 2000 px) aprobadas por Sebastián. Sin texto/hints de teclas.

---

## 8. Archivos y gancho para src-51

### Nuevos
- `docs/features/FD-322_bahia_vertical_radial.md` (este archivo)
- `core_v2/levels/bay_vertical/BayProtocolCycle.gd`
- `core_v2/levels/bay_vertical/BayVerticalWell.gd`
- `core_v2/levels/bay_vertical/BayTransitionBuffer.gd`
- `core_v2/levels/bay_vertical/BayModeConsole.gd`
- `core_v2/levels/bay_vertical/GlooSpan.gd`
- `core_v2/levels/bay_vertical/LaserGate.gd`
- `core_v2/levels/bay_vertical/BayVertical.tscn`
- `core_v2/levels/bay_vertical/preview.oys`
- `core_v2/tests/test_bay_vertical.gd`
- `docs/agents/sessions/2026-11-14_bahia_vertical.md`

### No se tocan
- `core_v2/levels/machines/*` y `core_v2/props/machines/*` (src-51)
- `core_v2/input|player|ui/*` (src-50)
- FDs existentes y `docs/features/archive/*` (src-52)

### Gancho src-51
El streaming de `BayVerticalWell` es local y mínimo. El activador por cercanía de src-51 se
engancha en `_call_proximity_activator(player_pos, chunks)` (marcado `TODO(src-51)`); hasta
entonces cae a la implementación local. No duplicar esa lógica al mergear.
