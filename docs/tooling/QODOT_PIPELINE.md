# Pipeline Qodot / TrenchBroom

Como agregar props, texturas y cableado para que TrenchBroom y el juego digan lo
mismo. El estado actual y los numeros estan en
[QODOT_INTEGRATION_AUDIT.md](QODOT_INTEGRATION_AUDIT.md).

## Regla numero uno: la fuente de verdad son los `.tres`

```
core_v2/qodot_fgd/props/*.tres          <- una point/solid class por prop
addons/.../fgd/qodot_fgd.tres           <- la lista que las junta
        |
        |  godot3-bin --no-window -s tools/qodot_export_fgd.gd
        v
Qodot.fgd                               <- GENERADO. No editarlo a mano.
        |
        |  scripts/link_trenchbroom_fgd.sh
        v
~/.TrenchBroom/games/Odisea/Qodot.fgd
```

El boton `export_file` de `QodotFGDFile` solo corre con el editor de Godot abierto
(`Engine.is_editor_hint()`), asi que en consola y en CI no sirve: por eso existe
`tools/qodot_export_fgd.gd`. Se dejo `export_file = false` a proposito — es un
pseudo-boton, no una configuracion.

Cualquier edicion a mano de `Qodot.fgd` se pierde en la siguiente regeneracion.
`tools/qodot_validate.gd` falla si el archivo en disco no coincide con los `.tres`.

## Herramientas

| comando | que hace |
|---|---|
| `godot3-bin --no-window -s tools/qodot_audit_props.gd` | mide el AABB real y los `export` de todos los props -> JSON |
| `python3 tools/qodot_sync_point_class_sizes.py [--dry-run]` | corrige `meta_properties.size` con esa medicion |
| `godot3-bin --no-window -s tools/qodot_export_fgd.gd` | regenera `Qodot.fgd` |
| `QODOT_FGD_CHECK=1 godot3-bin --no-window -s tools/qodot_export_fgd.gd` | falla si `Qodot.fgd` quedo viejo (para CI) |
| `godot3-bin --no-window -s tools/qodot_validate.gd` | FGD + texturas + `qodot_map.gd` |
| `godot3-bin --no-window -s tools/qodot_wiring_smoke.gd` | construye un mapa y verifica el cableado `targetname` -> `target` |
| `bash scripts/link_trenchbroom_fgd.sh` | enlaza el `.fgd` a `~/.TrenchBroom/games/Odisea` |
| `godot3-bin --no-window -s tools/qodot_export_trenchbroom_config.gd` | instala `GameConfig.cfg` + `Icon.png` + `initial_valve.map` en `~/.TrenchBroom/games/Odisea` |
| `godot3-bin --no-window -s tools/qodot_build_smoke.gd` | construye todos los `.map` y falla si alguno no genera geometria |

## Actualizar TrenchBroom

Son **dos** cosas distintas y se actualizan por caminos distintos.

### El FGD (las entidades)

`~/.TrenchBroom/games/Odisea/Qodot.fgd` es un **symlink al repo**, asi que se
actualiza solo cada vez que se corre `tools/qodot_export_fgd.gd`. Solo hay que
enlazarlo una vez:

```bash
bash scripts/link_trenchbroom_fgd.sh
```

En TrenchBroom, para que lo relea: **File > Reload Entity Definitions**. No hace falta
cerrar el editor.

### El GameConfig.cfg (tags, formatos, carpeta de texturas)

Esto NO se actualiza solo. Cambia cuando se toca
`addons/qodot/game_definitions/trenchbroom/trenchbroom_game_config.tres` (tags de
brush/cara, nombre del juego, icono, flags de superficie).

```bash
godot3-bin --no-window -s tools/qodot_export_trenchbroom_config.gd
```

TrenchBroom lee el `.cfg` **al arrancar**: hay que **cerrarlo y reabrirlo**, Reload
Entity Definitions no alcanza.

El exportador no copia el `.fgd` a proposito —lo dejaria como copia muerta en vez del
symlink—. Con `QODOT_TB_CHECK=1` no escribe nada y falla si el instalado quedo viejo.
El destino sale del `.tres`; se puede pisar con `TRENCHBROOM_ODISEA_GAME_DIR` (la
misma variable que usa `link_trenchbroom_fgd.sh`).

### Las texturas

TrenchBroom solo lista **archivos de imagen**. Los `.tres` le son invisibles: el
override de material lo aplica Qodot al construir el mapa dentro de Godot, y todo lo
que vive en `materials/` es la libreria de los props, que se carga por ruta desde
GDScript. En el browser de TrenchBroom nunca van a aparecer.

Las colecciones se habilitan **por mapa**, no globalmente: quedan en la property
`_tb_textures` del worldspawn. Una carpeta nueva no aparece sola.

- **En un mapa existente:** boton **Settings** en la barra de titulo del material
  browser. Ahi estan las listas *Available* / *Enabled* con `+` y `-`, y el **icono de
  flecha circular** que recarga todas las colecciones.
