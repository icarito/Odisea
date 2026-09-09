# HANDOFF — Zoom pin en KinematicArm3D (Box3D) + colas relacionadas

**Fecha:** 2026-09-09 (madrugada/tarde) **Autor:** sesión Kilo FD-290 **Estado:** REPRODUCIDO, causa raíz NO aislada
**Test de regresión:** `core_v2/tools/measure/test_zoom_pin_repro.oys` (fuera del suite a propósito: falla en Box3D hasta resolver)

## Síntoma (reporte de Sebastián, en vivo con Box3D)

Hacer zoom IN y luego intentar zoom OUT: la cámara no se aleja. Observación visual: "la colisión de
la cámara choca con el player capsule o algo así y luego no quiere alejarse de nuevo". Solo se
observó con el backend Box3D (binario 3.6.4.rc v0.2.0); en Bullet el zoom funciona.

## Repro

```bash
GODOT_BIN=/home/icarito/Descargas/godot.box3d.linux.x86_64.editor \
  ./runtest.sh --oys test_zoom_pin_repro
```

(El test vive en `core_v2/tools/measure/` — moverlo a `core_v2/tests/` cuando pase.) Estado capturado
por el propio test vía `GET_NODE_PROP` (nuevo en el intérprete OYS, soporta rutas `Pilot/sub/nodo`
que resuelven contra el player vivo de SessionManager — los nombres planos fallan en PASS 2 por los
renombres `@Nodo@N` al re-instanciar):

```
antes:            base_spring_length_3d = 2.5
tras zoom in:     current_length = 0.75 (base 0.6)   ✓
tras zoom out:    current_length = 0.559426
                  _zoom_out_blocked   = true
                  _collision_latched_length = 0.559426
                  _excluded_objects = [Pilot root]   ✓ la exclusión SÍ está
```

Mecánica del deadlock: el latch se forma durante la retracción del zoom-in; parado, `_advance_clear_length`
toma la rama de hold estacionario (`collision_stationary_release_delay = 0.25`, default del script —
el Pilot no lo pisa) y **retorna antes del verify**, así que el latch nunca se re-evalúa ni suelta; y
`_zoom_out_blocked = ... or _collision_latched_length >= 0.0` hace que el controlador descarte los
zoom_delta positivos (`PlayerControllerV2:1392`). Caminando se libera (la pose cambia > 0.025 m).

## Descartado (con sondas, ambas motores)

Sondas en `/tmp/kilo/cast_probe*.gd` (efímeras; los números quedan acá):

1. **Invariancia de `cast_motion` al largo del barrido**: pared a 3 m, esfera r=0.25 desde el origen,
   L=4 → d_hit 2.28 (Bullet) / 2.245 (Box3D); L=8 → idéntico. La derivación del hit principal desde el
   barrido largo del lookahead (FD-290) es válida.
2. **Exclusión por nodo vs RID en `cast_motion`**: ambas funcionan en ambos motores (f=1 excluyendo
   por nodo pese a que el binding es `Vector<RID>` — la conversión Object→RID aplica).
3. **Exclusión de un KinematicBody** (cápsula del jugador, esfera a 0.559 detrás barriendo +Z): f=1 en
   todos los casos — el cast NO la detecta moviéndose away, excluida o no.
4. **La escena**: mover `PushableBoxV2` de TestScene_v2 50 m no cambia el drift de strafe (5.6 m) —
   la caja no era.
5. La lista de exclusión del brazo contiene al Pilot root (la cápsula del root está excluida).

## Estado del arte del código

- El latch lo arma **`snap_collision_to_scene()`** (print `snap hit=...`) o el hit-path /
  `_start_collision_latch` durante el zoom-in. En las corridas capturadas **no hay print de snap ni
  de ARM_DEBUG** → el latch se formó por un camino NO instrumentado: los casts internos de
  `_resolve_collision_hit_length` y el **motion lookahead** (`_cast_motion_lookahead_hit_length` →
  `_cast_shape_hit_length`) no tienen el debug. **Primer paso del que retome: instrumentar esos dos
  casts** (env `ODISEA_ARM_DEBUG=1`, ya cableado en el merged probe y en el verify).
- Semántica start-touch/start-inside (sonda cast_probe2): Bullet da slack (touching → f=0.03);
  Box3D bloquea seco (f=0). A distancias cortas (0.5-0.8 m) ese slack puede voltear hits marginales:
  candidato a ajuste en el módulo (matchear el slack de Bullet) o política Odisea-side (ignorar hits
  con `d_hit < epsilon` por ser start-touch).
- El gate del controlador (`PlayerControllerV2:1392`) y la fórmula
  `_zoom_out_blocked = ceiling or anticipated or safe_hit or latched` son PRE-EXISTENTES (no tocados
  por FD-290). En Bullet el latch no se forma en este escenario; en Box3D sí.

## Camino sugerido

1. `ODISEA_ARM_DEBUG=1` + instrumentar el motion lookahead y `_resolve_collision_hit_length`
   (mismo patrón del bloque merged) → correr el repro → identificar el collider y el cast que arma
   el latch.
2. Si el collider es el Pilot root a pesar de la exclusión: reproducir en la sonda con la jerarquía
   real (OTS offset + pitch de la Pilot) — puede ser un segundo body en la jerarquía del Pilot.
3. Si es geometría del TestScene a 0.6-3 m detrás del spawn: decidir diseño — el hold es correcto
   (la cámara recortaría), pero entonces el gate de zoom-out no debería bloquear el `base` (solo el
   rendered), o el hold estacionario debe correr el verify antes del retorno temprano.
4. A/B Bullet: correr el mismo repro con `godot3-bin` — pasa; capturar por qué el verify de Bullet
   no re-latchea (¿la sonda start-touch f=0.03 es la diferencia?).

## Colas relacionadas (mismo lote de investigación)

- **Tank yaw en replays**: `test_locomocion_strafe.oys` quedó revertido al contrato viejo porque la
  reescritura a tanque puro (blend 1.0) falla en replay: `yaw` se queda en 0 tras 1 s de LEFT — la
  aplicación del yaw de tanque (`_update_camera_orbit_state:1240`) no surte efecto bajo el stepping
  centralizado del replay. El blend quedó como HEAD (script 0.5, Pilot 0.9). Ojo: en modo órbita
  (mouse activo) el strafe es full por diseño (`is_tank_turn_mode = false`).
- **`sleeping = true` en escenas**: `TestScene_PushableBox.tscn` lleva cajas con `sleeping = true`
  spawnenando a y=5. Box3D honra el flag estrictamente (Box2D semantics: la gravedad no despierta)
  y flotan; Bullet las despierta y caen. Decidir semántica canónica en el módulo o limpiar el flag
  de las escenas (probable click accidental en el inspector). Guardia: `test_box_air_sleep.oys`.
- **CI determinista Box3D**: con estos cambios la única roja es `test_cargol_basic` (flake
  pre-existente del mismo commit; ver FD-290 "Historia del rojo").
