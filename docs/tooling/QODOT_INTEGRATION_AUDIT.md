# Auditoria de la integracion Qodot / TrenchBroom

Estado del puente entre los assets de Odisea y el editor de niveles, con el detalle
de que quedo sincronizado y que sigue pendiente. Es un documento de datos: casi todo
lo que dice se puede volver a generar.

Para las convenciones y el flujo de trabajo, ver [QODOT_PIPELINE.md](QODOT_PIPELINE.md).

## Como se regenera este informe

```bash
# 1. Mide el AABB real y los export de los 123 .tscn de core_v2/props/
QODOT_AUDIT_OUT=/tmp/qodot_props_audit.json \
  godot3-bin --no-window -s tools/qodot_audit_props.gd

# 2. Corrige meta_properties.size de las point classes con esa medicion
python3 tools/qodot_sync_point_class_sizes.py --dry-run   # revisar
python3 tools/qodot_sync_point_class_sizes.py

# 3. Regenera Qodot.fgd desde los .tres
godot3-bin --no-window -s tools/qodot_export_fgd.gd

# 4. Valida el conjunto (FGD, texturas, qodot_map.gd)
godot3-bin --no-window -s tools/qodot_validate.gd
godot3-bin --no-window -s tools/qodot_wiring_smoke.gd
```

## Estado

| | antes | ahora |
|---|---:|---:|
| `.tscn` bajo `core_v2/props/` | 123 | 123 |
| expuestos al FGD con `scene_file` | 45 | 55 |
| point classes de logica pura (`script_class`) | 0 | 5 |
| brush entities propias (`SolidClass`) | 0 | 1 |
| clases totales en `Qodot.fgd` | 62 | 77 |
| huecos `null` en `entity_definitions` | 13 | 0 |
| point classes con `size` medido del prop | 0 | 50 |
| point classes que heredan `Targetname`/`Target` | 0 | 59 |
| texturas de `.map` sin archivo en disco | 2 | 0 |
| texturas de mundo con espacios en el nombre | 10 | 0 |

`Qodot.fgd`, `qodot_fgd.tres` y `core_v2/qodot_fgd/props/` estan alineados: la unica
fuente de verdad son los `.tres` y el `.fgd` se genera desde ellos.

## Convenciones que hay que saber antes de tocar nada

Tres cosas de Qodot que no son obvias y que estaban mal aplicadas:

1. **`meta_properties["size"]` no guarda una extension.** Es un `AABB` usado como par
   min/max: `position` es el minimo y `size` es el **maximo**. `build_def_text()` los
   imprime crudos como `size(minx miny minz, maxx maxy maxz)`.
2. **Los ejes se permutan.** El `.map` es Z-up y Qodot mapea `quake(x,y,z) ->
   godot(y,z,x)`. Para ir al reves: `quake.x = godot.z`, `quake.y = godot.x`,
   `quake.z = godot.y`.
3. **La escala es 16.** `inverse_scale_factor = 16`, o sea 1 unidad de TrenchBroom =
   6.25 cm. Un `size(-8 -8 -8, 8 8 8)` es un cubo de 1 m.

`tools/qodot_sync_point_class_sizes.py` aplica las tres. Las cajas se redondean a
unidades enteras hacia afuera: precision de sobra para el editor, y evita que el
`.fgd` salga con `-57.599998`.

## Medicion de dimensiones

`tools/qodot_audit_props.gd` mide el AABB real de cada prop. Detalles que cambian el
resultado y que hubo que resolver:

- **Las luces no cuentan.** `VisualInstance.get_aabb()` sobre una `OmniLight` devuelve
  su volumen de influencia, no su cuerpo. Sin excluirlas, `light_work_tripod` medía
  49 m.
- **Los `Area` no cuentan.** Solo se suman las `CollisionShape` colgadas de un
  `PhysicsBody`. El area de empuje de `prop_industrial_fan` es de 4x4x10 m contra un
  prop de 2 m.
- **Los CSG restadores no cuentan.** La caja que perfora el hueco de una puerta suele
  ser mas grande que la puerta.
- **21 props construyen su geometria en `_ready()`** (los andamios, la valla, el
  radiador, la cinta de peligro). Fuera del arbol miden cero, asi que a esos —y solo a
  esos— se los instancia de verdad y se los mide despues de cuatro frames.

Quedan **3 sin medir**, todos correctos: `SparkEmitterV2`, `plasma_particles` y
`TrackerBase` no tienen geometria propia (son emisores / nodos de seguimiento).
Conservan una caja chica puesta a mano.

## Props expuestos al FGD

Ver tambien las point classes de logica pura mas abajo.

