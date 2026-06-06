extends Node
class_name AirlockTransitionFX

# Drives the flicker-and-jump transition effect for airlocks.
#
# Attach as child of AirlockControllerV2. On airlock_ready it starts a strobe
# at beacon frequency, fires transition_moment at the darkest point of
# `transition_on_cycle`, then continues strobing for `post_transition_cycles`
# more cycles. AirlockZoneV2 polls is_transition_moment_reached() instead of
# deciding on its own.

signal transition_moment()
signal fx_complete()

export(float, 0.2, 8.0) var pulse_speed := 0.8           # Hz
export(int, 1, 8)        var pre_transition_cycles := 1  # full cycles before jump
export(int, 0, 8)        var post_transition_cycles := 1 # cycles to continue after jump
export(float, 0.0, 1.0)  var player_hide_threshold := 0.25  # hide player when brightness below this
export(float, 0.0, 1.0)  var post_transition_min_brightness := 0.65

var _controller: Node = null
var _active := false
var _time := 0.0
var _cycle_count := 0
var _transition_fired := false
var _complete := false
var _skip_next_airlock_ready := false
var _post_only := false
var _managed_lights: Array = []  # [{ node, property, base_value }]

func _ready() -> void:
	_controller = _find_controller()
	if not is_instance_valid(_controller):
		printerr("[AirlockTransitionFX] No controller found!")
		return
	if _controller.has_signal("airlock_ready") and not _controller.is_connected("airlock_ready", self, "_on_airlock_ready"):
		_controller.connect("airlock_ready", self, "_on_airlock_ready")
	set_process(false)
	call_deferred("_check_already_exit_open")

func _on_airlock_ready() -> void:
	if _skip_next_airlock_ready:
		_skip_next_airlock_ready = false
		return
	_start_fx()

func _check_already_exit_open() -> void:
	if not is_instance_valid(_controller):
		return
	var s = _controller.get("state")
	if s != null and int(s) == int(AirlockControllerV2.State.EXIT_OPEN):
		if not _active and not _complete:
			_start_post_transition_fx(false)

# Called by SessionManager on scene arrival to replay post-transition flicker.
# Sets a one-shot flag so the next airlock_ready signal (from open_exit_door)
# is skipped — keeps the signal connected for future use of the same airlock.
func start_post_transition_fx() -> void:
	_start_post_transition_fx(true)

func _start_post_transition_fx(skip_next_ready: bool) -> void:
	_skip_next_airlock_ready = skip_next_ready
	_active = true
	_time = 0.0
	_cycle_count = 0
	_transition_fired = true  # skip the jump, just do post cycles
	_complete = false
	_post_only = true
	_collect_managed_lights()
	set_process(true)

func is_transition_moment_reached() -> bool:
	return _transition_fired

func is_complete() -> bool:
	return _complete

func _start_fx() -> void:
	_active = true
	_time = 0.0
	_cycle_count = 0
	_transition_fired = false
	_complete = false
	_post_only = false
	_collect_managed_lights()
	set_process(true)

func _process(delta: float) -> void:
	if not _active:
		return

	var prev_time := _time
	_time += delta

	var period := 1.0 / max(pulse_speed, 0.001)
	var prev_cycle := int(prev_time / period)
	var curr_cycle := int(_time / period)

	# Phase within current cycle [0..1]
	var phase := fmod(_time, period) / period

	# At nadir (phase ~0.5, i.e. sin=-1) of the transition cycle, fire the jump.
	# We detect crossing phase 0.5 between frames.
	var total_cycles_needed := post_transition_cycles if _post_only else pre_transition_cycles + post_transition_cycles
	if not _transition_fired and curr_cycle >= pre_transition_cycles:
		# Fire at the nadir crossing of the pre_transition_cycles-th cycle.
		var nadir_time := pre_transition_cycles * period + period * 0.5
		if prev_time < nadir_time and _time >= nadir_time:
			_transition_fired = true
			emit_signal("transition_moment")

	# Apply flicker to managed lights.
	var brightness := _flicker_brightness(phase)
	if _post_only:
		brightness = lerp(clamp(post_transition_min_brightness, 0.0, 1.0), 1.0, brightness)
	_apply_brightness(brightness)

	# End after total cycles.
	if curr_cycle > prev_cycle and curr_cycle >= total_cycles_needed:
		_finish_fx()

