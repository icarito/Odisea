# Handoff — glow no deseado en el interior de los tubos de la válvula (Dome_Intro)

**Estado: MITIGADO Y VERIFICADO (2026-09-03).** Dos causas independientes; la
mitigación final = el dither queda a elección del usuario (Opciones) + el clamp
de los emisores de estado. Ver §0.

---

## 0. DESENLACE FINAL

**Dos fuentes independientes, cada una medida por separado:**

1. **El cone-occlusion dither** (`PropDitherShader`): los agujeros del cono
   dejan ver fondos brillantes (paneles de estado, tubería iluminada) y el
   bloom los convierte en nubes blancas. El usuario lo desactivó desde
   Opciones y el destello desapareció — confirmación directa. El experimento
   alpha-fade (fade continuo por `blend_mix`) fue **construido y descartado**:
   empeoró el defecto (el velo al 70% opaco concentra el brillo del prop
   sobreiluminado; ~4700 px quemados vs ~940 del dither). Los shaders fueron
   restaurados a su estado previo (con los fixes ARM de la sesión GLES2→3).

2. **Los emisores de estado en el umbral del bloom**: TODOS los elementos de
   indicación del domo (sight glass del tank, displays de piso del elevador,
   status lights de válvula, bulb de la lámpara de pared) tienen
   `emission_energy` entre 2.0 y 10.0 — el `glow_hdr_threshold` es 2.0: cada
   uno genera su propio halo blanco (los "destellos múltiples desde otro
   ángulo", el "8" era el display de 7 segmentos del elevador).

**Mitigación final aplicada (el paquete, 2 cambios):**

1. **`IceObjectFreezer.gd` — el overlay de hielo solo cuando la línea de hielo
   HA SUBIDO** (fix de 1 línea en `_sync_activation`): `_room_is_freezing()`
   solo (la temperatura del domo criógeno) activaba el next_pass de hielo
   desde el boot con `ice_height=0`; la banda de transición
   (`freeze_band_height` 3m + jitter ±1.8m) invadía props hasta y≈4.8 — los
   parches emisivos (self_illum 0.6) eran los "destellos" orgánicos sobre
   criopods y tubería. Ahora: `and _ice_has_risen()` (el diseño FD-051).
2. **El clamp de los emisores de estado** (todos estaban en 2.0–10.0, el
   `glow_hdr_threshold` es 2.0 — cada uno su propio halo):
   - `CoolantTank.tscn`: sight glass `2.2 → 1.4`.
   - `ElevatorFloorSelector.tscn`: display de piso `3.0/2.0 → 1.2`.
   - `PipeValve.gd` (status light): `1.0 → 0.5`.
   - `SciFiRecessedWallLightV2.tscn`: bulb `10.0 → 2.5`, indicador verde
     `2.0 → 1.2`.

El dither queda **activo por defecto** con su toggle de Opciones operativo.
Verificación (capturas antes/después, mismos ángulos): vista replay
`blown 943 → 0`; vista alta (la del usuario) `blown 4686 → 0` — la tubería
teal recupera su color (antes blanqueada por el bloom). Los elementos siguen
legibles (cian/verde saturado) sin cruzar el umbral del bloom.
`test_determinism_v2` PASSED.

**Restaurado a su estado previo** (intervenciones descartadas): el PBR del
ValveBody (`metallic 1.0`, normal map ON), `glow_hdr_threshold 2.0`,
`FrostMistCrown` visible, `AO_LIGHT_AFFECT 0.0` en los shaders.

Notas de diagnóstico que sí valen para el futuro:

- `PropDitherManager` re-copia los params del material embebido del mesh del
  kit en cada carga: los fixes PBR al ValveBody deben hacerse en el source
  (`PipeValveKit_body.mesh`), no en la instancia (§4.2).
- El ReflectionProbe (`cull_mask 1047616`) SÍ incluye la capa 7: los bulb
  glows aditivos brillantes se capturan en su cubemap y los props metálicos
  los espejan.
- Las capturas same-frame tras un toggle son INCONFIABLES (stale): ocultar y
  capturar deben ir en comandos separados. Varios falsos negativos de esta
  sesión salieron de ahí.

**Pendiente (propuesto al usuario):** decidir el reemplazo del cone-occlusion
para GLES3 — ver §10.

Base: `cd2accf3`. Árbol de trabajo con 34 archivos modificados (detalle abajo).
Plataforma: Godot 3.6.2, GLES3 (migrado desde GLES2 en esta sesión).

---

## 1. El síntoma

En `Dome_Intro`, los tubos del prop de válvula (`PipeValveKit`) muestran un brillo
no deseado en su **superficie interna**. Reportado por el usuario, textualmente:

- "solo las caras *interiores* de los tubos de la válvula son los que brillan así"
- "en la foto se ve el brillo desde arriba y desde abajo"
- "sigue ocurriendo cuando miro desde arriba nada más, la escena inicial en Dome_Intro"
- "los PipeValveKit siguen **destellando** indeseablemente desde arriba y abajo"

Cuatro rasgos que cualquier hipótesis tiene que explicar a la vez:

1. Solo la cara **interna** del tubo, no la externa.
2. Aparece **mirando desde arriba** (y desde abajo), no de frente.
3. **Destella / titila** — es temporal, no estático.
4. Se localiza en la **escena inicial de Dome_Intro** (spawn en `(-1, 4.7, 8)`).

⚠️ **Nada de esto fue verificado visualmente por el agente anterior.** Ver §6.

---

## 2. Descartado con medición

Todas las cifras salen de capturas headless con máscaras por diferencia (nodo
visible menos oculto), que aíslan los píxeles de un prop concreto.

### 2.1 No es el material del tubo

Máscara limpia del `ValveBody` (240.347 px), rueda e indicador ocultos:

| estado | mean | ≥160 |
|---|---|---|
| baseline | 93.0 | 15.39% |
| **albedo = NEGRO** | **88.6** | 11.32% |
| metallic=0, roughness=1 | 91.2 | 13.69% |
| emisión off | 120.3 (otra máscara) | 28.02% |
| glow off | 35.9 | 2.05% |

**Una superficie con albedo cero no puede brillar.** Que se mantenga en 88.6
prueba que lo que se ve en esos píxeles **no es el shading del tubo**. Cualquier
propuesta que toque `albedo`, `metallic`, `roughness` o `emission` del material
del tubo ya está refutada.

### 2.2 No es el cull mode

Se puso `CULL_BACK` en los 22 `.material` horneados de los risers y en los dos
`.mesh` del kit. **No eliminó el defecto**, y además era una regresión: los tubos
son **cáscaras abiertas**, no sólidos. Medido cambiando el shader a la variante
de doble cara y diferenciando el cuadro:

```
válvula de frente     +38.345 px  (7.4% del cuadro)
válvula de canto      +50.784 px  (9.8%)
válvula desde arriba  +22.826 px  (4.4%)
riser L1              +35.290 px  (6.8%)
```

Esos píxeles son interior visible por los extremos abiertos; con `CULL_BACK`
pasarían a mostrar el fondo. **Ya revertido** a `CULL_DISABLED`, que es la
autoría correcta.

### 2.3 No es el winding

Barrido de las 202 superficies de `.mesh` bajo `core_v2`, comparando la normal
geométrica del winding contra la normal de vértice:

```
195 superficies en una convención  ← incluye todas las tuberías
  7 superficies en la otra
```

Godot 3 usa cara frontal **CW**, así que la mayoría es la correcta y las
tuberías están bien. Los 7 "outliers" son superficies de **2 a 10 triángulos**
(6 y 30 vértices) de la escalera caracol, con material `cull_disabled`, donde el
winding contra la normal no significa nada. Verificado además con luz dinámica:

```
ESCALERA Sector_01   OFF=42.8  ON=110.8  delta=+68.0
CONTROL piso torre   OFF=41.2  ON=116.2  delta=+75.1
```

La escalera recibe luz normalmente. **No tocar el winding.**

### 2.4 No es el ReflectionProbe

`intensity` 0.6 → 0.0 mueve el 12.29% de píxeles ≥160 a 6.89%, dentro de la banda
de ruido (±6.7) de la animación del coolant. Se le puso `interior_enable = true`
porque estaba mal configurado (GLES2 no soporta ReflectionProbe, así que el nodo
nunca había corrido), pero **no es la causa**.

### 2.5 No es el glow del environment (aunque lo domina)

`glow_enabled = false` colapsa la región (mean 98.5 → 40.7, ≥160 de 12.29% a
0.39%) y `glow_levels/7` sola vale un −27% en la cavidad. Pero eso es cierto de
**cualquier** región brillante: el glow es una pasada de composición global, no
explica un artefacto localizado en el interior de un tubo. Se persiguió esta pista
y fue un error.

---

## 3. Pistas vivas, no confirmadas

Tres arreglos entraron al árbol **sin confirmación visual** de que resuelvan el
síntoma. El usuario reporta que persiste, pero no está claro si relanzó después
del tercero.

### 3.1 `interact_highlight.shader` — overlay aditivo de doble cara

`InteractableBaseV2._apply_highlight()` no tinta el prop: **clona su malla** en un
hijo `_highlight_overlay` con material propio. Estaba en:

```glsl
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;
```

`cull_disabled` hace que el clon dibuje la superficie interna; aditivo, sin
sombrear y sin escribir profundidad. Medido con A/B intercambiando el shader en
vivo sobre el mismo overlay:

```
cull_back      energía = 3.920.013   px = 118.342
cull_disabled  energía = 5.028.199   px = 174.596   (+28% energía, +48% px)
```

**Cambiado a `cull_back`.** Pendiente: el shader **también pulsa**
(`sin(TIME * 3.0)`, período ~2.1 s) y no es un contorno sino un **baño plano**
(`ALBEDO` constante) sobre toda la superficie. El pulso no se tocó, y el usuario
describe "destello".

### 3.2 `proximity_glow.shader` — rim + scanline animada

```glsl
render_mode unshaded, cull_back, blend_add;
float rim  = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
float scan = (sin(UV.y * scan_density + TIME * scan_speed) + 1.0) * 0.5;
float visibility = max(rim, base_alpha) * (1.0 + scan * scan_intensity);
```

`rim` es máximo en ángulo rasante — en un caño horizontal, el borde de **arriba y
abajo**. `scan` lo hace pulsar. `base_alpha = 0.3` es un **piso**: lava toda la
superficie, no solo el borde. El overlay es un clon escalado a 1.01.
**No modificado.** Encaja bien con la descripción "destellando desde arriba y
abajo" y merece revisarse.

### 3.3 `prop_dither_occlusion_double_sided.gdshader` — exención de piso

El sistema de dither descarta con Bayer los fragmentos **entre cámara y jugador**
— exactamente la condición "mirando desde arriba". En la variante de doble cara:

```glsl
NORMAL = FRONT_FACING ? NORMAL : -NORMAL;      // línea 114
...
bool floor_under = world_normal.y > 0.5 && camera_pos.y > world_pos.y && near_h && ...
if (!floor_under && !ceiling_above) { ...discard... }
```

La protección de piso (para no agujerear el suelo bajo los pies) usa la normal
**ya invertida**, así que la pared interna de un caño hueco reporta
`world_normal.y > 0.5` y **queda exenta del dither** mientras el exterior sí se
acribilla → se ve el interior por los agujeros.

**Se agregó el guard `FRONT_FACING &&`** a ambas condiciones. Medido en el spawn
inicial con la cámara arriba:

```
pitch 0.5   53.154 px cambian (10.2% del cuadro)   129.1 → 119.8
pitch 0.9   94.489 px cambian (18.2% del cuadro)   101.6 →  88.3
```

El efecto crece cuanto más desde arriba, que coincide con el reporte. **Este
arreglo es el más reciente; puede que el usuario no lo haya probado todavía.**

### 3.4 Sin explorar: el shader de coolant

`core_v2/props/pipe/pipe_coolant.shader`, aplicado en runtime por
`PipeCoolantRun.gd` a los tramos activos. **Anima** (`flow_phase`, bandas de
voronoi) y aparece como ruido de fondo en todas las mediciones (desvío 3.67 sin
ningún overlay). Además, la línea ~118:

```glsl
if (hide_caps && abs(dot(world_normal, axis)) > 0.8) { ... }
```

descarta las tapas del tubo — que es **precisamente lo que permite ver el
interior del caño**. Nadie miró esto todavía. Es el sospechoso mejor posicionado
que queda.

---

## 4. Arquitectura que hay que conocer antes de tocar nada

Esto explica por qué muchos cambios "no se veían" y costó horas descubrirlo.

### 4.1 Tres capas sobrescriben el material en runtime

1. **`PropDitherManager` (autoload)** reescribe el material de **todo prop de
   capa 7** como `ShaderMaterial` sobre `prop_dither_occlusion*.gdshader`.
   Verificado en vivo: `ValveBody` y los risers renderizan con ese shader, no con
   su `.material`.
   Copia: `albedo`, `metallic`, `roughness`, `specular`, mapa MRAO, normal,
   emisión, y elige variante según el cull del material fuente.
   **No copia `rim`** — el shader ni lo tiene.
   → *Editar un `.material` o `.mesh` solo llega a pantalla por esos parámetros.*
2. **`PipeCoolantRun.gd`** vuelve a sobrescribir las superficies de tubería
   activas con un `ShaderMaterial` de coolant.
3. **`InteractableBaseV2`** agrega hijos `_highlight_overlay` y
   `_proximity_overlay`: `MeshInstance` que **clonan la malla del prop** con
   material aditivo propio.

### 4.2 Cadena de horneado de las tuberías

```
core_v2/props/pipe/kit/PipeValveKit_body.mesh        (fuente, material embebido)
        ↓  tools/bake_pipe_network.gd copia el material tal cual
core_v2/levels/interiors/DomeIntro_*Pipes_mat_00.material   (22 archivos compartidos)
        ↓
DomeIntro_*Pipes_baked.mesh  →  instanciados en Dome_Intro
```

Un cambio en el `.material` horneado **no sobrevive un rehorneado** si no se
arregla también el `.mesh` del kit.

### 4.3 Geometría del kit

`PipeValveKit_body.mesh`: 1832 vértices, 1 superficie, indexada, `CULL_DISABLED`.
**228 vértices (12%) tienen la normal hacia adentro** → hay una pared interna
modelada. El volante igual: 231 de 2032 (11%). Los extremos están abiertos.

---

## 5. Bug real encontrado y arreglado (independiente del síntoma)

`prop_dither_occlusion.gdshader` asumía orden **MRAO** (R=metallic, G=roughness,
B=AO). Las texturas del proyecto son **ARM** de PolyHaven (R=AO, G=roughness,
B=metallic), y `PipeMetal.tres` **ya declaraba** los canales correctos
(`metallic_texture_channel = 2`, `roughness_texture_channel = 1`), que el shader
ignoraba:

```glsl
METALLIC  = mrao.r * metallic;   // r = AO
ROUGHNESS = mrao.g;              // descarta el multiplicador del material
AO        = mrao.b;              // b = el mapa de metal
```

Medido sobre `modular_pipes_metal_arm_1k.jpg`: AO=229, rough=142, metal=199. El
`METALLIC` recibía 0.90 (el AO) en vez de 0.78, y `ROUGHNESS` descartaba el
multiplicador — por eso "subir el roughness" nunca hizo nada en esos tubos.

Corregido con máscaras de canal (`dot(mrao, mask)`, portable en GLSL ES) que
`PropDitherManager` deriva de los canales que el material declara. **Vale la pena
conservarlo aunque no sea la causa del síntoma.**

---

## 6. Por qué el diagnóstico anterior falló

**El agente anterior nunca vio el defecto.** Las capturas del usuario venían a
2248x1450 y 2560x1341; una imagen con cualquier lado > 2000 px hace que la API
rechace **toda** lectura de imagen posterior en la sesión, incluidas las propias
de 700 px. A partir de ahí todo se dedujo con histogramas, máscaras y raycasts.

Cuatro conclusiones se presentaron con más seguridad de la que tenían: el cull,
el winding, el glow y el highlight. Ninguna resolvió el problema.

**Primera recomendación para el próximo agente: mirar.** Una sola captura del
spawn inicial con la cámara arriba, a menos de 2000 px, resuelve en un vistazo lo
que acá costó horas de inferencia.

---

## 7. Herramientas de diagnóstico que sí funcionan

- **Godot headless renderiza y captura.** `godot3-bin --path . --no-window
  --audio-driver Dummy` + `screenshot` de ANNA da imagen real (mean 42, stddev
  48; no es negro). **Esto contradice la skill `run-odisea`**, que dice que
  headless no captura. Permite iterar sin ventana ni audio.
- **Cámara libre:** `get_tree().current_scene.add_child(Camera.new())`, renombrar,
  `set_translation` + `look_at` + `make_current()`.
- **Máscara por diferencia:** captura con el nodo visible y oculto, los píxeles
  que cambian son los del prop. Indispensable — un recorte fijo mide el fondo.
- **Serie temporal** sobre esa máscara para cuantificar destellos.
- **Raycast por píxel** para nombrar el nodo:
  `direct_space_state.intersect_ray(cam.project_ray_origin(v), ... + cam.project_ray_normal(v)*30)`.
- **A/B de shaders en vivo:** escribir una variante a `res://`, y
  `mat.set_shader(ResourceLoader.load("res://variante.gdshader"))`. El único modo
  de comparar `render_mode`, que es de compilación.

### Trampas encontradas

- `/eval` tiene un máximo de **512 caracteres**.
- `execute_script` multilínea exige `ODISEA_TELEMETRY_ALLOW_SCRIPT_BLOCKS=1` y
  **prohíbe `while`, `for`, `func`, `load(`** (pero `ResourceLoader.load(` pasa).
- El peer limita a **10 comandos/s**; con más da 429 o 504.
- Los nodos de escalera/andamio tienen **rotación en `global_transform`**: el
  AABB local engaña. `Sector_01` tiene AABB local en `(10.22, 5.20, 23.31)` y
  centro real en `(-3.84, 5.20, -25.16)`.
- La **resolución de la captura puede diferir de `get_viewport().size`** (1025 vs
  960 de ancho). Escalar antes de desproyectar.
- El streamer re-oculta sectores por distancia: `set_visible(true)` desde `/eval`
  se revierte solo si el jugador está lejos.
- `queue_free()` sobre la cámara actual **cuelga el juego**.

### Reproducción

```bash
export ODISEA_FORCE_MUTE_AUDIO=1
setsid nohup godot3-bin --path . --no-window --audio-driver Dummy &
# goto_scene a Dome_Intro, y:
#   jugador (-1.00, 4.70, 8.00)   ← spawn inicial
#   pitch del rig a 0.9 → cámara (-1.34, 9.27, 7.24), encima mirando abajo
```

---

## 8. Estado del árbol

34 archivos modificados sobre `cd2accf3`, +116 −36 en las fuentes.

### Conservar — medido y aprobado por el usuario

| Archivo | Cambio |
|---|---|
| `shaders/prop_dither_occlusion*.gdshader` | canales ARM/MRAO (§5) |
| `core_v2/autoloads/PropDitherManager.gd` | pasa las máscaras de canal |
| `Environment_DomeIntro.tres` +3 envs | `glow_blend_mode` Additive→Screen: evitaba el recorte a blanco de las lámparas (quemados 0.41% → 0.001%) |
| `IndustrialWallLamp{Low,LOD}.mesh` | vidrio unshaded `0.72,0.84,1` → `0.45,0.53,0.63` |
| `Dome_Base.tscn`, `LightPathV2.gd` | `proximity_fade` en el billboard del bulbo (arregla clipping contra la pared) |
| `LightPathV2.gd` | `light_specular` 1.0 → 0.35 en las luces del pool |
| `SteelGratePlatform.gd`, 11 `.material`, `StainlessSteel.tres` | hacks de GLES2 (emisión falsa en barandas, `metallic_specular` 0.9, `rim`) |
| `tools/relight_gles3_materials.gd` | migración idempotente que aplica lo anterior |

### Especulativo — nació de hipótesis caídas

| Archivo | Cambio | Nota |
|---|---|---|
| `core_v2/visual/interact_highlight.shader` | `cull_disabled` → `cull_back` | correcto por su cuenta, no resolvió el síntoma |
| `prop_dither_occlusion_double_sided.gdshader` | guard `FRONT_FACING` | idem; el usuario puede no haberlo probado |
| `Environment_DomeIntro.tres` | `glow_bloom` 0.40 → **0.18**, `glow_levels/7` quitado | **REVERTIDO tras el handoff**: `glow_bloom` 0.4 y `glow_levels/7 = true` restaurados (y `glow_intensity` añadido en la misma pasada, eliminado). Del archivo queda solo `glow_blend_mode` Screen, que va en la lista de conservar. |
| `Dome_Intro.tscn` | `ReflectionProbe.interior_enable = true` | correcto (era interior sin declarar), no es la causa |
| `PipeValve_*_baked.mesh`, `airlock_baked/*.mesh` | metallic ≥0.8 → 0.75, roughness ≥0.45 | solo metal sin textura |

---

## 9. Plan sugerido

1. **Ver el defecto.** Captura del spawn inicial con la cámara arriba, < 2000 px.
   No proponer causas antes de esto.
2. Con el toolkit de §7, aislar la superficie: máscara por diferencia sobre
   `ValveBody`, serie temporal para caracterizar el destello (¿qué período?
   2.1 s → highlight; 1.6 s → proximity; irregular → dither o coolant), y
   raycast para nombrar el nodo.
3. Probar §3.4 (`pipe_coolant.shader` / `PipeCoolantRun`), que es lo único no
   explorado y lo único que anima de forma nativa en esa geometría.
4. Antes de tocar un `.material`, confirmar que **llega a pantalla**: las tres
   capas de §4.1 lo pueden estar sobrescribiendo.
5. ~~Decidir sobre `glow_bloom` / `glow_levels/7` (§8)~~ — resuelto: revertidos
   tras el handoff. No quedan cambios de dirección de arte especulativos en el
   árbol.

---

## 10. Propuesta de diseño — reemplazo del cone-occlusion (backlog, GLES3)

El destello quedó resuelto con el dither desactivado por Opciones. Para cuando
se retome el reemplazo del sistema (backlog del usuario), las opciones medidas
en esta sesión:

| Opción | Resultado | Nota |
|---|---|---|
| Alpha-fade (blend_mix + depth_draw_opaque) | **Descartado** | Empeora el destello: el velo al 70% opaco concentra el brillo del prop sobreiluminado; el bloom no lineal lo hace más sólido. Construido y revertido. |
| Dither con `transparency_max` limitado (~0.6) | Sin probar | Los agujeros revelan máx 60% del fondo → menos destello; el aliasing/titileo persiste. Cambio de 1 línea. |
| Ocultado por-prop (CPU) | Propuesta recomendada | Raycast/bbox por prop en `PropDitherManager` (ya rastrea el cono): prop que bloquea al jugador → `visible=false` (el estándar TPS, sin transparencias ni shader). Requiere materiales por instancia si se quiere fade, o aceptar el pop oculto por el movimiento continuo de cámara. |
| Muestrear `depth_texture` para desvanecer solo sobre fondo lejano | Complejo | GLES3 lo expone, pero añade un sampler y lógica por-píxel al shader más caliente del nivel. |

Restricciones conocidas que cualquier reemplazo debe respetar: MultiMesh
batcheados (criopods, bulb glows) comparten un solo material — un fade por
instancia necesita el camino del shader o re-batching; el next_pass del hielo
(`IceObjectFreezer`) se registra en el mismo cone-sync y duplica draw calls de
lo que envuelva.