- **En un mapa nuevo:** ya vienen todas habilitadas, porque `File > New` copia
  `initial_valve.map` (ver abajo).

### La plantilla de mapa nuevo

`maps/templates/initial_valve.map` es lo que TrenchBroom copia en `File > New`
(`GameConfig.cfg` lo declara como `initialmap` del formato Valve). Su unico trabajo es
que un mapa nuevo arranque con las colecciones habilitadas y una sala de referencia.
Se instala junto con la config:

```bash
godot3-bin --no-window -s tools/qodot_export_trenchbroom_config.gd
```

Si se agrega una carpeta de texturas nueva, hay que sumarla al `_tb_textures` de esa
plantilla, si no los mapas nuevos siguen sin verla.


## Agregar un prop nuevo

1. **El prop existe** como `core_v2/props/<grupo>/MiProp.tscn`, con su script raiz.
2. **Crear** `core_v2/qodot_fgd/props/MiProp_point_class.tres` copiando uno parecido
   (por ejemplo `PipeValve_point_class.tres`). Campos que importan:

   ```
   classname = "pipe_mi_prop"
   ```

   El `classname` va en minusculas y la **primera palabra antes del `_` crea el grupo
   en TrenchBroom**. Prefijos en uso:

   | prefijo | para que |
   |---|---|
   | `prop_` | props del mundo con cuerpo |
   | `light_` | luminarias |
   | `pipe_` | red de canerias y refrigerante |
   | `holo_` | terminales y proyecciones |
   | `sys_` | anclas invisibles de logica de sistemas |

   ```
   base_classes = [ ExtResource( <Targetname> ), ExtResource( <Target> ) ]
   ```

   Siempre las dos, salvo que el script del prop exporte una variable llamada
   `target` o `targetname` (ver el aviso de choque de nombres mas abajo).

   ```
   class_properties = { ... }              # los export REALES con su default real
   class_property_descriptions = { ... }   # ayuda legible en TrenchBroom
   scene = "MiProp"
   scene_file = ExtResource( <el .tscn> )
   ```

   No hace falta listar todos los `export`: solo los que un level designer va a tocar.
   `tools/qodot_audit_props.gd` imprime la lista completa con sus defaults reales.

3. **Referenciarla** desde `addons/qodot/game_definitions/fgd/qodot_fgd.tres`: un
   `ext_resource` nuevo con id libre, y ese `ExtResource( n )` al final de
   `entity_definitions`.
4. **Medir y regenerar**:

   ```bash
   QODOT_AUDIT_OUT=/tmp/qodot_props_audit.json \
     godot3-bin --no-window -s tools/qodot_audit_props.gd
   python3 tools/qodot_sync_point_class_sizes.py --audit /tmp/qodot_props_audit.json
   godot3-bin --no-window -s tools/qodot_export_fgd.gd
   godot3-bin --no-window -s tools/qodot_validate.gd
   ```

### Variantes: prop sin `.tscn`

Un script que extiende `Spatial` y no tiene escena (una ancla de logica: un sector de
presion, una fuga) va con `script_class` en vez de `scene_file`, y `size` a mano
—`AABB( -8, -8, -8, 8, 8, 8 )`, un cubo de 1 m, alcanza para agarrarlo—. Qodot le crea
un `QodotEntity` y le pega el script. Ver `PressureSection_point_class.tres`.

Un script que necesita que la geometria del brush sea **hija suya** va como
`SolidClass` con `node_class = "StaticBody"` y `script_class`. Ver
`PipeCoolantRun_solid_class.tres`.

### El `size` no se escribe a mano

Sale de `tools/qodot_sync_point_class_sizes.py`. Tres trampas que ya estan resueltas
ahi y conviene no reintroducir:

- `meta_properties["size"]` es un `AABB` usado como **par min/max**, no como
  posicion+extension: `position` = minimo, `size` = **maximo**.
- Los ejes se permutan: `quake.x = godot.z`, `quake.y = godot.x`, `quake.z = godot.y`.
- La escala es 16 (1 unidad de TrenchBroom = 6.25 cm).

## Agregar una textura de mundo

1. `textures/<grupo>/<nombre>.png`. **Sin espacios** en el archivo ni en la carpeta:
   Qodot no los lee.
2. Opcional, un override de material con **el mismo nombre**:
   `textures/<grupo>/<nombre>.tres` (`SpatialMaterial` o `ShaderMaterial`).
3. Opcional, variantes Auto-PBR en una subcarpeta con el nombre de la textura:

   ```
   textures/foliage/vines.png
   textures/foliage/vines/vines_normal.png
   textures/foliage/vines/vines_roughness.png
   ```

   Sufijos reconocidos: `_normal`, `_metallic`, `_roughness`, `_ao`, `_emission`,
   `_depth`.

Prioridad de Qodot: **override `.tres` -> textura plana -> Auto-PBR**.