| .tscn (bajo core_v2/props/) | en FGD | point class | script raiz | exports | activated | dims reales m (X Y Z Godot) | size AABB quake (min) (max) | medicion |
|---|:-:|---|---|---:|:-:|---|---|---|
| `CheckpointConsole.tscn` | no | — | `CheckpointConsole.gd` | 12 | si | 0.60 x 1.20 x 0.60 | — | estatica |
| `ElevatorPropBase.tscn` | no | — | `ElevatorController.gd` | 21 | si | 5.20 x 14.05 x 3.10 | — | estatica |
| `Industrial_Cage_Sconce.tscn` | no | — | — | 0 | — | 0.21 x 0.38 x 0.21 | — | estatica |
| `circuit/CircuitCable.tscn` | no | — | `CircuitCable.gd` | 20 | si | 3.00 x 0.06 x 0.06 | — | vivo |
| `circuit/CircuitExample.tscn` | no | — | `CircuitExampleProp.gd` | 14 | si | 5.20 x 5.03 x 0.50 | — | estatica |
| `circuit/CircuitTestScene.tscn` | no | — | `CircuitTestScene.gd` | 0 | — | 4.81 x 2.00 x 0.50 | — | estatica |
| `controls/DataSlate.tscn` | no | — | — | 0 | — | 0.25 x 0.35 x 0.02 | — | estatica |
| `controls/HoloTerminalV2.tscn` | **si** | `holo_terminal` | `HoloTerminalV2.gd` | 24 | si | 1.00 x 1.91 x 0.50 | `(-4 -8 -20) (4 8 12)` | estatica |
| `controls/HologramProjectorV2.tscn` | **si** | `prop_hologram_projector` | `HologramProjectorV2.gd` | 6 | — | 1.00 x 1.60 x 1.00 | `(-8 -8 -1) (8 8 25)` | estatica |
| `controls/Lever.tscn` | **si** | `prop_lever` | `InteractableBridge.gd` | 8 | — | 1.20 x 2.00 x 0.50 | `(-4 -10 0) (4 10 32)` | estatica |
| `controls/LeverV2.tscn` | no | — | `LeverV2.gd` | 13 | si | 0.40 x 0.75 x 0.70 | — | estatica |
| `controls/Manometer.tscn` | no | — | `Manometer.gd` | 2 | — | 0.62 x 0.62 x 0.19 | — | estatica |
| `controls/PedestalButton.tscn` | **si** | `prop_pedestal_button` | `PedestalButton.gd` | 19 | si | 0.40 x 1.10 x 0.40 | `(-4 -4 0) (4 4 18)` | estatica |
| `controls/PressurePlate.tscn` | **si** | `prop_pressure_plate` | `PressurePlateV2.gd` | 12 | si | 2.40 x 0.20 x 2.40 | `(-20 -20 -2) (20 20 2)` | estatica |
| `controls/PressurePump.tscn` | **si** | `prop_pressure_pump` | `PressurePump.gd` | 14 | si | 0.44 x 0.96 x 0.44 | `(-4 -4 0) (4 4 16)` | estatica |
| `controls/TableTerminal.tscn` | no | — | `HoloTerminalV2.gd` | 24 | si | 1.00 x 0.14 x 0.50 | — | estatica |
| `controls/WallTerminal.tscn` | no | — | `HoloTerminalV2.gd` | 24 | si | 3.45 x 3.70 x 0.18 | — | estatica |
| `criopod/CriopodParallax.tscn` | no | — | — | 0 | — | 1.00 x 2.40 x 1.00 | — | estatica |
| `criopod/CriopodParallaxDecor.tscn` | no | — | — | 0 | — | 0.97 x 2.40 x 0.97 | — | estatica |
| `criopod/CriopodParallaxFull.tscn` | no | — | — | 0 | — | 0.97 x 2.75 x 0.97 | — | estatica |
| `criopod/Criopod_vert.tscn` | no | — | — | 0 | — | 4.50 x 4.36 x 1.95 | — | estatica |
| `decor/BrokenFloorPanel.tscn` | no | — | — | 0 | — | 2.00 x 0.10 x 2.10 | — | estatica |
| `decor/DebugConsoleHUD.tscn` | no | — | `DebugConsoleHUD.gd` | 42 | si | 0.80 x 0.60 x 0.01 | — | estatica |
| `decor/EmergencyBeaconSpotV2.tscn` | no | — | `EmergencyBeaconSpotV2.gd` | 32 | si | 0.40 x 0.40 x 0.38 | — | estatica |
| `decor/EmergencyBeaconV2.tscn` | **si** | `light_emergency_beacon` | `EmergencyBeaconV2.gd` | 31 | si | 0.40 x 0.40 x 0.38 | `(-4 -4 0) (4 4 7)` | estatica |
| `decor/HelmetHUD.tscn` | no | — | `HelmetHUDV2.gd` | 42 | si | 0.30 x 0.30 x 0.42 | — | estatica |
| `decor/LaserTripwire.tscn` | **si** | `prop_laser_tripwire` | `LaserTripwire.gd` | 16 | si | 4.20 x 0.50 x 0.20 | `(-2 -34 -4) (2 34 4)` | estatica |
| `decor/SteelPlate.tscn` | no | — | `SteelPlate.gd` | 14 | — | 2.00 x 0.10 x 1.00 | — | estatica |
| `decor/WarningBarrier.tscn` | no | — | — | 0 | — | 1.60 x 1.00 x 0.22 | — | estatica |
| `decor/ZeroGravityZone.tscn` | no | — | `ZeroGravityZone.gd` | 6 | — | 20.00 x 20.00 x 20.00 | — | vivo |
| `doors/AirlockChamber.tscn` | **si** | `prop_airlock` | `AirlockControllerV2.gd` | 15 | — | 7.00 x 7.23 x 8.98 | `(-72 -56 -63) (72 57 54)` | estatica |
| `doors/AirlockContainerChamber.tscn` | no | — | `AirlockControllerV2.gd` | 15 | — | 4.80 x 4.46 x 5.52 | — | estatica |
| `doors/AirlockShell.tscn` | no | — | `AirlockShell.gd` | 4 | — | 7.00 x 6.66 x 8.98 | — | estatica |
| `doors/ElevatorDoor.tscn` | no | — | `ElevatorDoor.gd` | 27 | si | 3.10 x 4.05 x 0.20 | — | estatica |
| `doors/FloorHatch.tscn` | **si** | `prop_door_floor_hatch` | `FloorHatchProxy.gd` | 1 | — | 4.40 x 0.33 x 4.40 | `(-36 -36 -2) (36 36 4)` | estatica |
| `doors/HeavyBlastDoor.tscn` | **si** | `prop_door_heavy_blast` | `DualSlidingObjectV2.gd` | 15 | si | 4.00 x 4.00 x 0.40 | `(-4 -32 0) (4 33 65)` | estatica |
| `doors/IrisDoorV2.tscn` | **si** | `prop_door_iris` | `InteractableBridge.gd` | 8 | — | 7.20 x 7.20 x 1.00 | `(-8 -58 -58) (8 58 58)` | estatica |
| `doors/VerticalDoor.tscn` | **si** | `prop_door_vertical` | `InteractableBridge.gd` | 8 | — | 6.90 x 10.20 x 3.00 | `(-24 -56 -2) (24 56 162)` | estatica |
| `elevator/ElevatorFloorSelector.tscn` | no | — | `ElevatorFloorSelector.gd` | 25 | si | 0.56 x 1.45 x 0.24 | — | estatica |
| `elevator/MaintenanceElevator.tscn` | no | — | `MaintenanceElevator.gd` | 12 | — | 3.22 x 8.60 x 3.07 | — | estatica |
| `elevator/MaintenanceElevatorTest.tscn` | no | — | `MaintenanceElevator.gd` | 12 | — | 4.40 x 8.60 x 4.40 | — | estatica |
| `emitters/FireEmitter.tscn` | no | — | `FireEmitter.gd` | 10 | — | 1.35 x 2.10 x 0.29 | — | vivo |
| `emitters/FrostEmitter.tscn` | no | — | `FrostEmitter.gd` | 13 | — | 2.20 x 2.20 x 0.31 | — | vivo |
| `emitters/LeakEmitter.tscn` | **si** | `prop_leak_emitter` | `LeakEmitter.gd` | 8 | — | 1.50 x 1.50 x 0.00 | `(-2 -12 -12) (2 12 12)` | estatica |
| `emitters/PlasmaGenerator.tscn` | **si** | `prop_plasma_generator` | `PlasmaGenerator.gd` | 0 | — | 2.00 x 3.85 x 2.00 | `(-16 -16 -4) (16 16 58)` | estatica |
| `emitters/SparkEmitterV2.tscn` | **si** | `prop_spark_emitter` | `SparkEmitterV2.gd` | 8 | — | - | `(-1 -1 -1) (1 1 1)` | SIN MEDIR |
| `exhaust/PlasmaExhaust.tscn` | no | — | `PlasmaExhaust.gd` | 0 | — | 4.00 x 4.00 x 3.00 | — | estatica |
| `exhaust/plasma_particles.tscn` | no | — | — | 0 | — | - | — | SIN MEDIR |
| `helmet_view/drone_dock/DroneDock.tscn` | no | — | `DroneDock.gd` | 14 | si | 2.60 x 0.31 x 2.60 | — | estatica |
| `helmet_view/fusion_core/FusionCore.tscn` | no | — | `FusionCore.gd` | 7 | — | 0.70 x 0.95 x 0.70 | — | estatica |
| `helmet_view/gravity_anchor/GravityAnchor.tscn` | no | — | `GravityAnchor.gd` | 14 | si | 1.20 x 1.15 x 1.20 | — | estatica |
| `helmet_view/grip_point/GripPoint.tscn` | no | — | `GripPoint.gd` | 14 | si | 0.40 x 1.00 x 0.40 | — | estatica |
| `helmet_view/hazard_tape/HazardTape.tscn` | **si** | `prop_hazard_tape` | `HazardTape.gd` | 20 | si | 5.04 x 1.50 x 0.00 | `(-2 -41 0) (2 41 24)` | vivo |
| `helmet_view/holo_planta/HoloPlanta.tscn` | no | — | `holo_planta.gd` | 14 | si | 0.00 x 0.00 x 0.00 | — | estatica |
| `helmet_view/neon_sign/NeonSign.tscn` | no | — | `neon_sign.gd` | 14 | si | 0.20 x 2.00 x 0.20 | — | estatica |
| `lights/HelmetFlashlight.tscn` | no | — | `HelmetFlashlight.gd` | 19 | — | 4.56 x 4.56 x 5.50 | — | estatica |
| `lights/SciFiBoxLightV2.tscn` | **si** | `light_box` | `SciFiBoxLightV2.gd` | 17 | si | 0.80 x 0.44 x 0.80 | `(-7 -7 -4) (7 7 4)` | estatica |
| `lights/SciFiFloatingLightV2.tscn` | **si** | `light_floating` | `SciFiFloatingLightV2.gd` | 4 | si | 0.06 x 0.41 x 0.40 | `(-4 -2 -4) (4 2 4)` | estatica |
| `lights/SciFiFloorPanelV2.tscn` | **si** | `light_floor_panel` | `SciFiFloorPanelV2.gd` | 15 | si | 4.00 x 0.20 x 4.00 | `(-32 -32 -4) (32 32 0)` | estatica |
| `lights/SciFiHangingLightV2.tscn` | **si** | `light_hanging` | `SciFiHangingLightV2.gd` | 20 | si | 0.14 x 0.91 x 0.16 | `(-3 -2 -15) (2 3 1)` | estatica |
| `lights/SciFiLightPathV2.tscn` | **si** | `light_path` | `SciFiLightPathV2.gd` | 21 | si | 4.10 x 0.89 x 0.10 | `(-2 -33 -1) (2 33 14)` | vivo |
| `lights/SciFiShieldV2.tscn` | **si** | `prop_shield` | `SciFiShieldV2.gd` | 16 | si | 2.39 x 2.40 x 2.39 | `(-20 -20 0) (20 20 39)` | estatica |
| `lights/SciFiSphereLightV2.tscn` | **si** | `light_sphere` | `SciFiSphereLightV2.gd` | 17 | si | 1.00 x 0.95 x 1.00 | `(-8 -8 -1) (8 8 15)` | estatica |
| `lights/SciFiStaticLightV2.tscn` | **si** | `light_static` | `SciFiStaticLightV2.gd` | 16 | si | 0.06 x 0.41 x 0.40 | `(-4 -2 -4) (4 2 4)` | estatica |
| `lights/VolumetricGlowLightV2.tscn` | **si** | `light_volumetric` | `VolumetricGlowLightV2.gd` | 6 | — | 0.40 x 0.40 x 0.40 | `(-4 -4 -4) (4 4 4)` | estatica |
| `machinery/CargolDroneProp.tscn` | **si** | `prop_cargol_drone` | `CargolDroneProp.gd` | 2 | si | 1.00 x 1.00 x 1.00 | `(-8 -8 40) (8 8 56)` | estatica |
| `machinery/Conveyor.tscn` | **si** | `prop_conveyor` | `Conveyor.gd` | 17 | si | 8.90 x 2.73 x 4.15 | `(-32 -72 -11) (35 72 33)` | estatica |
| `machinery/ConveyorCarrousel.tscn` | no | — | `ConveyorCarrousel.gd` | 15 | si | 7.10 x 1.29 x 7.10 | — | estatica |
| `machinery/ElevatorProp.tscn` | **si** | `prop_elevator` | `ElevatorController.gd` | 21 | si | 5.36 x 15.75 x 4.41 | `(-35 -37 -3) (36 50 250)` | estatica |
| `machinery/IndustrialFan.tscn` | **si** | `prop_industrial_fan` | `IndustrialFan.gd` | 16 | si | 2.40 x 2.40 x 0.50 | `(-4 -20 -20) (4 20 20)` | estatica |
| `machinery/MovingPlatformV2.tscn` | **si** | `prop_moving_platform` | `MovingPlatformV2.gd` | 9 | si | 5.00 x 0.20 x 5.00 | `(-40 -40 -2) (40 40 2)` | estatica |
| `machinery/RadiatorProp.tscn` | **si** | `prop_radiator` | `RadiatorProp.gd` | 23 | si | 1.20 x 0.80 x 0.15 | `(-1 -10 -7) (4 10 7)` | vivo |
| `machinery/RetractableBridge.tscn` | no | — | `RetractableBridge.gd` | 5 | — | 4.00 x 0.50 x 2.00 | — | estatica |
| `machinery/VentilationTurbine.tscn` | **si** | `prop_ventilation_turbine` | `PropBaseV2.gd` | 14 | si | 4.40 x 4.40 x 4.40 | `(-36 -36 -36) (36 36 36)` | estatica |
| `metal_fence/MetalFence.tscn` | **si** | `prop_metal_fence` | `MetalFence.gd` | 19 | si | 4.11 x 2.50 x 4.13 | `(-66 -33 0) (1 34 41)` | vivo |
| `pipe/CoolantTank.tscn` | **si** | `pipe_coolant_tank` | `CoolantTank.gd` | 3 | — | 2.85 x 3.40 x 2.30 | `(-19 -19 0) (19 28 55)` | estatica |
| `pipe/PipeCorner.tscn` | **si** | `pipe_corner` | — | 0 | — | 1.20 x 1.20 x 0.40 | `(-4 -4 -4) (4 16 16)` | estatica |
| `pipe/PipeManometer.tscn` | **si** | `pipe_manometer` | `PipeManometer.gd` | 6 | — | 0.62 x 0.91 x 0.19 | `(-2 -5 -10) (2 5 5)` | estatica |
| `pipe/PipeSection.tscn` | **si** | `pipe_section` | — | 0 | — | 2.00 x 0.40 x 0.40 | `(-4 -16 -4) (4 16 4)` | estatica |
| `pipe/PipeTee.tscn` | **si** | `pipe_tee` | — | 0 | — | 2.00 x 2.00 x 0.40 | `(-4 -16 -16) (4 16 16)` | estatica |
| `pipe/PipeValve.tscn` | **si** | `pipe_valve` | `PipeValve.gd` | 11 | si | 0.84 x 0.91 x 0.69 | `(-4 -7 -7) (8 7 8)` | estatica |
| `scaffold/ScaffoldCross.tscn` | no | — | `SteelGratePlatform.gd` | 50 | — | 6.04 x 1.62 x 6.04 | — | vivo |
| `scaffold/ScaffoldCurve.tscn` | no | — | `SteelGratePlatform.gd` | 50 | — | 3.04 x 2.79 x 12.04 | — | vivo |
| `scaffold/ScaffoldEnd.tscn` | no | — | `SteelGratePlatform.gd` | 50 | — | 4.04 x 2.79 x 4.04 | — | vivo |
| `scaffold/ScaffoldGap.tscn` | no | — | `SteelGratePlatform.gd` | 50 | — | 3.04 x 2.79 x 10.04 | — | vivo |
| `scaffold/ScaffoldHubRing.tscn` | no | — | `ScaffoldHubRing.gd` | 26 | — | 15.29 x 1.37 x 15.29 | — | vivo |
| `scaffold/ScaffoldHubTower.tscn` | no | — | `ScaffoldHubTower.gd` | 18 | — | 15.29 x 23.87 x 15.29 | — | vivo |
| `scaffold/ScaffoldPlatform.tscn` | no | — | `SteelGratePlatform.gd` | 50 | — | 15.04 x 1.62 x 6.04 | — | vivo |
| `scaffold/ScaffoldRailing.tscn` | no | — | `SteelGratePlatform.gd` | 50 | — | 4.04 x 2.79 x 10.04 | — | vivo |
| `scaffold/ScaffoldStairs.tscn` | no | — | `SteelGratePlatform.gd` | 50 | — | 4.04 x 4.78 x 10.04 | — | vivo |
| `scaffold/ScaffoldTJunction.tscn` | no | — | `SteelGratePlatform.gd` | 50 | — | 6.04 x 2.79 x 6.04 | — | vivo |
| `scaffold/ScaffoldWalkway.tscn` | **si** | `prop_scaffold_walkway` | `SteelGratePlatform.gd` | 50 | — | 3.04 x 1.62 x 10.04 | `(-81 -25 0) (81 25 26)` | vivo |
| `scaffold/SteelGratePlatform.tscn` | **si** | `prop_steel_grate_platform` | `SteelGratePlatform.gd` | 50 | — | 3.04 x 2.79 x 3.04 | `(-25 -25 0) (25 25 45)` | vivo |
| `scenes/SteelPlateStack.tscn` | no | — | — | 0 | — | 2.21 x 0.43 x 1.34 | — | estatica |
| `scifi_doors/DoorDoubleSidewaysV2.tscn` | **si** | `prop_door_scifi_double_sideways` | `SciFiDoorV2.gd` | 25 | si | 4.26 x 3.69 x 0.60 | `(-5 -35 -2) (6 35 58)` | estatica |
| `scifi_doors/DoorDoubleVerticalV2.tscn` | **si** | `prop_door_scifi_double_vertical` | `SciFiDoorV2.gd` | 25 | si | 4.38 x 3.86 x 0.62 | `(-5 -36 -3) (6 36 60)` | estatica |
| `scifi_doors/DoorSingleVerticalV2.tscn` | **si** | `prop_door_scifi_vertical` | `SciFiDoorV2.gd` | 25 | si | 4.50 x 3.92 x 0.62 | `(-5 -36 -2) (6 36 62)` | estatica |
| `scifi_lights/FluorescentLightCeiling.tscn` | **si** | `light_ceiling` | `FluorescentLight.gd` | 24 | si | 2.02 x 0.12 x 2.00 | `(-16 -17 -2) (16 17 2)` | estatica |
| `scifi_lights/FluorescentLightFlickering.tscn` | **si** | `light_flickering` | `FluorescentLight.gd` | 24 | si | 2.02 x 0.12 x 2.00 | `(-16 -17 -2) (16 17 2)` | estatica |
| `scifi_lights/FluorescentLightWall.tscn` | **si** | `light_wall` | `FluorescentLight.gd` | 24 | si | 0.10 x 1.00 x 1.00 | `(-8 -2 -8) (8 2 8)` | estatica |
| `scifi_lights/IndustrialCagedSconceBMesh.tscn` | no | — | — | 0 | — | 0.21 x 0.38 x 0.21 | — | estatica |
| `scifi_lights/Industrial_Caged_Sconce.tscn` | no | — | `IndustrialCagedSconce.gd` | 3 | — | 0.17 x 0.31 x 0.17 | — | estatica |
| `scifi_lights/SciFiPathMarkerArrowV2.tscn` | **si** | `light_path_arrow` | `SciFiPathMarkerV2.gd` | 19 | si | 0.56 x 0.16 x 0.63 | `(-5 -5 -1) (6 5 4)` | estatica |
| `scifi_lights/SciFiPathMarkerV2.tscn` | **si** | `light_path_marker` | `SciFiPathMarkerV2.gd` | 19 | si | 0.44 x 0.12 x 0.44 | `(-4 -4 -1) (4 4 3)` | estatica |
| `scifi_lights/SciFiRecessedFloorLightV2.tscn` | **si** | `light_recessed_floor` | `SciFiWorkLightV2.gd` | 26 | si | 0.30 x 0.10 x 0.30 | `(-3 -3 -1) (3 3 3)` | estatica |
| `scifi_lights/SciFiRecessedWallLightV2.tscn` | **si** | `light_recessed_wall` | `SciFiWorkLightV2.gd` | 26 | si | 0.40 x 0.25 x 0.11 | `(-2 -4 -2) (3 4 2)` | estatica |
| `scifi_lights/SciFiWallSconceV2.tscn` | **si** | `light_wall_sconce` | `SciFiWorkLightV2.gd` | 26 | si | 0.50 x 0.95 x 0.57 | `(-3 -4 -8) (7 4 8)` | estatica |
| `scifi_lights/SciFiWorkLightTripodV2.tscn` | **si** | `light_work_tripod` | `SciFiWorkLightV2.gd` | 26 | si | 1.55 x 2.53 x 1.46 | `(-10 -13 -1) (14 13 40)` | estatica |
| `scifi_lights/SciFiWorkLightV2.tscn` | **si** | `light_work` | `SciFiWorkLightV2.gd` | 26 | si | 0.70 x 1.10 x 0.70 | `(-6 -6 0) (6 6 18)` | estatica |
| `scifi_lights/SearchLightV2.tscn` | no | — | `SearchLightV2.gd` | 33 | si | 1.00 x 0.70 x 1.00 | — | estatica |
| `scifi_lights/SecurityCameraV2.tscn` | no | — | `SecurityCameraV2.gd` | 28 | si | 0.60 x 0.35 x 0.73 | — | estatica |
| `scifi_lights/TrackerBase.tscn` | no | — | `TrackerBase.gd` | 24 | si | - | — | SIN MEDIR |
| `signage/AreaInfoScreen.tscn` | no | — | `AreaInfoScreen.gd` | 10 | — | 1.15 x 0.85 x 0.08 | — | estatica |
| `signage/FloorLabel.tscn` | no | — | `SignagePanel.gd` | 26 | — | 1.20 x 0.72 x 0.04 | — | estatica |
| `signage/HangingSign.tscn` | no | — | `SignagePanel.gd` | 26 | — | 1.20 x 0.72 x 0.04 | — | estatica |
| `signage/SignagePanel.tscn` | no | — | `SignagePanel.gd` | 26 | — | 1.20 x 0.72 x 0.04 | — | estatica |
| `signage/WallSign.tscn` | no | — | `SignagePanel.gd` | 26 | — | 1.20 x 0.72 x 0.04 | — | estatica |
| `transit/TransitPod.tscn` | no | — | `TransitPod.gd` | 2 | — | 3.00 x 5.40 x 5.00 | — | estatica |
| `transit/TransitStation.tscn` | no | — | `TransitStation.gd` | 12 | si | 4.00 x 4.00 x 1.55 | — | estatica |
| `tube/TubeAirlock.tscn` | no | — | `TubeAirlock.gd` | 3 | — | 7.20 x 7.20 x 2.50 | — | estatica |
| `tube/TubeRing.tscn` | no | — | — | 0 | — | 5.40 x 0.15 x 5.40 | — | estatica |
| `tube/TubeSection.tscn` | no | — | — | 0 | — | 8.00 x 9.00 x 8.00 | — | estatica |
| `tube/TubeZeroGravityZone.tscn` | no | — | `ZeroGravityZone.gd` | 6 | — | 60.00 x 8000.00 x 60.00 | — | vivo |

