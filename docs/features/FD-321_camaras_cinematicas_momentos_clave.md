# FD-321: Cámaras cinemáticas — transiciones, no áreas de nivel

**Status:** Reconciled (corrección de alcance 2026-11-14)
**Priority:** Medium
**Effort:** Small
**Created:** 2026-11-13
**Revised:** 2026-11-14

## Corrección de alcance (2026-11-14)

El pedido de diseño corrigió el alcance original: **las cámaras cinemáticas eran
para las transiciones nomás, no para áreas del nivel.** El planteamiento inicial de
dos "momentos clave" como `CameraZone` dentro de `MachineBay.tscn` (llegada a la
bahía y puente sobre el fuego) quedó **fuera de alcance**: disparar cinemáticas al
caminar por el nivel rompe la regla de inmersión (el jugador pierde control sin
cambiar de zona) y duplica responsabilidad que pertenece al sistema de
transiciones.

En consecuencia, se eliminaron de `MachineBay.tscn` los nodos por área:

- `Cinematics/ArrivalGate` (Area + `CameraZone.gd`, `cinematic_rig_path=../ArrivalRevealRig`)
- `Cinematics/ArrivalRevealRig` (instancia de `CinematicRig`)
- `Cinematics/BridgeFireGate` (Area + `CameraZone.gd`)
- `Cinematics/BridgeFireRevealRig` (instancia de `CinematicRig`)

y los `ext_resource` de `CameraZone.gd` y `CinematicRig.tscn`, que quedaron sin uso
en el nivel.

## Solution (vigente)

Las cinemáticas de transición las implementa el **sistema de transiciones**
(componente aparte), reusando `CinematicManager`/`CinematicRig`. La Bahía de Máquinas
es un nivel **sin** cinemáticas por área: se recorre con control continuo y la cámara
nunca salta al entrar o salir de zonas del nivel. Cualquier encuadre compuesto de un
beat jugable se resuelve por transición, no por trigger de área.

### Contrato de inmersión

- La cámara no cambia al caminar por el nivel (sin `CameraZone` de área).
- El sistema de transiciones es el único dueño de los encuadres cinemáticos.
- El nivel no expone grupos `CameraZoneV2` ni instancias de `CinematicRig`.

## Files

- `core_v2/levels/machines/MachineBay.tscn` (modified — se quitaron los 4 nodos de
  área y 2 `ext_resource`; se preservan `LabyrinthSection` y
  `MachineBayLabyrinthStreamer`).
- `core_v2/tests/test_machine_bay_no_area_cinematics.gd` (new — guardia de fuente e
  instancia: el nivel no puede reintroducir cinemáticas por área). Reemplaza a
  `core_v2/tests/test_cinematic_moments.gd`, eliminado.
- `docs/features/FD-321_camaras_cinematicas_momentos_clave.md` (este doc).
- `docs/features/FEATURE_INDEX.md` (actualizado).

## Verification

1. Guardia de área:
   `./.venv/bin/pytest tests/test_odisea_runner.py -k test_machine_bay_no_area_cinematics`
2. La ruta crítica de FD-320 no cambia:
   `./.venv/bin/pytest tests/test_odisea_runner.py -k 'machine_bay or labyrinth'`

## Notas históricas (descartado)

El diseño previo describía dos `CameraZone`+`CinematicRig` instanciados en la
escena del nivel (Option A). Se conserva aquí solo como registro: esa aproximación
fue reemplazada por la implementación en el sistema de transiciones.

### Momentos evaluados y descartados (siguen vigentes como criterio)

- **Despertar / apertura de criopods (RingHub)**: el anillo arranca sin luz; se
  resolvería por transición, no por área.
- **Primer contacto con Odisea / Programmer**: ya tiene cámara de foco
  (`ProgrammerHoloNPC.focus_camera`). No se duplica.
- **Cierre por válvula (Estación 5)**: ya tiene `focus_camera` de Odisea al completar
  la orden. No se duplica.
