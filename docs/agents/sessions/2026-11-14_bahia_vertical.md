# 2026-11-14 — Bahía radial centrífuga (FD-322) — greybox

Sesión: rediseño de la bahía de máquinas a un cilindro rotante de 3 anillos
concéntricos con gravedad centrífuga radial. Rama
`ao/redise-o-de/root-bahia-vertical-radial`.

## Qué se hizo

- **FD-322** (`docs/features/FD-322_bahia_vertical_radial.md`): visión, contrato de
  chunk polar/cilíndrico, anillos, tipos de atajo, interfaz de peligro con el ciclo
  global, **contrato de cambio de modo activado por el jugador**, estado serializable,
  gravedad agnóstica al modo, tabla de reconciliación de FDs cruzados y plan por etapas.
- **Greybox** en `core_v2/levels/bay_vertical/`:
  - `BayVerticalWell.gd` — layout sembrado de 3 niveles, ruta principal, streaming por
    cercanía, atajos, gravedad leída de `GravityWorld`, piso de caída, baliza de cima,
    sala de control, buffers de transición y puente mode-gated.
  - `BayProtocolCycle.gd` — ciclo global calma/aviso/peligro (generaliza el de
    `LabyrinthSection.gd`).
  - `GlooSpan.gd` / `LaserGate.gd` — puertas de gloo y láser (API pública de `MultiToolV2`:
    grupo `gloo_blob` / `laser_hit`).
  - `BayTransitionBuffer.gd` — entrada/salida como espacio buffer físico seamless
    (`TODO(src-54)`, contrato `.operator-shared/specs/seamless-transitions.md`).
  - `BayModeConsole.gd` — consola de cambio de modo (interruptor físico por proximidad,
    sin texto).
  - `BayVertical.tscn` — escena jugable.
  - `preview.oys` — capturas de los 3 anillos + consola.
- **Tests** `core_v2/tests/test_bay_vertical.gd` (11 casos): determinismo del layout,
  conectividad entrada→cima, anillo de la cima, ciclo determinista + snapshot, streaming
  por cercanía, corte de la puerta láser, gloo span con blobs, **toggle de modo
  determinista + serialización** y fuente de gravedad no hardcodeada.

## Verificación

- `./.venv/bin/pytest tests/test_odisea_runner.py -k test_gd__core_v2_tests_test_bay_vertical_gd` → 11/11.
- Capturas headful vía harness OYS (`--no-window`, editor del fork):
  `test_output/ui/bayvertical_0_anillo_exterior.png` … `_3_consola_modo.png` (800×450).

## Decisiones de Sebastián incorporadas

1. **Premisa corregida:** NO pozo con gravedad descendente; **cilindro rotante con
   gravedad centrífuga radial** (piso = cara interior del anillo). "3 niveles" = 3 anillos
   a radios decrecientes; trepar = ir hacia el eje; cima = eje (casi zero-G), visible desde
   todo el anillo; fallar = caer hacia afuera.
2. **Gravedad agnóstica al modo:** siempre leer el vector de `GravityWorld`
   (`STANDARD_1G` propulsión / `SPIN_*` centrífugo / `ZERO_G`), sin asumir "hacia afuera".
3. **Cambio de modo activado por el jugador** desde consolas: puzle que reconfigura rutas,
   no un reloj. Modo + blend serializables (save + replay). Al menos un atajo existe en un
   solo modo.
4. **Transiciones seamless** sin fade; entrada/salida como buffer físico; no `goto_scene`.

## Pendiente / límites (con evidencia)

- El greybox **no monta todavía el cilindro rotante real** (`CylinderRotator` +
  `ScaffoldStreamController(cylinder_mode=true)` + `GravityWorld` spin). Montar la
  proyección canónica por chunk con colisiones estables exige el acarreo acotado por frame
  de `WorldRotator` (lección de clip-through de `OdiseaExterior`) y una sesión dedicada: la
  geometría/orientación de módulos para trepar radialmente no es directa (el frente de un
  `ScaffoldStairs` sube a lo largo de su Z local, y la subida radial depende de la
  proyección, no de una rampa de módulo). El FD deja el contrato y el seam
  (`TODO(src-51/cilindro)`); el greybox actual usa la geometría vertical como placeholder
  jugable de contenido.
- En el greybox, la reproducción del modo se demuestra con el toggle de `GravityWorld` +
  blend + un puente mode-gated; el reencuadre geométrico axial↔centrífugo por chunk queda
  para la etapa G del FD.
- Los atajos son 4 (cinta, caja, gloo, láser) + el puente mode-gated; enriquecer a ~5 por
  semilla es etapa G.
