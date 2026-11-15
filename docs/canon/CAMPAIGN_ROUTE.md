# Ruta Principal de Campaña — Transit-Run (Vertical Slice)

Este documento describe la línea principal de progresión del jugador desde **Nueva partida**,
el mecanismo de transición, el buffer físico de cada tramo y los flags de configuración.

## 1. Orden de la línea principal

1. **Menú → `Dome_Intro.tscn`** (`Menu.FIRST_GAME_SCENE`)
   - **Spawn:** `Dome_Base/SpawnPointV2` (frente al criopod en `Dome_Intro`).
   - **Despertar:** beats de `DomeSystemDirector` (1–5) y reparación/bypass del domo.
   - **Transición:** UI → mundo (`fade` + pantalla de carga + warmup de shaders en `Menu.gd`).
   - **Buffer:** no hay mundo previo; ver `.operator-shared/specs/seamless-transitions.md` §6.
   - **Continuar:** `PersistenceManager` respeta el checkpoint (`last`) y la escena guardada.

2. **`Dome_Intro.tscn` → `Dome_Intro_Hangar.tscn`**
   - **Ruta principal:** ruta de mantenimiento (`DomeMaintenanceSeal` → `DomeSystemDirector.request_maintenance_override()` → `BlastDoorController.open_maintenance`).
   - **Atajo opcional:** reparar las 4/4 redes abre también el blast door (`blast_door_open`).
   - **Productor:** `HangarDescent/HangarTransition` (`target_scene` resuelto vía `DomeSystemDirector.get_hangar_scene()` = `res://core_v2/levels/interiors/Dome_Intro_Hangar.tscn`, `target_spawn_id` = `from_dome_intro_platform`).
   - **Buffer:** pozo del blast door y descenso por plataforma/rampa (`HangarPlatform`, precarga en `descend_started`).
   - **Transición:** `wait_for_fade_out: true` (deuda documentada en `seamless-transitions.md` §4 hasta contar con buffer de llegada equivalente).

3. **`Dome_Intro_Hangar.tscn` → `MagRailHangarToRingHub.tscn` → `RingHub_Level.tscn`**
   - **Productor en hangar:** `Exit/Airlock_Exit/AirlockZoneV2` en `Dome_Intro_Hangar.tscn` (enrutado por `Exit` / `HangarMagRailConnector.gd`: `target_scene = "res://core_v2/levels/MagRailHangarToRingHub.tscn"`, `target_spawn_id = "from_hangar"`, `target_airlock_path = NodePath("Airlock_FromHangar")`).
   - **Tramo MagRail (brazo centrífugo):** `MagRail_CentrifugalArm` con pasarela de respaldo continua (`Catwalk_Backup`) para no bloquear la línea principal, entrada seamless por `Airlock_FromHangar` y salida seamless por `Airlock_ToRingHub` (`target_scene = "res://core_v2/levels/RingHub_Level.tscn"`, `target_spawn_id = "from_dome_intro_hangar"`, `target_airlock_path = NodePath("Hub/Airlock_FromHangar")`).
   - **Fallback detrás de flag:** `HangarMagRailConnector.magrail_hangar_connector_enabled = false` restaura automáticamente el enlace directo `Airlock_Exit` → `RingHub_Level.tscn` (`Hub/Airlock_FromHangar`).
   - **Transición:** `"transition": "seamless"` en ambas fronteras (cámara de esclusa `AirlockChamber` + `AirlockManager.notify_transition` + `_pre_position_at_destination`).
   - **Llegada:** `Hub/Airlock_FromHangar` (y respaldo `Hub/Spawn_FromHangar`, `spawn_id = "from_dome_intro_hangar"`). `RingHubWakeup` detecta la llegada por spawn y omite el encierro en `Criopod_Vert`.

4. **`RingHub_Level.tscn` → `MachineBay.tscn`**
   - **Guía:** al activar `Hub/PedestalLight` (encender las luces del domo), `RingHubLightState._notify_suit_lights_restored()` invoca al `ProgrammerHoloNPC` y lo dirige a la boca del conector real (`Hub/BayConnector`).
   - **Productor:** `Hub/BayConnector/AirlockTrigger` (`BayAirlockTrigger.gd`) → `RingHubLightState.enter_machine_bay()`.
   - **Buffer físico:** túnel radial `RingHubBayConnector` (`WindTunnelV2` + `IrisDoorV2`).
   - **Transición:** `"transition": "seamless"` vía `AirlockManager.notify_transition`.
   - **Atajos de debug:** `Hub/PedestalMachineBay` y `Hub/PedestalBayVertical` quedan desactivados y ocultos detrás de `RingHubLightState.debug_pedestals_enabled` (`false` por defecto).

5. **`MachineBay.tscn` → `BayVertical.tscn` → Salida por la cima**
   - **Ruta en la bahía:** corredor de parkour a salto limpio (≤ 80 % del alcance, `WFC_FLOW_METRICS.md`); las 5 estaciones son Side Sockets opcionales.
   - **Productor:** `ExitLockTrigger` (fondo del `ExitPad`, en `machine_bay.json`) → `MachineLevel.enter_bay_vertical()`; sin compuerta de puzle. `VoiceExit` precarga el destino al pisar el `ExitPad`.
   - **Buffer físico:** esclusa `ExitLock*` (cámara cerrada con una sola boca).
   - **Transición:** `"transition": "seamless"` + `AirlockManager.notify_transition`, llegada por spawn `bay_vertical_entry`; reenvía `ringhub_return_state` para que la cima pueda volver al hub.
   - **Retorno opcional:** `ReturnHubButton` (pedestal del `ExitPad`) sigue volviendo a RingHub con fade.
   - `BayVertical` → salida por la cima (`ExitBuffer`, `completes_slice`) → `RingHub_Level.tscn`, spawn `bay_vertical_return`.

## 2. Flags relevantes

| Flag | Ubicación | Valor en línea principal | Propósito |
|---|---|---|---|
| `maintenance_override_enabled` | `DomeSystemDirector.gd` | `true` | Permite abrir el descenso de mantenimiento sin completar los 4/4 puzles de redes (rollback a `false`). |
| `magrail_hangar_connector_enabled` | `HangarMagRailConnector.gd` (`Dome_Intro_Hangar/Exit`) | `true` | Enruta la salida del hangar por el tramo MagRail (`MagRailHangarToRingHub.tscn`); `false` restaura el airlock directo a `RingHub_Level.tscn`. |
| `debug_pedestals_enabled` | `RingHubLightState.gd` | `false` | Oculta y desactiva `PedestalMachineBay` y `PedestalBayVertical` en la línea principal; `true` los habilita para debug. |

## 3. Verificación automatizada

El test `core_v2/tests/test_campaign_route.gd` recorre el grafo real desde `Menu.FIRST_GAME_SCENE` y verifica que todas las escenas requeridas de la línea principal sean alcanzables y que todo `target_scene` y `target_spawn_id` exista.