## Point classes de logica pura (`script_class`, sin `.tscn`)

Anclas invisibles de los sistemas del laboratorio. No tienen escena: son scripts que
extienden `Spatial` y Qodot les crea un `QodotEntity` y les pega el script. El level
designer las planta como marcador y la geometria de la sala son los brushes de
alrededor.

| classname | script | properties expuestas | size AABB quake |
|---|---|---:|---|
| `pipe_coolant_run` | `core_v2/props/pipe/PipeCoolantRun.gd` | 7 | `` |
| `sys_coolant_leak` | `core_v2/systems/cryo/CoolantLeak.gd` | 7 | `(-8 -8 -8) (8 8 8)` |
| `sys_leak_patch_point` | `core_v2/systems/cryo/LeakPatchPoint.gd` | 2 | `(-8 -8 -8) (8 8 8)` |
| `sys_pressure_section` | `core_v2/systems/atmosphere/PressureSection.gd` | 8 | `(-8 -8 -8) (8 8 8)` |
| `sys_purge_dial` | `core_v2/systems/atmosphere/PurgeDial.gd` | 3 | `(-8 -8 -8) (8 8 8)` |

Mas una brush entity: `pipe_coolant_run` (`PipeCoolantRun.gd`, `SolidClass`,
`node_class = StaticBody`), que aplica el shader de flujo a la geometria del propio
brush. Funciona porque `apply_properties` corre **despues** de `apply_entity_meshes`:
los setters de `flow_speed`/`flow_intensity` vuelven a llamar a `_apply()` cuando las
`MeshInstance` del brush ya son hijas del nodo. Si se lo usara como point class con
scene_file no funcionaria: el script recorre sus hijos, y Qodot no anida point
entities entre si.

