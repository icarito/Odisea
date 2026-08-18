# FD-268 t1 — La fisura se ve: grieta en el caño y chorro de refrigerante

## Objetivo

La fisura del circuito de refrigerante no se ve como una fisura: hoy es una esfera naranja
emisiva, un marcador puesto para que el disparo tenga dónde pegar. El jugador no tiene cómo saber
dónde está la rotura salvo por ese marcador.

Y hay una promesa incumplida: `core_v2/systems/cryo/LeakPatchPoint.gd` abre diciendo
*"Emits visual damage parameter to pipe shader"*, pero `core_v2/props/pipe/pipe_coolant.shader`
**no tiene ningún uniform de daño**. Lo único que pasa hoy es que baja el brillo de la corrida
entera, parejo a lo largo de todo el caño.

Hay que hacer que la avería se vea **en el punto donde está**: una grieta en el caño y un chorro
de refrigerante saliendo de ahí, que se corten cuando el jugador la parchea con gloo.

El diseño está en `docs/features/FD-268_fissure_visual.md`. **Léalo antes de empezar.**

## Contexto del sistema

- **Godot 3.6, GDScript 1.x**. `yield`, no `await`. Todo el código en `core_v2/`.
- **GLES2**: el nodo `Particles` **no se renderiza** (se ve solo el mesh). Use `CPUParticles`.
  Para animación de flipbook, `anim_offset_random`.
- **Determinismo — contrato duro, `AGENTS.md` §5.3.** Nada de `randf()` / `rand_range()` /
  `randomize()` en lógica de estado. Lógica en `_physics_process`. Nodo con estado ⇒ grupo
  `replay_sync` + `get_snapshot()` / `restore_snapshot(data)`.
- Español neutro en comentarios. Sin voseo argentino. Los comentarios explican **por qué**.

### Restricción de shaders en GLES2 — léala, ya costó caro dos veces

En Adreno (Android) el fragment shader corre en `mediump`. Los `hash()` del patrón clásico
`fract(dot(p, vec3(constantes grandes)) * otra constante grande)` **pierden precisión y colapsan
en bloques visibles**. Es un problema ya resuelto dos veces en este repo:

- `core_v2/systems/gas/shaders/gas_flipbook.shader` — dither ordenado (Bayer).
- `core_v2/systems/ice/shaders/transparent_ice_mobile.shader` — la receta que sirve acá.

**Receta hash-free para grietas** (solo `sin` / `dot` / `abs` / `min`, ninguna sufre el colapso):

1. **Crestas angulares:** `abs(sin(dot(p, dir) * freq))` da una cresta en V con esquina dura en
   cada cruce por cero — a diferencia del cruce curvo de un `sin` puro. El `min()` de 2-3 de esas
   crestas en ángulos distintos da una red de líneas que se cruzan.
2. **Domain warping anguloso:** sin warp, esas familias de rectas infinitas teselan el plano en
   una grilla perfectamente regular (se lee "a parquet"). Hay que deformar el dominio con **otro
   par de `abs(sin(...))`, no con un `sin` suave**: el quiebre en la esquina del `abs()` dobla la
   línea en un ángulo, en vez de curvarla.
3. **Cobertura angosta:** enmascarar con un `smoothstep` de rango chico sobre otro campo, para
   cortar las líneas en **segmentos cortos** en vez de tiras continuas infinitas.

La iteración real que llevó a esto: sin warp se veía "a olitas" (curvas suaves) → con warp suave
y líneas sin fragmentar se veía "a parquet" (grilla regular) → warp anguloso + cobertura angosta
finalmente leyó como grietas reales. **No reinvente esto con `hash()`**: se ve bien en escritorio
y se rompe en Android.

### Las piezas que ya existen

- `core_v2/props/pipe/pipe_coolant.shader` — el caño con refrigerante corriendo. Muestrea ruido en
  **coordenadas de mundo** (para que el flujo cruce tramos sin costura) y deriva el eje del tramo
  con `use_local_axis`. Lea sus comentarios: explican por qué cada decisión está donde está.
- `core_v2/props/pipe/PipeCoolantRun.gd` — aplica ese material a los `MeshInstance` de la corrida
  y maneja `flow_dir`, `flow_speed`, `flow_intensity`, `flow_phase`. **Solo lectura**: no lo
  modifique, pero mírelo para entender qué uniforms ya se manejan desde afuera y cómo.
- `core_v2/systems/cryo/CoolantLeak.gd` — `get_leak_intensity() -> float` (0 a 1) y
  `get_state() -> int` sobre `enum State { HEALTHY, WARNING, LEAKING, SEALED }`.
- `core_v2/systems/cryo/LeakPatchPoint.gd` — `is_patched() -> bool`, señales `patch_applied` y
  `patch_expired`, y está en el grupo `gloo_patchable`.
- `core_v2/props/emitters/LeakEmitter.gd` — **NO lo use**: su cabecera dice que es decorativo y no
  determinista (`rand_range`), y prohíbe usarlo para gameplay con consecuencia. La fisura sí es
  gameplay: maneja el drain del tanque y la victoria.
- `core_v2/props/emitters/FrostEmitter.gd` — ese **sí** cumple el contrato de replay. Mírelo como
  referencia de estilo para un emisor determinista.

## Qué implementar

### 1. Uniforms de grieta en `pipe_coolant.shader`

