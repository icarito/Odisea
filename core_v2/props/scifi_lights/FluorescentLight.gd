tool
extends PropBaseV2
class_name FluorescentLight

# FluorescentLight.gd - A tubular fluorescent light prop with optional flickering.
# Extends PropBaseV2 for compatibility with Logic Circuit System and interactions.

export(Color) var light_color := Color(0.8, 0.9, 1.0) setget set_light_color
export(float, 0.0, 10.0) var light_energy := 1.0 setget set_light_energy
export(float, 0.0, 20.0) var light_range := 10.0 setget set_light_range
export(bool) var flicker_enabled := false
export(float, 0.1, 20.0) var flicker_speed := 10.0
export(float, 0.0, 1.0) var flicker_intensity := 0.5
export(int, 1, 4) var flicker_tick_interval_frames := 2
export(float, 0.0, 300.0) var flickr_timeout := 30.0
export(float, 0.0, 300.0) var flickr_timeout_random_spread := 15.0
export(float, 0.0, 1.0) var flickr_timeout_endgame_chance := 0.5

var _omni_light: OmniLight = null
var _spot_light: SpotLight = null # Optional support for spotlight too
var _mesh: MeshInstance = null
var _time_acc: float = 0.0
var _flicker_tick_countdown := 0
var _flicker_tick_accumulator := 0.0
var _flickr_timeout_timer := 0.0
var _flickr_finished := false
var _initial_light_energy := 1.0

func _ready():
	._ready()
	_omni_light = _find_child_by_type("OmniLight")
	_spot_light = _find_child_by_type("SpotLight")
	_mesh = _find_child_by_type("MeshInstance")
	_initial_light_energy = light_energy
	if not Engine.editor_hint and flicker_enabled:
		_flickr_timeout_timer = flickr_timeout + (randf() * 2.0 - 1.0) * flickr_timeout_random_spread
	_apply_settings()

func set_light_color(v: Color) -> void:
	light_color = v
	if is_inside_tree():
		_apply_settings()

func set_light_energy(v: float) -> void:
	light_energy = v
	if is_inside_tree():
		_update_visuals()

func set_light_range(v: float) -> void:
	light_range = v
	if is_inside_tree():
		if _omni_light:
			_omni_light.omni_range = v
		if _spot_light:
			_spot_light.spot_range = v

func _apply_settings():
	if _omni_light:
		_omni_light.light_color = light_color
		_omni_light.omni_range = light_range
	if _spot_light:
		_spot_light.light_color = light_color
		_spot_light.spot_range = light_range

	if _mesh and _mesh.material_override:
		if not _mesh.material_override.resource_local_to_scene:
			_mesh.material_override = _mesh.material_override.duplicate()
		if _mesh.material_override is SpatialMaterial:
			_mesh.material_override.emission = light_color

	_update_visuals()

func _update_visuals() -> void:
	._update_visuals()

	var base_energy = light_energy * anim_progress
	var flicker_factor = 1.0

	if flicker_enabled and anim_progress > 0.01:
		var noise = sin(_time_acc * flicker_speed) * sin(_time_acc * flicker_speed * 0.79 + 1.23)
		noise += 0.5 * sin(_time_acc * flicker_speed * 3.14)
		flicker_factor = 1.0 - (flicker_intensity * 0.5 * (1.0 + noise))
		flicker_factor = clamp(flicker_factor, 0.0, 1.2)

	var flicker_energy = base_energy * flicker_factor

	if _omni_light:
		_omni_light.light_energy = flicker_energy
	if _spot_light:
		_spot_light.light_energy = flicker_energy

	if _mesh and _mesh.material_override:
		var mat = _mesh.material_override
		if mat is SpatialMaterial:
			mat.emission_energy = base_energy
			mat.albedo_color.a = clamp(base_energy / max(light_energy, 0.001), 0.15, 1.0)
		elif mat is ShaderMaterial:
			mat.set_shader_param("emission_energy", base_energy)
			var alpha = clamp(base_energy / max(light_energy, 0.001), 0.15, 1.0)
			mat.set_shader_param("albedo", Color(light_color.r, light_color.g, light_color.b, alpha))

func step(dt: float) -> void:
	.step(dt)
	
	if not Engine.editor_hint and flicker_enabled and not _flickr_finished:
		_flickr_timeout_timer -= dt
		if _flickr_timeout_timer <= 0:
			_on_flicker_timeout()

	var flicker_dt = _consume_flicker_tick(dt)
	if flicker_dt < 0.0:
		return
	_time_acc += flicker_dt

	if flicker_enabled and anim_progress > 0.01:
		_update_visuals()

func _on_flicker_timeout():
	_flickr_finished = true
	flicker_enabled = false
	# Determine final state based on chance
	if randf() < flickr_timeout_endgame_chance:
		# Resolve to ON: ensure light_energy is restored/kept
		set_light_energy(_initial_light_energy)
	else:
		# Resolve to OFF: kill light energy
		set_light_energy(0.0)
	_update_visuals()

func _find_child_by_type(type_name: String) -> Node:
	for child in get_children():
		if child.get_class() == type_name:
			return child
	return null

func _consume_flicker_tick(delta: float) -> float:
	_flicker_tick_accumulator += max(0.0, delta)
	if flicker_tick_interval_frames <= 1:
		var dt = _flicker_tick_accumulator
		_flicker_tick_accumulator = 0.0
		return dt
	if _flicker_tick_countdown > 0:
		_flicker_tick_countdown -= 1
		return -1.0
	_flicker_tick_countdown = flicker_tick_interval_frames - 1
	var sampled_dt = _flicker_tick_accumulator
	_flicker_tick_accumulator = 0.0
	return sampled_dt