## Props deliberadamente fuera del FGD

68 de los 123 `.tscn` no se exponen. Agrupados por motivo:

| motivo | props |
|---|---|
| **UI / HUD, no van en el mundo 3D** | `DebugConsoleHUD`, `HelmetHUD`, `HelmetFlashlight`, `DataSlate` |
| **Piezas internas de otro prop** | `AirlockShell`, `ElevatorDoor`, `ElevatorPropBase`, `plasma_particles`, `TrackerBase`, `IndustrialCagedSconceBMesh`, `ElevatorFloorSelector` |
| **Generados por un streamer, no se plantan a mano** | los 10 `Scaffold*` restantes (los coloca `ScaffoldStreamController` / el WFC), `TubeRing`, `TubeSection`, `TubeAirlock` (los coloca `DuctMazeStreamer`), los 4 `Criopod*` (`RadialScatter`) |
| **Escenas de prueba, no assets** | `CircuitExample`, `CircuitTestScene`, `MaintenanceElevatorTest`, `SteelPlateStack` |
| **Zonas: van como brush `trigger`, no como punto** | `ZeroGravityZone`, `TubeZeroGravityZone` |
| **Sin revisar todavia** | `CheckpointConsole`, `Manometer`, `LeverV2`, `TableTerminal`, `WallTerminal`, `BrokenFloorPanel`, `SteelPlate`, `WarningBarrier`, `AirlockContainerChamber`, `MaintenanceElevator`, `FireEmitter`, `FrostEmitter`, `PlasmaExhaust`, los 6 de `helmet_view/`, `ConveyorCarrousel`, `RetractableBridge`, `SearchLightV2`, `SecurityCameraV2`, `Industrial_Cage_Sconce`, `Industrial_Caged_Sconce`, los 5 de `signage/`, `TransitPod`, `TransitStation`, `CircuitCable` |