- Centro de la grieta, radio e intensidad. El centro conviene en **espacio local del tramo** para
  que no se despegue si el tramo se mueve; justifique en un comentario la elección que haga.
- Fuera del radio, el caño tiene que verse **exactamente igual que hoy**. Un tramo sano no puede
  cambiar de aspecto: es la prueba de que el cambio no rompió nada.
- Con intensidad en 0, idem: idéntico a hoy.
- La grieta se dibuja con la receta hash-free de arriba.
- La zona rota también debería leerse como que **pierde** refrigerante (por ejemplo la emisión
  cayendo hacia el centro de la grieta), no solo como un dibujo encima.

**Ceiling conocido y aceptado:** un solo centro de grieta por material, o sea una fisura por
corrida. Alcanza para el caso de hoy. Márquelo con un comentario `ponytail:` que diga cuál es el
techo y por dónde se ampliaría (varias fisuras ⇒ array de centros o textura de daño).

### 2. `LeakFissureVisual.gd` + `.tscn`

Un componente `extends Spatial` que se cuelga en el punto de la fisura y **solo mira y dibuja**:

- Referencias por `NodePath` a su `CoolantLeak`, a su `LeakPatchPoint` y a la corrida
  (`PipeCoolantRun`) sobre la que está.
- Lee estado **solo por API pública** (`get_leak_intensity()`, `get_state()`, `is_patched()`).
  **No modifique `CoolantLeak.gd` ni `LeakPatchPoint.gd`**: los está tocando otra tarea en
  paralelo y cualquier edición genera conflicto.
- Maneja tres cosas:
  1. **La grieta**: escribe los uniforms de §1 en el material de la corrida, en la posición de la
     fisura, con intensidad siguiendo el estado.
  2. **El chorro**: `CPUParticles` de refrigerante saliendo de la fisura. La cantidad y la
     velocidad siguen `get_leak_intensity()`. En `WARNING` (la fase de condensación, antes de que
     reviente) tiene que verse **distinto y más leve** que en `LEAKING`: el aviso es previo al
     fallo y esa anticipación es intencional en el diseño del sistema.
  3. **Parcheada**: con `is_patched()`, la grieta se tapa y el chorro se corta. Que se lea que hay
     gloo puesto, no que el caño está sano.
- El componente entero tiene que poder apagarse con un `export` (para tramos sin fisura).

### 3. Tests

`core_v2/tests/test_leak_fissure_visual.gd` (GdUnit3, mismo estilo que los de al lado):

1. Sin fuga ⇒ intensidad de grieta 0 y sin partículas activas.
2. Fuga activa ⇒ intensidad de grieta > 0 y partículas emitiendo; `WARNING` da menos que
   `LEAKING`.
3. Parcheado ⇒ grieta tapada y chorro cortado.
4. Determinismo: dos corridas de los mismos ticks dan el mismo estado; snapshot / restore lo
   reproduce.

Correr:

```bash
./runtest.sh -a ./core_v2/tests/test_leak_fissure_visual.gd
./runtest.sh -a ./core_v2/tests/test_coolant_lab.gd
```

Las dos en verde. `test_coolant_lab.gd` **no se toca**: es la red de seguridad de que el shader
sigue llegando al caño y no rompió el laboratorio.

## Archivos permitidos

- `core_v2/props/pipe/pipe_coolant.shader`
- `core_v2/systems/cryo/LeakFissureVisual.gd` (nuevo)
- `core_v2/systems/cryo/LeakFissureVisual.tscn` (nuevo)
- `core_v2/tests/test_leak_fissure_visual.gd` (nuevo)

## Archivos prohibidos

Hay **dos tareas corriendo en paralelo** sobre este mismo sistema. Tocar sus archivos genera
conflicto directo:

- `core_v2/systems/cryo/CoolantLeak.gd`, `core_v2/systems/cryo/LeakPatchPoint.gd`,
  `core_v2/systems/cryo/CoolantFlowAdapter.gd`, `core_v2/props/pipe/CoolantTank.gd`,
  `core_v2/scenes/CoolantLab.gd` — son de FD-266.
- `core_v2/systems/pipe/**`, `core_v2/systems/circuit/**` — son de FD-267.
- `core_v2/props/pipe/PipeCoolantRun.gd` — léalo como referencia, no lo modifique.
- `core_v2/scenes/CoolantLab.tscn` — escena ya verificada; el cableado del componente lo hace
  Sebastián. **Entregue el componente listo para instanciar, no lo instancie usted.**
- `core_v2/tests/test_coolant_lab.gd`, y cualquier escena de nivel (`core_v2/levels/**`).

## Qué NO hacer

- No usar `hash()` ni ruido basado en `fract(dot(...))` en el shader: se rompe en Android.
- No usar el nodo `Particles` (GLES2 no lo renderiza). `CPUParticles`.
- No usar `LeakEmitter` ni copiar su enfoque no determinista.
- No meter aleatoriedad en nada que afecte estado.
- No agregar daño al jugador: el refrigerante **ciega, no daña**.
- No cambiar el aspecto de los tramos sanos.

## Al terminar

**Publique el Pull Request** contra la rama de trabajo indicada, con un resumen de qué uniforms
agregó al shader y cómo se ve cada estado. Si puede, incluya una captura. Si algo del brief
resultó imposible o ambiguo, dígalo en el PR en vez de adivinar.
