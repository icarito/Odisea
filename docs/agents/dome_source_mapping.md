# Dome_Intro — mapping fuente → baker → producto

Contrato: autoría (`*Source.tscn`) → baker determinista (`tools/bake_*.gd`) →
producto horneado (`.mesh`/`.shape`/`.material`/`.tscn` de body) → runtime
(`Dome_Intro.tscn` / `Dome_Base.tscn`). Ningún baker relee un producto ya
horneado como si fuera fuente. Contexto extendido en
[FD-250](../features/FD-250-dome-intro-reproducible-bake.md) y
[FD-261](../features/FD-261-dome-intro-pipe-signage-bake.md).

| Fuente (`core_v2/levels/interiors/`) | Baker (`tools/`) | Producto |
|---|---|---|
| `DomeIntro_CriopodsSource.tscn` | `bake_dome_intro_criopods.gd` | `DomeIntro_Criopods<N>_{shell,glass,cards}.mesh`, `DomeIntro_Criopod_{shell,glass}.material`, `DomeIntro_Criopod_box.shape`, `DomeIntro_Criopods.nodes` |
| `DomeIntro_ScaffoldSource.tscn` | `bake_scaffold_walkways.gd` | `DomeIntro_<Group>_sector_NN.mesh`, `DomeIntro_<Group>_mat_NN.material`, `DomeIntro_<Group>_body.tscn` |
| `DomeIntro_HubTowerSource.tscn` (child `ScaffoldHubTower`) | `bake_dome_intro_hub_floors.gd` | `Dome_Intro_<FloorName>_baked.mesh`/`.shape`, `Dome_Intro_HubRing_mat_NN.material` |
| `DomeIntro_PipeNetworkSource.tscn` | `bake_pipe_network.gd` | `DomeIntro_<GroupName>Pipes_baked.mesh`, `DomeIntro_<GroupName>Pipes_body.tscn`, `DomeIntro_<GroupName>Pipes_mat_NN.material`, `DomeIntro_PipeNetworkVisualBake.tres` |
| `DomeIntro_SignageSource.tscn` | `bake_signage_panels.gd` | `DomeIntro_SignageAtlas.res`, `DomeIntro_SignagePanels.material`, `DomeIntro_SignagePanels_baked.mesh`, `DomeIntro_SignagePanels_body.tscn` |

Cada baker lee su fuente vía `DEFAULT_SOURCE_PATH`, overridable con la env var
`ODISEA_BAKE_SOURCE` — no hay duplicación que consolidar, la separación de
FD-250/FD-261 ya cumple la regla de arquitectura.

## `Dome_Base.tscn` ES la base del módulo de criogenia

Verificado en runtime, no inferido. `Dome_Base.tscn` contiene el
`ScaffoldHubTower` entero (`Floor_1..5`), `SpiralStairs`, `HubSpokes`,
`SpiralWalkways` y el ascensor, y referencia los `Dome_Intro_Floor_N_baked.mesh`
por ruta. Lo instancian **exactamente dos** escenas: `Dome_Intro.tscn` y
`Dome_Prologue.tscn` (`Dome_Default.tscn` es otra cosa: terraza + airlocks, sin
torre).

Consecuencia práctica, medida hornear-y-cargar:

| | Dome_Intro | Dome_Prologue |
|---|---|---|
| hornear `DomeIntro_HubTowerSource` | cambia | **cambia también, sin editar la escena** |
| hornear `DomeIntro_CriopodsSource` | cambia (via splicer) | no tiene criopods |

O sea: **hoy Prologue no puede tener un hub distinto de Intro.** El hub ya es
modular y compartido; lo que no es modular son los criopods y los pipes, que
viven sólo en `Dome_Intro.tscn`.

Para que dos domos difieran en el hub hay dos caminos, ninguno tomado todavía:

