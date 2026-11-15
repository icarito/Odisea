# Handoff — Investigación de tiles sospechosos en el duct maze MST (FD-052)

**Estado:** abierto. Geometría base, exclusas (iris) y capa de cámara ya resueltos
(ver más abajo). Queda investigar piezas que se solapan / se ven confusas, en
particular **arcos "W" duplicados sobre el eje del cilindro**.

**Archivos clave:**
- `core_v2/systems/DuctMazeSpawner.gd` — instancia y posiciona los tiles.
- `core_v2/systems/ScaffoldMSTGenerator.gd` — genera el grid (variantes + conexiones).
- `core_v2/systems/DuctArcBuilder.gd` — construye la malla del arco toroidal.
- `core_v2/tests/test_duct_maze_streaming.gd`, `test_mst_gen.gd` — suites (9 verdes hoy).
- Escena viva: `scenes/levels/act0_duct_maze.tscn` (axial + streaming + MST wrap_x).

---

## Problema #1 (PRINCIPAL) — Arcos "W" apilados sobre el eje del cilindro

### Síntoma observado (telemetría en vivo, no teoría)
Con el jugador dentro del cilindro, inspeccionando el árbol vivo por el peer
(`/command execute_script`), se encontraron **~5 MeshInstance con
`variant_id="W"`, `rotation=90`, todos con el MISMO origen `(0, -155, 0)`** en un
solo anillo. Eso es el eje central del cilindro (x=0, z=0). El resultado visual es
z-fighting y "piezas confusas" / clipping que reporta el usuario.

Query usada para reproducir (ajustar la ruta del streamer, hoy
`/root/Core/Act0DuctMaze/DuctMazeStreamer`):
```gdscript
var p = SessionManager.player.global_transform.origin
var streamer = get_tree().get_root().get_node("Core/Act0DuctMaze/DuctMazeStreamer")
var out = []
for chunk in streamer.get_children():
    for tile in chunk.get_children():
        if not (tile is MeshInstance): continue
        if tile.get_meta("variant_id") != "W": continue
        out.append({"rotY": tile.rotation_degrees.y, "pos": tile.global_transform.origin})
return out
```

### Causa raíz sospechada (a confirmar)
Hay **dos sistemas de coordenadas distintos** para colocar tiles, y el del arco
es el sospechoso:

1. **Tiles procedurales** (rectos N-S, codos, tees, cruces, salas) →
   `_make_procedural_tile(...)` + `instance.transform = _grid_to_world(gx, gy, h)`
   ([DuctMazeSpawner.gd:216](core_v2/systems/DuctMazeSpawner.gd) y `_grid_to_world`).
   `_grid_to_world` coloca la pieza en su **sector angular real** (x = r·cosθ,
   z = r·sinθ con θ = gx·angle_step) y orienta la base (tangente/up/radial).

2. **Arco "W" tangencial** (W con `rotation % 180 != 0`, sin stair) →
   ruta especial en [DuctMazeSpawner.gd:181-220](core_v2/systems/DuctMazeSpawner.gd):
   - malla construida por `DuctArcBuilder.get_or_build_arc(major_r, duct_radius, angle_step)`
   - `major_r = _cell_radius(gy, base_height)` = `inner_radius + height` (NO depende de gx)
   - colocada en `translation = Vector3(0, _axis_position(gy), 0)` — **siempre el eje**
   - rotada por `rotation_degrees.y = (gx - 0.5) * angle_step`

El arco de `DuctArcBuilder._build_arc` (ver el archivo) es un segmento de toro que
**empieza en u=0 (sobre +X, en `R`) y barre `arc_deg`**. Es decir, el arco asume
que su sector arranca en ángulo 0 y luego se rota por `(gx-0.5)*angle_step`.

Hipótesis a verificar:
- **(A) Rotación derivada colisiona.** Si dos celdas con distinto `gx` producen la
  misma `rotation_degrees.y` efectiva (módulo 360, o por el `-0.5` mal calibrado),
  sus arcos quedan encimados. Verificar imprimiendo `rotY` real de las 5 (la query
  de arriba con `get_aabb` falló; usar `tile.rotation_degrees.y` directo).
- **(B) El MST emite W rot90 en celdas donde no corresponde un arco completo.** El
  MST devuelve `W rot90` para conexión E-W (`conn[1] and conn[3]`,
  [ScaffoldMSTGenerator.gd:679](core_v2/systems/ScaffoldMSTGenerator.gd)). Si un
  anillo entero está conectado tangencialmente (p.ej. un anello cerrado por el
  wrap_x), CADA celda del anillo emite un arco — y todos comparten origen en el
  eje. 5 arcos = posiblemente medio anillo. Eso NO es duplicación lógica, pero SÍ
  produce geometría coincidente si `major_r` es igual y el barrido se solapa con el
  del vecino (el arco barre `angle_step` completo desde su borde, y el `-0.5`
  intenta centrarlo — revisar si el solape de medio paso entre vecinos es el
  z-fighting).
- **(C) major_r ignora el sector pero el arco depende del radio del anillo.** Como
  `major_r = inner_radius + height`, dos celdas del mismo anillo a la misma altura
  comparten `major_r` y por ende la MISMA malla cacheada
  ([DuctArcBuilder.gd:get_or_build_arc](core_v2/systems/DuctArcBuilder.gd) cachea
  por key `major_r_minor_r_arc_segs`). Comparten malla está bien; el problema es la
  posición/rotación.

