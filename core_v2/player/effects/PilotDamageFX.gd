extends Spatial

# Visual-only thermal feedback for Pilot: drives shader parameters and a light mist emitter.
export(NodePath) var suit_path := NodePath("../../../Logic/SuitThermalResistance")
export(NodePath) var mesh_path := NodePath("../Skeleton/Skinned_Mesh_0/Skeleton/Mesh_0001")
export(NodePath) var particles_path := NodePath("DamageMist")
export(NodePath) var foot_particles_path := NodePath("FootFrostMist")
export(float, 0.0, 1.0) var min_damage_particles := 0.005
export(float, 0.1, 8.0) var pulse_speed := 1.45
export(float, 0.0, 1.0) var flash_decay_per_second := 0.55
export(float, 0.0, 3.0) var visual_damage_gain := 2.55
export(float, 0.0, 2.0) var hit_flash_gain := 0.95
export(float, 0.05, 3.0) var freeze_rise_speed := 1.35
export(float, 0.05, 3.0) var freeze_fall_speed := 0.7

var _suit: Node = null
var _mesh: MeshInstance = null
var _material: ShaderMaterial = null
var _particles: CPUParticles = null
var _foot_particles: CPUParticles = null
var _damage := 0.0
var _last_ratio := 1.0
var _hit_flash := 0.0
var _pulse_t := 0.0
var _visual_damage := 0.0
var _particles_were_active := false

func _ready() -> void:
	_mesh = get_node_or_null(mesh_path) as MeshInstance
	if not is_instance_valid(_mesh):
		_mesh = _find_mesh_fallback()
	_particles = get_node_or_null(particles_path) as CPUParticles
	_foot_particles = get_node_or_null(foot_particles_path) as CPUParticles
	if is_instance_valid(_mesh):
		_material = _resolve_shader_material(_mesh)
	_connect_suit()
	_apply_damage_ratio(1.0)

func _find_mesh_fallback() -> MeshInstance:
	# Imported scenes can rename mesh nodes, so we fallback to the first mesh under Pivot.
	var pivot := get_parent()
	if not is_instance_valid(pivot):
		return null
	for child in pivot.get_children():
		var found := _find_first_mesh(child)
		if is_instance_valid(found):
			return found
	return null

func _find_first_mesh(node: Node) -> MeshInstance:
	if node is MeshInstance:
		return node as MeshInstance
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if is_instance_valid(found):
			return found
	return null

func _resolve_shader_material(mesh: MeshInstance) -> ShaderMaterial:
	if mesh.material_override is ShaderMaterial:
		return mesh.material_override as ShaderMaterial
	if mesh.mesh and mesh.mesh.get_surface_count() > 0:
		var surf := mesh.get_surface_material(0)
		if surf is ShaderMaterial:
			return surf as ShaderMaterial
	return null

func _process(delta: float) -> void:
	if not is_instance_valid(_suit):
		_connect_suit()
	_hit_flash = max(_hit_flash - delta * flash_decay_per_second, 0.0)
	if _damage > 0.001:
		_pulse_t += delta * pulse_speed
	else:
		_pulse_t = 0.0
	var target_damage := clamp(_damage * visual_damage_gain + _hit_flash * hit_flash_gain, 0.0, 1.0)
	var speed := freeze_rise_speed if target_damage > _visual_damage else freeze_fall_speed
	_visual_damage = move_toward(_visual_damage, target_damage, delta * speed)
	var pulse := (sin(_pulse_t) * 0.5 + 0.5) * _visual_damage
	if is_instance_valid(_material):
		_material.set_shader_param("damage_amount", _visual_damage)
		_material.set_shader_param("pulse", pulse)
	_update_particles(_visual_damage, pulse)

func _connect_suit() -> void:
	_suit = get_node_or_null(suit_path)
	if not is_instance_valid(_suit):
		return
	if _suit.has_signal("thermal_state_changed") and not _suit.is_connected("thermal_state_changed", self, "_on_thermal_state_changed"):
		var _err = _suit.connect("thermal_state_changed", self, "_on_thermal_state_changed")
	if _suit.has_method("get_ratio"):
		_apply_damage_ratio(float(_suit.get_ratio()))

func _on_thermal_state_changed(ratio: float) -> void:
	if ratio < _last_ratio:
		# Trigger a short visual hit flash when the suit integrity drops.
		var drop := clamp(_last_ratio - ratio, 0.0, 1.0)
		_hit_flash = max(_hit_flash, clamp(drop * 8.0, 0.2, 0.7))
		if is_instance_valid(_particles):
			_particles.restart()
		if is_instance_valid(_foot_particles):
			_foot_particles.restart()
	_last_ratio = ratio
	_apply_damage_ratio(ratio)

func _apply_damage_ratio(ratio: float) -> void:
	_damage = clamp(1.0 - ratio, 0.0, 1.0)
	var target_damage := clamp(_damage * visual_damage_gain, 0.0, 1.0)
	_visual_damage = max(_visual_damage, target_damage * 0.25)
	if is_instance_valid(_material):
		_material.set_shader_param("damage_amount", _visual_damage)
		_material.set_shader_param("pulse", 0.0)
	_update_particles(_visual_damage, 0.0)

func _update_particles(visual_damage: float, _pulse: float) -> void:
	if not is_instance_valid(_particles) and not is_instance_valid(_foot_particles):
		return
	var active := visual_damage >= min_damage_particles or _damage > 0.015 or _hit_flash > 0.08
	if active and not _particles_were_active:
		if is_instance_valid(_particles):
			_particles.restart()
		if is_instance_valid(_foot_particles):
			_foot_particles.restart()
	_particles_were_active = active
	if not active:
		if is_instance_valid(_particles):
			_particles.emitting = false
		if is_instance_valid(_foot_particles):
			_foot_particles.emitting = false
		return
	var burst_damage := max(visual_damage, _hit_flash)
	if is_instance_valid(_particles):
		# Main frost falls from the suit downward like cold dust/snow.
		_particles.emitting = true
		_particles.initial_velocity = lerp(0.12, 0.32, burst_damage)
		_particles.initial_velocity_random = lerp(0.08, 0.18, burst_damage)
		_particles.scale_amount = lerp(0.06, 0.11, burst_damage)
		_particles.spread = lerp(16.0, 32.0, burst_damage)
		_particles.gravity = Vector3(0, -0.1, 0)
		_particles.explosiveness = 0.0
		_particles.randomness = lerp(0.14, 0.28, burst_damage)
		_particles.speed_scale = lerp(0.8, 1.15, burst_damage)
		_particles.color = Color(0.99, 0.995, 1.0, lerp(0.28, 0.52, burst_damage))
	if is_instance_valid(_foot_particles):
		# Keep only a faint floor-near residue to avoid the boiling-water look.
		_foot_particles.emitting = burst_damage > 0.8
		_foot_particles.initial_velocity = lerp(0.01, 0.04, burst_damage)
		_foot_particles.initial_velocity_random = lerp(0.01, 0.03, burst_damage)
		_foot_particles.scale_amount = lerp(0.04, 0.07, burst_damage)
		_foot_particles.spread = lerp(5.0, 10.0, burst_damage)
		_foot_particles.gravity = Vector3(0, -0.02, 0)
		_foot_particles.explosiveness = 0.0
		_foot_particles.randomness = lerp(0.04, 0.08, burst_damage)
		_foot_particles.speed_scale = lerp(0.4, 0.55, burst_damage)
		_foot_particles.color = Color(0.98, 0.99, 1.0, lerp(0.03, 0.08, burst_damage))
