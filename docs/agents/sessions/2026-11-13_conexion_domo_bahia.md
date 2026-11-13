# Conexión domo → bahía de máquinas — plan y bitácora, 2026-11-13

Sesión: `ao/objetivo-pulido-nocturno-3/root` (worktree `src-5`).
Objetivo (usuario, textual): *«el ideal es que haya una apertura en el domo y un
airlock con un tunel para llegar a la bahía tal vez con algunos hazzards»*.

Hoy el acceso a la bahía es un **botón**: `Hub/PedestalMachineBay`
(`core_v2/levels/RingHub_Level.tscn:675`) → `RingHubLightState.enter_machine_bay()`
(`core_v2/levels/RingHubLightState.gd:187`) → `SceneManager.goto_scene("…/MachineBay.tscn")`
con payload de retorno. FD-320 cerró dejando la conexión domo/tubo **fuera de alcance**
(`docs/features/FD-320_bahia_de_maquinas.md:79`); esto la reabre como pivote explícito.

## Fase 1 — Reconocimiento (medido, no inferido)

Script de medición: `/tmp/kilo/measure_ringhub.gd` y `/tmp/kilo/measure_shell.gd`
(headless, `eval.sh -f`, solo lectura).

| Objeto | Hecho medido |
|---|---|
| `Hub/DomeInteriorLowPoly/DomeMesh` | hemisferio, AABB x,z ∈ [-35,35], y ∈ [0,35]; `DomeInteriorLowPoly_baked.mesh` (1 superficie, 496 verts, **240 tris**, formato V+N+UV+**UV2**+IDX) + `.shape` (240 caras, `ConcavePolygonShape`) |
| `Hub/GroundFloor` | piso y=0, BoxShape extents (35,0.3,35) → disco 70×70 caminable hasta r=35 |
| `Hub/RingFloor` (Floor_1) y `Floor_2..5` | anillos del hub r 6..13, decks y=4.5·N; AABB radial hasta ~14.1 |
| `Hub/PedestalMachineBay` | world **(31.8, 0, 3.2)** → azimut θ₀ = atan2(3.2,31.8) = **5.75°**, r≈32 |
| `Hub/PedestalLight` | world (32.5, 0, 0) → azimut ≈ 0° |
| Shell: fuente/baker | `tools/bake_dome_interior_lowpoly.gd` lee `assets/models/dome_interior_lowpoly/DomeInteriorLowPoly.glb` (16 radiales × 8 anillos = 240 tris, r fuente 16.5 → escalado a **r=35**). Único consumidor del producto: `RingHub_Level.tscn` (no lo comparten Dome_Intro/Prologue) |
| Kit de tubo | `TubeSection.tscn`: cilindro radio 4, alto 9, **sin colisión** (solo visual). `TubeRing.tscn`: radio 2.7. `TubeAirlock.tscn`: Area + BoxShape(2,2,1) + `IrisDoorV2` + CSG frame; script con guard de doble disparo + gracia post-transición. `TubeZeroGravityZone.tscn`: Area con `ZeroGravityZone.gd`. `TubeBuilder.gd`: barrido de malla sobre `Curve3D` (transporte paralelo + fillet) |
| `AirlockShell.tscn` | cilindro con colisión (Concave), `AirlockSafetyFloor` BoxShape (2.85,0.08,4) → interior ~5.4 m de diámetro, 8 m de piso |
| `FreeAirlockDoor.tscn` | compuerta de dos hojas animada, jambas en ±2.5 (≈5 m de ancho), blocker abre a anim_progress>0.8 |
| Hazard | `WindTunnelV2.gd` (`core_v2/components/`): Area `replay_sync`, `_physics_process`, aplica `set_external_velocity` (usa `external_source_is_static=false`), determinista. Escena de ejemplo: `IndustrialFan.tscn` |
| Escena de test del kit | `core_v2/tests/test_tube_airlock.tscn` (Pilot + TubeSection + 2 Airlock + ZeroG + rings) y `test_tube_airlock.oys` — plantilla directa |

## Ubicación elegida

**Piso 0 (ground floor, y=0) del RingHub, contra la cáscara del domo, azimut θ₀ ≈ 5.75°**
(la radial del `PedestalMachineBay` existente).

Por qué:
- La bahía «vive» ahí en la ficción: el pedestal *Esclusa de Mantenimiento — Bahía 3*
  (`RingHub_Level.tscn:678`) ya está en esa pared. Hacer coincidir la compuerta física y el
  botón las lee como **la misma esclusa**, sin inventar una segunda ubicación narrativa.
