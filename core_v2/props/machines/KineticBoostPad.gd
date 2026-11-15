extends Area
# Sin class_name: registrarlo exige que el editor reescriba project.godot.

# Impulsor cinético determinista para Side Sockets opcionales en MachineBay.
# Cuando está activo y el jugador entra al área, aplica un impulso direccional
# preservando momentum previo en la dirección de avance.

signal boosted(body)

export(Vector3) var size := Vector3(2.4, 1.2, 2.4)
export(Vector3) var impulse_velocity := Vector3(0.0, 8.5, 11.0)
export(bool) var starts_active := false
export(int) var cooldown_ticks := 24
export(Color) var color_inactive := Color("#3a424d")
export(Color) var color_active := Color("#00e5ff")

var is_active := false
var _cooldown := 0
var _mat: SpatialMaterial = null
var _mesh: MeshInstance = null
var _shape: CollisionShape = null


func _ready() -> void:
	add_to_group("replay_sync")
	collision_layer = 0
	collision_mask = 255
	monitoring = true
	monitorable = false
	is_active = starts_active
	_build()
	_update_visual()
	set_physics_process(true)


func _build() -> void:
	if _shape == null:
		_shape = CollisionShape.new()
		var box := BoxShape.new()
		box.extents = size * 0.5
		_shape.shape = box
		_shape.translation = Vector3(0.0, size.y * 0.5, 0.0)
		add_child(_shape)
	if _mesh == null:
		_mesh = MeshInstance.new()
		var cube := CubeMesh.new()
		cube.size = Vector3(size.x, 0.12, size.z)
		_mesh.mesh = cube
		_mesh.translation = Vector3(0.0, 0.06, 0.0)
		_mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		_mat = SpatialMaterial.new()
		_mesh.material_override = _mat
		add_child(_mesh)


func set_active(active: bool = true) -> void:
	is_active = active
	_update_visual()


func activate() -> void:
	set_active(true)


func is_boost_active() -> bool:
	return is_active


func _update_visual() -> void:
	if _mat == null:
		return
	var col: Color = color_active if is_active else color_inactive
	_mat.albedo_color = col
	_mat.emission_enabled = is_active
	_mat.emission = col
	_mat.emission_energy = 2.0 if is_active else 0.0


func _physics_process(_delta: float) -> void:
	if _cooldown > 0:
		_cooldown -= 1
		return
	if not is_active:
		return
	for body in get_overlapping_bodies():
		if not is_instance_valid(body) or not body.is_in_group("player"):
			continue
		_apply_boost(body)
		_cooldown = cooldown_ticks
		emit_signal("boosted", body)
		return


func _apply_boost(body: Node) -> void:
	if not ("velocity" in body):
		return
	var v: Vector3 = body.velocity
	v.x = _merge_axis(v.x, impulse_velocity.x)
	v.y = max(v.y, impulse_velocity.y) if impulse_velocity.y > 0.0 else v.y
	v.z = _merge_axis(v.z, impulse_velocity.z)
	body.velocity = v
	if "movement_logic" in body and is_instance_valid(body.movement_logic):
		var h: Vector3 = body.movement_logic.horizontal_velocity
		body.movement_logic.horizontal_velocity = Vector3(
			_merge_axis(h.x, impulse_velocity.x),
			0.0,
			_merge_axis(h.z, impulse_velocity.z)
		)
	if "jump_logic" in body and is_instance_valid(body.jump_logic) and impulse_velocity.y > 0.0:
		body.jump_logic.internal_velocity = max(float(body.jump_logic.internal_velocity), impulse_velocity.y)


func _merge_axis(current: float, target: float) -> float:
	if abs(target) < 0.01:
		return current
	if target > 0.0:
		return max(current, target)
	return min(current, target)


func save_snapshot() -> Dictionary:
	return {
		"is_active": is_active,
		"cooldown": _cooldown,
	}


func restore_snapshot(data: Dictionary) -> void:
	is_active = bool(data.get("is_active", starts_active))
	_cooldown = int(data.get("cooldown", 0))
	_update_visual()