### Qué entregar
- Confirmar cuál de (A)/(B)/(C) ocurre (con números reales del runtime).
- Decidir el fix. Dos caminos candidatos:
  1. **Unificar coordenadas:** renderizar el arco tangencial como pieza procedural
     vía `_make_procedural_tile` (igual que ya se hace para los W-stair, que se
     desvían de la ruta arco en [DuctMazeSpawner.gd:174-181](core_v2/systems/DuctMazeSpawner.gd)).
     Elimina el sistema de coordenadas paralelo del arco. Riesgo: el tubo
     tangencial procedural ya existe (`_local_port_endpoint` dir 1/3) — verificar
     que cierra el anillo sin gap.
  2. **Corregir la colocación del arco** para que use el mismo `_grid_to_world`
     (posición en sector + base) en vez de eje+rotación, y que el barrido del arco
     cubra exactamente un `angle_step` centrado en el sector sin solapar al vecino.
- Validar con la query de telemetría que ya NO hay dos MeshInstance "W" en el mismo
  origen, y visualmente (cámara ya atraviesa los ducts, ver abajo).

---

## Problema #2 (menor, a revisar de paso) — Codos / nexos "se atraviesan"

El usuario reportó codos confusos. Parte se debió a `_basis_from_z_axis`
produciendo una base **espejada** (det -1 → escala negativa → normales invertidas
→ con CULL_DISABLED se ve interior+exterior mezclado = "se atraviesa"). **Ya
arreglado** (ver abajo), pero conviene revisar de nuevo en vivo si persiste algún
codo raro tras el fix de arcos: el solape arco↔tubo procedural del vecino en la
junta tangencial puede contribuir.

---

## Ya resuelto en sesiones previas (NO re-hacer; contexto)

Todo verificado con tests (9 verdes: `test_duct_maze_streaming.gd` +
`test_mst_gen.gd`) y, donde se indica, en vivo por el peer:

1. **MST envuelto en el cilindro** (`wrap_x`): eje angular cíclico (sector N-1 ↔ 0).
   Reemplazó a `concentric_axial_lanes`/`dual_axial_lanes` (eliminados).
2. **Tubos cruzan su cáscara:** todo tile con cáscara (cápsula de sala o esfera de
   nexo grado>1) extiende sus tubos hasta `shell_reach` + overlap, o el hueco
   tallado quedaba sin túnel detrás ("cáscara con hueco, sin salida"). Los puertos
   tangenciales E/W caían a ~2.5, dentro de la esfera ~4.1. Guardado por
   `test_junction_tubes_cross_the_nexus_shell`.
3. **Exclusas = IrisDoorV2** (no DuctGateValve), en cada boca de tubo, escaladas
   ~2.26× al bore. El interactable real es el hijo `IrisMechanism` (la raíz es un
   `InteractableBridge` que NO está en grupo "interactable").
4. **Iris arranca ABIERTO** (`starts_active=true`) — cerrado por defecto bloqueaba
   toda entrada ("ninguna puerta abre para entrar"). + `InteractionArea` (layer 16)
   añadida al mechanism para que el jugador la enfoque esté abierta o cerrada.
5. **`_basis_from_z_axis` ahora right-handed** (det +1): la base espejada daba
   escala -2.26 en el iris y volteaba el giro de los blades → "Operar exclusa no
   hace nada" (verificado en vivo: `interact()` SÍ togglea `is_active` y anima;
   el bug era sólo la base de colocación).
6. **Tiles en capa Prop (bit 64 = `DUCT_COLLISION_LAYER`), no Entorno (1):** el
   jugador colisiona (su required mask incluye Prop) pero la cámara
   (`camera_collision_mask=129`, sin Prop) **atraviesa** los ducts → se ve el
   interior. Incluye los StaticBody del iris .tscn vía
   `_move_static_bodies_to_prop_layer`. Guardado por
   `test_duct_tiles_are_on_prop_layer_so_camera_passes_through`.

---

## Cómo investigar en vivo (peer / ANNA V2)

- Asegurar peer: `tools/ensure_peer.sh`. Lanzar juego: `tools/launch_game.sh
  --scene res://scenes/levels/act0_duct_maze.tscn` (headful para ver; **avisar al
  usuario antes de lanzar** — cierra el juego si no sabe que estás probando).
- Inspeccionar árbol vivo: `curl -XPOST localhost:4999/command -d
  '{"action":"execute_script","args":{"script":"..."}}'`.
- Posición jugador: `curl "localhost:4999/eval?expr=SessionManager.player.global_transform.origin"`.
- Screenshot suele dar `timeout` bajo streaming pesado; reintentar o reducir
  `stream_active_chunks_each_side`. Headless `--no-window` da framebuffer negro
  (quirk GLES2): para geometría usar un probe SceneTree que imprima números.
- Validar geometría sin juego: SceneTree script que haga
  `spawner._make_procedural_tile(conns, [0,0,0,0], ring_radius, is_room)` e
  inspeccione AABB / colisión de los hijos.
