extends Spatial
class_name LeakPatchPoint

# LeakPatchPoint.gd - Spatial node representing a coolant pipe fissure (FD-264 §3 / FD-266).
# Emits visual damage parameter to pipe shader, controls associated CoolantLeak,
# and supports firm vs provisional gloo patching based on branch pressure at application time.

export(NodePath) var leak_path: NodePath
export(NodePath) var target_pipe_run_path: NodePath
export(NodePath) var manometer_path: NodePath
export(NodePath) var flow_adapter_path: NodePath
export(float, 1.0, 120.0) var gloo_patch_duration: float = 15.0
export(float, 0.0, 10.0) var firm_patch_pressure_threshold: float = 0.2
export(String) var interaction_text := "Sellar fuga de refrigerante"
export(String) var interaction_title := "Fuga de Criorefrigerante"
export(String, MULTILINE) var interaction_description := "Aísla la línea y aplica espuma criogénica de sellado."
export(bool) var seal_group_on_interact := false

signal patch_applied()
signal patch_expired()

var is_interactable: bool = true

var _leak = null
var _pipe_run = null
var _manometer = null
var _flow_adapter = null

var _is_patched: bool = false
var _is_firm_patch: bool = false
var _patch_timer: float = 0.0


func _ready() -> void:
	add_to_group("gloo_patchable")
	add_to_group("interactable")
	add_to_group("replay_sync")

	_resolve_references()

	if _leak != null:
		if not _leak.is_connected("state_changed", self, "_on_leak_state_changed"):
			_leak.connect("state_changed", self, "_on_leak_state_changed")

	_update_pipe_visuals()

	# PERF: en Dome_Intro hay ~24 LeakPatchPoint y solo se parchan los que el jugador
	# realmente repara — _physics_process no hace nada salvo que haya un parche
	# provisorio contando su timer (ver abajo). Arranca dormido; patch_with_gloo() lo
	# despierta si aplica un parche NO firme.
	set_physics_process(false)


func _resolve_references() -> void:
	if leak_path != null and not leak_path.is_empty():
		_leak = get_node_or_null(leak_path)
	if target_pipe_run_path != null and not target_pipe_run_path.is_empty():
		_pipe_run = get_node_or_null(target_pipe_run_path)
	if manometer_path != null and not manometer_path.is_empty():
		_manometer = get_node_or_null(manometer_path)
	if flow_adapter_path != null and not flow_adapter_path.is_empty():
		_flow_adapter = get_node_or_null(flow_adapter_path)


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	if _is_patched and not _is_firm_patch:
		_patch_timer += delta
		if _patch_timer >= gloo_patch_duration:
			_unpatch()


func get_interaction_prompt() -> String:
	if _is_patched and _is_firm_patch:
		return ""
	return interaction_text if interaction_text.strip_edges() != "" else "Sellar fuga de refrigerante"


func interact() -> void:
	if seal_group_on_interact:
		_seal_coolant_group()
	else:
		patch_with_gloo()


func _seal_coolant_group() -> void:
	_resolve_references()
	var director = get_node_or_null("/root/DomeSystemDirector")
	if director != null and director.has_method("is_beat_fired") and not bool(director.call("is_beat_fired", 1)):
		if director.has_method("request_first_power_attempt"):
			director.call("request_first_power_attempt")
	if _leak != null and "valve_path" in _leak and _leak.valve_path != null and not _leak.valve_path.is_empty():
		var valve = _leak.get_node_or_null(_leak.valve_path)
		if valve != null and "is_active" in valve and bool(valve.is_active) and valve.has_method("set_active"):
			valve.call("set_active", false, true)
	patch_with_gloo()
	var parent_node := get_parent()
	if parent_node != null:
		for sibling in parent_node.get_children():
			if sibling != self and sibling.is_in_group("gloo_patchable") and sibling.has_method("patch_with_gloo"):
				sibling.call("patch_with_gloo")


