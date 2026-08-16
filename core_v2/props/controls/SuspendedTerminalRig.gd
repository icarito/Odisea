extends Spatial

# Keeps the diagnostic carriage near the active maintenance worker. The whole
# suspended assembly turns on yaw so its overhead beam, cables, lamp, and
# terminal face together.

export(float) var follow_height_offset: float = 1.6
export(float) var min_carriage_y: float = 4.2
export(float) var max_carriage_y: float = 23.8
export(float) var follow_speed: float = 0.35
export(float) var rotation_speed: float = 0.18
export(float) var carriage_radial_distance: float = 3.5
export(float) var cable_anchor_y: float = 26.55
export(float) var carriage_beam_y: float = 2.35

onready var _carriage: Spatial = get_node_or_null("Carriage")
onready var _left_cable: CSGBox = get_node_or_null("DropLineLeft")
onready var _right_cable: CSGBox = get_node_or_null("DropLineRight")
onready var _central_cable: CSGBox = get_node_or_null("CentralDropLine")
onready var _movement_sfx: AudioStreamPlayer3D = get_node_or_null("Carriage/MovementSFX")

var _player: Spatial = null

func _ready() -> void:
	_player = _find_player()
	_update_cables()
	_invert_hanging_display_image()

func _physics_process(delta: float) -> void:
	if Engine.editor_hint or _carriage == null:
		return
	if not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return

	var follow_weight: float = min(follow_speed * delta, 1.0)
	var previous_position: Vector3 = _carriage.translation
	var previous_yaw: float = rotation.y
	_face_player(delta)
	var target_y: float = clamp(_player.global_transform.origin.y + follow_height_offset, min_carriage_y, max_carriage_y)
	var target_horizontal: Vector3 = _target_carriage_horizontal()
	_carriage.translation.y = lerp(_carriage.translation.y, target_y, follow_weight)
	_carriage.translation.x = lerp(_carriage.translation.x, target_horizontal.x, follow_weight)
	_carriage.translation.z = lerp(_carriage.translation.z, target_horizontal.z, follow_weight)
	_update_cables()
	_update_movement_sound(previous_position, previous_yaw)

func _find_player() -> Spatial:
	var players: Array = get_tree().get_nodes_in_group("player")
	for candidate in players:
		if candidate is Spatial:
			return candidate as Spatial
	return null

func _face_player(delta: float) -> void:
	var target: Vector3 = _player.global_transform.origin
	target.y = global_transform.origin.y
	var direction: Vector3 = target - global_transform.origin
	if direction.length_squared() <= 0.01:
		return
	var target_yaw: float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, min(rotation_speed * delta, 1.0))

func _target_carriage_horizontal() -> Vector3:
	var local_player: Vector3 = to_local(_player.global_transform.origin)
	var horizontal: Vector3 = Vector3(local_player.x, 0.0, local_player.z)
	if horizontal.length_squared() <= 0.01:
		return Vector3.ZERO
	return horizontal.normalized() * min(horizontal.length(), carriage_radial_distance)

func _update_cables() -> void:
	if _carriage == null:
		return
	var cable_end_y: float = _carriage.translation.y + carriage_beam_y
	_update_cable(_left_cable, cable_end_y, Vector3(-2.35, 0.0, 0.0))
	_update_cable(_right_cable, cable_end_y, Vector3(2.35, 0.0, 0.0))
	_update_cable(_central_cable, cable_end_y, Vector3.ZERO)

func _update_cable(cable: CSGBox, cable_end_y: float, horizontal_offset: Vector3) -> void:
	if cable == null:
		return
	var cable_height: float = max(cable_anchor_y - cable_end_y, 0.1)
	cable.height = cable_height
	cable.translation.x = _carriage.translation.x + horizontal_offset.x
	cable.translation.y = cable_end_y + cable_height * 0.5
	cable.translation.z = _carriage.translation.z + horizontal_offset.z

func _update_movement_sound(previous_position: Vector3, previous_yaw: float) -> void:
	if _movement_sfx == null:
		return
	var moved: bool = _carriage.translation.distance_squared_to(previous_position) > 0.000004
	var turned: bool = abs(rotation.y - previous_yaw) > 0.00005
	if moved or turned:
		if not _movement_sfx.playing:
			_movement_sfx.play()
	elif _movement_sfx.playing:
		_movement_sfx.stop()

func _invert_hanging_display_image() -> void:
	var screen: CSGBox = get_node_or_null("Carriage/HangingDisplay/ScreenContainer/ScreenMesh")
	if screen == null or not screen.material is ShaderMaterial:
		return
	var material: ShaderMaterial = (screen.material as ShaderMaterial).duplicate() as ShaderMaterial
	material.render_priority = 100
	material.set_shader_param("aligned_flip_v", false)
	screen.material = material
	screen.visible = true
	var experimental_surface: Node = screen.get_parent().get_node_or_null("ProjectionSurface")
	if experimental_surface != null:
		experimental_surface.queue_free()
