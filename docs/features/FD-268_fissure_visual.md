# FD-268: La fisura se ve — grieta en el caño y chorro de refrigerante

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-08-17
**Parent:** FD-256 / FD-264 / FD-265 / FD-266

## Problem

La fisura del circuito de refrigerante **no se ve como una fisura**. En el laboratorio de FD-265
es una esfera naranja emisiva: un marcador grey-box puesto para que el gloo tenga dónde pegar, no
una avería que se lea.

Peor, hay una promesa incumplida en el código. `LeakPatchPoint.gd` abre diciendo:

> `# Emits visual damage parameter to pipe shader, controls associated CoolantLeak, ...`

pero `core_v2/props/pipe/pipe_coolant.shader` **no tiene ningún uniform de daño**, y
`_update_pipe_visuals()` lo único que hace es modular `flow_intensity` de la corrida entera. O sea:
el caño baja el brillo parejo en toda su largo, y el punto exacto de la rotura no existe
visualmente. El jugador no tiene cómo saber *dónde* disparar el gloo salvo por el marcador naranja.

`core_v2/props/emitters/LeakEmitter.gd` **no sirve** para esto: está marcado explícitamente como
decorativo y **no determinista** (usa `rand_range`), y su propia cabecera prohíbe usarlo para
gameplay con consecuencia. La fisura *es* gameplay: maneja el drain del tanque y la condición de
victoria.

## Solution

Dos piezas, ambas deterministas:

### 1. Uniforms de grieta en `pipe_coolant.shader`

Un centro de grieta en espacio local del tramo, un radio y una intensidad. Fuera del radio el caño
se ve exactamente como hoy — el cambio no puede alterar los tramos sanos.

La grieta se dibuja con la **receta hash-free** que ya se ganó en
`core_v2/systems/ice/shaders/transparent_ice_mobile.shader`, obligatoria porque el proyecto corre
en GLES2 y en Adreno el fragment shader va en `mediump`: los `hash()` de `fract(dot(...)*constante
grande)` colapsan en bloques visibles en Android.

### 2. Componente visual de la fisura

Un componente que lee el estado (fuga y parche) por API pública y maneja los tres aspectos: la
grieta en el shader, un chorro de refrigerante con `CPUParticles` (GLES2: el nodo `Particles` no
renderiza), y el aspecto distinto de una fisura parcheada con gloo.

No toca la lógica: solo la mira y la dibuja. Así FD-266 puede cambiar la semántica del puzle en
paralelo sin chocar.

## Files to Modify

- `core_v2/props/pipe/pipe_coolant.shader` — uniforms de grieta
- `core_v2/systems/cryo/LeakFissureVisual.gd` (nuevo) — el componente
- `core_v2/systems/cryo/LeakFissureVisual.tscn` (nuevo) — con su `CPUParticles`
- `core_v2/tests/test_leak_fissure_visual.gd` (nuevo)

**Fuera de alcance:** `CoolantLab.tscn` (lo cablea Sebastián), la lógica de fuga/parche (FD-266),
y el barrido de tubos (FD-267).

## Verification

1. Un tramo sano se ve igual que antes del cambio.
2. Con fuga activa aparece la grieta en el punto de la fisura y el chorro sale de ahí.
3. Parche de gloo ⇒ la grieta se tapa y el chorro se corta.
4. Determinismo: mismos ticks ⇒ mismo estado visual; sin `randf()`.
5. Se ve bien en GLES2, sin bloques de precisión.
