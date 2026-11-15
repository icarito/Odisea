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

## Estado del montaje cilíndrico (2026-11-14, 2.ª pasada)

`BayVertical.tscn` ahora monta el **stack cilíndrico real**: `CylinderRotator` +
`ScaffoldStreamController(cylinder_mode=true)` + `PhysicalTerrace` + `Pilot` (el mismo de
`TestScaffoldOrbit`/`OdiseaExterior`), a `base_radius=48` para que la curvatura sea
perceptible. Se agregó `BayGravityMount` (dueño del modo, lee/escribe `GravityWorld` y
reconfigura un puente mode-gated), `BayModeConsole`, `BayProtocolCycle`, buffers
seamless con transición real (`AirlockManager.notify_transition` + `SceneManager.goto_scene`
sin fade) y luces de sala.

### Pendiente / límites (con evidencia)

- **Curvatura legible:** las capturas del montaje cilíndrico muestran la estructura y el
  piso, pero a `base_radius=48` y con la cámara a nivel de ojo la curvatura del anillo no se
  lee con claridad; además el OYS `LOOK pitch` no altera el encuadre en esta escena (las
  capturas con distinto pitch salen idénticas), así que no se pudo tomar una vista elevada
  que muestre el eje/la cima arriba. Falta tuning de cámara/altura y una vista de validación.
- **Piso físico vs. decks:** el `PhysicalTerrace` plano domina el piso visible; los decks
  del scaffold llegan como LOD delgado, por lo que la lectura de "piso = cara interior del
  anillo" aún no es convincente. Requiere subir `full_detail_radius`, dar material a los
  decks y/o reemplazar el piso plano por la superficie del anillo.
- **Contenido curado sobre el cilindro:** los atajos (cintas, gloo, láser) y el ciclo de
  luces siguen implementados sobre `BayVerticalWell` (componente con tests de determinismo
  y conectividad); falta layerlos sobre los chunks del `ScaffoldStreamController`. El FD
  deja el contrato; es la etapa G.
- **Modo:** el toggle de `GravityWorld` + blend + puente mode-gated funciona y es
  serializable; el reencuadre geométrico axial↔centrífugo por chunk (pisos↔paredes) queda
  para la etapa G.
- `BayVerticalWell` conserva la geometría polar de contenido (placeholder) y sus 11 tests;
  no es ya la escena jugable, sino el componente de contenido/validación.