1. Sacar el `ScaffoldHubTower` de `Dome_Base` y que cada domo instancie el suyo.
2. Dejarlo en `Dome_Base` y sobreescribir `mesh`/`shape` de cada `Floor_N` por
   escena — menos diff, pero mete cinco overrides de recurso por domo, que son
   justo los que el editor barre al reserializar (ver
   [[project_tscn_overrides_swept_by_editor]]).

Los bakers aceptan `ODISEA_BAKE_PREFIX` para hornear con otro prefijo de salida
(`make dome-variant-sources` / `make bake-dome-variant VARIANT=X`), pero mientras
el consumidor sea `Dome_Base` **no hay dónde enchufar ese producto**. Sin la env
var el nombre es el histórico, así que `make bake-dome-geometry` sigue horneando
Dome_Intro igual.

## El lazo de iteración

```sh
make preview-dome-variant VARIANT=DomeIntro   # segundos, no escribe artefactos
```

Arma una escena temporal con las fuentes (hub + scaffold + criopods), fuerza
`rebuild_baked_items` sobre copias y saca fotos con `tools/shot_scaffold.gd`.
Muestra el `.tscn` fuente tal como está ahora, esté horneado o no. Los criopods
entran a propósito: es la vista donde se ve si quedó un pod flotando sobre un
hueco del deck. Hornear recién cuando el patrón ya está elegido.

En el editor el lazo es más corto todavía: los `Floor_N` no sobreescriben
`auto_build`, así que tocar `skipped_sides` en el inspector reconstruye el piso
en el acto. El guard de `_ready()` sólo evita el rebuild al ABRIR la escena.
Guardar la fuente es inofensivo: sus `CombinedMesh` embebidos son sólo vista
previa y el baker los reconstruye igual.

Editar las `DomeIntro_*Source.tscn` cambia Dome_Intro **y** Dome_Prologue.

## Caso aparte: `DomeIntro_BakeLights.tscn`

No es una fuente de bake de malla. Es un rig de luces estáticas consumido
únicamente por `tools/editor_bake_dome_intro_lightmap.gd` durante el bake del
`BakedLightmap` (produce `Dome_Intro.lmbake`), vía
`tools/generate_dome_intro_bake_lights.gd` /
`tools/set_dome_intro_bake_lights.gd` / `tools/verify_dome_intro_bake_lights.gd`.
No pasa por ningún `bake_*.gd` de malla.

## Verificado: consumidores de `Dome_Intro_Floor_1..5_baked.mesh/.shape`

Estos `ext_resource` (ids 105-114 en `Dome_Intro.tscn`) no tenían un
consumidor visible en el árbol superficial de `Dome_Intro.tscn`; se confirmó
que los consume `ScaffoldHubTower` (instancia de `ScaffoldHubTower.tscn`,
hijos `Floor_1..5`) — producto de `bake_dome_intro_hub_floors.gd`. No están
huérfanos.

## Reproducibilidad (verificación pendiente de ejecutar)

Correr cada baker dos veces seguidas y comparar hash de los artefactos
producidos; deben ser idénticos. Comando por grupo (ver `Makefile`,
target `bake-dome-geometry` para pipe/scaffold/hub — criopods y signage se
corren manualmente con `godot3-bin --path . --no-window -s tools/bake_dome_intro_criopods.gd`
y `... -s tools/bake_signage_panels.gd` respectivamente):

```sh
godot3-bin --path . --no-window -s tools/bake_scaffold_walkways.gd
sha1sum core_v2/levels/interiors/DomeIntro_*_sector_*.mesh > /tmp/run1.sha1
godot3-bin --path . --no-window -s tools/bake_scaffold_walkways.gd
sha1sum core_v2/levels/interiors/DomeIntro_*_sector_*.mesh > /tmp/run2.sha1
diff /tmp/run1.sha1 /tmp/run2.sha1  # debe estar vacío
```

## Cuántos criopods hay, y de dónde sale ese número