- Es piso 0, no un anillo del hub: el deck del hub está a y=4.5 y a r≤13; la cáscara está a
  r=35. Un anillo no llega a la pared. El piso 0 llega caminando hasta r=35.
- La cáscara del RingHub es **suya** (no compartida con Dome_Intro/Prologue) → cortar ahí no
  toca el domo de criogenia (contrato `dome_source_mapping.md:22-54`).

## Fase 2 — Slice vertical mínima y reversible

1. **Abertura en la cáscara.** Herramienta nueva `tools/cut_ringhub_dome_opening.gd`:
   lee `DomeInteriorLowPoly_baked.{mesh,shape}` y **recorta** los triángulos (clipping
   Sutherland-Hodgman de polígono contra caja orientada) dentro de una ventana
   ~5.0 m × 3.4 m centrada en θ₀. **Preserva UV1/UV2/normales interpolando**, así el
   `RingHub.lmbake` horneado sigue válido (los texels nuevos caen donde caían). Escribe
   salidas **nuevas** `DomeInteriorLowPoly_breach.{mesh,shape}`; `RingHub_Level.tscn`
   apunta a ellas. La fuente (`_baked`) queda intacta: rehornear el shell no pierde el corte.
   - Comando: `tools/godot --path . --no-window -s tools/cut_ringhub_dome_opening.gd`
   - Verificador: el propio tool imprime caras antes/después y falla si no removió nada.
2. **Túnel transitable.** Escena nueva `core_v2/props/tube/RingHubBayConnector.tscn`:
   piso (StaticBody+BoxShape), paredes/techo, `TubeSection`/`TubeRing` como piel visual,
   orientada con +X = radial hacia afuera. Se instancia en `RingHub_Level.tscn` bajo `Hub`.
3. **Airlock.** En el extremo externo del túnel, un Area con el script nuevo
   `core_v2/props/tube/BayAirlockTrigger.gd` que, al entrar el jugador, llama
   **`RingHubLightState.enter_machine_bay()`** del nivel actual: reusa el camino
   hub→bahía ya probado (arma el payload de retorno) y **no requiere tocar** SceneManager,
   AirlockManager, AirlockTransitionFX ni AirlockControllerV2. Estética: `IrisDoorV2`
   (FD-025: el IrisDoor es la mejor base).
4. **Hazard de ejemplo.** `WindTunnelV2` (Area, script referenciado) en el tramo medio,
   soplando hacia **adentro** (−X), `is_active=true`: el jugador tiene que avanzar contra
   la corriente. Determinista, sin `randf`/`get_frames_drawn`.
5. **Acceso viejo.** `PedestalMachineBay` queda **intacto**: sigue siendo un acceso válido.
   Convivencia: mismo destino, misma narrativa; el nuevo es el acceso «físico».
   `HUB/PedestalMachineBay` es un botón; el conector es la boca.

### Archivos

- Nuevos: `tools/cut_ringhub_dome_opening.gd`,
  `core_v2/levels/interiors/DomeInteriorLowPoly_breach.{mesh,shape}` (producto),
  `core_v2/props/tube/RingHubBayConnector.tscn`, `core_v2/props/tube/BayAirlockTrigger.gd`,
  `core_v2/tests/test_ringhub_bay_connector.gd`.
- Editados: `core_v2/levels/RingHub_Level.tscn` (ext_resource de la cáscara cortada +
  instancia del conector), `docs/agents/sessions/2026-11-13_conexion_domo_bahia.md`.
- **Sin tocar**: `RingHub_HubTowerSource.tscn` (no hace falta abrir sector de anillo),
  `DomeInteriorLowPoly_baked.*` (la fuente horneada), HUD/UI, señalética, MachineBay,
  MachineLevel.gd, ni los scripts de transición.

### Criterio de hecho

- `tools/cut_ringhub_dome_opening.gd` remueve caras y produce `_breach.{mesh,shape}`;
  un chequeo headless cuenta las caras removidas (>0) y que UV2 siga presente.
- `RingHub_Level.tscn` carga con la cáscara cortada y el conector; el jugador puede
  caminar del piso 0 por la boca, el túnel, hasta el airlock.
- Tests focalizados verdes (ver abajo).
- Capturas 960×540 en `:0` de la boca, el túnel y el hazard, con `hardware_input_enabled=false`.

### Riesgos y mitigación

- **Lightmap.** Si el corte regenerara UV2, el `RingHub.lmbake` quedaría desalineado. Se
  evita preservando UV2 (interpolado en los vértices de corte) y por eso se corta el
  **producto** en vez de reintroducir un parámetro en el baker del GLB.