func _flicker_brightness(phase: float) -> float:
	# Full sine wave: 1.0 at phase 0 and 1.0, 0.0 at phase 0.5.
	return (sin(phase * TAU - PI * 0.5) + 1.0) * 0.5

func _finish_fx() -> void:
	var was_post_only := _post_only
	_active = false
	_complete = true
	_post_only = false
	set_process(false)
	_restore_lights(was_post_only)
	emit_signal("fx_complete")

func _collect_managed_lights() -> void:
	_managed_lights.clear()
	if not is_instance_valid(_controller):
		return
	_collect_managed_lights_recursive(_controller)
	var beacon = _controller.get("_beacon")
	if is_instance_valid(beacon) and beacon.has_method("set_active"):
		_managed_lights.append({"node": beacon, "type": "beacon", "base_value": true})

func _collect_managed_lights_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is OmniLight or child is SpotLight or child is DirectionalLight:
			_managed_lights.append({"node": child, "type": "light_energy", "base_value": float(child.light_energy)})
		elif child is MeshInstance or child is CSGBox or child is CSGCombiner:
			var mat = child.get("material")
			if mat is SpatialMaterial and mat.emission_enabled:
				_managed_lights.append({"node": child, "type": "emission_energy", "base_value": float(mat.emission_energy), "material": mat})
			elif mat is ShaderMaterial:
				var intensity = mat.get_shader_param("intensity")
				if intensity != null:
					_managed_lights.append({"node": child, "type": "shader_intensity", "base_value": float(intensity), "material": mat})
				var seam_em = mat.get_shader_param("seam_emission")
				if seam_em != null:
					_managed_lights.append({"node": child, "type": "shader_seam_emission", "base_value": float(seam_em), "material": mat})
		if child.get_child_count() > 0:
			_collect_managed_lights_recursive(child)

func _apply_brightness(t: float) -> void:
	# Scene-level lights and environments via SceneLighting autoload
	var sl := get_node_or_null("/root/SceneLighting")
	if sl and not _post_only:
		sl.set_brightness(t)
	# Chamber-local lights
	for entry in _managed_lights:
		var node: Node = entry["node"]
		if not is_instance_valid(node):
			continue
		match entry["type"]:
			"light_energy":
				node.set("light_energy", float(entry["base_value"]) * t)
			"emission_energy":
				var mat: SpatialMaterial = entry["material"]
				if is_instance_valid(mat):
					mat.emission_energy = float(entry["base_value"]) * t
			"shader_intensity":
				var mat: ShaderMaterial = entry["material"]
				if is_instance_valid(mat):
					mat.set_shader_param("intensity", float(entry["base_value"]) * t)
			"shader_seam_emission":
				var mat: ShaderMaterial = entry["material"]
				if is_instance_valid(mat):
					mat.set_shader_param("seam_emission", float(entry["base_value"]) * t)
			"beacon":
				if node.has_method("set_active"):
					node.call("set_active", t > 0.5, true)

func _restore_lights(skip_scene_lighting: bool = false) -> void:
	var sl := get_node_or_null("/root/SceneLighting")
	if sl and not skip_scene_lighting:
		sl.restore_brightness()
	for entry in _managed_lights:
		var node: Node = entry["node"]
		if not is_instance_valid(node):
			continue
		match entry["type"]:
			"light_energy":
				node.set("light_energy", float(entry["base_value"]))
			"emission_energy":
				var mat: SpatialMaterial = entry["material"]
				if is_instance_valid(mat):
					mat.emission_energy = float(entry["base_value"])
			"shader_intensity":
				var mat: ShaderMaterial = entry["material"]
				if is_instance_valid(mat):
					mat.set_shader_param("intensity", float(entry["base_value"]))
			"shader_seam_emission":
				var mat: ShaderMaterial = entry["material"]
				if is_instance_valid(mat):
					mat.set_shader_param("seam_emission", float(entry["base_value"]))
			"beacon":
				if node.has_method("set_active"):
					node.call("set_active", true, true)

func _find_controller() -> Node:
	var node: Node = get_parent()
	while node:
		if node is AirlockControllerV2:
			return node
		node = node.get_parent()
	return null
