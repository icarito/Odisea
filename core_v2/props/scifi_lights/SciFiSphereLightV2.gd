tool
extends PropBaseV2
class_name SciFiSphereLightV2

# SciFiSphereLightV2.gd - Animated cone/sphere with emissive dot shader.
# Has a solid BaseSphere for visibility + a shader cone for the animated effect.

export(Color) var light_color := Color(0.79, 0.43, 1.0) setget set_light_color
export(float, 0.0, 5.0) var light_energy_max := 1.5

var _cone_mesh: MeshInstance = null
var _base_sphere: MeshInstance = null
var _omni_light: OmniLight = null
var _time_accumulator := 0.0

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

func _physics_process(delta: float) -> void:
	._physics_process(delta)
	if is_active:
		_time_accumulator += delta
		if _cone_mesh and _cone_mesh.material_override is ShaderMaterial:
			_cone_mesh.material_override.set_shader_param("iTime", _time_accumulator)

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	# Cone shader
	if _cone_mesh and _cone_mesh.material_override is ShaderMaterial:
		_cone_mesh.material_override.set_shader_param("blenda", t)
		_cone_mesh.material_override.set_shader_param("blendb", t)
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