Los de "sin revisar" son candidatos legitimos: exponerlos es mecanico (medida ya
tomada en la tabla de arriba) y solo falta curar que `export` mostrar en TrenchBroom.

Dos casos que **no** se pueden exponer tal cual:

- **`RoomDialsPanel`** (`core_v2/things/RoomDialsPanel.gd`) extiende `Control`. Es UI
  2D que vive dentro del viewport de `DomeIntroCryoDiagnosticsUI.tscn`, no un nodo del
  mundo. No hay forma de plantarlo en TrenchBroom.
- **`PurgeTuner`** (`core_v2/props/controls/PurgeTuner.gd`) no tiene `.tscn`: su
  geometria esta escrita inline como hijos CSG dentro de `AtmoStation.tscn`. Como
  `script_class` quedaria invisible y sin colisionador, o sea no interactuable.
  Exponerlo pide antes extraer un `core_v2/props/controls/PurgeTuner.tscn`; es trabajo
  de prop, no de tooling, y quedo fuera de alcance.

## Cableado a circuitos

Las 59 point classes propias heredan ahora `Targetname` y `Target`, que antes no
emitian nada (`targetname` estaba declarado como `null`, y `build_def_text()` descarta
las properties sin valor; `Target` directamente tenia `class_properties` vacio).