Para un `ShaderMaterial` con el pack PSX, copiar
`textures/_templates/psx_lit_brush.tres` (o la variante `_transparent`), renombrarlo
igual que el `.png` y apuntar `albedoTex`. Ojo: si la textura ya la usan mapas
existentes, el override les cambia el aspecto a todos.

Despues de agregar archivos hay que importarlos. `--quit` no alcanza para un asset
recien agregado; usar:

```bash
CLEAN_CACHE=0 IMPORT_MODE=full bash scripts/godot_import_smoke.sh
```

### Texturas especiales

| textura | efecto |
|---|---|
| `special/clip` | brush solido pero invisible |
| `special/skip` | la cara no se renderiza |
| `special/trigger` | la que aplica el tag Trigger de TrenchBroom a un brush `trigger*` |

Son los valores por defecto de `brush_clip_texture` / `face_skip_texture` en cada
`QodotMap`, y estan etiquetadas en la config de TrenchBroom (Clip / Skip).

`materials/` **no** es parte de esto: es la libreria de materiales de los props, que
se cargan por ruta desde GDScript. Qodot solo mira `textures/`.

## Cablear un prop a un circuito

Hay dos caminos y no compiten: uno arma la topologia dentro del `.map`, el otro la
guarda en un recurso.

### A) Cableado directo en TrenchBroom (`targetname` -> `target`)

En el emisor se pone `target` con el `targetname` del receptor.

```
{ "classname" "prop_pedestal_button"   "targetname" "boton_purga"
  "target" "turbina_norte"             "origin" "-64 0 0" }

{ "classname" "prop_ventilation_turbine"
  "targetname" "turbina_norte"         "origin" "64 0 32" }
```

Al construir el mapa, Qodot conecta el emisor al receptor con la primera de estas que
encaje:

1. `trigger` -> `use()`
2. `activated` -> `set_active(true)` y `deactivated` -> `set_active(false)`

El caso 2 es el contrato de `InteractableBaseV2`, o sea casi todos los props del Core.
`tools/qodot_audit_props.gd` marca en la columna `activated` cuales lo cumplen.

Para logica intermedia (retardos, renombrar señales) estan las point classes `signal` y
`receiver` de Qodot: emisor -> `signal` -> `receiver` -> receptor.

**Dejar `target` vacio es correcto**: significa "sin cablear". Ya no conecta con nada.

**Choque de nombres:** si el script del prop exporta una variable que se llama igual
que una property del FGD, `apply_properties` se la pisa. Es lo que pasa con
`sys_purge_dial`, cuyo `target: float` es el valor objetivo del dial: por eso hereda
solo `Targetname`. Antes de darle `base_classes` a una point class nueva, revisar que
su script no exporte `target`, `targetname`, `angle`, `angles`, `mangle`, `origin`,
`classname`, `scale` ni `rotation`.

### B) `LogicCircuitManager` + `CircuitGraphResource`

Para grafos con compuertas (AND/OR/XOR/DELAY) y cables visibles. El manager engancha
`activated`/`deactivated` de cada nodo `PROP`, que es la **misma señal** que usa el
camino A: un prop cableado de una forma u otra habla el mismo idioma.

**Limitacion conocida.** `CircuitGraphResource` resuelve cada nodo con
`get_node_or_null(scene_path)`, pero Qodot nombra las entidades
`entity_<indice>_<classname>`, no por `targetname`, y el indice depende del orden en el
`.map`. Un grafo apuntado contra esos nombres se rompe en silencio si se reordenan las
entidades. Mientras eso no se resuelva (ver bug 3 del audit), para props plantados
desde TrenchBroom conviene el camino A.

## Antes de commitear

```bash
godot3-bin --no-window -s tools/qodot_validate.gd
godot3-bin --no-window -s tools/qodot_wiring_smoke.gd
godot3-bin --no-window -s tools/qodot_build_smoke.gd
```

### El brush que compila y no existe

Si los 3 puntos de un plano estan en el winding contrario, el brush compila sin una
sola queja pero su volumen queda **vacio**: Qodot dice "Build complete", el mapa carga,
y no se ve nada. Asi estuvo `maps/interior_a.map` desde que se agrego.

Editando en TrenchBroom no pasa —el editor escribe el winding bien—, pero si pasa al
generar `.map` a mano o con un script. `tools/qodot_build_smoke.gd` es el unico chequeo
que lo detecta: construye cada mapa y compara brushes contra `MeshInstance`.

Y si se toco `trenchbroom_game_config.tres`, reinstalar la config:

```bash
godot3-bin --no-window -s tools/qodot_export_trenchbroom_config.gd
```

`qodot_validate` chequea que `qodot_fgd.tres` cargue, que no haya `classname`
duplicados ni vacios ni huecos `null`, que `Qodot.fgd` este al dia, que existan
`special/clip` y `special/skip`, que toda textura pedida por un `.map` tenga archivo, y
que `qodot_map.gd` compile.
