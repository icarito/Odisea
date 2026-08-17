tool
extends Spatial
class_name LeakPatchPoint

# LeakPatchPoint.gd - Spatial node representing a coolant pipe fissure (FD-264 §3).
# Emits visual damage parameter to pipe shader, controls associated CoolantLeak,
# and supports temporary gloo patching with deterministic physics decay.

export(NodePath) var leak_path: NodePath
export(NodePath) var target_pipe_run_path: NodePath
export(float, 1.0, 120.0) var gloo_patch_duration: float = 15.0

signal patch_applied()
signal patch_expired()

var _leak = null
var _pipe_run = null
var _is_patched: bool = false
var _patch_timer: float = 0.0


func _ready() -> void:
	add_to_group("gloo_patchable")
	add_to_group("replay_sync")

	if leak_path != null and not leak_path.is_empty():
		_leak = get_node_or_null(leak_path)
	if target_pipe_run_path != null and not target_pipe_run_path.is_empty():
		_pipe_run = get_node_or_null(target_pipe_run_path)

	if _leak != null:
		if not _leak.is_connected("state_changed", self, "_on_leak_state_changed"):
			_leak.connect("state_changed", self, "_on_leak_state_changed")

	_update_pipe_visuals()


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	if _is_patched:
		_patch_timer += delta
		if _patch_timer >= gloo_patch_duration:
			_unpatch()


func patch_with_gloo() -> bool:
	if _is_patched:
		_patch_timer = 0.0 # Reset patch duration on additional gloo hit
		return true

	_is_patched = true
	_patch_timer = 0.0

	if _leak != null:
		_leak.seal()

	_update_pipe_visuals()
	emit_signal("patch_applied")
	return true


func _unpatch() -> void:
	if not _is_patched:
		return

	_is_patched = false
	_patch_timer = 0.0

	if _leak != null:
		_leak.trigger_leak()

	_update_pipe_visuals()
	emit_signal("patch_expired")


func is_patched() -> bool:
	return _is_patched


func get_patch_time_remaining() -> float:
	if not _is_patched:
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
		"patch_timer": _patch_timer,
		"gloo_patch_duration": gloo_patch_duration
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("gloo_patch_duration"):
		gloo_patch_duration = float(data["gloo_patch_duration"])
	if data.has("is_patched"):
		_is_patched = bool(data["is_patched"])
	if data.has("patch_timer"):
		_patch_timer = float(data["patch_timer"])

	_update_pipe_visuals()