La unica excepcion es **`sys_purge_dial`**, que hereda solo `Targetname`: su script
exporta `target: float` (el valor objetivo del dial) y la property `target` del FGD se
lo pisaria con `""`. Es el unico choque de nombres del proyecto — se verificaron
tambien `targetname`, `angle`, `angles`, `mangle`, `origin`, `classname`, `scale` y
`rotation` contra los export de los 123 props, sin colisiones.

`tools/qodot_wiring_smoke.gd` + `maps/tests/qodot_wiring_smoke.map` construyen un mapa
de verdad y verifican que un boton con `target` queda conectado a su ventilador y que
un ventilador sin `target` no queda conectado a nada.

## Bugs de integracion

### Arreglados (eran bloqueantes para exponer `target`)

Ambos en `addons/qodot/src/nodes/qodot_map.gd`. No se toco `LogicCircuitManager`.

1. **`target` vacio cableaba el mapa entero contra si mismo.** `apply_properties`
   inyecta los defaults del FGD en toda entidad, asi que con `target` declarado en la
   base class *todas* llegaban con `target == ""`, y `get_nodes_by_targetname("")`
   devolvia *todas* las entidades. Guarda agregada en `get_nodes_by_targetname` (un
   solo punto: lo llaman tres sitios).
2. **Apuntar a un prop instanciado reventaba.** `connect_signal` leia
   `target_node.properties['classname']` a ciegas, pero la raiz de un `.tscn` de prop
   no es un `QodotEntity` y no tiene `properties`. Ademas el cableado directo solo
   entendia la señal `trigger`; ahora tambien acepta el par
   `activated`/`deactivated` -> `set_active(bool)`, que es el contrato real de
   `InteractableBaseV2` y el mismo que consume `LogicCircuitManager`.

3. **Qodot emitia tokens de TrenchBroom obsoletos en `GameConfig.cfg`.** TrenchBroom
   renombro *texture* -> *material* en el `.cfg` version 9, y con el token viejo
   rechaza el archivo entero: *"Failed to load game configuration file
   Odisea/GameConfig.cfg: Unexpected smart tag match type 'texture'"*. Dos lugares en
   `trenchbroom_game_config_folder.gd`: `get_match_key(0)` devolvia `"texture"` en vez
   de `"material"`, y `parse_tags` escribia la clave `"texture":` en vez de
   `"material":`. El `base_text` del mismo archivo ya usaba el bloque `"materials"`
   nuevo, o sea que a este fork le faltaron estos dos. Verificado contra los 13
   `games/*/GameConfig.cfg` que trae TrenchBroom: los unicos `match` validos son
   `classname`, `contentflag`, `material`, `surfaceflag` y `surfaceparm`, y las unicas
   claves son `attribs`, `flags`, `match`, `material`, `name` y `pattern`.

### Reportados, sin tocar

4. **`LogicCircuitManager` no puede direccionar entidades de TrenchBroom.**
   `CircuitGraphResource` resuelve cada nodo `PROP` con
   `get_node_or_null(scene_path)`, pero Qodot nombra las entidades
   `entity_<indice>_<classname>` (`qodot_map.gd:785`), no por `targetname`. El indice
   depende del orden de las entidades en el `.map`, o sea que mover un brush en
   TrenchBroom puede renumerar todo y romper el grafo en silencio.
   *Arreglo sugerido, no aplicado:* que `build_entity_nodes` use el `targetname` como
   nombre del nodo cuando existe, y que el grafo se guarde contra ese nombre. Toca
   nombres de nodo de mapas ya construidos, asi que es un cambio que hay que decidir,
   no colar.
