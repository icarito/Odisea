# FD-321: Cámaras cinemáticas en momentos clave (Bahía de Máquinas)

**Status:** In Progress
**Priority:** Medium
**Effort:** Small
**Created:** 2026-11-13
**Completed:** -

## Problem

El Vertical Slice no tiene cámaras cinemáticas en sus momentos clave. La
infraestructura ya existe (`CinematicManager` autoload, `CinematicRigV2`,
`CinematicPathRig`, `CameraZone`), pero no está enganchada a ningún beat
jugable: el jugador nunca ve un encuadre compuesto/sin control directo.

## Solution

Reusar la infraestructura de cinemáticas existente (no crear un segundo
sistema de cámara) para dos momentos clave de la **Bahía de Máquinas**
(`MachineBay.tscn`), cada uno como una `CameraZone` (Area, grupo
`CameraZoneV2`) con un `CinematicRigV2` hijo. El `PlayerControllerV2` ya
detecta la zona (polling determinista) y pide el modo al `CinematicManager`,
que activa el rig con blend de entrada/salida.

1. **Llegada / descenso a la bahía** — `Cinematics/ArrivalGate` +
   `ArrivalRevealRig`. Al bajar por la rampa de entrada la cámara se eleva
   detrás y muestra el pozo monumental de la bahía hacia +Z.
2. **Puente sobre el fuego (Estación 5)** — `Cinematics/BridgeFireGate` +
   `BridgeFireRevealRig`. Al llegar al deck de la Estación 5 la cámara
   encuadra el puente basculante ardiendo y los quemadores laterales.

Contrato de inmersión respetado: la cámara nunca salta (blend con
`transition_time` del rig, latch de input en entrada/salida) y al salir de la
zona el control vuelve al jugador sin cambiar su pose ni la relación
cámara-personaje (modo de movimiento `FREE`, cámara-relative).

### Momentos evaluados y descartados

- **Despertar / apertura de criopods (RingHub)**: el anillo arranca sin luz
  (`RingHubLightState.start_lit = false`); un encuadre ahí renderiza negro y
  necesitaría trabajo de iluminación fuera de alcance. Descartado por ahora.
- **Primer contacto con Odisea / Programmer**: ya tiene cámara de foco
  (`ProgrammerHoloNPC.focus_camera` en `VoiceEntry` y en la válvula maestra).
  No se duplica.
- **Cierre por válvula (Estación 5 / Terminal de Flujo)**: ya tiene
  `focus_camera` de Odisea al completar la orden. No se duplica.

### Considered Options

- **Option A (selected)**: `CameraZone` + `CinematicRig` instanciados en la
  escena del nivel. Cero código nuevo; usa el polling determinista del
  `PlayerControllerV2` y el FSM del `CinematicManager`.
- **Option B**: extender OYS (`CINEMATIC_CAMERA`) para mover la cámara. Requiere
  tocar `OYS_Interpreter` (fuera del alcance permitido) y sería un segundo
  camino de cámara.
- **Option C**: `activate_vcamera`/`blend_to_vcamera` por script. Necesita un
  trigger propio y duplica el manejo de blend que ya hace el FSM de requests.
- **Selected**: A — mínima superficie, reusa el contrato de requests/blend.

## Files to Modify

- `core_v2/levels/machines/MachineBay.tscn` (modify — instancia las 2 zonas + rigs)
- `core_v2/tests/test_cinematic_moments.gd` (new — wiring + integración)
- `docs/features/FD-321_camaras_cinematicas_momentos_clave.md` (new — este doc)

## Verification

1. Wiring + encuadre (mira hacia la acción) y activación/retorno de control:
   `./runtest.sh -a ./core_v2/tests/test_cinematic_moments.gd` (3/3 verdes).
2. Sin regresión de recorrido ni de estaciones:
   `./runtest.sh -a ./core_v2/tests/test_machine_bay_route.gd`,
   `./runtest.sh -a ./core_v2/tests/test_machine_bay.gd`.
3. Capturas 960x540 del encuadre de cada shot (artefactos):
   `cine_machinebay_arrival_960x540.png`, `cine_machinebay_bridge_fire_960x540.png`.
