extends GdUnitTestSuite

# FD-320 (O20) — regresión del reenvío del payload de retorno anillo <-> bahía.
#
# Camino aprobado (ordinary path) cubierto acá:
#   hub  -> bahía : RingHubLightState.enter_machine_bay() arma
#                   {wakeup, light_state, player_snapshot} y lo pasa a goto_scene().
#   bahía -> hub  : MachineLevel.return_to_ring_hub() reenvía ese payload y agrega
#                   state_data.player_snapshot para el spawn de RingHub.
#
# La intercepción usa la COLA REAL del SceneManager: con _is_transitioning en true,
# goto_scene() encola en _pending_scene_path / _pending_transition_params en vez de
# swapear la escena viva. No hay dobles falsos del manager ni cambio de escena real.
#
# NO cubierto a propósito (se reporta aparte): el fallback de entrada directa de
# desarrollador (la rama `get_tree().change_scene(...)` cuando no hay SceneManager),
# que exigiría un swap real de escena.

const MachineLevelScript = preload("res://core_v2/props/machines/MachineLevel.gd")
const RingHubLightStateScript = preload("res://core_v2/levels/RingHubLightState.gd")

const RING_HUB_SCENE_PATH := "res://core_v2/levels/RingHub_Level.tscn"
const MACHINE_BAY_SCENE_PATH := "res://core_v2/levels/machines/MachineBay.tscn"


# Hub falso: sólo expone el contrato que el productor consume
# (get_snapshot() + hijo "Pilot" con get_full_snapshot()).
class StubHub:
	extends Spatial
	var snapshot := {
		"selected_slot": 3,
		"gated_oys_script": "",
		"wakeup_completed": true,
	}

	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)


class StubPilot:
	extends Spatial
	var snapshot := {
		"position": [31.8, 3.0, 4.0],
		"velocity": [0.0, 0.0, 0.0],
		"yaw": 0.75,
		"pitch": -0.2,
		"base_spring_length_3d": 5.5,
		"movement_state": {"speed": 0.0, "on_floor": true},
	}

	func get_full_snapshot() -> Dictionary:
		return snapshot.duplicate(true)


func _return_payload() -> Dictionary:
	return {
		"wakeup": {"selected_slot": 3, "gated_oys_script": "", "wakeup_completed": true},
		"light_state": {"lit": true, "flicker_active": false, "flicker_clock": 0.0, "flicker_target": true},
		"player_snapshot": {
			"position": [31.8, 3.0, 4.0],
			"velocity": [0.0, 0.0, 0.0],
			"yaw": 0.75,
			"pitch": -0.2,
			"base_spring_length_3d": 5.5,
			"movement_state": {"speed": 0.0, "on_floor": true},
		},
	}


# --- Snapshot/restore de los autoloads tocados ------------------------------
# SceneManager: sólo se escribe la cola (_pending_*) y, para el caso de la bahía,
# _transition_params (de donde MachineLevel._ready() lee el payload). _is_transitioning
# se lee y se fuerza para interceptar; se restaura su valor original.
func _snapshot_scene_manager() -> Dictionary:
	var manager := get_node_or_null("/root/SceneManager")
	if manager == null:
		return {}
	return {
		"node": manager,
		"is_transitioning": manager._is_transitioning,
		"pending_scene_path": manager._pending_scene_path,
		"pending_transition_params": manager._pending_transition_params.duplicate(true),
		"transition_params": manager._transition_params.duplicate(true),
	}


func _restore_scene_manager(saved: Dictionary) -> void:
	if saved.empty():
		return
	var manager = saved["node"]
	manager._is_transitioning = saved["is_transitioning"]
	manager._pending_scene_path = saved["pending_scene_path"]
	manager._pending_transition_params = saved["pending_transition_params"].duplicate(true)
	manager._transition_params = saved["transition_params"].duplicate(true)


# GLES3VendorGate: MachineLevel._ready() -> _apply_flat_lighting() mueve estas palancas.
func _snapshot_gate() -> Dictionary:
	var gate := get_node_or_null("/root/GLES3VendorGate")
	if gate == null:
		return {}
	return {
		"node": gate,
		"flat_ambient": gate.get("_flat_ambient"),
		"world_light": gate.get("_world_light"),
		"glow_floor": gate.get("_glow_floor"),
	}


func _restore_gate(saved: Dictionary) -> void:
	if saved.empty():
		return
	var gate = saved["node"]
	gate.set("_flat_ambient", saved["flat_ambient"])
	gate.set("_world_light", saved["world_light"])
	gate.set("_glow_floor", saved["glow_floor"])


# --- Casos ------------------------------------------------------------------

