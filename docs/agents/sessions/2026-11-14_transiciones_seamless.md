# Transiciones seamless — bitácora de sesión, 2026-11-14

## Pedido

Sebastián: "las transiciones deberían ser todas completamente seamless. Nada de fade a negro, pantallas de carga ni cortes de cámara entre áreas."

La sesión fue coordinada por src-49, que envió una referencia clave: *"el prototipo de la transición casi perfecta deseada la hace el airlock"* y pidió identificar cuál, documentar su flujo exacto, qué le falta (el "casi"), y generalizar ese patrón a `SceneManager` para migrar el resto de transiciones.

## Referencia: el airlock "casi perfecto"

Después de leer el código y el git log, la referencia es el **airlock de Dome_Crio ↔ OdiseaExterior** (`AirlockZoneV2` + `AirlockManager` + `IrisDoorV2` + Pilot horneado), el único camino que hoy hace un **swap seamless real de escena**: el jugador entra a la cámara sellada, las puertas se cierran, la escena destino se precarga, y al cruzar el umbral `AirlockManager` levanta al jugador a `/root` (la cámara sigue viva), `SceneManager` agrega la escena nueva antes de liberar la vieja (add-before-free) y el jugador reaparece en el airlock espejo con pose/velocidad relativas.

`AirlockZoneV2` ya hace esto pasando `transition:"none"` + `notify_transition`: sin fade, sin cartel. El **"casi"** (lo que le faltaba para ser perfecto):

1. **Audio**: el camino `transition:"none"` no corta el fade, pero `SceneManager` seguía ejecutando `fade_out_current_bgm()` (fade-out de 0.35s de la BGM) y luego refrescaba al llegar — un corte perceptible de música en el cruce. El modo `"seamless"` nuevo elimina el fade-out y refresca la zona de BGM del destino con `0s` (cruce sin hueco).
2. **No era generalizable a los demás productores**: portal/tubo/tránsito/bahía/hangar no usaban el lift ni el modo sin-fade; cada uno tenía su fade propio.
3. **El disparo determinista**: cualquier espera por loader asíncrono como gate de disparo rompe el replay (drift medido ~1–2 cm contra umbral de 1 cm). El airlock real lo resuelve esperando en `_physics_process` con `_scene_ready` (determinista).

El airlock del laberinto de ductos con `standalone_cycle=true` es el prototipo del **buffer físico puro** (ciclo local puertas/presurización sin cambio de escena), pero no hace swap; no es la referencia del swap.

## Inventario de transiciones del slice (verificado sobre origin/main en 2026-11-14)

