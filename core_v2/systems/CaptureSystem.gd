extends Node

# CaptureSystem.gd
# Handles the stasis field capture sequence, checkpoint teleportation, and drone resets.

const CaptureOverlayScene = preload("res://core_v2/ui/CaptureOverlay.tscn")

var capture_count := 0
var is_capturing := false

var _overlay_instance: Node = null

# Dialogue pools
var low_count_lines := [
	"STASIS LOCK ENGAGED. RECONSTRUCTING PATTERN AT LAST CHECKPOINT...",
	"CONTAINMENT SUCCESSFUL. TARGET SAFETY PROTOCOL INITIATED...",
	"CRITICAL DISCREPANCY DETECTED. RESETTING LOCAL SPACE-TIME TRANSFORMATION...",
	"KINETIC IMPACT RECOVERED. RE-ESTABLISHING COMPANION TELEMETRY..."
]

var high_count_lines := [
	"PATTERN DRIFT DETECTED. ODISEA ADVISES CAUTION IN KINETIC SECTOR...",
	"MULTIPLE VOLTAGE IMPULSES DETECTED. CONDUIT CONTINUITY DEGRADED...",
	"CONTAINMENT LOOP EXCEEDED. RESPAWNING TARGET MANIFOLD...",
	"WARNING: BIO-METRIC DECOHERENCE APPROACHING CRITICAL THRESHOLDS..."
]

func trigger_capture(ddc_drone: Node = null) -> void:
	if is_capturing:
		return
	is_capturing = true

	# Find player
	var player = null
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	if not player or not is_instance_valid(player):
		is_capturing = false
		return

	# 1. Lock player input
	player.input_locked = true

	# 2. Instantiate and setup CaptureOverlay if not already present
	if not is_instance_valid(_overlay_instance):
		_overlay_instance = CaptureOverlayScene.instance()
		add_child(_overlay_instance)
	else:
		_overlay_instance.reset_overlay()

	# 3. Create 3D stasis field visual at player position
	var stasis_field = Spatial.new()
	stasis_field.name = "StasisField"
	player.add_child(stasis_field)

	# Sphere mesh
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 1.4
	sphere_mesh.height = 2.8

	var sphere_mat = SpatialMaterial.new()
	sphere_mat.flags_transparent = true
	sphere_mat.albedo_color = Color(0.0, 0.5, 1.0, 0.3)
	sphere_mat.emission_enabled = true
	sphere_mat.emission = Color(0.0, 0.5, 1.0)
	sphere_mat.emission_energy = 0.5

	var mesh_inst = MeshInstance.new()
	mesh_inst.mesh = sphere_mesh
	mesh_inst.material_override = sphere_mat
	mesh_inst.transform.origin = Vector3.UP * 1.0 # center around player torso
	stasis_field.add_child(mesh_inst)

	# Particles
	var particles = CPUParticles.new()
	particles.amount = 20
	particles.emission_shape = CPUParticles.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 1.0
	particles.gravity = Vector3.UP * 1.2
	particles.color = Color(0.0, 0.7, 1.0, 0.8)
	var p_mesh = CubeMesh.new()
	p_mesh.size = Vector3(0.08, 0.08, 0.08)
	particles.mesh = p_mesh
	particles.transform.origin = Vector3.UP * 1.0
	stasis_field.add_child(particles)
	particles.emitting = true

	# 4. Zoom camera out slightly during capture
	var original_spring_length = player.base_spring_length_3d
	player.base_spring_length_3d = original_spring_length + 3.0

	# 5. Play sound effects
	var audio_shock = AudioStreamPlayer.new()
	var audio_buzz = AudioStreamPlayer.new()
	add_child(audio_shock)
	add_child(audio_buzz)

	var file_checker = File.new()
	var shock_path = "res://assets/sfx/electric-shock-97989.mp3"
	var buzz_path = "res://assets/sfx/electronic-buzzing-sound-29464.mp3"

	if file_checker.file_exists(shock_path):
		var shock_stream = load(shock_path)
		if shock_stream:
			audio_shock.stream = shock_stream
			audio_shock.play()

	if file_checker.file_exists(buzz_path):
		var buzz_stream = load(buzz_path)
		if buzz_stream:
			audio_buzz.stream = buzz_stream
			audio_buzz.play()

	# 6. Shows Odisea dialogue as subtitle
	var dialogue_text = ""
	if capture_count < 3:
		dialogue_text = low_count_lines[capture_count % low_count_lines.size()]
	else:
		dialogue_text = high_count_lines[capture_count % high_count_lines.size()]

	var som = get_node_or_null("/root/SubtitlesOverlayManager")
	if som and som.has_method("show_subtitle"):
		som.show_subtitle(dialogue_text, Color.cyan, 3.0)

	# Fade stasis screen tint in
	_overlay_instance.fade_stasis_in(0.5)

	# Yield for stasis build-up (~1.0s)
	yield(get_tree().create_timer(1.0), "timeout")

	# Fade to black cover
	_overlay_instance.fade_black_out(0.6)
	yield(get_tree().create_timer(0.6), "timeout")

	# 7. Teleport to checkpoint
	var checkpoint_manager = get_node_or_null("/root/CheckpointManager")
	if checkpoint_manager and checkpoint_manager.has_method("get_respawn_transform"):
		var respawn = checkpoint_manager.get_respawn_transform()
		var pos = respawn["position"]
		var yaw = respawn["yaw"]
		var pitch = respawn["pitch"]
		var rot_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var target_transform = Transform(rot_basis, pos)
		player.teleport_to(target_transform)

	# Clean up 3D stasis field from player
	if is_instance_valid(stasis_field):
		stasis_field.queue_free()

	# Restore camera zoom
	player.base_spring_length_3d = original_spring_length

	# 8. Resets active DDC drones to spawn positions
	for drone in get_tree().get_nodes_in_group("ddc_drone"):
		if is_instance_valid(drone) and drone.has_method("reset_to_spawn"):
			drone.reset_to_spawn()

	# Stun/Reset containment pursuit drones so they don't spawn on top
	for pursuit in get_tree().get_nodes_in_group("ddc_containment"):
		if is_instance_valid(pursuit):
			if pursuit.has_method("stun"):
				pursuit.stun(3.5)
			elif "state" in pursuit:
				pursuit.state = 0 # CHARGING
				pursuit.state_timer = 0.0

	# 9. Increment capture counter
	capture_count += 1

	# 10. Fade in from black
	_overlay_instance.fade_stasis_out(0.3)
	_overlay_instance.fade_black_in(0.5)
	yield(get_tree().create_timer(0.5), "timeout")

	# Clean up audio
	audio_shock.queue_free()
	audio_buzz.queue_free()

	# Unlock input
	player.input_locked = false
	is_capturing = false