# Bahía -> hub: el payload que recibió la bahía vuelve íntegro y con el snapshot del
# jugador expuesto además como state_data.player_snapshot.
func test_machine_bay_return() -> void:
	var manager := get_node_or_null("/root/SceneManager")
	assert_object(manager).is_not_null()
	if manager == null:
		return

	var manager_saved := _snapshot_scene_manager()
	var gate_saved := _snapshot_gate()

	var return_payload := _return_payload()

	# La bahía recibe el payload por el canal real de la transición.
	manager._transition_params = {"ringhub_return_state": return_payload.duplicate(true)}
	var level = MachineLevelScript.new()
	level.name = "MachineBayReturnRegression"
	# No arrastrar teleports/objetivos de campaña al agregar el nivel.
	level.enable_player_multi_tool = false
	get_tree().root.add_child(level)
	manager._transition_params = manager_saved["transition_params"].duplicate(true)

	# _ready() copió el payload (deep) desde el SceneManager.
	assert_dict(level._ringhub_return_state).is_equal(return_payload)

	# Intercepción: la cola real del SceneManager ya está ocupada, así que no hay swap.
	manager._is_transitioning = true
	assert_bool(manager._is_transitioning).is_true()
	assert_bool(manager.is_transitioning()).is_true()

	var saved_pending_path: String = manager._pending_scene_path
	level.return_to_ring_hub()

	# Escena destino real de retorno, sin transición en vivo.
	assert_str(manager._pending_scene_path).is_equal(RING_HUB_SCENE_PATH)
	var params: Dictionary = manager._pending_transition_params
	assert_int(params.size()).is_equal(4)
	assert_dict(params).contains_keys(
		["preserve_player_state", "wait_for_fade_out", "ringhub_return_state", "state_data"])
	assert_bool(bool(params.get("preserve_player_state", true))).is_false()
	assert_bool(bool(params.get("wait_for_fade_out", false))).is_true()

	# Payload anidado exacto.
	assert_dict(params.get("ringhub_return_state", {})).is_equal(return_payload)

	# state_data.player_snapshot == el snapshot del jugador del payload.
	var state_data: Dictionary = params.get("state_data", {})
	assert_dict(state_data).contains_keys(["player_snapshot"])
	assert_dict(state_data.get("player_snapshot", {})).is_equal(return_payload["player_snapshot"])

	# Deep copies independientes (contrato de duplicate(true)).
	var queued_payload: Dictionary = params["ringhub_return_state"]
	level._ringhub_return_state["wakeup"]["wakeup_completed"] = false
	assert_bool(queued_payload["wakeup"]["wakeup_completed"]).is_true()
	queued_payload["player_snapshot"]["movement_state"]["speed"] = 9.0
	assert_float(level._ringhub_return_state["player_snapshot"]["movement_state"]["speed"]).is_equal_approx(0.0, 0.0001)
	# La copia de state_data no comparte memoria con la de ringhub_return_state.
	queued_payload["player_snapshot"]["yaw"] = 3.5
	assert_float(state_data["player_snapshot"]["yaw"]).is_equal_approx(0.75, 0.0001)

	_restore_scene_manager(manager_saved)
	_restore_gate(gate_saved)
	assert_str(manager._pending_scene_path).is_equal(saved_pending_path)
	level.free()


# Hub -> bahía: RingHubLightState arma {wakeup, light_state, player_snapshot} con los
# snapshots reales (hub + sí mismo + Pilot) y lo encola sin cargar la escena de la bahía.
func test_machine_bay_return_ringhub_light_state_producer() -> void:
	var manager := get_node_or_null("/root/SceneManager")
	assert_object(manager).is_not_null()
	if manager == null:
		return

	var tree := get_tree()
	var manager_saved := _snapshot_scene_manager()
	var gate_saved := _snapshot_gate()
	var previous_scene: Node = tree.current_scene

	var hub := StubHub.new()
	hub.name = "RingHub_Level"
	var pilot := StubPilot.new()
	pilot.name = "Pilot"
	hub.add_child(pilot)
	tree.root.add_child(hub)
	tree.current_scene = hub

	var light_state = RingHubLightStateScript.new()
	light_state.name = "LightState"
	hub.add_child(light_state)

	manager._is_transitioning = true
	assert_bool(manager.is_transitioning()).is_true()

	light_state.enter_machine_bay()

	assert_str(manager._pending_scene_path).is_equal(MACHINE_BAY_SCENE_PATH)
	var params: Dictionary = manager._pending_transition_params
	assert_int(params.size()).is_equal(3)
	assert_dict(params).contains_keys(
		["preserve_player_state", "wait_for_fade_out", "ringhub_return_state"])
	assert_bool(bool(params.get("preserve_player_state", true))).is_false()
	assert_bool(bool(params.get("wait_for_fade_out", false))).is_true()

	var payload: Dictionary = params.get("ringhub_return_state", {})
	assert_dict(payload).is_equal({
		"wakeup": hub.get_snapshot(),
		"light_state": light_state.get_snapshot(),
		"player_snapshot": pilot.get_full_snapshot(),
	})

	# El payload encolado es una copia profunda, independiente del hub vivo.
	hub.snapshot["wakeup_completed"] = false
	assert_bool(payload["wakeup"]["wakeup_completed"]).is_true()

	tree.current_scene = previous_scene
	hub.free()
	_restore_scene_manager(manager_saved)
	_restore_gate(gate_saved)