func patch_with_gloo() -> bool:
	_resolve_references()

	# Note: firm_patch_pressure_threshold is preserved for scene backward compatibility,
	# but is no longer used now that authority shifted from manometer pressure to flow adapter.
	var is_pressurized := true
	if _flow_adapter != null and _flow_adapter.has_method("is_pressurized_at") and _leak != null:
		is_pressurized = bool(_flow_adapter.call("is_pressurized_at", _leak))
	elif _leak != null and _leak.has_method("is_depressurized"):
		is_pressurized = not bool(_leak.call("is_depressurized"))

	var applies_firmly := not is_pressurized

	if _is_patched:
		if applies_firmly:
			_is_firm_patch = true
			is_interactable = false
			set_physics_process(false)
			if _leak != null:
				_leak.seal()
		else:
			_patch_timer = 0.0 # Reset provisional patch duration on additional gloo hit
		return true

	_is_patched = true
	_is_firm_patch = applies_firmly
	_patch_timer = 0.0
	is_interactable = not _is_firm_patch

	if _leak != null:
		if _is_firm_patch:
			_leak.seal()
		else:
			_leak.set_provisionally_patched(true)

	_update_pipe_visuals()
	emit_signal("patch_applied")
	# Solo el parche PROVISORIO necesita contar _patch_timer cada frame; uno firme no
	# caduca solo (ver comentario de remove_patch()).
	set_physics_process(not _is_firm_patch)
	return true


func _unpatch() -> void:
	if not _is_patched:
		return

	_is_patched = false
	_is_firm_patch = false
	_patch_timer = 0.0
	is_interactable = true
	set_physics_process(false)

	if _leak != null:
		_leak.set_provisionally_patched(false)
		_leak.trigger_leak()

	_update_pipe_visuals()
	emit_signal("patch_expired")


# El gloo dejo de existir: lo destruyo el laser, o se disipo. La fisura vuelve a soltar.
# Sin esto quedaba tapada para siempre, porque desde FD-266 un parche firme ya no caduca
# solo y el timer de _physics_process es la unica otra salida.
func remove_patch() -> void:
	if not _is_patched:
		return
	var was_firm := _is_firm_patch
	_unpatch()
	# Un parche firme sella el cano de verdad (deja _has_been_sealed en la fuga), asi que
	# el trigger_leak() de _unpatch() rebota. Romper el parche a proposito no es lo mismo
	# que dejarlo degradar: hay que volver a abrir la averia.
	if was_firm and _leak != null:
		_leak.reset()
		_leak.trigger_leak()


func is_patched() -> bool:
	return _is_patched


func is_firmly_patched() -> bool:
	return _is_patched and _is_firm_patch


func get_patch_time_remaining() -> float:
	if not _is_patched or _is_firm_patch:
		return 0.0
	return max(0.0, gloo_patch_duration - _patch_timer)


func _on_leak_state_changed(_new_state: int) -> void:
	_update_pipe_visuals()


func _update_pipe_visuals() -> void:
	if _pipe_run == null:
		return
	var leak_intensity := 0.0
	if _leak != null and not _is_patched:
		leak_intensity = _leak.get_leak_intensity()

	# Reflect fissure damage or flow intensity adjustment on pipe run
	if leak_intensity > 0.0:
		_pipe_run.set_flow_intensity(max(0.2, 1.0 - leak_intensity * 0.5))
	else:
		_pipe_run.set_flow_intensity(1.0)


func get_snapshot() -> Dictionary:
	return {
		"is_patched": _is_patched,
		"is_firm_patch": _is_firm_patch,
		"patch_timer": _patch_timer,
		"gloo_patch_duration": gloo_patch_duration,
		"firm_patch_pressure_threshold": firm_patch_pressure_threshold
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("gloo_patch_duration"):
		gloo_patch_duration = float(data["gloo_patch_duration"])
	if data.has("firm_patch_pressure_threshold"):
		firm_patch_pressure_threshold = float(data["firm_patch_pressure_threshold"])
	if data.has("is_patched"):
		_is_patched = bool(data["is_patched"])
	if data.has("is_firm_patch"):
		_is_firm_patch = bool(data["is_firm_patch"])
	if data.has("patch_timer"):
		_patch_timer = float(data["patch_timer"])

	is_interactable = not (_is_patched and _is_firm_patch)
	_update_pipe_visuals()
