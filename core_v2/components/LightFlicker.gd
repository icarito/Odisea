tool
extends Node
class_name LightFlicker

# LightFlicker.gd - Reusable deterministic light flicker component (FD-287).
# Modulates emissive, light energy, or visibility of target nodes/props
# in a deterministic, snapshot-able, GLES2-safe manner.

export(NodePath) var target_path: NodePath
export(float) var base_intensity: float = 1.0
export(float, 0.0, 1.0) var on_ratio: float = 0.85
export(float, 0.1, 30.0) var period: float = 0.9
export(int) var seed: int = 0 setget set_seed
export(bool) var only_when_active: bool = true

var _target: Node = null
var _time_acc: float = 0.0
var _rng := RandomNumberGenerator.new()

var _cached_lights: Array = []
var _cached_materials: Array = []
var _has_flicker_method: bool = false
var _is_fallback_visible: bool = false
var _cached_base_visible: bool = true
var _base_values_cached: bool = false

func _ready() -> void:
	add_to_group("replay_sync")
	_init_rng()
	_resolve_target()
	_refresh_process_state()

func set_seed(v: int) -> void:
	seed = v
	_init_rng()

func _init_rng() -> void:
	_rng.seed = seed

func _resolve_target() -> void:
	if target_path and not target_path.is_empty():
		_target = get_node_or_null(target_path)
	if not _target:
		_target = get_parent()

	if not _target:
		return

	_connect_target_signals()
	_cache_target_base_values()

func _connect_target_signals() -> void:
	if not _target:
		return
	if _target.has_signal("activated") and not _target.is_connected("activated", self, "_on_target_activated"):
		_target.connect("activated", self, "_on_target_activated")
	if _target.has_signal("deactivated") and not _target.is_connected("deactivated", self, "_on_target_deactivated"):
		_target.connect("deactivated", self, "_on_target_deactivated")
	if _target.has_signal("state_changed") and not _target.is_connected("state_changed", self, "_on_target_state_changed"):
		_target.connect("state_changed", self, "_on_target_state_changed")
	if _target.has_signal("toggled") and not _target.is_connected("toggled", self, "_on_target_toggled"):
		_target.connect("toggled", self, "_on_target_toggled")
	if _target.has_signal("interaction_started") and not _target.is_connected("interaction_started", self, "_on_target_activated"):
		_target.connect("interaction_started", self, "_on_target_activated")

func _cache_target_base_values() -> void:
	if not _target or _base_values_cached:
		return

	_cached_lights.clear()
	_cached_materials.clear()
	_has_flicker_method = _target.has_method("set_flicker_multiplier")

	if _has_flicker_method:
		_base_values_cached = true
		return

	_scan_node_resources(_target)

	if _cached_lights.empty() and _cached_materials.empty():
		_is_fallback_visible = true
		if _target is Spatial or _target is CanvasItem:
			_cached_base_visible = bool(_target.get("visible"))
	else:
		_is_fallback_visible = false

	_base_values_cached = true

func _scan_node_resources(node: Node) -> void:
	if node is Light:
		var light_node := node as Light
		_cached_lights.append({
			"node": light_node,
			"base_energy": light_node.light_energy
		})
	elif node is MeshInstance:
		var mesh_inst := node as MeshInstance
		var mat: Material = mesh_inst.material_override
		if not mat and mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
			mat = mesh_inst.get_surface_material(0)
		if mat:
			if mat is SpatialMaterial:
				var spat_mat := mat as SpatialMaterial
				_cached_materials.append({
					"material": spat_mat,
					"base_emission": spat_mat.emission_energy,
					"is_shader": false
				})
			elif mat is ShaderMaterial:
				var sh_mat := mat as ShaderMaterial
				var emission_energy = sh_mat.get_shader_param("emission_energy")
				if emission_energy == null:
					emission_energy = 1.0
				_cached_materials.append({
					"material": sh_mat,
					"base_emission": float(emission_energy),
					"is_shader": true
				})

	for child in node.get_children():
		_scan_node_resources(child)

func _is_target_active() -> bool:
	if not _target:
		return false
	if "is_active" in _target:
		return bool(_target.get("is_active"))
	if "anim_progress" in _target:
		return float(_target.get("anim_progress")) > 0.01
	if _target.has_method("is_active"):
		return bool(_target.call("is_active"))
	if _target is Spatial:
		return (_target as Spatial).visible
	return true

