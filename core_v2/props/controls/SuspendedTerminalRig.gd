extends Spatial

# Keeps the diagnostic carriage near the active maintenance worker. The whole
# suspended assembly turns on yaw so its overhead beam, cables, lamp, and
# terminal face together.

export(float) var follow_height_offset: float = 1.6
export(float) var min_carriage_y: float = 4.2
export(float) var max_carriage_y: float = 23.0
export(float) var follow_speed: float = 0.35
export(float) var cable_anchor_y: float = 25.08
export(float) var carriage_beam_y: float = 2.35

onready var _carriage: Spatial = get_node_or_null("Carriage")
onready var _left_cable: CSGBox = get_node_or_null("DropLineLeft")
onready var _right_cable: CSGBox = get_node_or_null("DropLineRight")

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

	var target_y: float = clamp(_player.global_transform.origin.y + follow_height_offset, min_carriage_y, max_carriage_y)
	var follow_weight: float = min(follow_speed * delta, 1.0)
	_carriage.translation.y = lerp(_carriage.translation.y, target_y, follow_weight)
	_update_cables()
	_face_player()

func _find_player() -> Spatial:
	var players: Array = get_tree().get_nodes_in_group("player")
	for candidate in players:
		if candidate is Spatial:
			return candidate as Spatial
	return null

func _face_player() -> void:
	var target: Vector3 = _player.global_transform.origin
	target.y = global_transform.origin.y
	if target.distance_squared_to(global_transform.origin) > 0.01:
		look_at(target, Vector3.UP)

func _update_cables() -> void:
	if _carriage == null:
		return
	var cable_end_y: float = _carriage.translation.y + carriage_beam_y
	_update_cable(_left_cable, cable_end_y)
	_update_cable(_right_cable, cable_end_y)

func _update_cable(cable: CSGBox, cable_end_y: float) -> void:
	if cable == null:
		return
	var cable_height: float = max(cable_anchor_y - cable_end_y, 0.1)
	cable.height = cable_height
	cable.translation.y = cable_end_y + cable_height * 0.5

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
