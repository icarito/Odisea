extends "res://core_v2/components/InteractableBaseV2.gd"

# CheckpointConsole.gd
# Interactive or proximity-based console to set the active checkpoint.

export(float) var spawn_yaw := 0.0
export(float) var spawn_pitch := 0.0

onready var _audio_player := AudioStreamPlayer3D.new()

func _ready() -> void:
	add_to_group("checkpoint_console")
	var cm = get_node_or_null("/root/CheckpointManager")
	if cm and cm.has_method("register_checkpoint"):
		cm.register_checkpoint(self)

	# Setup audio player
	_audio_player.name = "ChimePlayer"
	_audio_player.unit_db = 15.0
	_audio_player.max_db = 3.0
	_audio_player.max_distance = 25.0

	var file_checker = File.new()
	var sfx_path = "res://assets/sfx/chime.wav"
	if file_checker.file_exists(sfx_path):
		var sfx_stream = load(sfx_path)
		if sfx_stream:
			_audio_player.stream = sfx_stream

	add_child(_audio_player)

	# Set up proximity area dynamically if none was created in scene editor
	_setup_proximity_area()

	_update_visuals()

func _setup_proximity_area() -> void:
	# Avoid duplicate area if already present in .tscn
	if has_node("ProximityArea"):
		var area = get_node("ProximityArea")
		if not area.is_connected("body_entered", self, "_on_proximity_body_entered"):
			area.connect("body_entered", self, "_on_proximity_body_entered")
		return

	var area = Area.new()
	area.name = "ProximityArea"
	area.collision_mask = 2 # Player layer
	area.collision_layer = 0

	var col = CollisionShape.new()
	var sphere = SphereShape.new()
	sphere.radius = 2.0
	col.shape = sphere
	area.add_child(col)

	add_child(area)
	area.connect("body_entered", self, "_on_proximity_body_entered")

func _on_proximity_body_entered(body: Node) -> void:
	if body.is_in_group("player") and not is_active:
		interact()

func _update_visuals() -> void:
	# Amber light (inactive) to Green light (active)
	var led_color = Color(1.0, 0.6, 0.0) if not is_active else Color(0.0, 1.0, 0.0) # Amber vs Green

	var light = get_node_or_null("OmniLight")
	if light and light is Light:
		light.light_color = led_color

	var mesh = get_node_or_null("MeshInstance")
	if mesh and mesh is MeshInstance:
		var mat = mesh.get_surface_material(0)
		if not mat or not mat is SpatialMaterial:
			mat = SpatialMaterial.new()
			mat.resource_local_to_scene = true
			mesh.set_surface_material(0, mat)
		if mat is SpatialMaterial:
			mat.albedo_color = Color(0.2, 0.2, 0.2)
			mat.emission_enabled = true
			mat.emission = led_color
			mat.emission_energy = 1.0

func _on_animation_completed() -> void:
	._on_animation_completed()
	if is_active:
		# Play chime sound
		if _audio_player and _audio_player.stream:
			_audio_player.play()

		# Set this checkpoint as the active one in CheckpointManager
		var cm = get_node_or_null("/root/CheckpointManager")
		if cm and cm.has_method("set_active_checkpoint"):
			# Set the spawn position slightly offset from the console's position so player doesn't spawn exactly inside
			var spawn_pos = global_transform.origin + global_transform.basis.z * 1.2
			cm.set_active_checkpoint(spawn_pos, spawn_yaw, spawn_pitch)

func deactivate() -> void:
	if is_active:
		# Directly transition to inactive state without triggers
		is_active = false
		target_progress = 0.0
		anim_progress = 0.0
		_update_visuals()
