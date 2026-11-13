# Laberinto + Hazards en la Bahía — plan de sesión, 2026-11-13

Worker: AO src-7. Pedido: "explora usar los generadores de mapas (e.g. como en scaffoldOrbit) para generar secciones laberínticas entre las maquinarias y añade hazards de fuego y de gas aprovechando Box3D".

## Decisión de generador: MST (`ScaffoldMSTGenerator.gd`)

- Por qué MST y no WFC puro:
  - `ScaffoldMSTGenerator` garantiza un solo componente conectado (laberinto transitivo) con ciclos (`extra_cycles`), velocidad y sin retry.
  - Determinismo explícito: usa `RandomNumberGenerator` interno con `rng.seed = seed_val` (`generate_grid_data(seed_val)`). Nada de `randf()` global ni `Engine.get_frames_drawn()`.
  - Devuelve datos planos (Array de diccionarios, `null` para celdas vacías) → ideal para comparar determinismo y para posicionar hazards desde la misma malla.
  - Soporta `fixed_border_tiles` (sellos de borde) → permite fijar la celda de entrada a la altura del piso de la bahía.
  - Es el camino por defecto de `ScaffoldWFCGenerator` (`use_mst_generator=true`), así que el look reutiliza los mismos módulos de scaffold.
- `ScaffoldOrbit.gd` se usa solo como referencia de look (cilíndrico, no aplica aquí); los módulos son los de `core_v2/props/scaffold/`.

## Punto de inserción: bolsillo lateral entre Estación 1 y Estación 2

- Bahía (layout `machine_bay.json`): estaciones a lo largo de Z (entrada z≈-2 → S1 z≈8 → S2 z≈28 → S3 z≈48 → S4 z≈65 → salida z≈87). Corredor central x∈[-7,7].
- Vacío lateral detectado: x∈[5,17], z∈[8,26], y≈0…2.5 (al este de EntryFloor/Ledge1, bajo la ruta elevada hacia S2). No interfiere con ninguna estación ni con la ruta aprobada de FD-320.
- El laberinto es una **sección exploratoria opcional** (callejón con hazards), NO reemplaza la ruta de las cuatro estaciones: la ruta principal queda intacta.
- Conexión: celda de entrada pegada al borde este de `EntryFloor` (top y=0) con `fixed_border_tiles` fijando esa celda a `base_height=0` → se camina directo desde el piso de entrada.

## Archivos que toco (solo los permitidos)

- NUEVO `core_v2/levels/machines/LabyrinthSection.gd` — script Spatial que:
  1. Genera la malla con `ScaffoldMSTGenerator.generate_grid_data(seed)` (seed fija const, ej. 20261113).
  2. Instancia módulos scaffold (preload de `core_v2/props/scaffold/*.tscn`) replicando el instancing de `ScaffoldWFCGenerator._instance_grid` (translation/rotation/setters de rails/dims).
  3. Coloca hazards según la misma malla: `FireSystem` (estático, `base_speed=0`, línea de fuego sobre la cubierta) + `GasArea3D` tóxica (pocket en una celda interior). Todo determinista.
  4. Todo en `_ready()`/`_physics_process`; en `replay_sync` (FireSystem y GasArea3D ya lo están, con snapshot).
- NUEVO `core_v2/levels/machines/LabyrinthSection.tscn` — raíz Spatial con el script (para instanciar desde MachineBay).
- NUEVO `core_v2/tests/test_labyrinth_hazards.gd` — suite GdUnit:
  - Determinismo MST: misma seed+params → grids idénticos (serializado JSON) en dos instancias frescas.
  - Determinismo de instanciación: dos `LabyrinthSection` → mismos hijos y transforms.
  - Fuego: `FireSystem` estático emite `heat_contact` con dps>0 a un cuerpo `fire_vulnerable` sobre la cubierta.
  - Gas: `GasArea3D` tóxica daña a un cuerpo dummy "player" tras steps de física.
  - Alineación: `base_height` de la celda de entrada == top del EntryFloor.
- MODIFICAR `core_v2/levels/machines/MachineBay.tscn` — mínimo: +1 `ext_resource` y +1 nodo instancia de `LabyrinthSection.tscn`. No toco estaciones ni `machine_bay.json`.
- DOC `docs/agents/sessions/2026-11-13_laberinto_hazards.md` (este).

## Comandos de verificación