5. **`target_source` / `target_destination` nunca se emiten.** En
   `qodot_fgd_class.gd`, las ramas `value is NodePath` y `value is Object` fijan
   `prop_type` pero no `prop_val`, y el `if (prop_val)` de mas abajo las descarta. Por
   eso `targetname`/`target` se declaran aca como `string`: funciona igual para el
   cableado, pero TrenchBroom no dibuja las lineas de enlace entre entidades. Arreglo
   upstream de cuatro lineas; no se aplico para no cambiar el parseo del `.fgd` sin
   poder verificarlo a ojo en el editor.

## Texturas, materiales y shaders

### Como quedo organizado

```
textures/                       <- base_texture_dir de QodotMap: el namespace que ve TrenchBroom
  special/clip.png              <- brush solido invisible  (brush_clip_texture)
  special/skip.png              <- cara no renderizada     (face_skip_texture)
  kenney_prototype_textures/    <- el grueso del mundo actual (dark, light, purple, red, green, orange)
  prototype_textures/           <- colores planos de bloqueo
  trenchbroom/                  <- texturas propias con override de material
  _templates/                   <- plantillas .tres para copiar, no las usa ninguna cara

materials/                      <- libreria de materiales de los PROPS (se cargan por ruta
                                   desde los scripts). Qodot no la mira nunca.
shaders/                        <- pack psx_lit*/psx_unlit* + post-proceso
```

La distincion que importa: `textures/` es el namespace de Qodot —un `.png` ahi es un
nombre que TrenchBroom puede pintar en una cara, y un `.tres` con el mismo nombre es
su override de material. `materials/` es otra cosa: la libreria de los props, que se
carga por ruta desde GDScript.

### Cambios aplicados

- **`special/clip` y `special/skip` no existian.** Los cinco `QodotMap` del proyecto
  ya los declaraban en `brush_clip_texture` / `face_skip_texture`, pero no habia
  archivo, asi que el flujo de clip/skip nunca fue usable. Creados como PNG de 64x64
  con rayas diagonales (magenta y cian) para que se reconozcan de un vistazo en el
  browser de TrenchBroom. Se agrego tambien `special/trigger.png` (verde), que es el
  material que el tag Trigger aplica al activarse y que no existia. Son los tres
  unicos binarios nuevos del trabajo.
- **10 texturas tenian espacios en el nombre** (`blue 1.png`, `Green 2.png`,
  `Grey 2.png`, `purple 3.png`, ...). Qodot no lee nombres con espacios. Renombradas a
  `snake_case`.
- **`interior_a.map` estaba roto**: pedia `prototype_textures/gray` y el archivo se
  llamaba `Grey.png`. El renombrado a `gray.png` lo repara.
- **`steel_grate` estaba suelta en la raiz de `textures/`.** Movida a
  `textures/trenchbroom/` junto a su override, y las 36 caras de `box.map`
  reapuntadas.
- **Tags de TrenchBroom cableados.** `trenchbroom_game_config.tres` tenia `brush_tags`
  y `face_tags` vacios aunque los cuatro recursos existian. Ahora incluye Detail,
  Trigger, Clip y Skip; los patrones de clip/skip se corrigieron de `clip`/`skip` a
  `special/clip`/`special/skip`, que es el nombre real de la textura, y el material del
  tag Trigger de `trigger` a `special/trigger`.
- **`GameConfig.cfg` se instala ahora desde consola** con
  `tools/qodot_export_trenchbroom_config.gd`; antes solo salia por el pseudo-boton del
  editor y el instalado tenia los tags vacios.

### Colecciones de textura y plantilla de mapa nuevo

TrenchBroom habilita las colecciones **por mapa** (property `_tb_textures` del
worldspawn), asi que ninguna carpeta nueva aparecia sola:

- Se agregaron las colecciones faltantes a los 11 `.map` del repo. Ninguno tenia
  `textures/special`; a la mitad le faltaba tambien `kenney_prototype_textures/orange`
  y `textures/trenchbroom`; `interior_a.map` solo tenia `prototype_textures`. Se sumo,
  no se saco nada.
- Se agrego `maps/templates/initial_valve.map`, que TrenchBroom copia en `File > New`
  (`GameConfig.cfg` ya lo declaraba como `initialmap` y el archivo no existia). Es una
  sala hueca con las nueve colecciones ya habilitadas.
- La coleccion raiz `textures` quedo **vacia** al mover `steel_grate.png` a
  `textures/trenchbroom/`. Sigue habilitada en los mapas que la listaban; no muestra
  nada y es inofensiva.

### Icono en la lista de juegos

`assets/odisea_icon.jpg` es una imagen de 640x640 sin canal alfa, y el exportador la
guardaba como PNG **RGB** (colortype 2), mientras que los 13 `Icon.png` que trae
TrenchBroom son 32x32 **RGBA**. Ahora se convierte a `FORMAT_RGBA8` antes de guardar.

Dicho eso: la imagen en si es oscura (luminancia media 46/255) y a 32x32 queda como un
borron. Los cuatro candidatos del proyecto —`odisea_icon.png`, `odisea_icon2.png`,
`odisea_icon.jpg` y el icono de Android— son la misma imagen con el mismo problema. Si
se quiere un icono legible hace falta arte especifico; no se invento aca.

### Brushes con winding invertido

`maps/interior_a.map` venia roto desde el commit
`01d3f217`: los 3 puntos de cada plano de su unico brush estaban en el winding
contrario, asi que el volumen quedaba vacio. Qodot decia "Build complete" y generaba
**cero** `MeshInstance`, sin ninguna queja. Regenerado con el winding de `box.map`;
ahora genera geometria.

`tools/qodot_build_smoke.gd` construye los 12 `.map` y falla si alguno tiene brushes y
cero mallas. Es el unico chequeo que detecta esto, y se verifico contra la version
rota original.

### Auto-PBR

**Ninguna textura tiene hoy variantes `_normal` / `_metallic` / `_roughness` / `_ao` /
`_emission` / `_depth`.** Las 101 texturas de `textures/` son albedo plano. El flujo
Auto-PBR de Qodot esta disponible y documentado en el pipeline, pero no hay material
al que aplicarselo sin generar mapas nuevos, que seria agregar assets.

### psx_lit sobre brushes: decision pendiente de arte