- **Escala del shell.** 16 radiales = facetas de 22.5°; remover facetas enteras abriría un
  hueco de ~13 m. Por eso se hace **clipping exacto**, no remoción por centroide.
- **Determinismo / replays.** Cambiar la colisión de la cáscara puede invalidar replays que
  rocen la pared (precedente: parapeto del hub, `dome_source_mapping.md:145`). El corte está
  lejos de las rutas del hub (r 6..13 vs r≈35); aun así, repetir los fixtures de determinismo
  aislados si se toca movimiento.
- **Rollback.** Todo es aditivo: revertir `RingHub_Level.tscn` a
  `DomeInteriorLowPoly_baked.*` y borrar el nodo conector deshace la conexión.

## Comandos

```sh
# corte de la cáscara
tools/godot --path . --no-window -s tools/cut_ringhub_dome_opening.gd
# verificadores del hub (no deben cambiar)
tools/godot --path . --no-window -s tools/check_hub_ring_skipped_sides.gd
make verify-ringhub-hub
# tests focalizados
/home/icarito/Proyectos/Odisea_Game/src/.venv/bin/pytest tests/test_odisea_runner.py -q \
  -k "test_ringhub_light_state or test_airlock_zone_v2 or test_airlock_standalone_bidirectional or test_tube_builder or test_ringhub_bay_connector"
```

## Nota de entorno (worktree src-5)

El worktree AO llegó sin `.venv` y con `.import/` incompleto (2621 vs 5556 `.stex`), lo que
impedía cargar `RingHub_Level.tscn` headless. Se completó `.import/` por `rsync` desde
`/home/icarito/Proyectos/Odisea_Game/src/.import/` (mismo commit 4c916f2b, 281 MB) y se usa
el venv de ese checkout hermano (`…/.venv/bin/pytest`). `_REPO_ROOT` del runner resuelve al
worktree (`tests/test_odisea_runner.py:437`). Nada de esto se commitea.

## Bitácora / resultado

### Fase 2 implementada

- **Abertura**: `tools/cut_ringhub_dome_opening.gd` (clipping Sutherland-Hodgman
  contra caja orientada, preserva UV1/UV2). Salida: `DomeInteriorLowPoly_breach.{mesh,shape}`.
  Corrida: `[cut_dome] OK azimut=5.75gr ... tri fuente=240 intersectados=2 ... salida tri=246
  caras_colision=246 uv2=si`. `RingHub_Level.tscn` apunta el `DomeMesh`/`WorldCollision` a la
  versión `_breach`. La fuente `DomeInteriorLowPoly_baked.*` queda intacta.
- **Verificación del agujero** (raycast radial contra el shape de salida, `/tmp/kilo/verify_opening.gd`):
  centro de la boca (az 5.75°, y 0.1/1.6/3.1) → 1 impacto (pared cercana AUSENTE = agujero);
  a ±12° y a y=6 → 2 impactos (pared presente). Confirmado.
- **Túnel + esclusa + hazard**: `core_v2/props/tube/RingHubBayConnector.tscn`
  (piso/paredes/techo con colisión, `TubeSection`/`TubeRing` de piel, 2 `OmniLight` propios,
  un `WindTunnelV2` en el tramo medio soplando hacia adentro, `IrisDoorV2` y un
  `BayAirlockTrigger`). Instanciado en `Hub/BayConnector` con
  `origin = n·28 = (27.859, 0, 2.805)`, `+X local → n` (azimut 5.75°). El túnel va de r≈33 a
  r≈50 y cruza la cáscara en r=35.
- **Transición**: `core_v2/props/tube/BayAirlockTrigger.gd` llama
  `RingHubLightState.enter_machine_bay()` del nivel → reusa el camino hub→bahía ya probado
  (arma el payload de retorno). **No** se tocó SceneManager/AirlockManager/AirlockTransitionFX/
  AirlockControllerV2 (los posee el worker de transiciones); no hizo falta.
- **Acceso viejo**: `Hub/PedestalMachineBay` queda intacto; mismo destino y misma narrativa
  (Esclusa de Mantenimiento — Bahía 3). El botón es el acceso «administrativo», la boca es el
  acceso físico.

### Trampas encontradas

- **Serialización de `Transform` en `.tscn`**: en el texto `Transform(a,b,c,d,e,f,g,h,i,o)`
  las columnas de la matriz son `col0=(a,d,g)`, `col1=(b,e,h)`, `col2=(c,f,i)` (lo que uno
  escribe como «y_axis» cae en la COLUMNA 1, no en la «fila» 1). Escribir el transform
  «transpuesto» puso el `TubeSection` vertical. La forma segura es dejar que Godot genere el
  texto: crear el `Basis` en un script y leer su serialización (lo que imprime `.x/.y/.z` NO
  es el orden del `.tscn`; verificarlo con un probe `global_transform.xform(local)`).