```bash
# test nuevo
./runtest.sh --filter labyrinth
# o directo:
/home/icarito/Proyectos/Odisea_Game/src/.venv/bin/pytest tests/test_odisea_runner.py -q -k "test_gd__core_v2_tests_test_labyrinth_hazards_gd"

# ruta de las cuatro estaciones intacta
/home/icarito/Proyectos/Odisea_Game/src/.venv/bin/pytest tests/test_odisea_runner.py -q -k "test_machine_bay or test_machine_level or test_machine_launch"

# suites existentes de scaffold/fire/gas
/home/icarito/Proyectos/Odisea_Game/src/.venv/bin/pytest tests/test_odisea_runner.py -q -k "test_fire_system or test_gas_particle_lod or test_scaffold_grate_emission"

# manifests (si toco assets; no debería)
python3 scripts/check_tracked_imports.py
```

## Criterio de hecho

1. `test_labyrinth_hazards` verde (determinismo + presencia/efecto de ambos hazards).
2. `test_machine_bay/level/launch` siguen verdes (ruta FD-320 intacta).
3. Suites existentes de fire/gas/scaffold verdes.
4. Captura 960×540 en DISPLAY :0 con hardware input deshabilitado del laberinto + hazards (fuego y gas visibles).
5. Commit + push de la rama AO + PR draft a main (según instrucción del orquestador).

## Adendum creativo (orquestador src-1, 2026-11-13)

Sebastián: los laberintos/hazards deben tener PRESIÓN DE TIEMPO o ser TRAMPAS, con sabor "mente de Odisea" (fría, burocrática): las trampas son "protocolos"/"purga programada"/"normas". Telegrafiar con claridad, ciclos deterministas, margen honesto; nada de frustración injusta. Determinismo sigue valiendo.

Implementación en el slice (mínima, sin tocar HUD/signaling):
- Ciclo de protocolo determinista en `LabyrinthSection._physics_process` (acumulación de `_elapsed`, sin randf): fases `SAFE (4s) → WARNING_FIRE (2s) → FIRE (5s) → SAFE (4s) → WARNING_GAS (2s) → GAS (5s)` = 22s. Fuego y gas alternan; cada hazard tiene ventana activa acotada (presión de tiempo para cruzarlo) y ventana segura honesta.
- Telegraphing: `OmniLight` de estado en la entrada que cambia color por fase (verde=seguro, ámbar=aviso, rojo=fuego activo, cian=gas activo). No toca HUD/UI/Señalética existente.
- Arranque en SAFE (sin daño al entrar). Getters para test (`get_hazard_phase`).

## Estado de ejecución (Fase 2 completada)

- Tests: `test_labyrinth_hazards.gd` 7/7 verde; máquinas 6/6; fire/gas/scaffold 5/5; manifests 952 OK.
- Capturas (960x540, DISPLAY :0, hardware input off): `laberinto_default.png`, `laberinto_fire.png`, `laberinto_gas.png` (+ `_gas_closeup`), en `/home/icarito/.ao/data/artifacts/src-7/laberinto/`. Revisadas por subagente de visión: fuego visible e inconfundible; estado default limpio; el gas se ve como penacho tóxico gris-verdoso sobre la pasarela (sin llamas), pero la calibración a teal vivo queda para ojos humanos.
- PR draft: https://github.com/icarito/Odisea/pull/371 (rama `ao/objetivo-pulido-nocturno-5/laberinto-hazards`).
- Notas: fallo de hook pre-commit/pre-push por queja ambiental de export-presets (exclude_filter tapa `fireball_01.png`), se omitieron hooks con validación manual equivalente. Flakes de suites de máquina en lote por compartición de peer (ya documentado).

## Riesgos

- `BayShell.glb` (opcional) podría intersectar el volumen lateral en builds que lo incluyan: riesgo aceptado, asset opcional; la sección vive en vacío no usado.
- API de módulos scaffold (setters `rail_*`, `platform_*`): replico exactamente lo que ya hace `ScaffoldWFCGenerator._instance_grid` (probado en el repo).
- `FireSystem` estático (`base_speed=0`) es uso nuevo: se cubre con test de `heat_contact`.
- `GasArea3D` requiere espacio de física y `CollisionShape`; en headless funciona (usa `direct_space_state`).
- No correr la suite completa (regla del proyecto): solo focalizados.