Los brushes se construyen hoy con el `default_material` de cada `QodotMap`, que es un
`SpatialMaterial` con AO. Poner un override `psx_lit` sobre, por ejemplo,
`kenney_prototype_textures/purple/texture_11` le cambiaria el aspecto a las 2884 caras
que la usan en DomeTerrace y Dome_Crio de una sola vez. Eso es una decision de arte y
no se tomo aca.

Lo que si quedo listo para usar: `textures/_templates/psx_lit_brush.tres` y
`psx_lit_brush_transparent.tres`, con los seis `shader_param` del pack ya escritos.
Copiar, renombrar igual que el `.png` y apuntar `albedoTex`.

### Mapa textura -> material -> shader

| textura (`res://textures/<n>.png`) | caras en .map | override de material | variantes Auto-PBR | mapas |
|---|---:|---|---|---|
| `kenney_prototype_textures/purple/texture_11` | 2884 | —(Auto-PBR) | — | DomeTerrace.map, Dome_Crio.map |
| `kenney_prototype_textures/dark/texture_04` | 1184 | —(Auto-PBR) | — | box.map, pathway.map |
| `kenney_prototype_textures/purple/texture_07` | 824 | —(Auto-PBR) | — | DomeFacade.map, DomeFacadeFD.map |
| `kenney_prototype_textures/dark/texture_07` | 625 | —(Auto-PBR) | — | DomeFacade.map, DomeTerrace.map, Dome_Basementd.map, box.map, crio.map, machine_room.map, pathway.map, qodot_wiring_smoke.map |
| `kenney_prototype_textures/light/GuardrailTranslucent` | 270 | `SpatialMaterial` | — | Dome_Basementd.map, box.map, crio.map, machine_room.map |
| `kenney_prototype_textures/red/texture_08` | 214 | —(Auto-PBR) | — | box.map, machine_room.map |
| `kenney_prototype_textures/dark/texture_01` | 194 | —(Auto-PBR) | — | box.map, machine_room.map, pathway.map |
| `kenney_prototype_textures/dark/texture_08` | 100 | —(Auto-PBR) | — | Dome_Crio.map, box.map, crio.map, machine_room.map |
| `kenney_prototype_textures/light/texture_03` | 98 | —(Auto-PBR) | — | DomeTerrace.map, crio.map |
| `kenney_prototype_textures/light/texture_06` | 52 | —(Auto-PBR) | — | Dome_Basementd.map, box.map |
| `kenney_prototype_textures/orange/texture_05` | 36 | —(Auto-PBR) | — | box.map, pathway.map |
| `prototype_textures/black` | 36 | —(Auto-PBR) | — | crio.map |
| `trenchbroom/steel_grate` | 36 | `SpatialMaterial` | — | box.map |
| `kenney_prototype_textures/dark/texture_03` | 30 | —(Auto-PBR) | — | box.map |
| `kenney_prototype_textures/orange/texture_09` | 30 | —(Auto-PBR) | — | Dome_Basementd.map |
| `kenney_prototype_textures/green/texture_11` | 24 | —(Auto-PBR) | — | box.map |
| `kenney_prototype_textures/red/texture_09` | 24 | —(Auto-PBR) | — | box.map, machine_room.map |
| `kenney_prototype_textures/dark/texture_05` | 13 | —(Auto-PBR) | — | box.map |
| `kenney_prototype_textures/dark/texture_02` | 12 | —(Auto-PBR) | — | box.map |
| `kenney_prototype_textures/purple/texture_08` | 12 | —(Auto-PBR) | — | crio.map |
| `kenney_prototype_textures/dark/texture_06` | 10 | —(Auto-PBR) | — | box.map |
| `kenney_prototype_textures/dark/texture_12` | 10 | —(Auto-PBR) | — | box.map |
| `prototype_textures/gray` | 6 | —(Auto-PBR) | — | interior_a.map |
| `special/skip` | 5 | —(Auto-PBR) | — | qodot_wiring_smoke.map |
| `kenney_prototype_textures/orange/texture_08` | 2 | —(Auto-PBR) | — | box.map |
| `kenney_prototype_textures/dark/texture_09` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/dark/texture_10` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/dark/texture_11` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/dark/texture_13` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_01` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_02` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_03` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_04` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_05` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_06` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_07` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_08` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_09` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_10` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_12` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/green/texture_13` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_01` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_02` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_04` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_05` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_07` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_08` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_09` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_10` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_11` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_12` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/light/texture_13` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_01` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_02` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_03` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_04` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_06` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_07` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_10` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_11` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_12` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/orange/texture_13` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_01` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_02` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_03` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_04` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_05` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_06` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_09` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_10` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_12` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/purple/texture_13` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_01` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_02` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_03` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_04` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_05` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_06` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_07` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_10` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_11` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_12` | 0 | —(Auto-PBR) | — | — |
| `kenney_prototype_textures/red/texture_13` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/Orange` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/blue_1` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/blue_2` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/blue_3` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/gray_2` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/green_1` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/green_2` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/green_3` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/pink` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/purple_1` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/purple_2` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/purple_3` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/red` | 0 | —(Auto-PBR) | — | — |
| `prototype_textures/yelow` | 0 | —(Auto-PBR) | — | — |
| `special/clip` | 0 | —(Auto-PBR) | — | — |
| `trenchbroom/metal_fence_panel` | 0 | `SpatialMaterial` | — | — |
| `trenchbroom/steel_grate_platform` | 0 | `SpatialMaterial` | — | — |
| `trenchbroom/steel_grate_shadow` | 0 | `SpatialMaterial` | — | — |

`maps/autosave/` queda como esta: son copias de respaldo de TrenchBroom, no assets, y
todavia mencionan el nombre viejo `steel_grate`.

## Pendientes

1. Decidir el punto 4 de la seccion de bugs: nombrar las entidades por `targetname`
   para que `CircuitGraphResource` pueda direccionarlas de forma estable. Sin eso, un
   circuito armado en TrenchBroom sigue siendo fragil.
2. Extraer `PurgeTuner.tscn` de `AtmoStation.tscn` y exponerlo.
3. Exponer los props marcados "sin revisar" en la tabla de arriba.
4. Decidir si el pack `psx_lit` se aplica a los brushes del mundo.
5. `SparkEmitterV2`, `plasma_particles` y `TrackerBase` conservan cajas puestas a
   mano; si alguna vez tienen geometria, `qodot_audit_props.gd` las va a medir solo.
