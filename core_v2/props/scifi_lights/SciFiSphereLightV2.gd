tool
extends PropBaseV2
class_name SciFiSphereLightV2

# SciFiSphereLightV2.gd - Animated sphere light with a cheap emissive cone fallback.
# Keeps the silhouette without relying on a custom shader.

export(Color) var light_color := Color(0.79, 0.43, 1.0) setget set_light_color
export(float, 0.0, 5.0) var light_energy_max := 1.5
export(int, 1, 4) var visual_tick_interval_frames := 2

var _cone_mesh: MeshInstance = null
var _base_sphere: MeshInstance = null
var _omni_light: OmniLight = null
var _time_accumulator := 0.0
var _visual_tick_countdown := 0
var _visual_tick_accumulator := 0.0

func _ready():
	._ready()
	_cone_mesh = get_node_or_null("ConeMesh")
	_base_sphere = get_node_or_null("BaseSphere")
	_omni_light = get_node_or_null("OmniLight")
	_apply_color()

func set_light_color(v: Color) -> void:
	light_color = v
	if is_inside_tree():
		_apply_color()

func _apply_color():
	if _omni_light:
		_omni_light.light_color = light_color
	if _base_sphere and _base_sphere.material_override is SpatialMaterial:
		_base_sphere.material_override.emission = light_color
	if _cone_mesh and _cone_mesh.material_override is SpatialMaterial:
		_cone_mesh.material_override.albedo_color = Color(light_color.r, light_color.g, light_color.b, _cone_mesh.material_override.albedo_color.a)
		_cone_mesh.material_override.emission = light_color

func _physics_process(delta: float) -> void:
	._physics_process(delta)
	var visual_dt = _consume_visual_tick(delta)
	if visual_dt < 0.0:
		return
	if is_active:
		_time_accumulator += visual_dt
		if _cone_mesh and _cone_mesh.material_override is ShaderMaterial:
			_cone_mesh.material_override.set_shader_param("iTime", _time_accumulator)

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	# Deprecated shader path, kept for compatibility with old scenes.
	if _cone_mesh and _cone_mesh.material_override is ShaderMaterial:
		_cone_mesh.material_override.set_shader_param("blenda", t)
		_cone_mesh.material_override.set_shader_param("blendb", t)
	elif _cone_mesh and _cone_mesh.material_override is SpatialMaterial:
		var cone_mat := _cone_mesh.material_override
		cone_mat.emission_energy = t * 1.6
		cone_mat.albedo_color.a = clamp(0.08 + t * 0.35, 0.0, 0.45)
	# Base sphere emission
	if _base_sphere and _base_sphere.material_override is SpatialMaterial:
		_base_sphere.material_override.emission_energy = t * 3.0
	# Light
	if _omni_light:
		_omni_light.light_energy = t * light_energy_max

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
	snap["sphere_time"] = _time_accumulator
	return snap

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_time_accumulator = data.get("sphere_time", 0.0)

func _consume_visual_tick(delta: float) -> float:
	_visual_tick_accumulator += max(0.0, delta)
	if visual_tick_interval_frames <= 1:
		var dt = _visual_tick_accumulator
		_visual_tick_accumulator = 0.0
		return dt
	if _visual_tick_countdown > 0:
		_visual_tick_countdown -= 1
		return -1.0
	_visual_tick_countdown = visual_tick_interval_frames - 1
	var sampled_dt = _visual_tick_accumulator
	_visual_tick_accumulator = 0.0
	return sampled_dt
