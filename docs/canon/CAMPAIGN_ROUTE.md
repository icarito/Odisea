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

3. **`Dome_Intro_Hangar.tscn` → `RingHub_Level.tscn`** *(punto de inserción MagRail)*
   - **Productor actual:** `Exit/Airlock_Exit/AirlockZoneV2` en `Dome_Intro_Hangar.tscn` (`target_scene = "res://core_v2/levels/RingHub_Level.tscn"`, `target_spawn_id = "from_dome_intro_hangar"`, `target_airlock_path = NodePath("Hub/Airlock_FromHangar")`).
   - **Buffer físico:** cámara de esclusa `AirlockChamber` (puerta doble en origen y destino `Hub/Airlock_FromHangar`) + `AirlockManager.notify_transition` + `_pre_position_at_destination` desde el frame 0.
   - **Transición:** `"transition": "seamless"` (sin fade ni corte de BGM).
   - **Llegada:** `Hub/Airlock_FromHangar` (y respaldo `Hub/Spawn_FromHangar`, `spawn_id = "from_dome_intro_hangar"`). `RingHubWakeup` detecta la llegada por spawn y omite el encierro en `Criopod_Vert`.
   - **Punto de inserción futuro (pista D / MagRail):** `Exit/Airlock_Exit` de `Dome_Intro_Hangar.tscn` se reemplazará/enlazará con el tramo MagRail por el brazo centrífugo antes de desembocar en `RingHub_Level.tscn`.

4. **`RingHub_Level.tscn` → `MachineBay.tscn`**
   - **Guía:** al activar `Hub/PedestalLight` (encender las luces del domo), `RingHubLightState._notify_suit_lights_restored()` invoca al `ProgrammerHoloNPC` y lo dirige a la boca del conector real (`Hub/BayConnector`).
   - **Productor:** `Hub/BayConnector/AirlockTrigger` (`BayAirlockTrigger.gd`) → `RingHubLightState.enter_machine_bay()`.
   - **Buffer físico:** túnel radial `RingHubBayConnector` (`WindTunnelV2` + `IrisDoorV2`).
   - **Transición:** `"transition": "seamless"` vía `AirlockManager.notify_transition`.
   - **Atajos de debug:** `Hub/PedestalMachineBay` y `Hub/PedestalBayVertical` quedan desactivados y ocultos detrás de `RingHubLightState.debug_pedestals_enabled` (`false` por defecto).

5. **`MachineBay.tscn` → `BayVertical.tscn` → Salida por la cima** *(pistas paralelas)*
   - `MachineBay` (corredor de parkour) → `BayVertical` (bahía radial centrífuga, spawn `bay_vertical_entry`): cableado por pista `src-61`.
   - `BayVertical` → salida por la cima: cableado por pista `src-57`.

## 2. Flags relevantes

| Flag | Ubicación | Valor en línea principal | Propósito |
|---|---|---|---|
| `maintenance_override_enabled` | `DomeSystemDirector.gd` | `true` | Permite abrir el descenso de mantenimiento sin completar los 4/4 puzles de redes (rollback a `false`). |
| `debug_pedestals_enabled` | `RingHubLightState.gd` | `false` | Oculta y desactiva `PedestalMachineBay` y `PedestalBayVertical` en la línea principal; `true` los habilita para debug. |

## 3. Verificación automatizada

El test `core_v2/tests/test_campaign_route.gd` recorre el grafo real desde `Menu.FIRST_GAME_SCENE` y verifica que todas las escenas requeridas de la línea principal sean alcanzables y que todo `target_scene` y `target_spawn_id` exista.