Los nodos `Item_N` de `*_CriopodsSource.tscn` son **producto**, no autoría: las seis
rings traen `rebuild_baked_items = true`, así que `RadialScatter._ready()` regenera
sus hijos antes de que el baker los lea. Borrar `Item_N` en el editor no baja el
conteo — vuelve en la siguiente carga.

Las perillas reales son `item_count` (40 en las seis) y `blocked_angle_ranges_deg`.
Con 40 slots el paso es 9°, o sea **5 pods por cada sector de 45° del hub**.

`blocked_angle_ranges_deg` de los criopods y `outer_openings_deg` /
`skipped_sides` del `ScaffoldHubRing` están en el mismo marco angular (el bloqueo
`(86.0, 123.9)` de `Criopods6` es la misma abertura que el `(90, 123)` de
`Floor_5`). Un sector `k` salteado en el hub se tapa en los criopods con
`Vector2(45*k, 45*(k+1))`.

## `ScaffoldHubRing.skipped_sides`

Índices de sector que no se construyen (ni deck, ni baranda de arco, ni franja, ni
columna), para abrir rutas alternativas o calar el anillo intercalando sectores.
El borde radial expuesto se cierra con baranda propia y la columna de la esquina
huérfana se repone. Acepta índices negativos o fuera de rango.

Los criopods se paran sobre estos decks (r = 12, con el deck de 6 a 13): un sector
salteado **sin** su bloqueo en los criopods deja 5 pods por piso flotando.

Check: `godot3-bin --path . --no-window -s tools/check_hub_ring_skipped_sides.gd`

## Kit modular de caneria (nuevo)

`assets/models/Modular Pipes` trae 53 piezas x 2 materiales (metal / pvc) en un
solo glTF, direccionables por nombre de nodo. Cubre lo que al sistema viejo le
faltaba: T real de 3 puertos, tapa, reduccion de calibre, codos y soportes.

| archivo | que es |
|---|---|
| `core_v2/props/pipe/kit/PipeKit.gd` | catalogo: largos, calibres y **puertos medidos** de cada pieza |
| `core_v2/props/pipe/kit/PipeRoute.gd` | nodo `tool`: polilinea -> caneria armada con el kit |
| `tools/verify_pipe_kit.gd` | vuelve a medir el kit y falla si no coincide con el catalogo |
| `tools/check_pipe_route.gd` | recorre la polilinea cada 2 cm y falla si hay tramo sin cano |

Convenciones del kit, **medidas de la malla** (no de la documentacion del asset):

- Recto grueso Ø0.10: de `(0,0,0)` a `(0,L,0)` — corre sobre **+Y**, pivote en la base.
- Recto fino Ø0.06: de `(0,0,0)` a `(L,0,0)` — corre sobre **+X**. El kit es
  inconsistente entre calibres; `PipeRoute._base()` lo normaliza.
- `turn_short`: entra en `(0,0,0)` hacia −Y, sale en `(0.10, 0.098, 0)` hacia +X.
  `turn_long`: 0.20 / 0.198.
- `valve_small_1` tiene **los mismos puertos que un recto de 40 cm**: una valvula
  entra en cualquier tramo sin recalcular el trazado.
- `pipe_uturn` no expone puertos en los extremos de eje; hay que medirlo aparte
  antes de usarlo.

El kit no trae codo de angulo libre. `PipeRoute` usa codo del kit arriba de 60
grados y junta a tope abajo (con 12 mm de solape para que no se abra la costura),
y avisa por `push_warning` en cada vertice que resuelve a tope.

Por que reemplaza a `DomeIntro_PipeNetworkSource.tscn`: esa escena son 1518 lineas
de `Transform` explicitos, ilegibles en un diff e imposibles de editar a mano — por
eso hubo que manipularlas con `fit_pipes_to_criopods.py` y
`generate_pipe_serpentine.py`. Con rutas, los cinco anillos y la serpentina son
unas diez listas de puntos.