- **`SET_POS "Pilot" [x,y,z]` en OYS** concatena el nombre del nodo y rompe el parseo de la X
  (`pos = "Pilot"[27.86,...] → x=0`). Usar `SET_POS [x,y,z]` sin el nombre (el intérprete
  teleporta al jugador activo) o `TELEPORT pos=...`.

### Evidencia (comandos y resultados)

```sh
tools/godot --path . --no-window -s tools/cut_ringhub_dome_opening.gd   # OK, 2 tri recortados
tools/godot --path . --no-window -s tools/check_hub_ring_skipped_sides.gd  # ok, 17 comprobaciones
tools/godot --path . --no-window -s tools/verify_ringhub_hub_chunks.gd  # PASS (exit 0)
python3 tools/check_criopod_layout.py                                   # ok
python3 scripts/check_tracked_imports.py                                # 952 manifests OK
# tests focalizados (verde):
pytest ... -k "test_ringhub_bay_connector or test_ringhub_light_state or test_airlock_zone_v2 \
  or test_airlock_standalone_bidirectional or test_tube_builder or test_hub_floor_low_tier \
  or test_ringhub_chunk_streaming or test_ringhub_floor_material"        # 8 passed
pytest ... -k "test_ringhub_wakeup"                                      # passed (aislado; flake conocido)
```

`test_ringhub_bay_connector.gd` incluye un test de **transitabilidad real**: el piloto arranca
en el piso del domo (r=29), se lo conduce con acciones (`move_forward`/etc. según la base de la
cámara) y llega a r≥42 apoyado en el piso → cruza la boca cortada, no es sólo geometría.

Capturas 960×540 en `:0` (binario gráfico del fork, `--show`/DISPLAY=:0), con el domo
**encendido** para que la geometría sea legible:
`/home/icarito/.ao/data/artifacts/src-5/conexion_domo_bahia/{1_aproximacion,2_boca,3_tunel,4_airlock}.png`.
Observación: `2_boca` muestra la boca y el túnel desde el piso del domo; en `3_tunel`/`4_airlock`
la cámara se mete dentro del `TubeSection` transparente (el spring arm colisiona con las
paredes de un túnel de 4.6 m), así que se ven las caras internas del tubo. La escena **commiteada
arranca en DARK**, así que las capturas se tomaron con las luces encendidas (estado válido del
juego, del pedestal); en DARK el túnel queda casi negro (ver follow-ups).

## Dudas abiertas / necesita ojos humanos (Sebastián)

1. **Ancho del túnel vs cámara**: 4.6 m hace que el spring arm (~7 m) colapse y la cámara quede
   casi en primera persona dentro del tubo (claustrofóbico, pero rompe la lectura de la pose).
   ¿Aceptable para una esclusa de servicio, o ensanchamos la boca/túnel (p.ej. 6 m) a costa de
   agrandar el corte de la cáscara?
2. **Iluminación en DARK**: el túnel tiene 2 `OmniLight` propios (energy 2.2/2.0) pero con el
   ambiente DARK (0.02) queda muy oscuro. ¿Le damos una tira emisiva propia / una luz que el
   `LightState` no atenúe, o es deseable que el jugador lo cruce con el foco del casco?
3. **Collar de la boca**: el corte deja el borde fino de la cáscara (~0.2 m de labio) tapado por
   el tubo. ¿Vale un marco/collar metálico para leerlo como compuerta (estética)?
4. **Pipeline**: `tools/cut_ringhub_dome_opening.gd` debe correrse DESPUÉS de
   `bake_dome_interior_lowpoly.gd` (si se rehornea el shell, se pierde la boca). ¿Lo encadenamos
   en el Makefile junto a `bake-ringhub-hub`?
5. **Determinismo**: la colisión de la cáscara cambió 240→246 caras en una zona local; no corrí
   las fixtures de determinismo completas (van en CI). El viento del túnel es `replay_sync` y
   determinista, pero conviene confirmarlo con el job de determinismo.
6. **`test_ringhub_wakeup`** flakeó 1/1 en la corrida en batería y pasó aislado: coincide con la
   nota de memoria (suite físico-sensible, CI la rescata con `ODISEA_RETRY_ISOLATED=1`). No lo
   atribuyo a este cambio (el caso fallido es de criopods).