| # | Transición | Productor | Cómo era | Estado nuevo |
|---|---|---|---|---|
| 1 | Boot → Menu | `BootLoader.gd` | loading + fade 0 (boot) | **No seamless (reportado)** — sin mundo previo |
| 2 | Menu → RingHub/Dome_Intro (Nueva partida/Continuar) | `Menu.gd` | fade del menú (0.85s) + loading | **No seamless (reportado)** — frontera UI→mundo |
| 3 | RingHub ↔ MachineBay | `RingHubLightState` / `MachineLevel.gd:526` | fade (default) + lift automático del par | **Seamless por auto-upgrade**; MachineLevel debe declarar `transition:"seamless"` (cambio reportado a src-51) |
| 4 | Dome_Crio ↔ OdiseaExterior | `AirlockZoneV2` | seamless (reference) pero con fade-out de BGM | **Seamless completo** (mode `"seamless"` + sin corte de audio) |
| 5 | Dome → Hangar (#407) | `HangarTransition.gd` | fade + spawn | **Pendiente** — productor fuera de alcance (se reporta API) |
| 6 | Tubos peatonales | `TubeAirlock.gd` | fade 0.5 | **Seamless (migrado)** |
| 7 | Airlock de la bahía (fallback) | `BayAirlockTrigger.gd` | fade | **Seamless (migrado fallback)**; primario va por RingHubLightState |
| 8 | Portales genéricos (estilo airlock) | `TransitionPortal.gd` | ciclo airlock + fade | **Seamless (migrado)** cuando AirlockManager presente |
| 9 | Cápsula de tránsito | `TransitSystem.gd` | fade 1.0 + "VIAJANDO A" | **Seamless** si AirlockManager presente (targets legacy no existen en slice) |

## Mecanismo común (extiende SceneManager)

- Nuevo modo `transition:"seamless"`: sin fade, sin cartel de carga, sin `fade_out_current_bgm`; al llegar refresca BGM de zonas con `0s`.
- **Auto-upgrade**: si el AirlockManager está armado (`notify_transition` ya llamado por el productor o por la heurística hub↔bahía) y el productor no declaró `transition` explícito, la transición se convierte en seamless. Así el par hub↔bahía deja de fadear sin tocar a MachineLevel/RingHubLightState.
- El lift y el swap add-before-free siguen siendo propiedad de `AirlockManager`; `"seamless"` exige el lift (si no, cae al camino legacy).
- **Determinismo**: gates de disparo en `_physics_process`; sin esperas asíncronas como gate (ver `TubeAirlock`).

## Archivos modificados

| Archivo | Cambio |
|---|---|
| `core_v2/autoloads/SceneManager.gd` | modo `"seamless"` (`_get_transition_mode`, `_should_use_fade`, `_should_show_loading`), `_maybe_upgrade_seamless()`, audio sin corte |
| `core_v2/autoloads/AirlockManager.gd` | sin cambios funcionales (solo se quitó instrumentación temporal) |
| `core_v2/components/TransitionPortal.gd` | estilo airlock arma `notify_transition` + `_seamless_params()` |
| `core_v2/props/tube/TubeAirlock.gd` | preload al entrar, puertas cerradas, disparo en `_physics_process`, params seamless, guard `is_transitioning` anti-rebote |
| `core_v2/props/tube/BayAirlockTrigger.gd` | fallback seamless |
| `core_v2/props/transit/TransitSystem.gd` | seamless si AirlockManager presente + preload durante viaje |
| `core_v2/tests/test_seamless_transitions.gd` | nuevo: helpers SceneManager, upgrade, params portal/tubo |
| `core_v2/tests/test_tube_airlock.oys` | ajustado al timing sin fade (un teleport + espera; ver abajo) |
| `.operator-shared/specs/seamless-transitions.md` | spec del contrato (nueva) |
| `docs/agents/sessions/2026-11-14_transiciones_seamless.md` | este doc |

Nota: `core_v2/props/machines/MachineLevel.gd` es de src-51 y **no** se tocó.

## Determinismo y el OYS de tube

El OYS `test_tube_airlock.oys` grababa con el camino fade (lento). Con el swap seamless instantáneo, el segundo `SET_POS` del script (que reposiciona en el airlock) caía **después** del swap y reenviaba al jugador al origen (assert `-4`). Se actualizó el OYS a un solo teleport al interior + espera de 2s (la aserción central — llegar a `SpawnPointEnd` — se conserva). Además, gatear el disparo esperando la precarga asíncrona rompía el replay (drift 0.011–0.023 > 0.01); se pasó el disparo a `_physics_process` sin espera (el preload se pide al entrar y el swap oculta la carga). PASS 1 + PASS 2 verdes.

## Tests ejecutados (puntuales, nunca suite completa)

- `pytest tests/test_odisea_runner.py -q -k 'seamless or transition_portal or airlock'` → 5 passed.
- `pytest tests/test_odisea_runner.py -q -k 'transition or test_machine_bay or test_menu_checkpoint_flow or airlock'` → **15 passed** (incluye test_seamless_transitions).
- `./runtest.sh --oys test_tube_airlock` → PASSED (ambos passes).
- `./runtest.sh --oys test_dome_crio_airlock_return` → PASSED (ambos passes) — referencia intacta.

## Chequeos visuales pendientes (no se pueden hacer headless)

- Confirmar en juego (desktop o device) que RingHub↔MachineBay y el descenso domo→hangar se ven continuos; el auto-upgrade eliminó el fade del par hub↔bahía (antes lo tapaba).
- Menú→primera escena y boot siguen con fade/loading a propósito (reportado).
- Tier low/Anbernic: costo de precargar (memoria) — pendiente de medir en hardware.

## Reporte para src-51 (MachineLevel.gd:526)

Cambio exacto requerido en `return_to_ring_hub` (ver spec §7):

```gdscript
var airlock_manager = get_node_or_null("/root/AirlockManager")
var params := {
    "preserve_player_state": false,
    "ringhub_return_state": _ringhub_return_state.duplicate(true),
    "state_data": {"player_snapshot": _ringhub_return_state.get("player_snapshot", {})}
}
if airlock_manager != null and airlock_manager.has_method("notify_transition"):
    airlock_manager.notify_transition(target_scene)
    params["transition"] = "seamless"
scene_mgr.goto_scene(target_scene, params)
```

`RingHubLightState.enter_machine_bay` ya arma `notify_transition`; agregar `"transition": "seamless"` al payload lo hace explícito.