func _refresh_process_state() -> void:
	if Engine.editor_hint:
		return
	if only_when_active and not _is_target_active():
		_restore_base_values()
		set_physics_process(false)
		set_process(false)
	else:
		set_physics_process(true)

func _on_target_activated() -> void:
	_refresh_process_state()

func _on_target_deactivated() -> void:
	_refresh_process_state()

func _on_target_state_changed(_val) -> void:
	_refresh_process_state()

func _on_target_toggled(_val) -> void:
	_refresh_process_state()

func step(dt: float) -> void:
	if Engine.editor_hint:
		return
	if not _target:
		_resolve_target()
		if not _target:
			return

	if only_when_active and not _is_target_active():
		_restore_base_values()
		set_physics_process(false)
		set_process(false)
		return

	_time_acc += dt
	var factor: float = calculate_factor(_time_acc)
	_apply_factor(factor)

func _physics_process(delta: float) -> void:
	step(delta)

func calculate_factor(t: float) -> float:
	var safe_period: float = max(0.1, period)
	var cycle_idx: int = int(floor(t / safe_period))
	var cycle_t: float = (t - cycle_idx * safe_period) / safe_period

	var cycle_seed: int = hash(seed + cycle_idx * 1013904223)
	var rng := RandomNumberGenerator.new()
	rng.seed = cycle_seed
	var r1: float = rng.randf()
	var r2: float = rng.randf()

	var duty: float = clamp(on_ratio, 0.0, 1.0)
	var raw_factor: float = 1.0

	if cycle_t < duty:
		raw_factor = 1.0
		if r1 < 0.35:
			if cycle_t > 0.05 and cycle_t < 0.18:
				raw_factor = 0.15
	else:
		var low_val: float = clamp(1.0 - duty, 0.0, 0.4)
		raw_factor = low_val
		if r2 < 0.4:
			var off_duration: float = 1.0 - duty
			var off_start: float = duty
			if cycle_t > (off_start + off_duration * 0.3) and cycle_t < (off_start + off_duration * 0.6):
				raw_factor = 0.85

	return clamp(raw_factor * base_intensity, 0.0, 10.0)

func _apply_factor(factor: float) -> void:
	if not _target:
		return

	if _has_flicker_method:
		_target.call("set_flicker_multiplier", factor)
		return

	if not _is_fallback_visible:
		for item in _cached_lights:
			var light: Light = item["node"]
			if is_instance_valid(light):
				light.light_energy = float(item["base_energy"]) * factor

		for item in _cached_materials:
			var mat: Material = item["material"]
			if is_instance_valid(mat):
				if bool(item["is_shader"]):
					(mat as ShaderMaterial).set_shader_param("emission_energy", float(item["base_emission"]) * factor)
				else:
					(mat as SpatialMaterial).emission_energy = float(item["base_emission"]) * factor
	else:
		if _target is Spatial:
			(_target as Spatial).visible = (factor > 0.3)

func _restore_base_values() -> void:
	if not _target:
		return

	if _has_flicker_method:
		_target.call("set_flicker_multiplier", 1.0)
		return

	if not _is_fallback_visible:
		for item in _cached_lights:
			var light: Light = item["node"]
			if is_instance_valid(light):
				light.light_energy = float(item["base_energy"])

		for item in _cached_materials:
			var mat: Material = item["material"]
			if is_instance_valid(mat):
				if bool(item["is_shader"]):
					(mat as ShaderMaterial).set_shader_param("emission_energy", float(item["base_emission"]))
				else:
					(mat as SpatialMaterial).emission_energy = float(item["base_emission"])
	else:
		if _target is Spatial:
			(_target as Spatial).visible = _cached_base_visible

func get_snapshot() -> Dictionary:
	return {
		"time_acc": _time_acc,
		"seed": seed
	}

func restore_snapshot(data: Dictionary) -> void:
	_time_acc = data.get("time_acc", 0.0)
	seed = data.get("seed", seed)
	_init_rng()
	_resolve_target()
	_refresh_process_state()
	if not only_when_active or _is_target_active():
		var factor: float = calculate_factor(_time_acc)
		_apply_factor(factor)
