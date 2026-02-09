tool
extends PropBaseV2
class_name SciFiShieldV2

# SciFiShieldV2.gd - Force field shield effect with FBM noise shader.
# Ported from graphic_demo_3d spheres/shield.shader.

export(float, 0.0, 5.0) var shield_energy := 2.0

var _shield_mesh: MeshInstance = null
var _time_accumulator := 0.0

func _ready():
	._ready()
	_shield_mesh = get_node_or_null("ShieldMesh")

func _physics_process(delta: float) -> void:
	._physics_process(delta)
	if is_active:
		_time_accumulator += delta
		if _shield_mesh and _shield_mesh.material_override is ShaderMaterial:
			_shield_mesh.material_override.set_shader_param("iTime", _time_accumulator)

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	if _shield_mesh:
		_shield_mesh.visible = t > 0.01
		if _shield_mesh.material_override is ShaderMaterial:
			_shield_mesh.material_override.set_shader_param("intensity", t)

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
	snap["shield_time"] = _time_accumulator
	return snap

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_time_accumulator = data.get("shield_time", 0.0)
