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

Cada baker ya lee su fuente vía `DEFAULT_SOURCE_PATH` (overridable con la env
var `ODISEA_BAKE_SOURCE` en el caso de criopods) — no hay duplicación que
consolidar, la separación de FD-250/FD-261 ya cumple la regla de arquitectura.

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
